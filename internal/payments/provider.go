// Package payments contains the provider abstraction, checkout, server-side verification,
// webhook processing, refunds, invoices and reconciliation.
//
// Invariants:
//   - A client-side "success" is never trusted; only provider-verified state or a signature-verified webhook finalises a payment.
//   - Finalisation is one DB transaction guarded by a row lock on the payment, so concurrent verify/webhook/reconcile
//     calls converge on exactly one activation.
package payments

import (
	"context"
	"encoding/json"
	"net/http"
)

type OrderRequest struct {
	AmountMinor int64
	Currency    string
	Receipt     string // our payment id
	Notes       map[string]string
}

type Order struct{ ID string }

type VerifyInput struct {
	OrderID   string
	PaymentID string
	Signature string
}

type Outcome string

const (
	OutcomePaid    Outcome = "paid"
	OutcomeFailed  Outcome = "failed"
	OutcomePending Outcome = "pending"
)

// Verification is the provider-confirmed state of a payment attempt.
type Verification struct {
	Outcome           Outcome
	ProviderPaymentID string
	AmountMinor       int64
	Currency          string
	FailureReason     string
}

type EventKind string

const (
	EventPaid         EventKind = "paid"
	EventFailed       EventKind = "failed"
	EventRefundDone   EventKind = "refund_processed"
	EventRefundFailed EventKind = "refund_failed"
	EventIgnored      EventKind = "ignored"
)

// WebhookEvent is a signature-verified, normalised provider event.
type WebhookEvent struct {
	ID                string          `json:"id"`   // provider's unique event id (dedupe key)
	Type              string          `json:"type"` // raw provider type, e.g. payment.captured
	Kind              EventKind       `json:"kind"`
	ProviderOrderID   string          `json:"provider_order_id"`
	ProviderPaymentID string          `json:"provider_payment_id"`
	ProviderRefundID  string          `json:"provider_refund_id"`
	AmountMinor       int64           `json:"amount_minor"`
	Currency          string          `json:"currency"`
	FailureReason     string          `json:"failure_reason"`
	Raw               json.RawMessage `json:"raw"`
}

type RefundRequest struct {
	ProviderPaymentID string
	AmountMinor       int64
	Reason            string
	Receipt           string
}

type RefundResult struct {
	ProviderRefundID string
	Done             bool // false = accepted but still processing (a webhook will confirm)
}

// Provider is the only surface business logic uses to talk to a payment gateway.
type Provider interface {
	Name() string
	TestMode() bool
	PublicKey() string
	CreateOrder(ctx context.Context, r OrderRequest) (*Order, error)
	VerifyCheckout(ctx context.Context, in VerifyInput) (*Verification, error)
	LookupOrder(ctx context.Context, orderID string) (*Verification, error)
	ParseWebhook(ctx context.Context, body []byte, h http.Header) (*WebhookEvent, error)
	Refund(ctx context.Context, r RefundRequest) (*RefundResult, error)
}
