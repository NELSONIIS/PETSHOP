package security

import (
	"strings"
	"testing"
	"time"
)

func TestPasswordHashing(t *testing.T) {
	h, err := HashPassword("Correct-horse-42")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(h, "$argon2id$") {
		t.Fatalf("unexpected hash format %q", h)
	}
	if !VerifyPassword("Correct-horse-42", h) || VerifyPassword("correct-horse-42", h) || VerifyPassword("x", "garbage") {
		t.Fatal("password verification incorrect")
	}
	h2, _ := HashPassword("Correct-horse-42")
	if h == h2 {
		t.Fatal("hashes must be salted")
	}
}

func TestTOTP(t *testing.T) {
	// RFC 6238 test vector (SHA1, secret "12345678901234567890", T=59 -> 94287082 -> last 6 digits 287082)
	secret := "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
	if got := TOTPCode(secret, time.Unix(59, 0)); got != "287082" {
		t.Fatalf("RFC 6238 vector: got %s", got)
	}
	now := time.Now()
	if !VerifyTOTP(secret, TOTPCode(secret, now.Add(-30*time.Second)), now) {
		t.Fatal("previous step should be accepted (clock drift)")
	}
	if VerifyTOTP(secret, TOTPCode(secret, now.Add(-120*time.Second)), now) {
		t.Fatal("old codes must be rejected")
	}
}

func TestBox(t *testing.T) {
	b, err := NewBox("MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=")
	if err != nil {
		t.Fatal(err)
	}
	enc, _ := b.Seal("secret")
	if out, err := b.Open(enc); err != nil || out != "secret" {
		t.Fatal("round trip failed")
	}
	if _, err := b.Open(enc[:len(enc)-4] + "AAAA"); err == nil {
		t.Fatal("tampered ciphertext must fail")
	}
	if _, err := NewBox("c2hvcnQ="); err == nil {
		t.Fatal("short keys must be rejected")
	}
}

func TestNumericCode(t *testing.T) {
	for i := 0; i < 100; i++ {
		if c := NumericCode(6); len(c) != 6 {
			t.Fatalf("bad code %q", c)
		}
	}
}
