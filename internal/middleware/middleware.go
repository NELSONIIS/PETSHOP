// Package middleware holds HTTP middleware: request IDs, logging, recovery, security headers,
// origin/CSRF checks, authentication, authorisation and rate limiting.
package middleware

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"regexp"
	"runtime/debug"
	"strings"
	"time"

	"petora/internal/auth"
	"petora/internal/authctx"
	"petora/internal/cache"
	"petora/internal/config"
	"petora/internal/httpx"
	"petora/internal/settings"
)

var reqIDRe = regexp.MustCompile(`^[A-Za-z0-9._-]{8,64}$`)

func RequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get("X-Request-ID")
		if !reqIDRe.MatchString(id) {
			b := make([]byte, 8)
			_, _ = rand.Read(b)
			id = hex.EncodeToString(b)
		}
		w.Header().Set("X-Request-ID", id)
		next.ServeHTTP(w, r.WithContext(httpx.WithRequestID(r.Context(), id)))
	})
}

type ctxKey int

const (
	ipKey ctxKey = iota
	viaCookieKey
	authErrKey
)

// RealIP resolves the client address. X-Forwarded-For is trusted only when TRUST_PROXY=true
// (i.e. we sit behind our own Caddy, which overwrites the header rather than appending client input).
func RealIP(trust bool) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ip, _, err := net.SplitHostPort(r.RemoteAddr)
			if err != nil {
				ip = r.RemoteAddr
			}
			if trust {
				if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
					ip = strings.TrimSpace(strings.Split(xff, ",")[0])
				}
			}
			next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), ipKey, ip)))
		})
	}
}

func ClientIP(r *http.Request) string {
	s, _ := r.Context().Value(ipKey).(string)
	return s
}

type statusWriter struct {
	http.ResponseWriter
	status, n int
}

func (w *statusWriter) WriteHeader(c int) { w.status = c; w.ResponseWriter.WriteHeader(c) }
func (w *statusWriter) Write(b []byte) (int, error) {
	if w.status == 0 {
		w.status = 200
	}
	n, err := w.ResponseWriter.Write(b)
	w.n += n
	return n, err
}
func (w *statusWriter) Unwrap() http.ResponseWriter { return w.ResponseWriter }

func Logger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w}
		next.ServeHTTP(sw, r)
		if r.URL.Path == "/healthz" || r.URL.Path == "/readyz" {
			return
		}
		lvl := slog.LevelInfo
		if sw.status >= 500 {
			lvl = slog.LevelError
		}
		attrs := []any{"method", r.Method, "path", r.URL.Path, "status", sw.status, "bytes", sw.n,
			"ms", time.Since(start).Milliseconds(), "ip", ClientIP(r), "request_id", httpx.RequestID(r.Context())}
		if p := authctx.From(r.Context()); p != nil {
			attrs = append(attrs, "user_id", p.UserID)
		}
		slog.Log(r.Context(), lvl, "http", attrs...)
	})
}

func Recoverer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				if rec == http.ErrAbortHandler {
					panic(rec)
				}
				slog.ErrorContext(r.Context(), "panic", "panic", rec, "stack", string(debug.Stack()), "request_id", httpx.RequestID(r.Context()))
				httpx.Fail(w, r, httpx.Err(500, httpx.CodeInternal, "Something went wrong. Please try again."))
			}
		}()
		next.ServeHTTP(w, r)
	})
}

func SecurityHeaders(secure bool) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			h := w.Header()
			h.Set("X-Content-Type-Options", "nosniff")
			h.Set("X-Frame-Options", "DENY")
			h.Set("Referrer-Policy", "strict-origin-when-cross-origin")
			h.Set("Permissions-Policy", "camera=(), microphone=(), geolocation=(self), payment=(self)")
			h.Set("Cross-Origin-Opener-Policy", "same-origin")
			if secure {
				h.Set("Strict-Transport-Security", "max-age=63072000; includeSubDomains")
			}
			if strings.HasPrefix(r.URL.Path, "/api/") {
				h.Set("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")
				h.Set("Cache-Control", "no-store")
			} else {
				h.Set("Content-Security-Policy", "default-src 'self'; script-src 'self' https://checkout.razorpay.com; "+
					"style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https:; font-src 'self' data:; "+
					"connect-src 'self' https://*.razorpay.com; frame-src https://api.razorpay.com https://checkout.razorpay.com; "+
					"frame-ancestors 'none'; base-uri 'self'; form-action 'self'")
			}
			next.ServeHTTP(w, r)
		})
	}
}

func isUnsafe(m string) bool {
	return m != http.MethodGet && m != http.MethodHead && m != http.MethodOptions
}

func isAllowedOrigin(origin string, set map[string]bool, dev bool) bool {
	if set[origin] {
		return true
	}
	if dev && origin != "" {
		if u, err := url.Parse(origin); err == nil {
			h := u.Hostname()
			if h == "localhost" || h == "127.0.0.1" {
				return true
			}
		}
	}
	return false
}

// OriginCheck rejects cross-site state-changing requests. Browsers always send Origin on such requests;
// native mobile clients send none, so they pass (and cannot be CSRF'd as they hold no ambient cookies).
func OriginCheck(allowed []string, dev bool) func(http.Handler) http.Handler {
	set := map[string]bool{}
	for _, a := range allowed {
		set[a] = true
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if o := r.Header.Get("Origin"); o != "" && isUnsafe(r.Method) && !isAllowedOrigin(o, set, dev) && !strings.HasPrefix(r.URL.Path, "/api/v1/webhooks/") {
				httpx.Fail(w, r, httpx.Forbidden("Cross-origin request blocked"))
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// CORS answers pre-flights and echoes allowed origins (only needed for staging/dev SPAs on another port).
func CORS(allowed []string, dev bool) func(http.Handler) http.Handler {
	set := map[string]bool{}
	for _, a := range allowed {
		set[a] = true
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if o := r.Header.Get("Origin"); o != "" && isAllowedOrigin(o, set, dev) {
				h := w.Header()
				h.Set("Access-Control-Allow-Origin", o)
				h.Set("Access-Control-Allow-Credentials", "true")
				h.Add("Vary", "Origin")
				if r.Method == http.MethodOptions {
					h.Set("Access-Control-Allow-Methods", "GET,POST,PUT,PATCH,DELETE,OPTIONS")
					h.Set("Access-Control-Allow-Headers", "Authorization,Content-Type,X-CSRF-Token,X-Client,Idempotency-Key,X-Request-ID")
					h.Set("Access-Control-Max-Age", "600")
					w.WriteHeader(http.StatusNoContent)
					return
				}
			}
			next.ServeHTTP(w, r)
		})
	}
}

// Authenticate resolves the principal when credentials are present. It never rejects by itself:
// use RequireAuth for protected routes so public routes can still personalise responses.
func Authenticate(svc *auth.Service) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			token, viaCookie := "", false
			if h := r.Header.Get("Authorization"); strings.HasPrefix(h, "Bearer ") {
				token = strings.TrimSpace(h[7:])
			} else if c, err := r.Cookie(auth.CookieAccess); err == nil {
				token, viaCookie = c.Value, true
			}
			if token == "" {
				next.ServeHTTP(w, r)
				return
			}
			p, err := svc.Authenticate(r.Context(), token)
			ctx := r.Context()
			if err != nil {
				ctx = context.WithValue(ctx, authErrKey, err)
			} else {
				ctx = authctx.With(ctx, p)
				ctx = context.WithValue(ctx, viaCookieKey, viaCookie)
			}
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// CSRF applies the double-submit-cookie check to cookie-authenticated, state-changing requests.
func CSRF(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if via, _ := r.Context().Value(viaCookieKey).(bool); via && isUnsafe(r.Method) {
			c, err := r.Cookie(auth.CookieCSRF)
			h := r.Header.Get("X-CSRF-Token")
			if err != nil || c.Value == "" || h == "" || h != c.Value {
				httpx.Fail(w, r, httpx.Forbidden("Missing or invalid CSRF token"))
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}

func RequireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if authctx.From(r.Context()) == nil {
			if err, _ := r.Context().Value(authErrKey).(error); err != nil {
				httpx.Fail(w, r, err)
				return
			}
			httpx.Fail(w, r, httpx.Unauthorized("Authentication required"))
			return
		}
		next.ServeHTTP(w, r)
	})
}

// RequireAccountType allows only the listed account types (buyer | seller | staff).
func RequireAccountType(types ...string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			p := authctx.From(r.Context())
			for _, t := range types {
				if p != nil && p.AccountType == t {
					next.ServeHTTP(w, r)
					return
				}
			}
			httpx.Fail(w, r, httpx.Forbidden("You do not have access to this resource"))
		})
	}
}

// RequireStaffMFA protects the administration API: staff account AND an MFA-verified session.
func RequireStaffMFA(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := authctx.From(r.Context())
		if p == nil || !p.IsStaff() {
			httpx.Fail(w, r, httpx.Forbidden("You do not have access to this resource"))
			return
		}
		if !p.MFAEnabled || !p.MFAVerified {
			httpx.Fail(w, r, httpx.Err(403, httpx.CodeMFARequired, "Multi-factor authentication is required for administration"))
			return
		}
		next.ServeHTTP(w, r)
	})
}

// RequirePerm checks a single permission (granted through staff roles).
func RequirePerm(perm string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if !authctx.From(r.Context()).Can(perm) {
				httpx.Fail(w, r, httpx.Forbidden("You do not have permission to perform this action"))
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

func RequireVerifiedEmail(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if p := authctx.From(r.Context()); p == nil || !p.EmailVerified {
			httpx.Fail(w, r, httpx.Err(403, httpx.CodeVerificationRequired, "Please verify your email address first"))
			return
		}
		next.ServeHTTP(w, r)
	})
}

// RateLimit throttles by key (default: client IP, or user id when authenticated).
func RateLimit(c *cache.Cache, name string, limit int, window time.Duration) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			key := ClientIP(r)
			if p := authctx.From(r.Context()); p != nil {
				key = p.UserID
			}
			if ok, retry := c.Allow(r.Context(), name+":"+key, limit, window); !ok {
				w.Header().Set("Retry-After", itoa(int(retry.Seconds())+1))
				httpx.Fail(w, r, httpx.Err(429, httpx.CodeRateLimited, "Too many requests. Please slow down."))
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

func itoa(i int) string {
	if i <= 0 {
		return "1"
	}
	return fmtInt(i)
}
func fmtInt(i int) string {
	var b [12]byte
	p := len(b)
	for i > 0 {
		p--
		b[p] = byte('0' + i%10)
		i /= 10
	}
	return string(b[p:])
}

// Maintenance returns 503 for non-staff traffic when the maintenance_mode setting is on.
func Maintenance(st *settings.Service, cfg config.Config) func(http.Handler) http.Handler {
	exempt := []string{"/healthz", "/readyz", "/api/v1/auth/", "/api/v1/admin/", "/api/v1/webhooks/", "/api/v1/config"}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if st.Bool(r.Context(), "maintenance.enabled", false) {
				for _, e := range exempt {
					if strings.HasPrefix(r.URL.Path, e) {
						next.ServeHTTP(w, r)
						return
					}
				}
				if p := authctx.From(r.Context()); p != nil && p.IsStaff() {
					next.ServeHTTP(w, r)
					return
				}
				if strings.HasPrefix(r.URL.Path, "/api/") {
					httpx.Fail(w, r, httpx.Err(503, httpx.CodeMaintenance, st.String(r.Context(), "maintenance.message", "PETORA is undergoing maintenance. Please check back soon.")))
					return
				}
			}
			next.ServeHTTP(w, r)
		})
	}
}
