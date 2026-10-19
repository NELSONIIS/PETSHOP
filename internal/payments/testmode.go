package payments

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"

	"petora/internal/security"
)

// TestMode is a development/staging adapter. No money moves. It is refused in production by config
// validation. Completion is driven by the gated POST /payments/{id}/test-complete endpoint or by
// signed simulated webhooks (header X-Test-Signature = HMAC-SHA256(body, JWT_SECRET)).
type TestMode struct{ secret string }

func NewTestMode(secret string) *TestMode { return &TestMode{secret: secret} }

func (t *TestMode) Name() string      { return "testmode" }
func (t *TestMode) TestMode() bool    { return true }
func (t *TestMode) PublicKey() string { return "" }

func (t *TestMode) CreateOrder(_ context.Context, o OrderRequest) (*Order, error) {
	return &Order{ID: "test_order_" + security.RandomToken(9)}, nil
}

// VerifyCheckout can never mark a test payment as paid by itself: only the explicit test-complete endpoint does.
func (t *TestMode) VerifyCheckout(_ context.Context, _ VerifyInput) (*Verification, error) {
	return &Verification{Outcome: OutcomePending}, nil
}
func (t *TestMode) LookupOrder(context.Context, string) (*Verification, error) {
	return &Verification{Outcome: OutcomePending}, nil
}

// Sign is used by tests and the test-complete endpoint to produce webhook signatures.
func (t *TestMode) Sign(body []byte) string { return security.HMACHex(t.secret, string(body)) }

type testEvent struct {
	ID        string `json:"id"`
	Type      string `json:"type"` // payment.captured | payment.failed | refund.processed
	OrderID   string `json:"order_id"`
	PaymentID string `json:"payment_id"`
	RefundID  string `json:"refund_id"`
	Amount    int64  `json:"amount"`
	Currency  string `json:"currency"`
	Reason    string `json:"reason"`
}

func (t *TestMode) ParseWebhook(_ context.Context, body []byte, h http.Header) (*WebhookEvent, error) {
	if !security.ConstantTimeEqual(t.Sign(body), h.Get("X-Test-Signature")) {
		return nil, ErrBadSignature
	}
	var e testEvent
	if err := json.Unmarshal(body, &e); err != nil || e.ID == "" {
		return nil, errors.New("invalid test event")
	}
	ev := &WebhookEvent{ID: e.ID, Type: e.Type, Kind: EventIgnored, ProviderOrderID: e.OrderID, ProviderPaymentID: e.PaymentID,
		ProviderRefundID: e.RefundID, AmountMinor: e.Amount, Currency: e.Currency, FailureReason: e.Reason, Raw: json.RawMessage(body)}
	switch e.Type {
	case "payment.captured":
		ev.Kind = EventPaid
	case "payment.failed":
		ev.Kind = EventFailed
	case "refund.processed":
		ev.Kind = EventRefundDone
	}
	return ev, nil
}

func (t *TestMode) Refund(_ context.Context, r RefundRequest) (*RefundResult, error) {
	return &RefundResult{ProviderRefundID: "test_rfnd_" + security.RandomToken(8), Done: true}, nil
}
