package httpserver

import (
	"context"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"petora/internal/auth"
	"petora/internal/httpx"
	mw "petora/internal/middleware"
	"petora/internal/payments"
)

// Router builds the full HTTP surface: /healthz, /readyz, /api/v1/*, /media/*, and the SPA.
func (a *App) Router() http.Handler {
	h := handlers{a}
	ah := auth.NewHandler(a.Auth, mw.ClientIP)
	ph := payments.NewHandler(a.Payments, a.Subs)
	ad := a.Admin
	c := a.Cache
	perm := mw.RequirePerm

	r := chi.NewRouter()
	r.Use(mw.RequestID, mw.RealIP(a.Config.TrustProxy), mw.Logger, mw.Recoverer, mw.SecurityHeaders(a.Config.CookieSecure))

	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) })
	r.Get("/readyz", a.ready)

	if ph := a.Store.PublicHandler(); ph != nil {
		r.Handle("/media/*", http.StripPrefix("/media/", ph))
	}

	r.Route("/api/v1", func(r chi.Router) {
		r.Use(mw.CORS(a.Config.AllowedOrigins, !a.Config.IsProduction()), mw.OriginCheck(a.Config.AllowedOrigins, !a.Config.IsProduction()), mw.Authenticate(a.Auth), mw.CSRF, mw.Maintenance(a.Settings, a.Config))
		r.Use(mw.RateLimit(c, "api", 600, time.Minute)) // coarse global ceiling per IP/user

		// Public
		r.Get("/config", h.config)
		r.Get("/categories", h.categories)
		r.Get("/categories/{slug}", h.category)
		r.Get("/pets", h.searchPets)
		r.Get("/pets/{id}", h.pet)
		r.Get("/pets/{id}/similar", h.similar)
		r.With(mw.RateLimit(c, "view", 60, time.Minute)).Post("/pets/{id}/view", h.view)
		r.Get("/sellers", h.sellersList)
		r.Get("/sellers/{slug}", h.seller)
		r.Get("/sellers/{slug}/pets", h.sellerPets)
		r.Get("/subscription-plans", ph.Plans)
		r.Get("/legal/{slug}", h.legal)
		r.Get("/content/{key}", h.content)
		r.With(mw.RateLimit(c, "support", 5, time.Hour)).Post("/support/contact", h.supportContact)
		r.Post("/webhooks/{provider}", ph.Webhook)

		// Auth
		regLimit := 30
		if !a.Config.IsProduction() {
			regLimit = 200
		}
		r.Route("/auth", func(r chi.Router) {
			r.With(mw.RateLimit(c, "register", regLimit, time.Hour)).Post("/register", ah.Register)
			r.With(mw.RateLimit(c, "login", 10, time.Minute)).Post("/login", ah.Login)
			r.With(mw.RateLimit(c, "refresh", 60, time.Minute)).Post("/refresh", ah.Refresh)
			r.With(mw.RateLimit(c, "forgot", 5, time.Hour)).Post("/forgot-password", ah.ForgotPassword)
			r.With(mw.RateLimit(c, "reset", 10, time.Hour)).Post("/reset-password", ah.ResetPassword)
			r.Group(func(r chi.Router) {
				r.Use(mw.RequireAuth)
				r.Post("/logout", ah.Logout)
				r.With(mw.RateLimit(c, "verify", 10, 15*time.Minute)).Post("/verify-email", ah.VerifyEmail)
				r.With(mw.RateLimit(c, "resend", 5, time.Hour)).Post("/resend-verification", ah.ResendVerification)
				r.With(mw.RequireAccountType("staff")).Post("/mfa/setup", ah.MFASetup)
				r.With(mw.RequireAccountType("staff"), mw.RateLimit(c, "mfa", 10, 15*time.Minute)).Post("/mfa/enable", ah.MFAEnable)
			})
		})

		// Any authenticated user
		r.Group(func(r chi.Router) {
			r.Use(mw.RequireAuth)
			r.Get("/me", ah.Me)
			r.Patch("/me", ah.UpdateMe)
			r.With(mw.RateLimit(c, "chpw", 10, time.Hour)).Post("/me/change-password", ah.ChangePassword)
			r.Get("/me/sessions", ah.Sessions)
			r.Delete("/me/sessions/{id}", func(w http.ResponseWriter, r *http.Request) { ah.RevokeSession(w, r, chi.URLParam(r, "id")) })
			r.With(mw.RateLimit(c, "delete", 5, time.Hour)).Post("/me/delete-account", ah.DeleteAccount)
			r.Get("/notifications", h.notifications)
			r.Get("/notifications/unread-count", h.unreadCount)
			r.Post("/notifications/{id}/read", h.markRead)
			r.Post("/notifications/read-all", h.markAllRead)
			r.With(mw.RateLimit(c, "report", 20, time.Hour)).Post("/reports", h.report)
			r.Get("/blocks", h.blocks)
			r.Post("/blocks", h.block)
			r.Delete("/blocks/{userId}", h.unblock)
			r.Get("/disputes", h.disputes)
			r.With(mw.RateLimit(c, "dispute", 10, time.Hour)).Post("/disputes", h.openDispute)

			// Billing (buyers and sellers)
			r.Group(func(r chi.Router) {
				r.Use(mw.RequireAccountType("buyer", "seller"))
				r.Get("/subscriptions/current", ph.Current)
				r.With(mw.RequireVerifiedEmail, mw.RateLimit(c, "checkout", 20, time.Hour)).Post("/subscriptions/checkout", ph.Checkout)
				r.Post("/subscriptions/{id}/cancel", ph.Cancel)
				r.Get("/payments/{id}", ph.Get)
				r.With(mw.RateLimit(c, "verifypay", 30, time.Minute)).Post("/payments/{id}/verify", ph.Verify)
				if a.Payments.Provider().Name() == "testmode" && !a.Config.IsProduction() {
					r.Post("/payments/{id}/test-complete", ph.TestComplete)
				}
				r.Get("/billing/payments", ph.Payments)
				r.Get("/billing/invoices", ph.Invoices)
				r.Get("/billing/invoices/{id}", ph.Invoice)
			})

			// Buyer
			r.Group(func(r chi.Router) {
				r.Use(mw.RequireAccountType("buyer"))
				r.Get("/favourites", h.favourites)
				r.Post("/favourites", h.addFavourite)
				r.Delete("/favourites/{listingId}", h.removeFavourite)
				r.Get("/buyer/profile", h.buyerProfile)
				r.Put("/buyer/profile", h.putBuyerProfile)
				r.Get("/buyer/dashboard", h.buyerDashboard)
				r.Get("/buyer/recently-viewed", h.recentlyViewed)
				r.With(mw.RequireVerifiedEmail, mw.RateLimit(c, "unlock", 60, time.Hour)).Post("/pets/{id}/contact-unlock", h.contactUnlock)
				r.With(mw.RequireVerifiedEmail, mw.RateLimit(c, "enquiry", 10, time.Hour)).Post("/pets/{id}/enquiries", h.createEnquiry)
				r.Get("/buyer/enquiries", h.listEnquiries("buyer"))
				r.Get("/buyer/enquiries/{id}", h.getEnquiry("buyer"))
				r.With(mw.RateLimit(c, "msg", 30, time.Minute)).Post("/buyer/enquiries/{id}/messages", h.replyEnquiry("buyer"))
				r.Post("/buyer/enquiries/{id}/close", h.closeEnquiry("buyer"))
			})

			// Seller
			r.Route("/seller", func(r chi.Router) {
				r.Use(mw.RequireAccountType("seller"))
				r.Get("/dashboard", h.sellerDashboard)
				r.Get("/profile", h.sellerProfile)
				r.Put("/profile", h.putSellerProfile)
				r.With(mw.RateLimit(c, "logo", 20, time.Hour)).Post("/logo", h.sellerLogo)
				r.Get("/verification", h.verification)
				r.Post("/verification/submit", h.submitVerification)
				r.Get("/documents", h.documents)
				r.With(mw.RateLimit(c, "docupload", 30, time.Hour)).Post("/documents", h.uploadDocument)
				r.Delete("/documents/{id}", h.deleteDocument)
				r.Get("/listings", h.sellerListings)
				r.With(mw.RateLimit(c, "createlisting", 60, time.Hour)).Post("/listings", h.createListing)
				r.Get("/listings/{id}", h.sellerListing)
				r.Put("/listings/{id}", h.updateListing)
				r.Delete("/listings/{id}", h.archiveListing)
				r.With(mw.RequireVerifiedEmail).Post("/listings/{id}/submit", h.submitListing)
				r.Patch("/listings/{id}/availability", h.availability)
				r.With(mw.RateLimit(c, "upload", 120, time.Hour)).Post("/listings/{id}/images", h.uploadImage)
				r.Put("/listings/{id}/images/order", h.reorderImages)
				r.Put("/listings/{id}/images/{imageId}/cover", h.setCover)
				r.Delete("/listings/{id}/images/{imageId}", h.deleteImage)
				r.Get("/listings/{id}/analytics", h.listingAnalytics)
				r.Get("/enquiries", h.listEnquiries("seller"))
				r.Get("/enquiries/{id}", h.getEnquiry("seller"))
				r.With(mw.RateLimit(c, "msg", 30, time.Minute)).Post("/enquiries/{id}/messages", h.replyEnquiry("seller"))
				r.Post("/enquiries/{id}/close", h.closeEnquiry("seller"))
			})
		})

		// Administration: staff + MFA-verified session + per-route permission.
		r.Route("/admin", func(r chi.Router) {
			r.Use(mw.RequireAuth, mw.RequireStaffMFA)
			r.With(perm("dashboard.view")).Get("/dashboard", ad.Dashboard)
			r.With(perm("payments.view")).Get("/analytics/revenue", ad.Revenue)
			r.With(perm("users.view")).Get("/users", ad.Users)
			r.With(perm("users.view")).Get("/users/{id}", ad.User)
			r.With(perm("users.manage")).Post("/users/{id}/suspend", ad.Suspend)
			r.With(perm("users.manage")).Post("/users/{id}/reinstate", ad.Reinstate)
			r.With(perm("roles.manage")).Put("/users/{id}/roles", ad.SetRoles)
			r.With(perm("roles.manage")).Post("/staff", ad.CreateStaff)
			r.With(perm("roles.manage")).Get("/roles", ad.Roles)
			r.With(perm("sellers.verify")).Get("/sellers/verifications", h.adminVerifications)
			r.With(perm("sellers.verify")).Get("/sellers/verifications/{id}", h.adminVerification)
			r.With(perm("sellers.verify")).Post("/sellers/verifications/{id}/approve", h.adminDecide(true))
			r.With(perm("sellers.verify")).Post("/sellers/verifications/{id}/reject", h.adminDecide(false))
			r.With(perm("sellers.verify")).Get("/sellers/documents/{id}/file", h.adminDocument)
			r.With(perm("listings.moderate")).Get("/listings", ad.Listings)
			r.With(perm("listings.moderate")).Get("/listings/{id}", ad.Listing)
			r.With(perm("listings.moderate")).Post("/listings/{id}/approve", ad.Approve())
			r.With(perm("listings.moderate")).Post("/listings/{id}/reject", ad.Reject())
			r.With(perm("listings.moderate")).Post("/listings/{id}/suspend", ad.SuspendListing())
			r.With(perm("listings.moderate")).Post("/listings/{id}/reinstate", ad.ReinstateListing())
			r.With(perm("catalog.manage")).Get("/categories", h.adminCategories)
			r.With(perm("catalog.manage")).Post("/categories", h.adminCreateCategory)
			r.With(perm("catalog.manage")).Put("/categories/{id}", h.adminUpdateCategory)
			r.With(perm("catalog.manage")).Post("/categories/{id}/breeds", h.adminCreateBreed)
			r.With(perm("catalog.manage")).Put("/breeds/{id}", h.adminUpdateBreed)
			r.With(perm("plans.manage")).Get("/plans", h.adminPlans)
			r.With(perm("plans.manage")).Post("/plans", h.adminCreatePlan)
			r.With(perm("plans.manage")).Put("/plans/{id}", h.adminUpdatePlan)
			r.With(perm("subscriptions.view")).Get("/subscriptions", ad.Subscriptions)
			r.With(perm("payments.view")).Get("/payments", ad.Payments)
			r.With(perm("payments.view")).Get("/payments/{id}", ad.Payment)
			r.With(perm("refunds.create"), mw.RateLimit(c, "refund", 30, time.Hour)).Post("/payments/{id}/refunds", ph.AdminRefund)
			r.With(perm("reports.manage")).Get("/reports", ad.Reports)
			r.With(perm("reports.manage")).Post("/reports/{id}/resolve", ad.ResolveReport)
			r.With(perm("reports.manage")).Get("/disputes", ad.Disputes)
			r.With(perm("reports.manage")).Post("/disputes/{id}/resolve", ad.ResolveDispute)
			r.With(perm("reports.manage")).Get("/enquiries", ad.Enquiries)
			r.With(perm("settings.manage")).Get("/settings", ad.Settings)
			r.With(perm("settings.manage")).Put("/settings/{key}", ad.PutSetting)
			r.With(perm("content.manage")).Get("/content/{key}", ad.GetContent)
			r.With(perm("content.manage")).Put("/content/{key}", ad.PutContent)
			r.With(perm("content.manage")).Get("/legal", ad.Legal)
			r.With(perm("content.manage")).Post("/legal/{slug}", ad.PublishLegal)
			r.With(perm("content.manage")).Get("/notification-templates", ad.Templates)
			r.With(perm("content.manage")).Put("/notification-templates/{key}/{channel}", ad.PutTemplate)
			r.With(perm("audit.view")).Get("/audit-logs", ad.AuditLogs)
			r.With(perm("settings.manage")).Get("/jobs", ad.Jobs)
			r.With(perm("settings.manage")).Post("/jobs/{id}/retry", ad.RetryJob)
		})

		r.NotFound(func(w http.ResponseWriter, r *http.Request) { httpx.Fail(w, r, httpx.NotFound("Route")) })
		r.MethodNotAllowed(func(w http.ResponseWriter, r *http.Request) {
			httpx.Fail(w, r, httpx.Err(405, httpx.CodeBadRequest, "Method not allowed"))
		})
	})

	r.Get("/docs/openapi.yaml", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/yaml")
		http.ServeFile(w, r, "docs/openapi.yaml")
	})
	r.NotFound(a.spa().ServeHTTP)
	return r
}

func (a *App) ready(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	status := map[string]string{"database": "ok", "redis": "ok"}
	code := http.StatusOK
	if err := a.DB.Ping(ctx); err != nil {
		status["database"], code = "unavailable", http.StatusServiceUnavailable
	}
	if !a.Cache.Enabled() {
		status["redis"] = "disabled"
	} else if err := a.Cache.Ping(ctx); err != nil {
		status["redis"] = "degraded" // Redis is an optimisation; the API keeps working without it
	}
	httpx.JSON(w, code, status)
}

// spa serves the built React app: real files when they exist, index.html for client-side routes.
func (a *App) spa() http.Handler {
	dist := a.Config.FrontendDist
	index := filepath.Join(dist, "index.html")
	fs := http.FileServer(http.Dir(dist))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			httpx.Fail(w, r, httpx.NotFound("Route"))
			return
		}
		clean := filepath.Clean("/" + r.URL.Path)
		if strings.HasPrefix(clean, "/api/") {
			httpx.Fail(w, r, httpx.NotFound("Route"))
			return
		}
		p := filepath.Join(dist, clean)
		if st, err := os.Stat(p); err == nil && !st.IsDir() {
			if strings.HasPrefix(clean, "/assets/") {
				w.Header().Set("Cache-Control", "public, max-age=31536000, immutable") // hashed filenames
			}
			fs.ServeHTTP(w, r)
			return
		}
		if _, err := os.Stat(index); err != nil {
			http.Error(w, "Frontend not built. Run: cd frontend && npm ci && npm run build", http.StatusNotFound)
			return
		}
		w.Header().Set("Cache-Control", "no-cache")
		http.ServeFile(w, r, index)
	})
}
