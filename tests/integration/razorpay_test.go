package integration

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"petora/internal/config"
	"petora/internal/httpserver"
	"petora/internal/security"
)

const (
	rzpKey     = "rzp_test_PETORAFAKE01"
	rzpSecret  = "rzp-test-key-secret"
	rzpWebhook = "rzp-test-webhook-secret"
)

// fakeRazorpay mimics the subset of https://razorpay.com/docs/api/ PETORA uses:
// POST /orders, GET /payments/{id}, POST /payments/{id}/capture, GET /orders/{id}/payments, POST /payments/{id}/refund.
type fakeRazorpay struct {
	mu       sync.Mutex
	orders   map[string]map[string]any
	payments map[string]map[string]any
	refunds  []map[string]any
	down     bool
	n        int
}

func newFakeRazorpay() *fakeRazorpay {
	return &fakeRazorpay{orders: map[string]map[string]any{}, payments: map[string]map[string]any{}}
}

func (f *fakeRazorpay) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if u, p, ok := r.BasicAuth(); !ok || u != rzpKey || p != rzpSecret {
		w.WriteHeader(401)
		_ = json.NewEncoder(w).Encode(map[string]any{"error": map[string]string{"code": "BAD_REQUEST_ERROR", "description": "Authentication failed"}})
		return
	}
	if f.down {
		w.WriteHeader(500)
		_ = json.NewEncoder(w).Encode(map[string]any{"error": map[string]string{"code": "SERVER_ERROR", "description": "We are facing some trouble"}})
		return
	}
	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	var body map[string]any
	_ = json.NewDecoder(r.Body).Decode(&body)
	write := func(v any) { _ = json.NewEncoder(w).Encode(v) }
	switch {
	case r.Method == "POST" && len(parts) == 1 && parts[0] == "orders":
		f.n++
		id := fmt.Sprintf("order_FAKE%04d", f.n)
		o := map[string]any{"id": id, "entity": "order", "amount": body["amount"], "currency": body["currency"], "receipt": body["receipt"], "status": "created", "notes": body["notes"]}
		f.orders[id] = o
		write(o)
	case r.Method == "GET" && len(parts) == 2 && parts[0] == "payments":
		if p, ok := f.payments[parts[1]]; ok {
			write(p)
			return
		}
		w.WriteHeader(400)
		write(map[string]any{"error": map[string]string{"code": "BAD_REQUEST_ERROR", "description": "The id provided does not exist"}})
	case r.Method == "POST" && len(parts) == 3 && parts[0] == "payments" && parts[2] == "capture":
		p := f.payments[parts[1]]
		p["status"] = "captured"
		write(p)
	case r.Method == "POST" && len(parts) == 3 && parts[0] == "payments" && parts[2] == "refund":
		f.n++
		rf := map[string]any{"id": fmt.Sprintf("rfnd_FAKE%04d", f.n), "payment_id": parts[1], "amount": body["amount"], "status": "processed"}
		f.refunds = append(f.refunds, rf)
		write(rf)
	case r.Method == "GET" && len(parts) == 3 && parts[0] == "orders" && parts[2] == "payments":
		items := []any{}
		for _, p := range f.payments {
			if p["order_id"] == parts[1] {
				items = append(items, p)
			}
		}
		write(map[string]any{"entity": "collection", "count": len(items), "items": items})
	default:
		w.WriteHeader(404)
	}
}

// pay simulates the customer completing Checkout: creates a payment on the order and returns the
// Checkout handler response (payment id + signature computed exactly as Razorpay does).
func (f *fakeRazorpay) pay(orderID, status string, amountOverride int64) (paymentID, signature string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.n++
	o := f.orders[orderID]
	amount := int64(o["amount"].(float64))
	if amountOverride > 0 {
		amount = amountOverride
	}
	paymentID = fmt.Sprintf("pay_FAKE%04d", f.n)
	f.payments[paymentID] = map[string]any{"id": paymentID, "entity": "payment", "order_id": orderID, "amount": amount, "currency": o["currency"], "status": status}
	return paymentID, security.HMACHex(rzpSecret, orderID+"|"+paymentID)
}

func (f *fakeRazorpay) webhook(t *testing.T, eventID, event, paymentID string) int {
	t.Helper()
	f.mu.Lock()
	p := f.payments[paymentID]
	f.mu.Unlock()
	body, _ := json.Marshal(map[string]any{"entity": "event", "event": event, "contains": []string{"payment"},
		"payload": map[string]any{"payment": map[string]any{"entity": p}}, "created_at": time.Now().Unix()})
	return rawPost(t, "/api/v1/webhooks/razorpay", body, "X-Razorpay-Signature", security.HMACHex(rzpWebhook, string(body)), "X-Razorpay-Event-Id", eventID)
}

// withRazorpayApp runs fn against a second app instance configured exactly like production
// (PAYMENT_PROVIDER=razorpay) except that the Razorpay API base points at the fake.
func withRazorpayApp(t *testing.T, fn func(f *fakeRazorpay)) {
	t.Helper()
	fake := newFakeRazorpay()
	api := httptest.NewServer(fake)
	defer api.Close()
	cfg, err := config.Load()
	must(err)
	cfg.PaymentProvider, cfg.RazorpayKeyID, cfg.RazorpayKeySecret, cfg.RazorpayWebhookSecret, cfg.RazorpayAPIBase = "razorpay", rzpKey, rzpSecret, rzpWebhook, api.URL
	rzApp, err := httpserver.NewApp(context.Background(), cfg)
	must(err)
	rzSrv := httptest.NewServer(rzApp.Router())
	prevApp, prevSrv := app, srv
	app, srv = rzApp, rzSrv
	defer func() { app, srv = prevApp, prevSrv; rzSrv.Close(); rzApp.Close() }()
	fn(fake)
}

func rzCheckout(t *testing.T, c *client, plan string) (paymentID, orderID string, amount int64) {
	t.Helper()
	co := c.must(201, c.do("POST", "/subscriptions/checkout", map[string]any{"plan_id": planID(t, plan), "idempotency_key": fmt.Sprintf("rzp-%s-%d", plan, time.Now().UnixNano())})).data()
	if co["provider"] != "razorpay" || co["provider_key_id"] != rzpKey || co["test_mode"] != true {
		t.Fatalf("checkout should hand the client the Razorpay public key and order: %v", co)
	}
	if strings.Contains(fmt.Sprint(co), rzpSecret) {
		t.Fatal("key secret leaked to client")
	}
	return co["payment"].(map[string]any)["id"].(string), co["provider_order_id"].(string), int64(co["amount_minor"].(float64))
}

func TestRazorpayEndToEnd(t *testing.T) {
	withRazorpayApp(t, func(fake *fakeRazorpay) {
		// /config exposes the public key id for Checkout.js / the Android SDK.
		cfg := newClient(t).must(200, newClient(t).do("GET", "/config", nil)).data()
		if cfg["payment_provider"] != "razorpay" || cfg["razorpay_key_id"] != rzpKey {
			t.Fatalf("config: %v", cfg)
		}
		// Test-mode-only endpoint must not exist with a real provider.
		if r := newClient(t).do("POST", "/payments/x/test-complete", map[string]any{"outcome": "success"}); r.Status != 401 && r.Status != 404 {
			t.Fatalf("test-complete must not be routed for razorpay, got %d", r.Status)
		}

		t.Run("checkout creates a server-priced Razorpay order", func(t *testing.T) {
			b := register(t, "buyer")
			pid, order, amount := rzCheckout(t, b, "buyer_basic")
			fake.mu.Lock()
			o := fake.orders[order]
			fake.mu.Unlock()
			if o["amount"].(float64) != 23482 || amount != 23482 || o["currency"] != "INR" || o["receipt"] != pid {
				t.Fatalf("order must carry server-computed amount and our payment id as receipt: %v", o)
			}
		})

		t.Run("signed checkout callback is verified with Razorpay then activates", func(t *testing.T) {
			b := register(t, "buyer")
			pid, order, _ := rzCheckout(t, b, "buyer_basic")
			payID, sig := fake.pay(order, "authorized", 0) // account without auto-capture
			// Forged signature: rejected, nothing activated.
			if r := b.do("POST", "/payments/"+pid+"/verify", map[string]any{"provider_order_id": order, "provider_payment_id": payID, "signature": strings.Repeat("0", 64)}); r.Status != 400 || r.code() != "payment_failed" {
				t.Fatalf("forged signature must be refused, got %d %s", r.Status, r.Raw)
			}
			// Signature for another order: rejected.
			if r := b.do("POST", "/payments/"+pid+"/verify", map[string]any{"provider_order_id": "order_OTHER", "provider_payment_id": payID, "signature": sig}); r.Status != 400 {
				t.Fatalf("mismatched order must be refused, got %d", r.Status)
			}
			p := b.must(200, b.do("POST", "/payments/"+pid+"/verify", map[string]any{"provider_order_id": order, "provider_payment_id": payID, "signature": sig})).data()
			if p["status"] != "succeeded" {
				t.Fatalf("verified payment should succeed (after capture), got %v", p)
			}
			fake.mu.Lock()
			captured := fake.payments[payID]["status"]
			fake.mu.Unlock()
			if captured != "captured" {
				t.Fatal("authorised payment must be captured server-side")
			}
			if st := b.must(200, b.do("GET", "/subscriptions/current", nil)).data(); st["active"] != true {
				t.Fatal("membership should be active")
			}
			inv := b.must(200, b.do("GET", "/billing/invoices", nil)).list()
			if len(inv) != 1 || !strings.HasPrefix(inv[0].(map[string]any)["number"].(string), "TEST-PET/") {
				t.Fatalf("rzp_test_ payments must produce TEST- invoices: %v", inv)
			}
			// Re-verifying is a no-op.
			b.must(200, b.do("POST", "/payments/"+pid+"/verify", map[string]any{"provider_order_id": order, "provider_payment_id": payID, "signature": sig}))
		})

		t.Run("webhook activates when the browser never returns; duplicates ignored", func(t *testing.T) {
			b := register(t, "buyer")
			pid, order, _ := rzCheckout(t, b, "buyer_plus")
			payID, _ := fake.pay(order, "captured", 0)
			bad, _ := json.Marshal(map[string]any{"event": "payment.captured"})
			if code := rawPost(t, "/api/v1/webhooks/razorpay", bad, "X-Razorpay-Signature", "deadbeef", "X-Razorpay-Event-Id", "evt_x"); code != 400 {
				t.Fatalf("unsigned webhook must be 400, got %d", code)
			}
			for i := 0; i < 3; i++ {
				if code := fake.webhook(t, "evt_rzp_captured_1", "payment.captured", payID); code != 200 {
					t.Fatalf("webhook should be accepted, got %d", code)
				}
			}
			if code := fake.webhook(t, "evt_rzp_orderpaid_1", "order.paid", payID); code != 200 { // Razorpay also sends order.paid
				t.Fatalf("got %d", code)
			}
			if p := b.must(200, b.do("GET", "/payments/"+pid, nil)).data(); p["status"] != "succeeded" {
				t.Fatalf("webhook should settle the payment, got %v", p["status"])
			}
			var subs int
			must(app.DB.QueryRow(context.Background(), `SELECT count(*) FROM subscriptions WHERE user_id=$1`, b.userID).Scan(&subs))
			if subs != 1 {
				t.Fatalf("expected exactly one subscription, got %d", subs)
			}
		})

		t.Run("payment.failed webhook marks the payment failed", func(t *testing.T) {
			b := register(t, "buyer")
			pid, order, _ := rzCheckout(t, b, "buyer_basic")
			payID, _ := fake.pay(order, "failed", 0)
			fake.webhook(t, "evt_rzp_failed_1", "payment.failed", payID)
			if p := b.must(200, b.do("GET", "/payments/"+pid, nil)).data(); p["status"] != "failed" {
				t.Fatalf("expected failed, got %v", p["status"])
			}
		})

		t.Run("amount mismatch reported by Razorpay never activates", func(t *testing.T) {
			b := register(t, "buyer")
			pid, order, _ := rzCheckout(t, b, "buyer_basic")
			payID, sig := fake.pay(order, "captured", 100)
			p := b.must(200, b.do("POST", "/payments/"+pid+"/verify", map[string]any{"provider_order_id": order, "provider_payment_id": payID, "signature": sig})).data()
			if p["status"] == "succeeded" {
				t.Fatal("amount mismatch must not succeed")
			}
		})

		t.Run("reconciliation settles a payment with no callback and no webhook", func(t *testing.T) {
			b := register(t, "buyer")
			pid, order, _ := rzCheckout(t, b, "buyer_basic")
			fake.pay(order, "captured", 0)
			exec(t, `UPDATE payments SET created_at=now()-interval '10 minutes' WHERE id=$1`, pid)
			if _, err := app.Payments.Reconcile(context.Background()); err != nil {
				t.Fatal(err)
			}
			if p := b.must(200, b.do("GET", "/payments/"+pid, nil)).data(); p["status"] != "succeeded" {
				t.Fatalf("reconcile should settle, got %v", p["status"])
			}
		})

		t.Run("finance refund goes through Razorpay", func(t *testing.T) {
			b := register(t, "buyer")
			pid, order, amount := rzCheckout(t, b, "buyer_basic")
			payID, sig := fake.pay(order, "captured", 0)
			b.must(200, b.do("POST", "/payments/"+pid+"/verify", map[string]any{"provider_order_id": order, "provider_payment_id": payID, "signature": sig}))
			fin := staff(t, "finance")
			rf := fin.must(201, fin.do("POST", "/admin/payments/"+pid+"/refunds", map[string]any{"amount_minor": amount, "reason": "Customer asked within window", "idempotency_key": "rzp-refund-" + pid[:8]})).data()
			if rf["status"] != "succeeded" {
				t.Fatalf("processed refund expected, got %v", rf)
			}
			fake.mu.Lock()
			last := fake.refunds[len(fake.refunds)-1]
			fake.mu.Unlock()
			if last["payment_id"] != payID || last["amount"].(float64) != float64(amount) {
				t.Fatalf("Razorpay refund call wrong: %v", last)
			}
		})

		t.Run("Razorpay outage at checkout fails safely", func(t *testing.T) {
			b := register(t, "buyer")
			fake.mu.Lock()
			fake.down = true
			fake.mu.Unlock()
			r := b.do("POST", "/subscriptions/checkout", map[string]any{"plan_id": planID(t, "buyer_basic"), "idempotency_key": "rzp-outage-" + b.userID[:8]})
			fake.mu.Lock()
			fake.down = false
			fake.mu.Unlock()
			if r.Status != 502 || r.code() != "payment_failed" || !strings.Contains(r.Body["error"].(map[string]any)["message"].(string), "not been charged") {
				t.Fatalf("outage should be a clear 502, got %d %s", r.Status, r.Raw)
			}
		})
	})
}
