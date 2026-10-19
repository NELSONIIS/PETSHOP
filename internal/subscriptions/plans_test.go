package subscriptions

import (
	"encoding/json"
	"testing"
	"time"
)

func TestPlanPricing(t *testing.T) {
	now := time.Now()
	promo := int64(9900)
	past, future := now.Add(-time.Hour), now.Add(time.Hour)
	p := Plan{PriceMinor: 19900, TaxRateBps: 1800}
	p.compute(now)
	if p.EffectivePrice != 19900 || p.TaxMinor != 3582 || p.TotalMinor != 23482 {
		t.Fatalf("list price: %+v", p)
	}
	p.PromoPriceMinor, p.PromoEndsAt = &promo, &future
	p.compute(now)
	if p.EffectivePrice != 9900 || p.TaxMinor != 1782 {
		t.Fatalf("active promo: %+v", p)
	}
	p.PromoEndsAt = &past
	p.compute(now)
	if p.EffectivePrice != 19900 {
		t.Fatal("expired promo must not apply")
	}
	p.PromoEndsAt, p.PromoStartsAt = nil, &future
	p.compute(now)
	if p.EffectivePrice != 19900 {
		t.Fatal("future promo must not apply yet")
	}
}

func TestEntitlementLimits(t *testing.T) {
	s := Subscription{Entitlements: map[string]json.RawMessage{"listing_limit": json.RawMessage("3"), "contact_unlocks": json.RawMessage("null"), "analytics": json.RawMessage("true")}}
	if l, unl, g := s.Limit("listing_limit"); l != 3 || unl || !g {
		t.Fatal("numeric limit")
	}
	if _, unl, g := s.Limit("contact_unlocks"); !unl || !g {
		t.Fatal("null means unlimited")
	}
	if l, unl, g := s.Limit("enquiries"); l != 0 || unl || g {
		t.Fatal("absent means not granted")
	}
	if !s.Flag("analytics") || s.Flag("other") {
		t.Fatal("flags")
	}
}

func TestAddInterval(t *testing.T) {
	base := time.Date(2026, 1, 31, 0, 0, 0, 0, time.UTC)
	if got := addInterval(base, "year", 1); got.Year() != 2027 {
		t.Fatal("year")
	}
	if got := addInterval(base, "quarter", 1); got.Month() != time.May {
		t.Fatalf("quarter: %v", got)
	}
}

func TestPlanInputValidation(t *testing.T) {
	bad := PlanInput{Code: "x", Audience: "alien", Name: "X", PriceMinor: 100, BillingInterval: "week",
		Entitlements: map[string]json.RawMessage{"listing_limit": json.RawMessage(`-1`), "teleport": json.RawMessage(`1`)}}
	if err := bad.validate(true); err == nil {
		t.Fatal("invalid plan accepted")
	}
	promo := int64(500)
	over := PlanInput{Code: "y", Audience: "buyer", Name: "Y plan", PriceMinor: 100, BillingInterval: "month", PromoPriceMinor: &promo}
	if err := over.validate(true); err == nil {
		t.Fatal("promo above list price accepted")
	}
}
