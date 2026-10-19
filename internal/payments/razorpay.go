package payments

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"

	"petora/internal/security"
)

// Razorpay implements Provider against Razorpay's public REST API (https://razorpay.com/docs/api/).
// It is exercised end to end (checkout → order → signed callback → fetch/capture → webhook → refund →
// reconciliation) against a fake Razorpay API in tests/integration/razorpay_test.go. It has NOT yet been run
// against Razorpay's real servers: do the staging run in docs/DEPLOYMENT.md §4 before going live.
type Razorpay struct {
	keyID, keySecret, webhookSecret string
	baseURL                         string
	hc                              *http.Client
}

// NewRazorpay builds the adapter. baseURL is https://api.razorpay.com/v1 in production (enforced by config).
func NewRazorpay(keyID, keySecret, webhookSecret, baseURL string) *Razorpay {
	if baseURL == "" {
		baseURL = "https://api.razorpay.com/v1"
	}
	return &Razorpay{keyID: keyID, keySecret: keySecret, webhookSecret: webhookSecret,
		baseURL: baseURL, hc: &http.Client{Timeout: 15 * time.Second}}
}

func (r *Razorpay) Name() string      { return "razorpay" }
func (r *Razorpay) TestMode() bool    { return len(r.keyID) >= 8 && r.keyID[:8] == "rzp_test" }
func (r *Razorpay) PublicKey() string { return r.keyID }

func (r *Razorpay) do(ctx context.Context, method, path string, body any, out any) error {
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, r.baseURL+path, rd)
	if err != nil {
		return err
	}
	req.SetBasicAuth(r.keyID, r.keySecret)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := r.hc.Do(req)
	if err != nil {
		return fmt.Errorf("razorpay request: %w", err) // network/timeout: caller treats as ambiguous
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode >= 400 {
		var e struct {
			Error struct{ Code, Description string } `json:"error"`
		}
		_ = json.Unmarshal(raw, &e)
		return &ProviderError{Status: resp.StatusCode, Code: e.Error.Code, Message: e.Error.Description}
	}
	if out != nil {
		return json.Unmarshal(raw, out)
	}
	return nil
}

// ProviderError is a definitive rejection by the gateway (as opposed to a network failure).
type ProviderError struct {
	Status  int
	Code    string
	Message string
}

func (e *ProviderError) Error() string {
	return fmt.Sprintf("provider error %d %s: %s", e.Status, e.Code, e.Message)
}

func (r *Razorpay) CreateOrder(ctx context.Context, o OrderRequest) (*Order, error) {
	var out struct {
		ID string `json:"id"`
	}
	err := r.do(ctx, http.MethodPost, "/orders", map[string]any{
		"amount": o.AmountMinor, "currency": o.Currency, "receipt": o.Receipt, "notes": o.Notes}, &out)
	if err != nil {
		return nil, err
	}
	return &Order{ID: out.ID}, nil
}

type rzpPayment struct {
	ID               string `json:"id"`
	OrderID          string `json:"order_id"`
	Amount           int64  `json:"amount"`
	Currency         string `json:"currency"`
	Status           string `json:"status"` // created | authorized | captured | refunded | failed
	ErrorDescription string `json:"error_description"`
}

func (p rzpPayment) verification() *Verification {
	v := &Verification{ProviderPaymentID: p.ID, AmountMinor: p.Amount, Currency: p.Currency, FailureReason: p.ErrorDescription}
	switch p.Status {
	case "captured":
		v.Outcome = OutcomePaid
	case "failed":
		v.Outcome = OutcomeFailed
	default:
		v.Outcome = OutcomePending
	}
	return v
}

// VerifyCheckout checks the checkout signature, then independently fetches the payment from Razorpay.
func (r *Razorpay) VerifyCheckout(ctx context.Context, in VerifyInput) (*Verification, error) {
	if in.OrderID == "" || in.PaymentID == "" || in.Signature == "" {
		return nil, errors.New("missing order, payment or signature")
	}
	want := security.HMACHex(r.keySecret, in.OrderID+"|"+in.PaymentID)
	if !security.ConstantTimeEqual(want, in.Signature) {
		return nil, ErrBadSignature
	}
	var p rzpPayment
	if err := r.do(ctx, http.MethodGet, "/payments/"+in.PaymentID, nil, &p); err != nil {
		return nil, err
	}
	if p.OrderID != in.OrderID {
		return nil, ErrBadSignature
	}
	if p.Status == "authorized" { // account without auto-capture: capture now
		if err := r.do(ctx, http.MethodPost, "/payments/"+p.ID+"/capture", map[string]any{"amount": p.Amount, "currency": p.Currency}, &p); err != nil {
			return &Verification{Outcome: OutcomePending, ProviderPaymentID: p.ID, AmountMinor: p.Amount, Currency: p.Currency}, nil
		}
	}
	return p.verification(), nil
}

var ErrBadSignature = errors.New("invalid payment signature")

// LookupOrder lists payments for an order (used by reconciliation for missed webhooks).
func (r *Razorpay) LookupOrder(ctx context.Context, orderID string) (*Verification, error) {
	var out struct {
		Items []rzpPayment `json:"items"`
	}
	if err := r.do(ctx, http.MethodGet, "/orders/"+orderID+"/payments", nil, &out); err != nil {
		return nil, err
	}
	res := &Verification{Outcome: OutcomePending}
	for _, p := range out.Items {
		v := p.verification()
		if v.Outcome == OutcomePaid {
			return v, nil
		}
		if v.Outcome == OutcomeFailed {
			res = v
		}
	}
	return res, nil
}

func (r *Razorpay) ParseWebhook(_ context.Context, body []byte, h http.Header) (*WebhookEvent, error) {
	sig := h.Get("X-Razorpay-Signature")
	if sig == "" || !security.ConstantTimeEqual(security.HMACHex(r.webhookSecret, string(body)), sig) {
		return nil, ErrBadSignature
	}
	id := h.Get("X-Razorpay-Event-Id")
	if id == "" {
		return nil, errors.New("missing X-Razorpay-Event-Id")
	}
	var env struct {
		Event   string `json:"event"`
		Payload struct {
			Payment struct{ Entity rzpPayment } `json:"payment"`
			Refund  struct {
				Entity struct {
					ID        string `json:"id"`
					PaymentID string `json:"payment_id"`
					Amount    int64  `json:"amount"`
					Status    string `json:"status"`
				}
			} `json:"refund"`
		} `json:"payload"`
	}
	if err := json.Unmarshal(body, &env); err != nil {
		return nil, err
	}
	ev := &WebhookEvent{ID: id, Type: env.Event, Kind: EventIgnored, Raw: json.RawMessage(body)}
	pe := env.Payload.Payment.Entity
	switch env.Event {
	case "payment.captured", "order.paid":
		ev.Kind = EventPaid
	case "payment.failed":
		ev.Kind = EventFailed
		ev.FailureReason = pe.ErrorDescription
	case "refund.processed":
		ev.Kind = EventRefundDone
	case "refund.failed":
		ev.Kind = EventRefundFailed
	}
	ev.ProviderOrderID, ev.ProviderPaymentID, ev.AmountMinor, ev.Currency = pe.OrderID, pe.ID, pe.Amount, pe.Currency
	if rf := env.Payload.Refund.Entity; rf.ID != "" {
		ev.ProviderRefundID, ev.ProviderPaymentID = rf.ID, rf.PaymentID
	}
	return ev, nil
}

func (r *Razorpay) Refund(ctx context.Context, rr RefundRequest) (*RefundResult, error) {
	var out struct {
		ID     string `json:"id"`
		Status string `json:"status"`
	}
	err := r.do(ctx, http.MethodPost, "/payments/"+rr.ProviderPaymentID+"/refund", map[string]any{
		"amount": rr.AmountMinor, "receipt": rr.Receipt, "notes": map[string]string{"reason": rr.Reason}}, &out)
	if err != nil {
		return nil, err
	}
	return &RefundResult{ProviderRefundID: out.ID, Done: out.Status == "processed"}, nil
}
