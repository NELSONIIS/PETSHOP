package payments

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"petora/internal/security"
)

func TestRazorpayCheckoutSignature(t *testing.T) {
	// Fake Razorpay API: returns a captured payment for pay_1 on order_1.
	api := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if u, p, _ := r.BasicAuth(); u != "rzp_test_key" || p != "secret" {
			w.WriteHeader(401)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"id": "pay_1", "order_id": "order_1", "amount": 23482, "currency": "INR", "status": "captured"})
	}))
	defer api.Close()
	rp := NewRazorpay("rzp_test_key", "secret", "whsec", api.URL)
	ctx := context.Background()

	good := security.HMACHex("secret", "order_1|pay_1")
	v, err := rp.VerifyCheckout(ctx, VerifyInput{OrderID: "order_1", PaymentID: "pay_1", Signature: good})
	if err != nil || v.Outcome != OutcomePaid || v.AmountMinor != 23482 {
		t.Fatalf("valid signature should verify: %+v %v", v, err)
	}
	if _, err := rp.VerifyCheckout(ctx, VerifyInput{OrderID: "order_1", PaymentID: "pay_1", Signature: "deadbeef"}); err != ErrBadSignature {
		t.Fatalf("bad signature must fail, got %v", err)
	}
	// Signature valid for a different order must not verify this order.
	other := security.HMACHex("secret", "order_2|pay_1")
	if _, err := rp.VerifyCheckout(ctx, VerifyInput{OrderID: "order_2", PaymentID: "pay_1", Signature: other}); err != ErrBadSignature {
		t.Fatalf("payment belonging to another order must fail, got %v", err)
	}
	if !rp.TestMode() {
		t.Fatal("rzp_test_ keys are test mode")
	}
}

func TestRazorpayWebhook(t *testing.T) {
	rp := NewRazorpay("rzp_live_x", "secret", "whsec", "")
	body := []byte(`{"event":"payment.captured","payload":{"payment":{"entity":{"id":"pay_9","order_id":"order_9","amount":1000,"currency":"INR","status":"captured"}}}}`)
	h := http.Header{}
	h.Set("X-Razorpay-Signature", security.HMACHex("whsec", string(body)))
	h.Set("X-Razorpay-Event-Id", "evt_1")
	ev, err := rp.ParseWebhook(context.Background(), body, h)
	if err != nil || ev.Kind != EventPaid || ev.ProviderOrderID != "order_9" || ev.AmountMinor != 1000 || ev.ID != "evt_1" {
		t.Fatalf("webhook parse: %+v %v", ev, err)
	}
	h.Set("X-Razorpay-Signature", security.HMACHex("whsec", string(body)+" "))
	if _, err := rp.ParseWebhook(context.Background(), body, h); err == nil {
		t.Fatal("tampered body must be rejected")
	}
}

func TestFormatINR(t *testing.T) {
	cases := map[int64]string{0: "0", 19900: "199", 23482: "234.82", 1199900: "11,999", 1234567800: "1,23,45,678"}
	for in, want := range cases {
		if got := formatINR(in); got != want {
			t.Errorf("formatINR(%d)=%s want %s", in, got, want)
		}
	}
}
