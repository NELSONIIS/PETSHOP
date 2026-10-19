package integration

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"testing"

	"petora/internal/payments"
)

// Scenarios 1–6, 14, 15: buyer journey, contact protection, enquiry delivery and IDOR protection.
func TestBuyerJourneyAndContactProtection(t *testing.T) {
	mod := staff(t, "moderator")
	seller := verifiedSeller(t, mod, "seller_pro")
	lid := publishedListing(t, seller, mod, "Labrador puppy for a loving home")

	// 1. Browse without paying.
	buyer := register(t, "buyer")
	if !publicIDs(t, "category=dogs")[lid] {
		t.Fatal("approved listing should be publicly searchable")
	}
	d := buyer.must(200, buyer.do("GET", "/pets/"+lid, nil)).data()
	if strings.Contains(string(mustJSON(d)), "9811112222") {
		t.Fatal("listing detail leaked seller phone")
	}
	if d["contact"].(map[string]any)["unlocked"] != false || d["disclaimer"] == "" {
		t.Fatalf("expected locked contact + disclaimer: %v", d["contact"])
	}

	// 2. Contact without membership → 402, no contact data in the error. 15. Anonymous → 401.
	r := buyer.do("POST", "/pets/"+lid+"/contact-unlock", nil)
	if r.Status != 402 || r.code() != "membership_required" || strings.Contains(string(r.Raw), "9811112222") {
		t.Fatalf("expected 402 membership_required without contact data, got %d %s", r.Status, r.Raw)
	}
	if plans := r.Body["error"].(map[string]any)["extra"].(map[string]any)["suggested_plans"].([]any); len(plans) == 0 {
		t.Fatal("402 should suggest buyer plans")
	}
	anon := newClient(t)
	if r := anon.do("POST", "/pets/"+lid+"/contact-unlock", nil); r.Status != 401 || strings.Contains(string(r.Raw), "9811112222") {
		t.Fatalf("anonymous unlock must be 401, got %d", r.Status)
	}
	if r := seller.do("POST", "/pets/"+lid+"/contact-unlock", nil); r.Status != 403 {
		t.Fatalf("sellers cannot use buyer unlock, got %d", r.Status)
	}
	if r := buyer.do("POST", "/pets/"+lid+"/enquiries", map[string]any{"message": "Hello, is he available?"}); r.Status != 402 {
		t.Fatalf("enquiry without membership should be 402, got %d", r.Status)
	}

	// 3+4. Checkout in test mode; idempotent replay; backend activates entitlement.
	key := "buyer-checkout-key-0001-" + buyer.userID[:8]
	co1 := buyer.must(201, buyer.do("POST", "/subscriptions/checkout", map[string]any{"plan_id": planID(t, "buyer_basic"), "idempotency_key": key})).data()
	co2 := buyer.must(201, buyer.do("POST", "/subscriptions/checkout", map[string]any{"plan_id": planID(t, "buyer_basic"), "idempotency_key": key})).data()
	pid := co1["payment"].(map[string]any)["id"].(string)
	if co2["payment"].(map[string]any)["id"] != pid {
		t.Fatal("idempotent checkout replay must return the same payment")
	}
	pay := co1["payment"].(map[string]any)
	if pay["amount_minor"].(float64) != 19900+3582 || pay["tax_minor"].(float64) != 3582 {
		t.Fatalf("server-side pricing wrong: %v", pay)
	}
	// verify endpoint must not succeed a test payment from client data alone
	v := buyer.must(200, buyer.do("POST", "/payments/"+pid+"/verify", map[string]any{"provider_payment_id": "fake", "signature": "fake"})).data()
	if v["status"] == "succeeded" {
		t.Fatal("client-supplied verify data must never succeed a payment")
	}
	if st := buyer.must(200, buyer.do("GET", "/subscriptions/current", nil)).data(); st["active"] != false {
		t.Fatal("membership must not be active before verified payment")
	}
	buyer.must(200, buyer.do("POST", "/payments/"+pid+"/test-complete", map[string]any{"outcome": "success"}))
	buyer.must(200, buyer.do("POST", "/payments/"+pid+"/test-complete", map[string]any{"outcome": "success"})) // repeat: no-op
	st := buyer.must(200, buyer.do("GET", "/subscriptions/current", nil)).data()
	if st["active"] != true {
		t.Fatalf("membership should be active: %v", st)
	}
	var subs int
	must(app.DB.QueryRow(context.Background(), `SELECT count(*) FROM subscriptions WHERE user_id=$1`, buyer.userID).Scan(&subs))
	if subs != 1 {
		t.Fatalf("expected exactly one subscription, got %d", subs)
	}
	if inv := buyer.must(200, buyer.do("GET", "/billing/invoices", nil)).list(); len(inv) != 1 {
		t.Fatalf("expected one invoice, got %d", len(inv))
	}
	// Buying the same plan again mid-term is refused (no double charge).
	if r := buyer.do("POST", "/subscriptions/checkout", map[string]any{"plan_id": planID(t, "buyer_basic"), "idempotency_key": "another-key-00000001"}); r.Status != 409 || r.code() != "already_subscribed" {
		t.Fatalf("expected already_subscribed, got %d %s", r.Status, r.Raw)
	}

	// 5. Unlock contact; repeating does not consume another unlock.
	c1 := buyer.must(200, buyer.do("POST", "/pets/"+lid+"/contact-unlock", nil)).data()
	if c1["phone"] != "+919811112222" || c1["remaining_unlocks"].(float64) != 9 {
		t.Fatalf("unexpected contact: %v", c1)
	}
	c2 := buyer.must(200, buyer.do("POST", "/pets/"+lid+"/contact-unlock", nil)).data()
	if c2["remaining_unlocks"].(float64) != 9 {
		t.Fatal("repeat unlock must not consume allowance")
	}
	if d := buyer.must(200, buyer.do("GET", "/pets/"+lid, nil)).data(); d["contact"].(map[string]any)["unlocked"] != true {
		t.Fatal("detail should report unlocked")
	}

	// 5. Enquiry; duplicate detection. 6. Seller receives it and replies.
	e := buyer.must(201, buyer.do("POST", "/pets/"+lid+"/enquiries", map[string]any{"message": "Hello! Is he still available this weekend?"})).data()
	eid := e["id"].(string)
	dup := buyer.do("POST", "/pets/"+lid+"/enquiries", map[string]any{"message": "Hello again, any update?"})
	if dup.Status != 409 || dup.Body["error"].(map[string]any)["extra"].(map[string]any)["enquiry_id"] != eid {
		t.Fatalf("duplicate enquiry should 409 with existing id, got %d %s", dup.Status, dup.Raw)
	}
	inbox := seller.must(200, seller.do("GET", "/seller/enquiries?unread=true", nil)).list()
	if cp := inbox[0].(map[string]any)["counterparty"].(map[string]any); cp["user_id"] != buyer.userID {
		t.Fatalf("seller should see buyer user_id for blocking: %v", cp)
	}
	if len(inbox) != 1 || inbox[0].(map[string]any)["id"] != eid {
		t.Fatalf("seller inbox should contain the enquiry: %v", inbox)
	}
	sd := seller.must(200, seller.do("GET", "/seller/enquiries/"+eid, nil)).data()
	if sd["status"] != "viewed" {
		t.Fatalf("seller viewing should mark viewed, got %v", sd["status"])
	}
	seller.must(201, seller.do("POST", "/seller/enquiries/"+eid+"/messages", map[string]any{"body": "Yes, come on Saturday at 11."}))
	bd := buyer.must(200, buyer.do("GET", "/buyer/enquiries/"+eid, nil)).data()
	if bd["status"] != "responded" || len(bd["messages"].([]any)) != 2 {
		t.Fatalf("buyer should see seller reply: %v", bd)
	}
	var notif int
	must(app.DB.QueryRow(context.Background(), `SELECT count(*) FROM notifications WHERE user_id=$1 AND kind='enquiry_reply'`, buyer.userID).Scan(&notif))
	if notif != 1 {
		t.Fatal("buyer should be notified of the reply")
	}

	// 14. Another buyer cannot read, reply to or close the enquiry; seller endpoints reject buyers.
	other := register(t, "buyer")
	for _, r := range []resp{
		other.do("GET", "/buyer/enquiries/"+eid, nil),
		other.do("POST", "/buyer/enquiries/"+eid+"/messages", map[string]any{"body": "intrusion"}),
		other.do("POST", "/buyer/enquiries/"+eid+"/close", nil),
	} {
		if r.Status != 404 {
			t.Fatalf("IDOR: expected 404, got %d %s", r.Status, r.Raw)
		}
	}
	if r := other.do("GET", "/seller/enquiries/"+eid, nil); r.Status != 403 {
		t.Fatalf("buyer on seller route should be 403, got %d", r.Status)
	}
	otherSeller := verifiedSeller(t, mod, "")
	if r := otherSeller.do("GET", "/seller/enquiries/"+eid, nil); r.Status != 404 {
		t.Fatalf("other seller must not read the enquiry, got %d", r.Status)
	}
	if r := otherSeller.do("PUT", "/seller/listings/"+lid, listingInput(t, "Hijacked title here")); r.Status != 404 {
		t.Fatalf("other seller must not edit the listing, got %d", r.Status)
	}
}

// Scenarios 7–11: seller onboarding, plan limits, moderation, expiry policy and restoration on renewal.
func TestSellerLifecycle(t *testing.T) {
	mod := staff(t, "moderator")
	s := register(t, "seller")
	// No subscription → cannot create listings.
	if r := s.do("POST", "/seller/listings", listingInput(t, "Beagle puppy available now")); r.Status != 402 || r.code() != "subscription_required" {
		t.Fatalf("expected subscription_required, got %d %s", r.Status, r.Raw)
	}
	// Verification requirements are enforced.
	if r := s.do("POST", "/seller/verification/submit", map[string]any{}); r.Status != 422 {
		t.Fatalf("submit without documents must fail, got %d", r.Status)
	}
	// Uploading a fake "PDF" that is really HTML is rejected by content sniffing.
	if r := s.do("POST", "/seller/documents", fileBody("file", "id.pdf", []byte("<html><script>alert(1)</script></html>"), map[string]string{"kind": "identity"})); r.Status != 422 {
		t.Fatalf("sniffed non-PDF must be rejected, got %d", r.Status)
	}
	s.must(200, s.do("PUT", "/seller/profile", map[string]any{"city": "Pune", "state": "Maharashtra", "contact_phone": "+919822223333"}))
	doc := s.must(201, s.do("POST", "/seller/documents", fileBody("file", "../../etc/passwd.pdf", pdfBytes, map[string]string{"kind": "identity"}))).data()
	if strings.Contains(doc["original_name"].(string), "/") {
		t.Fatal("document name must be sanitised")
	}
	// The document is private: no public media URL serves it.
	var key string
	must(app.DB.QueryRow(context.Background(), `SELECT storage_key FROM seller_documents WHERE id=$1`, doc["id"]).Scan(&key))
	if r := httpGet(t, "/media/"+key); r != 404 {
		t.Fatalf("private document must not be reachable via /media, got %d", r)
	}
	s.must(200, s.do("POST", "/seller/verification/submit", map[string]any{}))
	// Payment is not verification: buying a plan leaves verification pending.
	subscribe(t, s, "seller_starter")
	if v := s.must(200, s.do("GET", "/seller/verification", nil)).data(); v["status"] != "pending" {
		t.Fatalf("payment must not verify a seller, got %v", v["status"])
	}
	list := mod.must(200, mod.do("GET", "/admin/sellers/verifications?status=pending&per_page=100", nil)).list()
	for _, it := range list {
		if m := it.(map[string]any); m["user_email"] == s.email {
			docs := m["documents"].([]any)
			// staff can download it (audited)
			if code := authedGet(t, mod, "/api/v1/admin/sellers/documents/"+docs[0].(map[string]any)["id"].(string)+"/file"); code != 200 {
				t.Fatalf("moderator should download document, got %d", code)
			}
			mod.must(204, mod.do("POST", "/admin/sellers/verifications/"+m["id"].(string)+"/approve", nil))
		}
	}
	if v := s.must(200, s.do("GET", "/seller/verification", nil)).data(); v["status"] != "approved" {
		t.Fatalf("expected approved, got %v", v["status"])
	}

	// 9. Plan limit (starter = 3 live listings).
	var ids []string
	for i := 0; i < 3; i++ {
		ids = append(ids, s.must(201, s.do("POST", "/seller/listings", listingInput(t, fmt.Sprintf("Puppy number %d for adoption", i)))).data()["id"].(string))
	}
	if r := s.do("POST", "/seller/listings", listingInput(t, "One listing too many")); r.Status != 409 || r.code() != "limit_reached" {
		t.Fatalf("expected limit_reached, got %d %s", r.Status, r.Raw)
	}
	// Marking one sold frees a slot.
	s.must(200, s.do("PATCH", "/seller/listings/"+ids[2]+"/availability", map[string]any{"availability": "sold"}))
	s.must(201, s.do("POST", "/seller/listings", listingInput(t, "Fresh slot after sale")))

	// 10. Moderation: submission checklist, pending is not public, approval publishes.
	lid := ids[0]
	if r := s.do("POST", "/seller/listings/"+lid+"/submit", nil); r.Status != 422 {
		t.Fatalf("submit without a photo must fail, got %d", r.Status)
	}
	img := s.must(201, s.do("POST", "/seller/listings/"+lid+"/images", fileBody("file", "p.png", pngBytes(500, 400), nil))).data()
	if !strings.HasSuffix(img["large"].(string), "_large.jpg") || img["is_cover"] != true {
		t.Fatalf("image variants not generated: %v", img)
	}
	if r := s.do("POST", "/seller/listings/"+lid+"/images", fileBody("file", "x.png", []byte("GIF89a not really"), nil)); r.Status != 422 {
		t.Fatalf("non-image upload must be rejected, got %d", r.Status)
	}
	s.must(200, s.do("POST", "/seller/listings/"+lid+"/submit", nil))
	if publicIDs(t, "")[lid] {
		t.Fatal("pending listing must not be public")
	}
	if r := newClient(t).do("GET", "/pets/"+lid, nil); r.Status != 404 {
		t.Fatalf("pending listing detail must 404 publicly, got %d", r.Status)
	}
	mod.must(204, mod.do("POST", "/admin/listings/"+lid+"/approve", nil))
	if !publicIDs(t, "")[lid] {
		t.Fatal("approved listing should be public")
	}
	// Editing an approved listing sends it back to moderation.
	s.must(200, s.do("PUT", "/seller/listings/"+lid, listingInput(t, "Edited title after approval")))
	if publicIDs(t, "")[lid] {
		t.Fatal("edited listing must leave public search until re-approved")
	}
	mod.must(204, mod.do("POST", "/admin/listings/"+lid+"/approve", nil))

	// 11. Subscription expiry: grace (listings visible) → expired (listings hidden) → renew (restored).
	ctx := context.Background()
	exec(t, `UPDATE subscriptions SET current_period_end=now()-interval '1 minute', grace_ends_at=now()+interval '2 days' WHERE user_id=$1 AND status='active'`, s.userID)
	if _, err := app.Subs.SweepExpiry(ctx); err != nil {
		t.Fatal(err)
	}
	if st := s.must(200, s.do("GET", "/subscriptions/current", nil)).data(); st["subscription"].(map[string]any)["status"] != "grace" {
		t.Fatalf("expected grace, got %v", st)
	}
	if !publicIDs(t, "")[lid] {
		t.Fatal("listings stay visible during grace")
	}
	exec(t, `UPDATE subscriptions SET grace_ends_at=now()-interval '1 minute' WHERE user_id=$1 AND status='grace'`, s.userID)
	if _, err := app.Subs.SweepExpiry(ctx); err != nil {
		t.Fatal(err)
	}
	if publicIDs(t, "")[lid] {
		t.Fatal("listings must be hidden after the subscription expires")
	}
	ol := s.must(200, s.do("GET", "/seller/listings/"+lid, nil)).data()
	if ol["status"] != "expired" || ol["expired_reason"] != "subscription" {
		t.Fatalf("listing should be expired by subscription: %v %v", ol["status"], ol["expired_reason"])
	}
	if r := s.do("POST", "/seller/listings", listingInput(t, "Cannot create while expired")); r.Status != 402 {
		t.Fatalf("expired seller cannot create listings, got %d", r.Status)
	}
	subscribe(t, s, "seller_starter")
	if !publicIDs(t, "")[lid] {
		t.Fatal("renewal should restore subscription-expired listings")
	}
}

// Scenario 12: buyer contact retention policy after membership expiry (configurable).
func TestContactRetentionPolicy(t *testing.T) {
	mod := staff(t, "moderator")
	seller := verifiedSeller(t, mod, "seller_pro")
	lid := publishedListing(t, seller, mod, "Persian kitten looking for family")
	lid2 := publishedListing(t, seller, mod, "Second kitten looking for family")
	buyer := register(t, "buyer")
	subscribe(t, buyer, "buyer_basic")
	buyer.must(200, buyer.do("POST", "/pets/"+lid+"/contact-unlock", nil))
	exec(t, `UPDATE subscriptions SET current_period_end=now()-interval '1 minute', grace_ends_at=now()-interval '1 minute' WHERE user_id=$1`, buyer.userID)
	if _, err := app.Subs.SweepExpiry(context.Background()); err != nil {
		t.Fatal(err)
	}
	// Default policy: previously unlocked contacts are retained; new unlocks need a membership.
	buyer.must(200, buyer.do("POST", "/pets/"+lid+"/contact-unlock", nil))
	if r := buyer.do("POST", "/pets/"+lid2+"/contact-unlock", nil); r.Status != 402 {
		t.Fatalf("new unlock after expiry must be 402, got %d", r.Status)
	}
	// Policy switched by an admin: retained contacts are revoked.
	admin := staff(t, "super_admin")
	admin.must(204, admin.do("PUT", "/admin/settings/contacts.retain_after_expiry", map[string]any{"value": false}))
	if r := buyer.do("POST", "/pets/"+lid+"/contact-unlock", nil); r.Status != 402 {
		t.Fatalf("with retention off, expired buyer must get 402, got %d", r.Status)
	}
	if r := admin.do("PUT", "/admin/settings/contacts.retain_after_expiry", map[string]any{"value": "yes"}); r.Status != 422 {
		t.Fatalf("setting type must be enforced, got %d", r.Status)
	}
	admin.must(204, admin.do("PUT", "/admin/settings/contacts.retain_after_expiry", map[string]any{"value": true}))
}

// Scenario 13: duplicate (and forged) webhooks never double-activate.
func TestWebhookIdempotency(t *testing.T) {
	buyer := register(t, "buyer")
	co := buyer.must(201, buyer.do("POST", "/subscriptions/checkout", map[string]any{"plan_id": planID(t, "buyer_plus"), "idempotency_key": "webhook-test-key-" + buyer.userID[:8]})).data()
	pid := co["payment"].(map[string]any)["id"].(string)
	order := co["provider_order_id"].(string)
	amount := int64(co["amount_minor"].(float64))
	tm := app.Payments.Provider().(*payments.TestMode)
	send := func(evID string, amt int64, sign bool) int {
		body, _ := json.Marshal(map[string]any{"id": evID, "type": "payment.captured", "order_id": order, "payment_id": "pay_" + evID, "amount": amt, "currency": "INR"})
		sig := "bad"
		if sign {
			sig = tm.Sign(body)
		}
		return rawPost(t, "/api/v1/webhooks/testmode", body, "X-Test-Signature", sig)
	}
	if code := send("evt_forged", amount, false); code != 400 {
		t.Fatalf("unsigned webhook must be rejected, got %d", code)
	}
	if code := send("evt_short", amount-100, true); code != 200 {
		t.Fatalf("webhook should be accepted, got %d", code)
	}
	if st := buyer.must(200, buyer.do("GET", "/payments/"+pid, nil)).data(); st["status"] == "succeeded" {
		t.Fatal("amount mismatch must not activate")
	}
	for i := 0; i < 3; i++ {
		if code := send("evt_paid_1", amount, true); code != 200 {
			t.Fatalf("duplicate deliveries must be acknowledged, got %d", code)
		}
	}
	if code := send("evt_paid_2", amount, true); code != 200 { // distinct event, same payment
		t.Fatalf("got %d", code)
	}
	var subs, events int
	must(app.DB.QueryRow(context.Background(), `SELECT count(*) FROM subscriptions WHERE user_id=$1`, buyer.userID).Scan(&subs))
	must(app.DB.QueryRow(context.Background(), `SELECT count(*) FROM payment_webhook_events WHERE event_id='evt_paid_1'`).Scan(&events))
	if subs != 1 || events != 1 {
		t.Fatalf("expected 1 subscription and 1 stored event, got %d and %d", subs, events)
	}
	if st := buyer.must(200, buyer.do("GET", "/payments/"+pid, nil)).data(); st["status"] != "succeeded" {
		t.Fatalf("payment should be succeeded, got %v", st["status"])
	}
}

// Scenario 16 + MFA: permissions gate refunds and configuration.
func TestAdminPermissions(t *testing.T) {
	buyer := register(t, "buyer")
	pid := subscribe(t, buyer, "buyer_basic")
	mod := staff(t, "moderator")
	fin := staff(t, "finance")
	refund := map[string]any{"amount_minor": 23482, "reason": "Customer requested refund", "idempotency_key": "refund-key-" + pid[:8]}

	if r := mod.do("POST", "/admin/payments/"+pid+"/refunds", refund); r.Status != 403 {
		t.Fatalf("moderator must not refund, got %d", r.Status)
	}
	if r := mod.do("PUT", "/admin/settings/listings.auto_approve", map[string]any{"value": true}); r.Status != 403 {
		t.Fatalf("moderator must not change settings, got %d", r.Status)
	}
	if r := fin.do("POST", "/admin/plans", map[string]any{"code": "x", "audience": "buyer", "name": "X", "price_minor": 1, "billing_interval": "month"}); r.Status != 403 {
		t.Fatalf("finance must not create plans, got %d", r.Status)
	}
	if r := buyer.do("GET", "/admin/dashboard", nil); r.Status != 403 {
		t.Fatalf("buyer must not reach admin, got %d", r.Status)
	}
	if r := fin.do("POST", "/admin/payments/"+pid+"/refunds", map[string]any{"amount_minor": 99999999, "reason": "too much money", "idempotency_key": "over-refund-1"}); r.Status != 409 {
		t.Fatalf("over-refund must be refused, got %d", r.Status)
	}
	rf := fin.must(201, fin.do("POST", "/admin/payments/"+pid+"/refunds", refund)).data()
	again := fin.must(201, fin.do("POST", "/admin/payments/"+pid+"/refunds", refund)).data()
	if rf["id"] != again["id"] || rf["status"] != "succeeded" {
		t.Fatalf("refund should be idempotent and succeed in test mode: %v %v", rf, again)
	}
	if st := buyer.must(200, buyer.do("GET", "/subscriptions/current", nil)).data(); st["active"] != false {
		t.Fatal("full refund must end the membership")
	}
	var audits int
	must(app.DB.QueryRow(context.Background(), `SELECT count(*) FROM audit_logs WHERE action='refund.requested' AND entity_id=$1`, pid).Scan(&audits))
	if audits != 1 {
		t.Fatalf("refund must be audited once, got %d", audits)
	}
	// Dashboard metrics come from live queries.
	d := fin.must(200, fin.do("GET", "/admin/dashboard", nil)).data()
	if d["payments_succeeded"].(float64) < 1 || d["refunds_total_minor"].(float64) < 23482 {
		t.Fatalf("dashboard not reflecting data: %v", d)
	}

	// Staff without MFA cannot use the admin API.
	ctx := context.Background()
	email := uniqueEmail("nomfa")
	c := newClient(t)
	must(app.Auth.ChangePasswordForTest(ctx, email, password))
	d2 := c.must(200, c.do("POST", "/auth/login", map[string]any{"email": email, "password": password})).data()
	c.access = d2["access_token"].(string)
	if r := c.do("GET", "/admin/dashboard", nil); r.Status != 403 || r.code() != "mfa_required" {
		t.Fatalf("staff without MFA must get mfa_required, got %d %s", r.Status, r.Raw)
	}
}

// Sessions: refresh rotation, reuse detection, logout, brute-force lockout, CSRF.
func TestSessionSecurity(t *testing.T) {
	u := register(t, "buyer")
	old := u.refresh
	r := u.must(200, u.do("POST", "/auth/refresh", map[string]any{"refresh_token": old})).data()
	u.access, u.refresh = r["access_token"].(string), r["refresh_token"].(string)
	if u.refresh == old {
		t.Fatal("refresh token must rotate")
	}
	exec(t, `UPDATE sessions SET rotated_at=now()-interval '1 minute' WHERE user_id=$1`, u.userID)
	if r := u.do("POST", "/auth/refresh", map[string]any{"refresh_token": old}); r.Status != 401 {
		t.Fatalf("replayed refresh token must be rejected, got %d", r.Status)
	}
	if r := u.do("GET", "/me", nil); r.Status != 401 {
		t.Fatalf("reuse detection must revoke the session, got %d", r.Status)
	}

	// Lockout after repeated failures.
	v := register(t, "buyer")
	resetRateLimits()
	for i := 0; i < 5; i++ {
		v.do("POST", "/auth/login", map[string]any{"email": v.email, "password": "wrong-password-1"})
	}
	if r := v.do("POST", "/auth/login", map[string]any{"email": v.email, "password": password}); r.Status != 429 {
		t.Fatalf("account should be locked, got %d", r.Status)
	}

	// Cookie transport + CSRF double-submit.
	w := register(t, "buyer")
	resetRateLimits()
	web := &client{t: t, cookies: &cookieJar{}}
	lr := web.must(200, web.do("POST", "/auth/login", map[string]any{"email": w.email, "password": password})).data()
	if _, ok := lr["access_token"]; ok {
		t.Fatal("web login must not expose tokens in the body")
	}
	web.must(200, web.do("GET", "/me", nil))
	if r := web.do("PATCH", "/me", map[string]any{"name": "No CSRF header"}); r.Status != 403 {
		t.Fatalf("cookie request without CSRF header must be 403, got %d", r.Status)
	}
	web.csrf = lr["csrf_token"].(string)
	web.must(200, web.do("PATCH", "/me", map[string]any{"name": "With CSRF"}))
	if r := web.do("PATCH", "/me", map[string]any{"name": "Evil"}, "Origin", "https://evil.example"); r.Status != 403 {
		t.Fatalf("cross-origin request must be blocked, got %d", r.Status)
	}
	web.must(204, web.do("POST", "/auth/logout", nil))
	if r := web.do("GET", "/me", nil); r.Status != 401 {
		t.Fatalf("after logout /me must be 401, got %d", r.Status)
	}
}

// Suspended users/sellers and listings disappear from public surfaces immediately.
func TestSuspensionHidesContent(t *testing.T) {
	mod := staff(t, "moderator")
	admin := staff(t, "super_admin")
	s := verifiedSeller(t, mod, "seller_pro")
	lid := publishedListing(t, s, mod, "Golden retriever puppy female")
	mod.must(204, mod.do("POST", "/admin/listings/"+lid+"/suspend", map[string]any{"reason": "Suspicious duplicate photos"}))
	if publicIDs(t, "")[lid] {
		t.Fatal("suspended listing must vanish")
	}
	mod.must(204, mod.do("POST", "/admin/listings/"+lid+"/reinstate", nil))
	if !publicIDs(t, "")[lid] {
		t.Fatal("reinstated listing returns")
	}
	admin.must(204, admin.do("POST", "/admin/users/"+s.userID+"/suspend", map[string]any{"reason": "Fraud investigation"}))
	if publicIDs(t, "")[lid] {
		t.Fatal("suspended seller's listings must vanish")
	}
	if r := s.do("GET", "/me", nil); r.Status != 401 && r.Status != 403 {
		t.Fatalf("suspended user's session must stop working, got %d", r.Status)
	}
	if r := s.do("POST", "/auth/login", map[string]any{"email": s.email, "password": password}); r.code() != "account_suspended" {
		t.Fatalf("suspended login should say account_suspended, got %s", r.Raw)
	}
}

// Search filters, sorting and pagination metadata.
func TestSearchFilters(t *testing.T) {
	mod := staff(t, "moderator")
	s := verifiedSeller(t, mod, "seller_pro")
	cheap := publishedListing(t, s, mod, "Searchable shepherd budget")
	exec(t, `UPDATE pet_listings SET price_minor=500000 WHERE id=$1`, cheap)
	app.Listings.Invalidate(context.Background())
	c := newClient(t)
	r := c.must(200, c.do("GET", "/pets?q=shepherd&max_price=600000&sort=price_asc&per_page=5", nil))
	if !contains(r.list(), cheap) {
		t.Fatalf("text + price filter should find listing: %s", r.Raw)
	}
	if meta := r.Body["meta"].(map[string]any); meta["per_page"].(float64) != 5 {
		t.Fatalf("pagination meta missing: %v", meta)
	}
	if contains(c.must(200, c.do("GET", "/pets?q=shepherd&min_price=600000", nil)).list(), cheap) {
		t.Fatal("min_price filter not applied")
	}
	near := c.must(200, c.do("GET", "/pets?lat=18.52&lng=73.85&radius_km=10&sort=nearest", nil)).list()
	if !contains(near, cheap) {
		t.Fatal("radius filter should include nearby listing")
	}
	if contains(c.must(200, c.do("GET", "/pets?lat=28.61&lng=77.20&radius_km=50", nil)).list(), cheap) {
		t.Fatal("radius filter should exclude far listing")
	}
	if r := c.do("GET", "/pets?radius_km=10", nil); r.Status != 422 {
		t.Fatalf("radius without coordinates must 422, got %d", r.Status)
	}
	if r := c.do("GET", "/pets?q=%27%3B+DROP+TABLE+users%3B--", nil); r.Status != 200 {
		t.Fatalf("hostile query must be handled safely, got %d", r.Status)
	}
}

func contains(list []any, id string) bool {
	for _, it := range list {
		if it.(map[string]any)["id"] == id {
			return true
		}
	}
	return false
}

func mustJSON(v any) []byte { b, _ := json.Marshal(v); return b }

// Rate limiting on the login endpoint (requires Redis; skipped without it).
func TestLoginRateLimit(t *testing.T) {
	if !app.Cache.Enabled() {
		t.Skip("Redis not configured (TEST_REDIS_URL)")
	}
	resetRateLimits()
	c := newClient(t)
	var last int
	for i := 0; i < 11; i++ {
		last = c.do("POST", "/auth/login", map[string]any{"email": "nobody@example.test", "password": "whatever-123"}).Status
	}
	if last != 429 {
		t.Fatalf("11th login attempt within a minute should be 429, got %d", last)
	}
	resetRateLimits()
}
