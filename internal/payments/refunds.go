package payments

import (
	"context"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5"

	"petora/internal/audit"
	"petora/internal/authctx"
	"petora/internal/database"
	"petora/internal/httpx"
	"petora/internal/notifications"
)

type Refund struct {
	ID          string    `json:"id"`
	PaymentID   string    `json:"payment_id"`
	AmountMinor int64     `json:"amount_minor"`
	Reason      string    `json:"reason"`
	Status      string    `json:"status"`
	CreatedAt   time.Time `json:"created_at"`
}

type RefundInput struct {
	AmountMinor    int64  `json:"amount_minor"`
	Reason         string `json:"reason"`
	IdempotencyKey string `json:"idempotency_key"`
}

// Refund reserves the amount atomically (so concurrent refunds cannot exceed the payment), then calls the
// provider outside the transaction. A definitive provider failure releases the reservation.
// Caller must hold the refunds.create permission (enforced at the route).
func (s *Service) Refund(ctx context.Context, actor *authctx.Principal, paymentID string, in RefundInput) (*Refund, error) {
	var v httpx.V
	v.Range("amount_minor", in.AmountMinor, 1, 1_000_000_000)
	v.Length("reason", in.Reason, 5, 500)
	v.Length("idempotency_key", in.IdempotencyKey, 8, 80)
	if err := v.Err(); err != nil {
		return nil, err
	}
	var rf Refund
	var providerPaymentID, userID, email, name, invoiceNo string
	var existing bool
	err := s.db.InTx(ctx, func(tx pgx.Tx) error {
		var status, subID, provider string
		var amount, refunded int64
		var provPay *string
		err := tx.QueryRow(ctx, `SELECT p.status, p.amount_minor, p.refunded_minor, p.provider_payment_id, COALESCE(p.subscription_id::text,''), p.provider,
			p.user_id, u.email, u.name, COALESCE((SELECT number FROM invoices WHERE payment_id=p.id),'')
			FROM payments p JOIN users u ON u.id=p.user_id WHERE p.id::text=$1 FOR UPDATE OF p`, paymentID).
			Scan(&status, &amount, &refunded, &provPay, &subID, &provider, &userID, &email, &name, &invoiceNo)
		if database.IsNoRows(err) {
			return httpx.NotFound("Payment")
		}
		if err != nil {
			return err
		}
		// Idempotent replay.
		err = tx.QueryRow(ctx, `SELECT id, payment_id, amount_minor, reason, status, created_at FROM refunds WHERE idempotency_key=$1`, in.IdempotencyKey).
			Scan(&rf.ID, &rf.PaymentID, &rf.AmountMinor, &rf.Reason, &rf.Status, &rf.CreatedAt)
		if err == nil {
			if rf.PaymentID != paymentID {
				return httpx.Conflict(httpx.CodeConflict, "Idempotency key already used for another payment")
			}
			existing = true
			return nil
		}
		if !database.IsNoRows(err) {
			return err
		}
		if status != "succeeded" && status != "partially_refunded" {
			return httpx.Conflict(httpx.CodeConflict, "Only successful payments can be refunded")
		}
		if in.AmountMinor > amount-refunded {
			return httpx.Conflict(httpx.CodeConflict, "Refund exceeds the refundable balance")
		}
		if provPay == nil {
			return httpx.Conflict(httpx.CodeConflict, "Payment has no provider reference")
		}
		providerPaymentID = *provPay
		newStatus := "partially_refunded"
		if refunded+in.AmountMinor == amount {
			newStatus = "refunded"
		}
		if _, err := tx.Exec(ctx, `UPDATE payments SET refunded_minor=refunded_minor+$2, status=$3, updated_at=now() WHERE id=$1`, paymentID, in.AmountMinor, newStatus); err != nil {
			return err
		}
		if err := tx.QueryRow(ctx, `INSERT INTO refunds (payment_id, amount_minor, reason, status, idempotency_key, requested_by)
			VALUES ($1,$2,$3,'processing',$4,$5) RETURNING id, payment_id, amount_minor, reason, status, created_at`,
			paymentID, in.AmountMinor, in.Reason, in.IdempotencyKey, actor.UserID).Scan(&rf.ID, &rf.PaymentID, &rf.AmountMinor, &rf.Reason, &rf.Status, &rf.CreatedAt); err != nil {
			return err
		}
		// A full refund ends the subscription that payment bought; benefits must not outlive the money.
		if newStatus == "refunded" && subID != "" {
			var audience string
			if err := tx.QueryRow(ctx, `UPDATE subscriptions SET status='refunded', updated_at=now() WHERE id=$1 AND status IN ('active','grace')
				RETURNING audience`, subID).Scan(&audience); err == nil && audience == "seller" {
				if _, err := tx.Exec(ctx, `UPDATE pet_listings SET status='expired', expired_reason='subscription', updated_at=now()
					WHERE status='approved' AND seller_id IN (SELECT id FROM seller_profiles WHERE user_id=$1)`, userID); err != nil {
					return err
				}
			}
		}
		return audit.Log(ctx, tx, audit.Entry{Action: "refund.requested", EntityType: "payment", EntityID: paymentID,
			Metadata: map[string]any{"refund_id": rf.ID, "amount_minor": in.AmountMinor, "reason": in.Reason}})
	})
	if err != nil {
		return nil, err
	}
	if existing {
		return &rf, nil
	}
	res, perr := s.provider.Refund(ctx, RefundRequest{ProviderPaymentID: providerPaymentID, AmountMinor: in.AmountMinor, Reason: in.Reason, Receipt: rf.ID})
	if perr != nil {
		slog.ErrorContext(ctx, "provider refund failed", "refund_id", rf.ID, "err", perr)
		var pe *ProviderError
		if asProviderErr(perr, &pe) { // definitive rejection: release the reservation
			s.failRefund(ctx, rf.ID, paymentID, in.AmountMinor, pe.Message)
			return nil, httpx.Err(502, httpx.CodePaymentFailed, "The payment provider rejected the refund: "+pe.Message)
		}
		// Ambiguous (timeout): leave 'processing'; a refund webhook or support will settle it.
		return &rf, nil
	}
	status := "processing"
	if res.Done {
		status = "succeeded"
	}
	_, _ = s.db.Exec(ctx, `UPDATE refunds SET provider_refund_id=$2, status=$3, updated_at=now() WHERE id=$1`, rf.ID, res.ProviderRefundID, status)
	rf.Status = status
	if res.Done {
		_ = notifications.Create(ctx, s.db, userID, "refund_processed", "Refund issued", "A refund has been issued for invoice "+invoiceNo+".", map[string]any{"payment_id": paymentID})
		_ = notifications.EnqueueEmail(ctx, s.db, email, "refund_processed", map[string]string{"name": name, "amount": money(in.AmountMinor), "invoice": invoiceNo})
	}
	return &rf, nil
}

func (s *Service) failRefund(ctx context.Context, refundID, paymentID string, amount int64, reason string) {
	err := s.db.InTx(ctx, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `UPDATE refunds SET status='failed', failure_reason=$2, updated_at=now() WHERE id=$1 AND status IN ('requested','processing')`, refundID, reason)
		if err != nil || tag.RowsAffected() == 0 {
			return err
		}
		_, err = tx.Exec(ctx, `UPDATE payments SET refunded_minor=refunded_minor-$2,
			status=CASE WHEN refunded_minor-$2 = 0 THEN 'succeeded' ELSE 'partially_refunded' END, updated_at=now() WHERE id=$1`, paymentID, amount)
		return err
	})
	if err != nil {
		slog.Error("releasing failed refund reservation", "refund_id", refundID, "err", err)
	}
}

func (s *Service) applyRefundEvent(ctx context.Context, ev *WebhookEvent) error {
	var refundID, paymentID string
	var amount int64
	err := s.db.QueryRow(ctx, `SELECT r.id, r.payment_id, r.amount_minor FROM refunds r WHERE r.provider_refund_id=$1`, ev.ProviderRefundID).Scan(&refundID, &paymentID, &amount)
	if database.IsNoRows(err) {
		return nil // refund created outside our system (e.g. provider dashboard): nothing to reconcile automatically
	}
	if err != nil {
		return err
	}
	if ev.Kind == EventRefundDone {
		_, err = s.db.Exec(ctx, `UPDATE refunds SET status='succeeded', updated_at=now() WHERE id=$1 AND status IN ('requested','processing')`, refundID)
		return err
	}
	s.failRefund(ctx, refundID, paymentID, amount, "provider reported failure")
	return nil
}

func asProviderErr(err error, target **ProviderError) bool {
	for err != nil {
		if pe, ok := err.(*ProviderError); ok {
			*target = pe
			return true
		}
		u, ok := err.(interface{ Unwrap() error })
		if !ok {
			return false
		}
		err = u.Unwrap()
	}
	return false
}

func money(minor int64) string {
	return "₹" + formatINR(minor)
}

func formatINR(minor int64) string {
	rupees, paise := minor/100, minor%100
	s := itoa(rupees)
	// Indian grouping: last three digits, then groups of two.
	if len(s) > 3 {
		head, tail := s[:len(s)-3], s[len(s)-3:]
		var parts []string
		for len(head) > 2 {
			parts = append([]string{head[len(head)-2:]}, parts...)
			head = head[:len(head)-2]
		}
		if head != "" {
			parts = append([]string{head}, parts...)
		}
		s = join(parts, ",") + "," + tail
	}
	if paise != 0 {
		return s + "." + pad2(paise)
	}
	return s
}

func itoa(n int64) string {
	if n == 0 {
		return "0"
	}
	var b [20]byte
	p := len(b)
	for n > 0 {
		p--
		b[p] = byte('0' + n%10)
		n /= 10
	}
	return string(b[p:])
}
func pad2(n int64) string {
	if n < 10 {
		return "0" + itoa(n)
	}
	return itoa(n)
}
func join(a []string, sep string) string {
	out := ""
	for i, x := range a {
		if i > 0 {
			out += sep
		}
		out += x
	}
	return out
}
