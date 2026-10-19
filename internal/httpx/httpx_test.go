package httpx

import (
	"errors"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestValidators(t *testing.T) {
	var v V
	v.Email("email", "not-an-email")
	v.Password("password", "short")
	v.Password("p2", "longenoughbutnodigits")
	v.Phone("phone", "12ab")
	v.OneOf("role", "admin", "buyer", "seller")
	err := v.Err()
	var api *APIError
	if !errors.As(err, &api) || api.Status != 422 || len(api.Details) != 5 {
		t.Fatalf("expected 5 field errors, got %+v", err)
	}
	var ok V
	ok.Email("email", "a@b.in")
	ok.Password("password", "Correct-horse-42")
	ok.Phone("phone", "+919800000001")
	if ok.Err() != nil {
		t.Fatal(ok.Err())
	}
}

func TestDecodeStrict(t *testing.T) {
	var dst struct{ A string }
	r := httptest.NewRequest("POST", "/", strings.NewReader(`{"A":"x","role":"admin"}`))
	if err := Decode(httptest.NewRecorder(), r, &dst); err == nil {
		t.Fatal("unknown fields must be rejected (mass-assignment defence)")
	}
	r = httptest.NewRequest("POST", "/", strings.NewReader(`{"A":"x"} {"A":"y"}`))
	if err := Decode(httptest.NewRecorder(), r, &dst); err == nil {
		t.Fatal("trailing data must be rejected")
	}
}

func TestFailHidesInternalErrors(t *testing.T) {
	w := httptest.NewRecorder()
	Fail(w, httptest.NewRequest("GET", "/", nil), errors.New(`pq: relation "users" password=hunter2`))
	if w.Code != 500 || strings.Contains(w.Body.String(), "hunter2") || strings.Contains(w.Body.String(), "relation") {
		t.Fatalf("internal error leaked: %s", w.Body.String())
	}
}

func TestPagination(t *testing.T) {
	p := Pagination(httptest.NewRequest("GET", "/?page=3&per_page=500", nil), 20, 50)
	if p.PerPage != 50 || p.Offset != 100 {
		t.Fatalf("%+v", p)
	}
	if m := p.Meta(101); m.TotalPages != 3 {
		t.Fatalf("%+v", m)
	}
}
