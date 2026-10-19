package payments

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"petora/internal/audit"
	"petora/internal/authctx"
	"petora/internal/cache"
	"petora/internal/config"
	"petora/internal/database"
	"petora/internal/httpx"
	"petora/internal/jobs"
	"petora/internal/notifications"
	"petora/internal/subscriptions"
)

type Service struct {
	cfg      config.Config
	db       *database.DB
	cache    *cache.Cache
	provider Provider
	subs     *subscriptions.Service
}

func NewService(cfg config.Config, db *database.DB, c *cache.Cache, p Provider, subs *subscriptions.Service) *Service {
	return &Service{cfg: cfg, db: db, cache: c, provider: p, subs: subs}
}

func (s *Service) Provider() Provider { return s.provider }

type PlanRef struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Audience string `json:"audience"`
}

type Payment struct {
	ID            string     `json:"id"`
	Status        string     `json:"status"`
	Plan          PlanRef    `json:"plan"`
	SubtotalMinor int64      `json:"subtotal_minor"`
	TaxMinor      int64      `json:"tax_minor"`
	AmountMinor   int64      `json:"amount_minor"`
	RefundedMinor int64      `json:"refunded_minor"`
	Currency      string     `json:"currency"`
	Provider      string     `json:"provider"`
	FailureReason *string    `json:"failure_reason"`
	InvoiceID     *string    `json:"invoice_id"`
	CreatedAt     time.Time  `json:"created_at"`
	PaidAt        *time.Time `json:"paid_at"`
}

const paymentCols = `p.id, p.status, p.plan_snapshot->>'plan_id', p.plan_snapshot->>'name', p.plan_snapshot->>'audience', p.subtotal_minor, p.tax_minor,
	p.amount_minor, p.refunded_minor, p.currency, p.provider, p.failure_reason, (SELECT i.id::text FROM invoices i WHERE i.payment_id=p.id), p.created_at, p.paid_at`

func scanPayment(row pgx.Row) (*Payment, error) {
	var p Payment
	err := row.Scan(&p.ID, &p.Status, &p.Plan.ID, &p.Plan.Name, &p.Plan.Audience, &p.SubtotalMinor, &p.TaxMinor, &p.AmountMinor, &p.RefundedMinor,
		&p.Currency, &p.Provider, &p.FailureReason, &p.InvoiceID, &p.CreatedAt, &p.PaidAt)
	return &p, err
}

type Checkout struct {
	Payment         *Payment `json:"payment"`
	Provider        string   `json:"provider"`
	ProviderOrderID string   `json:"provider_order_id"`
	ProviderKeyID   string   `json:"provider_key_id,omitempty"`
	AmountMinor     int64    `json:"amount_minor"`
	Currency        string   `json:"currency"`
	TestMode        bool     `json:"test_mode"`
}

// ---------- checkout ----------

func (s *Service) Checkout(ctx context.Context, p *authctx.Principal, planID, idemKey string) (*Checkout, error) {
	var v httpx.V
	v.Required("plan_id", planID)
	v.Length("idempotency_key", idemKey, 16, 80)
	if err := v.Err(); err != nil {
		return nil, err
	}
	if p.AccountType == "staff" {
		return nil, httpx.Forbidden("Staff accounts cannot purchase plans")
	}
	plan, err := s.subs.GetPlan(ctx, s.db, planID)
	if err != nil {
		return nil, err
	}
	if !plan.IsActive {
		return nil, httpx.NotFound("Plan")
	}
	if plan.Audience != p.AccountType {
		return nil, httpx.Forbidden("This plan is not available for your account type")
	}
	// Idempotent replay.
	if existing, err := s.byIdempotency(ctx, p.UserID, idemKey); err != nil {
		return nil, err
	} else if existing != nil {
		if existing.Plan.ID != plan.ID {
			return nil, httpx.Conflict(httpx.CodeConflict, "This idempotency key was used for a different plan")
		}
		return s.checkoutView(ctx, existing.ID)
	}
	if err := s.subs.CanPurchase(ctx, s.db, p.UserID, plan); err != nil {
		return nil, err
	}
	// Reuse a recent open order for the same plan so a page reload cannot create a second chargeable order.
	var openID string
	err = s.db.QueryRow(ctx, `SELECT COALESCE((SELECT id::text FROM payments WHERE user_id=$1 AND plan_id=$2 AND status IN ('created','pending')
		AND provider_order_id IS NOT NULL AND provider=$3 AND created_at > now() - interval '30 minutes' ORDER BY created_at DESC LIMIT 1),'')`,
		p.UserID, plan.ID, s.provider.Name()).Scan(&openID)
	if err != nil {
		return nil, err
	}
	if openID != "" {
		return s.checkoutView(ctx, openID)
	}

	snap, _ := json.Marshal(plan.Snapshot())
	var paymentID string
	err = s.db.QueryRow(ctx, `INSERT INTO payments (user_id, plan_id, provider, subtotal_minor, tax_minor, amount_minor, currency, idempotency_key, plan_snapshot)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id`, p.UserID, plan.ID, s.provider.Name(), plan.EffectivePrice, plan.TaxMinor, plan.TotalMinor,
		plan.Currency, idemKey, snap).Scan(&paymentID)
	if database.IsUniqueViolation(err, "") { // concurrent replay of the same key
		if existing, e2 := s.byIdempotency(ctx, p.UserID, idemKey); e2 == nil && existing != nil {
			return s.checkoutView(ctx, existing.ID)
		}
	}
	if err != nil {
		return nil, err
	}
	// Free plans (₹0) skip the gateway: nothing to charge, activate immediately.
	if plan.TotalMinor == 0 {
		if err := s.finalizeSuccess(ctx, paymentID, "free_"+paymentID, plan.TotalMinor, "free"); err != nil {
			return nil, err
		}
		return s.checkoutView(ctx, paymentID)
	}
	order, err := s.provider.CreateOrder(ctx, OrderRequest{AmountMinor: plan.TotalMinor, Currency: plan.Currency, Receipt: paymentID,
		Notes: map[string]string{"payment_id": paymentID, "user_id": p.UserID, "plan": plan.Code}})
	if err != nil {
		_, _ = s.db.Exec(ctx, `UPDATE payments SET status='failed', failure_reason='could not create order', updated_at=now() WHERE id=$1`, paymentID)
		slog.ErrorContext(ctx, "create order failed", "err", err, "payment_id", paymentID)
		return nil, httpx.Err(502, httpx.CodePaymentFailed, "We could not start the payment. You have not been charged. Please try again.")
	}
	if _, err := s.db.Exec(ctx, `UPDATE payments SET provider_order_id=$2, updated_at=now() WHERE id=$1`, paymentID, order.ID); err != nil {
		return nil, err
	}
	return s.checkoutView(ctx, paymentID)
}

func (s *Service) byIdempotency(ctx context.Context, userID, key string) (*Payment, error) {
	p, err := scanPayment(s.db.QueryRow(ctx, `SELECT `+paymentCols+` FROM payments p WHERE p.user_id=$1 AND p.idempotency_key=$2`, userID, key))
	if database.IsNoRows(err) {
		return nil, nil
	}
	return p, err
}

func (s *Service) checkoutView(ctx context.Context, paymentID string) (*Checkout, error) {
	p, err := scanPayment(s.db.QueryRow(ctx, `SELECT `+paymentCols+` FROM payments p WHERE p.id=$1`, paymentID))
	if err != nil {
		return nil, err
	}
	var orderID *string
	if err := s.db.QueryRow(ctx, `SELECT provider_order_id FROM payments WHERE id=$1`, paymentID).Scan(&orderID); err != nil {
		return nil, err
	}
	c := &Checkout{Payment: p, Provider: p.Provider, AmountMinor: p.AmountMinor, Currency: p.Currency, TestMode: s.provider.TestMode(), ProviderKeyID: s.provider.PublicKey()}
	if orderID != nil {
		c.ProviderOrderID = *orderID
	}
	return c, nil
}

// ---------- reads ----------

func (s *Service) Get(ctx context.Context, userID, id string) (*Payment, error) {
	p, err := scanPayment(s.db.QueryRow(ctx, `SELECT `+paymentCols+` FROM payments p WHERE p.id::text=$1 AND p.user_id=$2`, id, userID))
	if database.IsNoRows(err) {
		return nil, httpx.NotFound("Payment")
	}
	return p, err
}

func (s *Service) List(ctx context.Context, userID string, pg httpx.Page) ([]Payment, int, error) {
	var total int
	if err := s.db.QueryRow(ctx, `SELECT count(*) FROM payments WHERE user_id=$1 AND status <> 'created'`, userID).Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := s.db.Query(ctx, `SELECT `+paymentCols+` FROM payments p WHERE p.user_id=$1 AND p.status <> 'created'
		ORDER BY p.created_at DESC LIMIT $2 OFFSET $3`, userID, pg.PerPage, pg.Offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := []Payment{}
	for rows.Next() {
		p, err := scanPayment(rows)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, *p)
	}
	return out, total, rows.Err()
}

// ---------- verification ----------

type VerifyBody struct {
	ProviderPaymentID string `json:"provider_payment_id"`
	ProviderOrderID   string `json:"provider_order_id"`
	Signature         string `json:"signature"`
}

// Verify checks a checkout result with the provider. Ambiguous outcomes (timeouts, authorised-not-captured)
// leave the payment `pending`: the webhook or the reconciliation job settles it. Nothing is ever marked
// successful from client-supplied data alone.
func (s *Service) Verify(ctx context.Context, userID, id string, in VerifyBody) (*Payment, error) {
	pay, err := s.Get(ctx, userID, id)
	if err != nil {
		return nil, err
	}
	if pay.Status == "succeeded" || pay.Status == "refunded" || pay.Status == "partially_refunded" {
		return pay, nil
	}
	var orderID *string
	if err := s.db.QueryRow(ctx, `SELECT provider_order_id FROM payments WHERE id=$1`, id).Scan(&orderID); err != nil {
		return nil, err
	}
	if orderID == nil {
		return nil, httpx.BadRequest("Payment has no provider order")
	}
	if in.ProviderOrderID != "" && in.ProviderOrderID != *orderID {
		return nil, httpx.BadRequest("Order does not match this payment")
	}
	ver, err := s.provider.VerifyCheckout(ctx, VerifyInput{OrderID: *orderID, PaymentID: in.ProviderPaymentID, Signature: in.Signature})
	switch {
	case errors.Is(err, ErrBadSignature):
		_ = audit.Log(ctx, s.db, audit.Entry{Action: "payment.bad_signature", EntityType: "payment", EntityID: id})
		return nil, httpx.Err(400, httpx.CodePaymentFailed, "Payment could not be verified")
	case err != nil:
		var pe *ProviderError
		if errors.As(err, &pe) { // definitive rejection
			return nil, httpx.Err(400, httpx.CodePaymentFailed, "Payment could not be verified")
		}
		slog.WarnContext(ctx, "verify ambiguous; leaving pending", "payment_id", id, "err", err)
		_, _ = s.db.Exec(ctx, `UPDATE payments SET status='pending', updated_at=now() WHERE id=$1 AND status='created'`, id)
		return s.Get(ctx, userID, id)
	}
	if err := s.applyVerification(ctx, id, ver, "verify"); err != nil {
		return nil, err
	}
	return s.Get(ctx, userID, id)
}

func (s *Service) applyVerification(ctx context.Context, paymentID string, v *Verification, source string) error {
	switch v.Outcome {
	case OutcomePaid:
		return s.finalizeSuccessCur(ctx, paymentID, v.ProviderPaymentID, v.AmountMinor, v.Currency, source)
	case OutcomeFailed:
		return s.finalizeFailure(ctx, paymentID, v.ProviderPaymentID, v.FailureReason)
	default:
		_, err := s.db.Exec(ctx, `UPDATE payments SET status='pending', updated_at=now() WHERE id=$1 AND status='created'`, paymentID)
		return err
	}
}

// finalizeSuccess is the single place where money becomes entitlement. One transaction, row-locked.
func (s *Service) finalizeSuccess(ctx context.Context, paymentID, providerPaymentID string, paidMinor int64, source string) error {
	return s.finalizeSuccessCur(ctx, paymentID, providerPaymentID, paidMinor, "", source)
}

// finalizeSuccessCur also checks the provider-reported currency when it is known.
func (s *Service) finalizeSuccessCur(ctx context.Context, paymentID, providerPaymentID string, paidMinor int64, paidCurrency, source string) error {
	err := s.db.InTx(ctx, func(tx pgx.Tx) error {
		var (
			status, currency, userID, userName, userEmail string
			amount                                        int64
			snapRaw                                       []byte
			subtotal, tax                                 int64
		)
		err := tx.QueryRow(ctx, `SELECT p.status, p.amount_minor, p.currency, p.user_id, p.plan_snapshot, p.subtotal_minor, p.tax_minor, u.name, u.email
			FROM payments p JOIN users u ON u.id=p.user_id WHERE p.id=$1 FOR UPDATE OF p`, paymentID).
			Scan(&status, &amount, &currency, &userID, &snapRaw, &subtotal, &tax, &userName, &userEmail)
		if database.IsNoRows(err) {
			return httpx.NotFound("Payment")
		}
		if err != nil {
			return err
		}
		switch status {
		case "succeeded", "refunded", "partially_refunded":
			return nil // already finalised: idempotent no-op
		}
		if paidMinor != amount || (paidCurrency != "" && !strings.EqualFold(paidCurrency, currency)) {
			// Never activate when the gateway amount differs from what we priced.
			_, _ = tx.Exec(ctx, `UPDATE payments SET status='pending', failure_reason='amount mismatch - manual review', updated_at=now() WHERE id=$1`, paymentID)
			audit.System(ctx, tx, "payment.amount_mismatch", "payment", paymentID, map[string]any{"expected": amount, "got": paidMinor, "currency": paidCurrency})
			return nil
		}
		var snap subscriptions.PlanSnapshot
		if err := json.Unmarshal(snapRaw, &snap); err != nil {
			return err
		}
		var invoiceID, invoiceNo string
		if invoiceNo, err = nextInvoiceNumber(ctx, tx, s.provider.TestMode()); err != nil {
			return err
		}
		lines, _ := json.Marshal([]map[string]any{{"description": snap.Name + " plan (" + snap.BillingInterval + ")", "amount_minor": subtotal}})
		if err := tx.QueryRow(ctx, `INSERT INTO invoices (number, payment_id, user_id, bill_to_name, bill_to_email, lines, subtotal_minor, tax_minor, total_minor, currency)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id`, invoiceNo, paymentID, userID, userName, userEmail, lines, subtotal, tax, amount, currency).Scan(&invoiceID); err != nil {
			return err
		}
		subID, err := s.subs.Activate(ctx, tx, paymentID, userID, snap, userName, userEmail, invoiceNo)
		if err != nil {
			return err
		}
		var provID *string
		if providerPaymentID != "" {
			provID = &providerPaymentID
		}
		if _, err := tx.Exec(ctx, `UPDATE payments SET status='succeeded', paid_at=now(), provider_payment_id=COALESCE($2, provider_payment_id),
			subscription_id=$3, failure_reason=NULL, updated_at=now() WHERE id=$1`, paymentID, provID, subID); err != nil {
			return err
		}
		audit.System(ctx, tx, "payment.succeeded", "payment", paymentID, map[string]any{"source": source, "amount_minor": amount, "subscription_id": subID})
		return nil
	})
	if err == nil {
		s.cache.DelPrefix(context.WithoutCancel(ctx), "pets:")
	}
	return err
}

func (s *Service) finalizeFailure(ctx context.Context, paymentID, providerPaymentID, reason string) error {
	return s.db.InTx(ctx, func(tx pgx.Tx) error {
		var status, userID, name, email, planName string
		err := tx.QueryRow(ctx, `SELECT p.status, p.user_id, u.name, u.email, p.plan_snapshot->>'name' FROM payments p JOIN users u ON u.id=p.user_id
			WHERE p.id=$1 FOR UPDATE OF p`, paymentID).Scan(&status, &userID, &name, &email, &planName)
		if err != nil {
			return err
		}
		if status != "created" && status != "pending" {
			return nil // never downgrade a succeeded/refunded payment
		}
		if reason == "" {
			reason = "payment failed"
		}
		var provID *string
		if providerPaymentID != "" {
			provID = &providerPaymentID
		}
		if _, err := tx.Exec(ctx, `UPDATE payments SET status='failed', failure_reason=$2, provider_payment_id=COALESCE($3, provider_payment_id), updated_at=now() WHERE id=$1`,
			paymentID, reason, provID); err != nil {
			return err
		}
		if err := notifications.Create(ctx, tx, userID, "payment_failed", "Payment failed", "Your payment for "+planName+" did not go through. You have not been charged.", map[string]any{"payment_id": paymentID}); err != nil {
			return err
		}
		return notifications.EnqueueEmail(ctx, tx, email, "payment_failed", map[string]string{"name": name, "plan": planName, "url": s.cfg.BaseURL + "/pricing"})
	})
}

// nextInvoiceNumber issues Indian financial-year numbering. Test-mode payments get a TEST- prefix so they can
// never be mistaken for tax invoices.
func nextInvoiceNumber(ctx context.Context, tx pgx.Tx, test bool) (string, error) {
	var seq int64
	if err := tx.QueryRow(ctx, `SELECT nextval('invoice_number_seq')`).Scan(&seq); err != nil {
		return "", err
	}
	now := time.Now().In(time.FixedZone("IST", 5*3600+1800))
	y := now.Year()
	if now.Month() < time.April {
		y--
	}
	prefix := "PET"
	if test {
		prefix = "TEST-PET"
	}
	return fmt.Sprintf("%s/%d-%02d/%06d", prefix, y, (y+1)%100, seq), nil
}

// ---------- test-mode completion (non-production only) ----------

func (s *Service) TestComplete(ctx context.Context, userID, id, outcome string) (*Payment, error) {
	if s.provider.Name() != "testmode" || s.cfg.IsProduction() {
		return nil, httpx.NotFound("Route")
	}
	pay, err := s.Get(ctx, userID, id)
	if err != nil {
		return nil, err
	}
	if pay.Provider != "testmode" {
		return nil, httpx.BadRequest("Not a test-mode payment")
	}
	switch outcome {
	case "success":
		err = s.finalizeSuccess(ctx, id, "test_pay_"+id, pay.AmountMinor, "test-complete")
	case "failure":
		err = s.finalizeFailure(ctx, id, "", "simulated failure")
	default:
		return nil, httpx.Invalid(httpx.FieldError{Field: "outcome", Message: "must be success or failure"})
	}
	if err != nil {
		return nil, err
	}
	return s.Get(ctx, userID, id)
}

// ---------- webhooks ----------

// HandleWebhook verifies the signature, persists the event (unique per provider event id), enqueues durable
// processing and tries to process inline. Duplicate deliveries are acknowledged without side effects.
func (s *Service) HandleWebhook(ctx context.Context, body []byte, h http.Header) error {
	ev, err := s.provider.ParseWebhook(ctx, body, h)
	if err != nil {
		return httpx.BadRequest("Invalid webhook")
	}
	// Persist the normalised event (the raw body is embedded) so processing never needs the original headers.
	if !json.Valid(ev.Raw) {
		ev.Raw = json.RawMessage(`null`)
	}
	normalized, _ := json.Marshal(ev)
	var eventRowID string
	var isNew bool
	err = s.db.InTx(ctx, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `INSERT INTO payment_webhook_events (provider, event_id, event_type, payload)
			VALUES ($1,$2,$3,$4) ON CONFLICT (provider, event_id) DO NOTHING`, s.provider.Name(), ev.ID, ev.Type, normalized)
		if err != nil {
			return err
		}
		isNew = tag.RowsAffected() == 1
		if err := tx.QueryRow(ctx, `SELECT id FROM payment_webhook_events WHERE provider=$1 AND event_id=$2`, s.provider.Name(), ev.ID).Scan(&eventRowID); err != nil {
			return err
		}
		if isNew {
			return jobs.Enqueue(ctx, tx, "webhook.process", map[string]string{"event_row_id": eventRowID}, jobs.Dedupe("webhook:"+eventRowID))
		}
		return nil
	})
	if err != nil {
		return err
	}
	if !isNew {
		return nil
	}
	if err := s.ProcessEvent(ctx, eventRowID); err != nil {
		slog.WarnContext(ctx, "inline webhook processing failed; job will retry", "event", ev.ID, "err", err)
	}
	return nil
}

// ProcessEvent applies a stored webhook event. Safe to call repeatedly.
func (s *Service) ProcessEvent(ctx context.Context, eventRowID string) error {
	var provider, eventID, evType, status string
	var payload []byte
	err := s.db.QueryRow(ctx, `SELECT provider, event_id, event_type, status, payload FROM payment_webhook_events WHERE id=$1`, eventRowID).
		Scan(&provider, &eventID, &evType, &status, &payload)
	if err != nil {
		return err
	}
	if status == "processed" || status == "ignored" {
		return nil
	}
	var ev WebhookEvent
	if err := json.Unmarshal(payload, &ev); err != nil {
		return s.markEvent(ctx, eventRowID, "failed", "cannot decode stored event: "+err.Error())
	}
	_, _ = s.db.Exec(ctx, `UPDATE payment_webhook_events SET attempts = attempts + 1 WHERE id=$1`, eventRowID)
	var perr error
	switch ev.Kind {
	case EventPaid, EventFailed:
		var paymentID string
		if err := s.db.QueryRow(ctx, `SELECT COALESCE((SELECT id::text FROM payments WHERE provider=$1 AND provider_order_id=$2),'')`, provider, ev.ProviderOrderID).Scan(&paymentID); err != nil {
			return err
		}
		if paymentID == "" {
			return s.markEvent(ctx, eventRowID, "ignored", "no matching payment")
		}
		if ev.Kind == EventPaid {
			perr = s.finalizeSuccessCur(ctx, paymentID, ev.ProviderPaymentID, ev.AmountMinor, ev.Currency, "webhook")
		} else {
			perr = s.finalizeFailure(ctx, paymentID, ev.ProviderPaymentID, ev.FailureReason)
		}
	case EventRefundDone, EventRefundFailed:
		perr = s.applyRefundEvent(ctx, &ev)
	default:
		return s.markEvent(ctx, eventRowID, "ignored", "event type not handled")
	}
	if perr != nil {
		_ = s.markEvent(ctx, eventRowID, "failed", perr.Error())
		return perr
	}
	return s.markEvent(ctx, eventRowID, "processed", "")
}

func (s *Service) markEvent(ctx context.Context, id, status, errMsg string) error {
	var e *string
	if errMsg != "" {
		e = &errMsg
	}
	_, err := s.db.Exec(ctx, `UPDATE payment_webhook_events SET status=$2, error=$3, processed_at=CASE WHEN $2 IN ('processed','ignored') THEN now() END WHERE id=$1`, id, status, e)
	return err
}

// JobHandler is registered with the worker for kind "webhook.process".
func (s *Service) JobHandler() jobs.Handler {
	return func(ctx context.Context, payload json.RawMessage) error {
		var p struct {
			EventRowID string `json:"event_row_id"`
		}
		if err := json.Unmarshal(payload, &p); err != nil {
			return err
		}
		return s.ProcessEvent(ctx, p.EventRowID)
	}
}

// ---------- reconciliation ----------

// Reconcile asks the provider about stale open payments (missed webhooks, closed browser tabs).
func (s *Service) Reconcile(ctx context.Context) (settled int, err error) {
	rows, err := s.db.Query(ctx, `SELECT id, provider_order_id, created_at FROM payments
		WHERE status IN ('created','pending') AND provider=$1 AND provider_order_id IS NOT NULL AND created_at < now() - interval '3 minutes'
		  AND created_at > now() - interval '7 days' ORDER BY created_at LIMIT 100`, s.provider.Name())
	if err != nil {
		return 0, err
	}
	type open struct {
		id, order string
		created   time.Time
	}
	var list []open
	for rows.Next() {
		var o open
		if err := rows.Scan(&o.id, &o.order, &o.created); err != nil {
			rows.Close()
			return 0, err
		}
		list = append(list, o)
	}
	rows.Close()
	for _, o := range list {
		v, err := s.provider.LookupOrder(ctx, o.order)
		if err != nil {
			slog.Warn("reconcile lookup failed", "payment_id", o.id, "err", err)
			continue
		}
		switch {
		case v.Outcome == OutcomePaid:
			if err := s.finalizeSuccessCur(ctx, o.id, v.ProviderPaymentID, v.AmountMinor, v.Currency, "reconcile"); err == nil {
				settled++
			}
		case v.Outcome == OutcomeFailed && time.Since(o.created) > time.Hour:
			if err := s.finalizeFailure(ctx, o.id, v.ProviderPaymentID, v.FailureReason); err == nil {
				settled++
			}
		case time.Since(o.created) > 24*time.Hour:
			_, _ = s.db.Exec(ctx, `UPDATE payments SET status='cancelled', failure_reason='abandoned', updated_at=now() WHERE id=$1 AND status IN ('created','pending')`, o.id)
		}
	}
	return settled, nil
}
