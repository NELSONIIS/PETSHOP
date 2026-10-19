// Package httpx holds HTTP helpers shared by every module: response envelope,
// typed API errors, strict JSON decoding, validation and pagination.
package httpx

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strconv"
)

type ctxKey int

const requestIDKey ctxKey = iota

func WithRequestID(ctx context.Context, id string) context.Context {
	return context.WithValue(ctx, requestIDKey, id)
}
func RequestID(ctx context.Context) string {
	s, _ := ctx.Value(requestIDKey).(string)
	return s
}

// Stable machine-readable error codes (documented in the OpenAPI spec).
const (
	CodeValidation           = "validation_failed"
	CodeBadRequest           = "bad_request"
	CodeUnauthorized         = "unauthorized"
	CodeForbidden            = "forbidden"
	CodeNotFound             = "not_found"
	CodeConflict             = "conflict"
	CodeRateLimited          = "rate_limited"
	CodeMembershipRequired   = "membership_required"
	CodeSubscriptionRequired = "subscription_required"
	CodeLimitReached         = "limit_reached"
	CodeVerificationRequired = "verification_required"
	CodePaymentFailed        = "payment_failed"
	CodeMFARequired          = "mfa_required"
	CodeAccountSuspended     = "account_suspended"
	CodeMaintenance          = "maintenance"
	CodeInternal             = "internal_error"
)

type FieldError struct {
	Field   string `json:"field"`
	Message string `json:"message"`
}

type APIError struct {
	Status  int          `json:"-"`
	Code    string       `json:"code"`
	Message string       `json:"message"`
	Details []FieldError `json:"details,omitempty"`
	Extra   any          `json:"extra,omitempty"` // e.g. suggested plan for membership_required
}

func (e *APIError) Error() string { return e.Code + ": " + e.Message }

func Err(status int, code, msg string) *APIError {
	return &APIError{Status: status, Code: code, Message: msg}
}
func BadRequest(msg string) *APIError     { return Err(400, CodeBadRequest, msg) }
func Unauthorized(msg string) *APIError   { return Err(401, CodeUnauthorized, msg) }
func Forbidden(msg string) *APIError      { return Err(403, CodeForbidden, msg) }
func NotFound(what string) *APIError      { return Err(404, CodeNotFound, what+" not found") }
func Conflict(code, msg string) *APIError { return Err(409, code, msg) }
func Invalid(details ...FieldError) *APIError {
	return &APIError{Status: 422, Code: CodeValidation, Message: "Some fields are invalid", Details: details}
}

type Meta struct {
	Page       int `json:"page"`
	PerPage    int `json:"per_page"`
	Total      int `json:"total"`
	TotalPages int `json:"total_pages"`
}

type envelope struct {
	Data any   `json:"data"`
	Meta *Meta `json:"meta,omitempty"`
}
type errEnvelope struct {
	Error struct {
		*APIError
		RequestID string `json:"request_id"`
	} `json:"error"`
}

func JSON(w http.ResponseWriter, status int, data any) { write(w, status, envelope{Data: data}) }
func OK(w http.ResponseWriter, data any)               { JSON(w, http.StatusOK, data) }
func Created(w http.ResponseWriter, data any)          { JSON(w, http.StatusCreated, data) }
func NoContent(w http.ResponseWriter)                  { w.WriteHeader(http.StatusNoContent) }
func Paged(w http.ResponseWriter, data any, m Meta) {
	write(w, http.StatusOK, envelope{Data: data, Meta: &m})
}

func write(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// Fail renders err. Unknown errors become a generic 500 — internals are never leaked.
func Fail(w http.ResponseWriter, r *http.Request, err error) {
	var api *APIError
	if !errors.As(err, &api) {
		slog.ErrorContext(r.Context(), "unhandled error", "err", err, "path", r.URL.Path, "request_id", RequestID(r.Context()))
		api = Err(500, CodeInternal, "Something went wrong. Please try again.")
	}
	var env errEnvelope
	env.Error.APIError = api
	env.Error.RequestID = RequestID(r.Context())
	write(w, api.Status, env)
}

const maxBody = 1 << 20 // 1 MiB for JSON bodies

// Decode strictly decodes a JSON body: unknown fields and trailing data are rejected.
func Decode(w http.ResponseWriter, r *http.Request, dst any) error {
	r.Body = http.MaxBytesReader(w, r.Body, maxBody)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		var mbe *http.MaxBytesError
		switch {
		case errors.As(err, &mbe):
			return Err(413, CodeBadRequest, "Request body too large")
		case errors.Is(err, io.EOF):
			return BadRequest("Request body is required")
		default:
			return BadRequest("Malformed JSON: " + err.Error())
		}
	}
	if dec.More() {
		return BadRequest("Unexpected trailing data")
	}
	return nil
}

type Page struct{ Page, PerPage, Offset int }

// Pagination parses ?page&per_page with sane bounds.
func Pagination(r *http.Request, defPer, maxPer int) Page {
	q := r.URL.Query()
	page, _ := strconv.Atoi(q.Get("page"))
	per, _ := strconv.Atoi(q.Get("per_page"))
	if page < 1 {
		page = 1
	}
	if per < 1 {
		per = defPer
	}
	if per > maxPer {
		per = maxPer
	}
	return Page{Page: page, PerPage: per, Offset: (page - 1) * per}
}

func (p Page) Meta(total int) Meta {
	tp := (total + p.PerPage - 1) / p.PerPage
	return Meta{Page: p.Page, PerPage: p.PerPage, Total: total, TotalPages: tp}
}
