package auth

import (
	"net/http"
	"time"

	"petora/internal/authctx"
	"petora/internal/httpx"
)

const (
	CookieAccess  = "petora_at"
	CookieRefresh = "petora_rt"
	CookieCSRF    = "petora_csrf"
)

type Handler struct {
	svc *Service
	ip  func(*http.Request) string
}

func NewHandler(svc *Service, clientIP func(*http.Request) string) *Handler {
	return &Handler{svc: svc, ip: clientIP}
}

func (h *Handler) client(r *http.Request) ClientInfo {
	kind := "web"
	if r.Header.Get("X-Client") == "mobile" {
		kind = "mobile"
	}
	return ClientInfo{Kind: kind, UserAgent: r.UserAgent(), IP: h.ip(r)}
}

type authResponse struct {
	User         *User      `json:"user"`
	AccessToken  string     `json:"access_token,omitempty"`  // mobile only
	RefreshToken string     `json:"refresh_token,omitempty"` // mobile only
	ExpiresAt    *time.Time `json:"expires_at,omitempty"`
	CSRFToken    string     `json:"csrf_token,omitempty"` // web only (also set as a cookie)
}

// respond issues cookies for browsers and a JSON token pair for the mobile app.
func (h *Handler) respond(w http.ResponseWriter, r *http.Request, status int, u *User, t *Tokens) {
	ci := h.client(r)
	resp := authResponse{User: u, ExpiresAt: &t.ExpiresAt}
	if ci.Kind == "mobile" {
		resp.AccessToken, resp.RefreshToken = t.AccessToken, t.RefreshToken
	} else {
		resp.CSRFToken = h.setCookies(w, t)
	}
	httpx.JSON(w, status, resp)
}

func (h *Handler) setCookies(w http.ResponseWriter, t *Tokens) string {
	secure := h.svc.cfg.CookieSecure
	csrf := randomCSRF()
	http.SetCookie(w, &http.Cookie{Name: CookieAccess, Value: t.AccessToken, Path: "/", HttpOnly: true, Secure: secure,
		SameSite: http.SameSiteLaxMode, Expires: t.ExpiresAt.Add(time.Minute)})
	http.SetCookie(w, &http.Cookie{Name: CookieRefresh, Value: t.RefreshToken, Path: "/api/v1/auth", HttpOnly: true, Secure: secure,
		SameSite: http.SameSiteStrictMode, MaxAge: int(h.svc.cfg.RefreshTTL.Seconds())})
	http.SetCookie(w, &http.Cookie{Name: CookieCSRF, Value: csrf, Path: "/", HttpOnly: false, Secure: secure,
		SameSite: http.SameSiteLaxMode, MaxAge: int(h.svc.cfg.RefreshTTL.Seconds())})
	return csrf
}

func clearCookies(w http.ResponseWriter, secure bool) {
	for _, c := range []struct{ n, p string }{{CookieAccess, "/"}, {CookieRefresh, "/api/v1/auth"}, {CookieCSRF, "/"}} {
		http.SetCookie(w, &http.Cookie{Name: c.n, Value: "", Path: c.p, MaxAge: -1, HttpOnly: c.n != CookieCSRF, Secure: secure})
	}
}

func (h *Handler) Register(w http.ResponseWriter, r *http.Request) {
	var in RegisterInput
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	u, t, err := h.svc.Register(r.Context(), in, h.client(r))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	h.respond(w, r, http.StatusCreated, u, t)
}

func (h *Handler) Login(w http.ResponseWriter, r *http.Request) {
	var in LoginInput
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	u, t, err := h.svc.Login(r.Context(), in, h.client(r))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	h.respond(w, r, http.StatusOK, u, t)
}

func (h *Handler) Refresh(w http.ResponseWriter, r *http.Request) {
	var body struct {
		RefreshToken string `json:"refresh_token"`
	}
	ci := h.client(r)
	refresh := ""
	if ci.Kind == "mobile" {
		if err := httpx.Decode(w, r, &body); err != nil {
			httpx.Fail(w, r, err)
			return
		}
		refresh = body.RefreshToken
	} else if c, err := r.Cookie(CookieRefresh); err == nil {
		refresh = c.Value
	}
	u, t, err := h.svc.Refresh(r.Context(), refresh, ci)
	if err != nil {
		if ci.Kind == "web" {
			clearCookies(w, h.svc.cfg.CookieSecure)
		}
		httpx.Fail(w, r, err)
		return
	}
	h.respond(w, r, http.StatusOK, u, t)
}

func (h *Handler) Logout(w http.ResponseWriter, r *http.Request) {
	if p := authctx.From(r.Context()); p != nil {
		_ = h.svc.Logout(r.Context(), p.SessionID)
	}
	clearCookies(w, h.svc.cfg.CookieSecure)
	httpx.NoContent(w)
}

func (h *Handler) Me(w http.ResponseWriter, r *http.Request) {
	u, err := h.svc.Me(r.Context(), authctx.From(r.Context()))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.OK(w, u)
}

func (h *Handler) UpdateMe(w http.ResponseWriter, r *http.Request) {
	var in ProfileInput
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	u, err := h.svc.UpdateProfile(r.Context(), authctx.From(r.Context()), in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.OK(w, u)
}

func (h *Handler) VerifyEmail(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Code string `json:"code"`
	}
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	if err := h.svc.VerifyEmail(r.Context(), authctx.From(r.Context()).UserID, in.Code); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.NoContent(w)
}

func (h *Handler) ResendVerification(w http.ResponseWriter, r *http.Request) {
	if err := h.svc.ResendVerification(r.Context(), authctx.From(r.Context())); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.NoContent(w)
}

func (h *Handler) ForgotPassword(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email string `json:"email"`
	}
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	if err := h.svc.ForgotPassword(r.Context(), in.Email); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.OK(w, map[string]string{"message": "If an account exists for that email, a reset code has been sent."})
}

func (h *Handler) ResetPassword(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email    string `json:"email"`
		Code     string `json:"code"`
		Password string `json:"password"`
	}
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	if err := h.svc.ResetPassword(r.Context(), in.Email, in.Code, in.Password); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.NoContent(w)
}

func (h *Handler) ChangePassword(w http.ResponseWriter, r *http.Request) {
	var in struct {
		CurrentPassword string `json:"current_password"`
		NewPassword     string `json:"new_password"`
	}
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	if err := h.svc.ChangePassword(r.Context(), authctx.From(r.Context()), in.CurrentPassword, in.NewPassword); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.NoContent(w)
}

func (h *Handler) Sessions(w http.ResponseWriter, r *http.Request) {
	p := authctx.From(r.Context())
	out, err := h.svc.ListSessions(r.Context(), p.UserID, p.SessionID)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.OK(w, out)
}

func (h *Handler) RevokeSession(w http.ResponseWriter, r *http.Request, id string) {
	if err := h.svc.RevokeSession(r.Context(), authctx.From(r.Context()).UserID, id); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.NoContent(w)
}

func (h *Handler) MFASetup(w http.ResponseWriter, r *http.Request) {
	out, err := h.svc.MFASetup(r.Context(), authctx.From(r.Context()))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.OK(w, out)
}

func (h *Handler) MFAEnable(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Code string `json:"code"`
	}
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	if err := h.svc.MFAEnable(r.Context(), authctx.From(r.Context()), in.Code); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.NoContent(w)
}

func (h *Handler) DeleteAccount(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Password string `json:"password"`
	}
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	if err := h.svc.DeleteAccount(r.Context(), authctx.From(r.Context()), in.Password); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	clearCookies(w, h.svc.cfg.CookieSecure)
	httpx.NoContent(w)
}
