package config

import (
	"strings"
	"testing"
)

func prodEnv(t *testing.T, extra map[string]string) error {
	t.Helper()
	base := map[string]string{"APP_ENV": "production", "APP_BASE_URL": "https://petora.in", "DATABASE_URL": "postgres://x", "REDIS_URL": "redis://x",
		"JWT_SECRET": strings.Repeat("s", 40), "DATA_ENCRYPTION_KEY": "k", "PAYMENT_PROVIDER": "razorpay",
		"RAZORPAY_KEY_ID": "rzp_live_abc", "RAZORPAY_KEY_SECRET": "s", "RAZORPAY_WEBHOOK_SECRET": "w"}
	for k, v := range extra {
		base[k] = v
	}
	for k, v := range base {
		t.Setenv(k, v)
	}
	_, err := Load()
	return err
}

func TestProductionRazorpayGuards(t *testing.T) {
	if err := prodEnv(t, nil); err != nil {
		t.Fatalf("valid live config rejected: %v", err)
	}
	cases := map[string]map[string]string{
		"test keys in production": {"RAZORPAY_KEY_ID": "rzp_test_abc"},
		"API base override":       {"RAZORPAY_API_BASE": "http://evil.example/v1"},
		"testmode in production":  {"PAYMENT_PROVIDER": "testmode"},
		"missing webhook secret":  {"RAZORPAY_WEBHOOK_SECRET": ""},
		"plain http":              {"APP_BASE_URL": "http://petora.in"},
	}
	for name, env := range cases {
		if err := prodEnv(t, env); err == nil {
			t.Errorf("%s: expected configuration error", name)
		}
	}
}
