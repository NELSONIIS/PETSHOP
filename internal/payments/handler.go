package payments

import (
	"io"
	"net/http"

	"github.com/go-chi/chi/v5"

	"petora/internal/authctx"
	"petora/internal/httpx"
	"petora/internal/subscriptions"
)

type Handler struct {
	svc  *Service
	subs *subscriptions.Service
}

func NewHandler(svc *Service, subs *subscriptions.Service) *Handler {
	return &Handler{svc: svc, subs: subs}
}

func (h *Handler) Plans(w http.ResponseWriter, r *http.Request) {
	aud := r.URL.Query().Get("audience")
	if aud != "" && aud != "buyer" && aud != "seller" {
		httpx.Fail(w, r, httpx.Invalid(httpx.FieldError{Field: "audience", Message: "must be buyer or seller"}))
		return
	}
	out, err := h.subs.ListPlans(r.Context(), aud, true)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.OK(w, out)
}

func (h *Handler) Current(w http.ResponseWriter, r *http.Request) {
	p := authctx.From(r.Context())
	if p.AccountType == "staff" {
		httpx.Fail(w, r, httpx.BadRequest("Staff accounts have no subscription"))
		return
	}
	st, err := h.subs.StatusFor(r.Context(), p.UserID, p.AccountType)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.OK(w, st)
}

func (h *Handler) Cancel(w http.ResponseWriter, r *http.Request) {
	p := authctx.From(r.Context())
	if err := h.subs.Cancel(r.Context(), p.UserID, chi.URLParam(r, "id")); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	st, err := h.subs.StatusFor(r.Context(), p.UserID, p.AccountType)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.OK(w, st)
}

func (h *Handler) Checkout(w http.ResponseWriter, r *http.Request) {
	var in struct {
		PlanID         string `json:"plan_id"`
		IdempotencyKey string `json:"idempotency_key"`
	}
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	out, err := h.svc.Checkout(r.Context(), authctx.From(r.Context()), in.PlanID, in.IdempotencyKey)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Created(w, out)
}

func (h *Handler) Get(w http.ResponseWriter, r *http.Request) {
	out, err := h.svc.Get(r.Context(), authctx.From(r.Context()).UserID, chi.URLParam(r, "id"))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.OK(w, out)
}

func (h *Handler) Verify(w http.ResponseWriter, r *http.Request) {
	var in VerifyBody
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	out, err := h.svc.Verify(r.Context(), authctx.From(r.Context()).UserID, chi.URLParam(r, "id"), in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.OK(w, out)
}

func (h *Handler) TestComplete(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Outcome string `json:"outcome"`
	}
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	out, err := h.svc.TestComplete(r.Context(), authctx.From(r.Context()).UserID, chi.URLParam(r, "id"), in.Outcome)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.OK(w, out)
}

func (h *Handler) Payments(w http.ResponseWriter, r *http.Request) {
	pg := httpx.Pagination(r, 20, 50)
	out, total, err := h.svc.List(r.Context(), authctx.From(r.Context()).UserID, pg)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Paged(w, out, pg.Meta(total))
}

func (h *Handler) Invoices(w http.ResponseWriter, r *http.Request) {
	pg := httpx.Pagination(r, 20, 50)
	out, total, err := h.svc.ListInvoices(r.Context(), authctx.From(r.Context()).UserID, pg)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Paged(w, out, pg.Meta(total))
}

func (h *Handler) Invoice(w http.ResponseWriter, r *http.Request) {
	out, err := h.svc.GetInvoice(r.Context(), authctx.From(r.Context()).UserID, chi.URLParam(r, "id"))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.OK(w, out)
}

// Webhook reads the RAW body (signature is computed over exact bytes), capped at 1 MiB.
func (h *Handler) Webhook(w http.ResponseWriter, r *http.Request) {
	if chi.URLParam(r, "provider") != h.svc.provider.Name() {
		httpx.Fail(w, r, httpx.NotFound("Webhook"))
		return
	}
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 1<<20))
	if err != nil {
		httpx.Fail(w, r, httpx.BadRequest("Unreadable body"))
		return
	}
	if err := h.svc.HandleWebhook(r.Context(), body, r.Header); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.OK(w, map[string]bool{"received": true})
}

// ---- admin ----

func (h *Handler) AdminRefund(w http.ResponseWriter, r *http.Request) {
	var in RefundInput
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	out, err := h.svc.Refund(r.Context(), authctx.From(r.Context()), chi.URLParam(r, "id"), in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Created(w, out)
}
