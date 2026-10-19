// Package admin implements the administration API. Every route is mounted behind
// RequireStaffMFA + a specific permission; sensitive actions are audited in the same transaction.
package admin

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"petora/internal/audit"
	"petora/internal/auth"
	"petora/internal/authctx"
	"petora/internal/database"
	"petora/internal/httpx"
	"petora/internal/jobs"
	"petora/internal/listings"
	"petora/internal/notifications"
	"petora/internal/security"
	"petora/internal/settings"
)

type Handler struct {
	db       *database.DB
	auth     *auth.Service
	listings *listings.Service
	settings *settings.Service
}

func New(db *database.DB, a *auth.Service, ls *listings.Service, st *settings.Service) *Handler {
	return &Handler{db: db, auth: a, listings: ls, settings: st}
}

func fail(w http.ResponseWriter, r *http.Request, err error) { httpx.Fail(w, r, err) }

// statusParam treats ?status=all the same as no filter, consistently across admin lists.
func statusParam(r *http.Request) string {
	if s := r.URL.Query().Get("status"); s != "all" {
		return s
	}
	return ""
}

// ---------- dashboard ----------

type Dashboard struct {
	UsersTotal           int    `json:"users_total"`
	ActiveBuyers         int    `json:"active_buyers"`
	ActiveSellers        int    `json:"active_sellers"`
	PendingVerifications int    `json:"pending_verifications"`
	ListingsTotal        int    `json:"listings_total"`
	ListingsApproved     int    `json:"listings_approved"`
	PendingModeration    int    `json:"pending_moderation"`
	ActiveSubscriptions  int    `json:"active_subscriptions"`
	MRRMinor             int64  `json:"monthly_recurring_revenue_minor"`
	PaymentsSucceeded    int    `json:"payments_succeeded"`
	PaymentsFailed       int    `json:"payments_failed"`
	Revenue30dMinor      int64  `json:"revenue_30d_minor"`
	RefundsTotalMinor    int64  `json:"refunds_total_minor"`
	OpenReports          int    `json:"open_reports"`
	OpenDisputes         int    `json:"open_disputes"`
	DeadJobs             int    `json:"dead_jobs"`
	Currency             string `json:"currency"`
}

func (h *Handler) Dashboard(w http.ResponseWriter, r *http.Request) {
	var d Dashboard
	// MRR = live subscriptions' list price (ex-tax, from the payment snapshot) normalised to one month.
	err := h.db.QueryRow(r.Context(), `SELECT
		(SELECT count(*) FROM users WHERE status <> 'deleted'),
		(SELECT count(*) FROM users WHERE account_type='buyer' AND status='active'),
		(SELECT count(*) FROM users WHERE account_type='seller' AND status='active'),
		(SELECT count(*) FROM seller_verifications WHERE status='pending'),
		(SELECT count(*) FROM pet_listings WHERE deleted_at IS NULL),
		(SELECT count(*) FROM pet_listings WHERE deleted_at IS NULL AND status='approved'),
		(SELECT count(*) FROM pet_listings WHERE deleted_at IS NULL AND status='pending'),
		(SELECT count(*) FROM subscriptions WHERE status IN ('active','grace')),
		COALESCE((SELECT sum(p.subtotal_minor * 1.0 / (CASE pl.billing_interval WHEN 'year' THEN 12 WHEN 'quarter' THEN 3 ELSE 1 END * pl.interval_count))::bigint
			FROM subscriptions s JOIN payments p ON p.id=s.payment_id JOIN subscription_plans pl ON pl.id=s.plan_id WHERE s.status IN ('active','grace')), 0),
		(SELECT count(*) FROM payments WHERE status IN ('succeeded','refunded','partially_refunded')),
		(SELECT count(*) FROM payments WHERE status='failed'),
		COALESCE((SELECT sum(amount_minor - refunded_minor) FROM payments WHERE status IN ('succeeded','partially_refunded','refunded') AND paid_at > now() - interval '30 days'), 0),
		COALESCE((SELECT sum(amount_minor) FROM refunds WHERE status IN ('succeeded','processing')), 0),
		(SELECT count(*) FROM reports WHERE status IN ('open','reviewing')),
		(SELECT count(*) FROM disputes WHERE status IN ('open','under_review')),
		(SELECT count(*) FROM jobs WHERE status='dead')`).Scan(&d.UsersTotal, &d.ActiveBuyers, &d.ActiveSellers, &d.PendingVerifications, &d.ListingsTotal,
		&d.ListingsApproved, &d.PendingModeration, &d.ActiveSubscriptions, &d.MRRMinor, &d.PaymentsSucceeded, &d.PaymentsFailed, &d.Revenue30dMinor,
		&d.RefundsTotalMinor, &d.OpenReports, &d.OpenDisputes, &d.DeadJobs)
	if err != nil {
		fail(w, r, err)
		return
	}
	d.Currency = h.settings.String(r.Context(), "platform.currency", "INR")
	httpx.OK(w, d)
}

func (h *Handler) Revenue(w http.ResponseWriter, r *http.Request) {
	days, _ := strconv.Atoi(r.URL.Query().Get("days"))
	if days <= 0 || days > 365 {
		days = 30
	}
	rows, err := h.db.Query(r.Context(), `SELECT to_char(d,'YYYY-MM-DD'),
		COALESCE((SELECT sum(amount_minor) FROM payments p WHERE p.paid_at >= d AND p.paid_at < d + interval '1 day' AND p.status IN ('succeeded','partially_refunded','refunded')),0),
		COALESCE((SELECT count(*) FROM payments p WHERE p.paid_at >= d AND p.paid_at < d + interval '1 day' AND p.status IN ('succeeded','partially_refunded','refunded')),0)
		FROM generate_series(date_trunc('day', now()) - make_interval(days => $1 - 1), date_trunc('day', now()), interval '1 day') d ORDER BY d`, days)
	if err != nil {
		fail(w, r, err)
		return
	}
	defer rows.Close()
	type pt struct {
		Date     string `json:"date"`
		Revenue  int64  `json:"revenue_minor"`
		Payments int    `json:"payments"`
	}
	out := []pt{}
	for rows.Next() {
		var p pt
		if err := rows.Scan(&p.Date, &p.Revenue, &p.Payments); err != nil {
			fail(w, r, err)
			return
		}
		out = append(out, p)
	}
	httpx.OK(w, out)
}

// ---------- users ----------

type AdminUser struct {
	ID              string     `json:"id"`
	Email           string     `json:"email"`
	Phone           *string    `json:"phone"`
	Name            string     `json:"name"`
	AccountType     string     `json:"account_type"`
	Roles           []string   `json:"roles"`
	EmailVerified   bool       `json:"email_verified"`
	MFAEnabled      bool       `json:"mfa_enabled"`
	Status          string     `json:"status"`
	LastLoginAt     *time.Time `json:"last_login_at"`
	SuspendedReason *string    `json:"suspended_reason"`
	CreatedAt       time.Time  `json:"created_at"`
}

const userSelect = `SELECT u.id, u.email, u.phone, u.name, u.account_type,
	COALESCE((SELECT array_agg(role_code ORDER BY role_code) FROM user_roles WHERE user_id=u.id), '{}'),
	u.email_verified_at IS NOT NULL, u.mfa_enabled_at IS NOT NULL, u.status, u.last_login_at, u.suspended_reason, u.created_at FROM users u`

func scanUser(row pgx.Row) (*AdminUser, error) {
	var u AdminUser
	err := row.Scan(&u.ID, &u.Email, &u.Phone, &u.Name, &u.AccountType, &u.Roles, &u.EmailVerified, &u.MFAEnabled, &u.Status, &u.LastLoginAt, &u.SuspendedReason, &u.CreatedAt)
	return &u, err
}

func (h *Handler) Users(w http.ResponseWriter, r *http.Request) {
	pg := httpx.Pagination(r, 25, 100)
	q := r.URL.Query()
	where := ` WHERE ($1='' OR u.email ILIKE '%'||$1||'%' OR u.name ILIKE '%'||$1||'%' OR u.id::text=$1) AND ($2='' OR u.account_type=$2) AND ($3='' OR u.status=$3)`
	args := []any{strings.TrimSpace(q.Get("q")), q.Get("account_type"), q.Get("status")}
	var total int
	if err := h.db.QueryRow(r.Context(), `SELECT count(*) FROM users u`+where, args...).Scan(&total); err != nil {
		fail(w, r, err)
		return
	}
	rows, err := h.db.Query(r.Context(), userSelect+where+` ORDER BY u.created_at DESC LIMIT $4 OFFSET $5`, append(args, pg.PerPage, pg.Offset)...)
	if err != nil {
		fail(w, r, err)
		return
	}
	defer rows.Close()
	out := []AdminUser{}
	for rows.Next() {
		u, err := scanUser(rows)
		if err != nil {
			fail(w, r, err)
			return
		}
		out = append(out, *u)
	}
	httpx.Paged(w, out, pg.Meta(total))
}

func (h *Handler) User(w http.ResponseWriter, r *http.Request) {
	u, err := scanUser(h.db.QueryRow(r.Context(), userSelect+` WHERE u.id::text=$1`, chi.URLParam(r, "id")))
	if database.IsNoRows(err) {
		fail(w, r, httpx.NotFound("User"))
		return
	}
	if err != nil {
		fail(w, r, err)
		return
	}
	httpx.OK(w, u)
}

func (h *Handler) Suspend(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Reason string `json:"reason"`
	}
	if err := httpx.Decode(w, r, &in); err != nil {
		fail(w, r, err)
		return
	}
	var v httpx.V
	v.Length("reason", in.Reason, 5, 500)
	if err := v.Err(); err != nil {
		fail(w, r, err)
		return
	}
	id := chi.URLParam(r, "id")
	actor := authctx.From(r.Context())
	if id == actor.UserID {
		fail(w, r, httpx.BadRequest("You cannot suspend your own account"))
		return
	}
	err := h.db.InTx(r.Context(), func(tx pgx.Tx) error {
		var accType string
		var isSuper bool
		err := tx.QueryRow(r.Context(), `SELECT account_type, EXISTS (SELECT 1 FROM user_roles WHERE user_id=u.id AND role_code='super_admin') FROM users u WHERE id::text=$1 AND status='active' FOR UPDATE`, id).Scan(&accType, &isSuper)
		if database.IsNoRows(err) {
			return httpx.NotFound("Active user")
		}
		if err != nil {
			return err
		}
		if accType == "staff" && !actor.Can("roles.manage") {
			return httpx.Forbidden("Only administrators who manage roles can suspend staff")
		}
		if isSuper && !actor.HasRole("super_admin") {
			return httpx.Forbidden("Only a super administrator can suspend a super administrator")
		}
		if _, err := tx.Exec(r.Context(), `UPDATE users SET status='suspended', suspended_reason=$2, updated_at=now() WHERE id::text=$1`, id, in.Reason); err != nil {
			return err
		}
		if err := h.auth.RevokeAll(r.Context(), tx, id, ""); err != nil {
			return err
		}
		return audit.Log(r.Context(), tx, audit.Entry{Action: "user.suspended", EntityType: "user", EntityID: id, Metadata: map[string]any{"reason": in.Reason}})
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	h.listings.Invalidate(r.Context())
	httpx.NoContent(w)
}

func (h *Handler) Reinstate(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	err := h.db.InTx(r.Context(), func(tx pgx.Tx) error {
		tag, err := tx.Exec(r.Context(), `UPDATE users SET status='active', suspended_reason=NULL, updated_at=now() WHERE id::text=$1 AND status='suspended'`, id)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return httpx.NotFound("Suspended user")
		}
		return audit.Log(r.Context(), tx, audit.Entry{Action: "user.reinstated", EntityType: "user", EntityID: id})
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	h.listings.Invalidate(r.Context())
	httpx.NoContent(w)
}

var staffRoles = map[string]bool{"moderator": true, "finance": true, "support": true, "super_admin": true}

func validRoles(roles []string) error {
	if len(roles) == 0 {
		return httpx.Invalid(httpx.FieldError{Field: "roles", Message: "at least one staff role is required"})
	}
	for _, r := range roles {
		if !staffRoles[r] {
			return httpx.Invalid(httpx.FieldError{Field: "roles", Message: "unknown staff role " + r})
		}
	}
	return nil
}

func (h *Handler) SetRoles(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Roles []string `json:"roles"`
	}
	if err := httpx.Decode(w, r, &in); err != nil {
		fail(w, r, err)
		return
	}
	if err := validRoles(in.Roles); err != nil {
		fail(w, r, err)
		return
	}
	id := chi.URLParam(r, "id")
	actor := authctx.From(r.Context())
	grantsSuper := false
	for _, x := range in.Roles {
		grantsSuper = grantsSuper || x == "super_admin"
	}
	if grantsSuper && !actor.HasRole("super_admin") {
		fail(w, r, httpx.Forbidden("Only a super administrator can grant super_admin"))
		return
	}
	err := h.db.InTx(r.Context(), func(tx pgx.Tx) error {
		var accType string
		var hadSuper bool
		err := tx.QueryRow(r.Context(), `SELECT account_type, EXISTS (SELECT 1 FROM user_roles WHERE user_id=u.id AND role_code='super_admin') FROM users u WHERE id::text=$1 FOR UPDATE`, id).Scan(&accType, &hadSuper)
		if database.IsNoRows(err) {
			return httpx.NotFound("User")
		}
		if err != nil {
			return err
		}
		if accType != "staff" {
			return httpx.BadRequest("Staff roles can only be assigned to staff accounts")
		}
		if hadSuper && !grantsSuper {
			if !actor.HasRole("super_admin") {
				return httpx.Forbidden("Only a super administrator can remove super_admin")
			}
			var supers int
			if err := tx.QueryRow(r.Context(), `SELECT count(*) FROM user_roles ur JOIN users u ON u.id=ur.user_id WHERE ur.role_code='super_admin' AND u.status='active'`).Scan(&supers); err != nil {
				return err
			}
			if supers <= 1 {
				return httpx.Conflict(httpx.CodeConflict, "The last super administrator cannot be demoted")
			}
		}
		var before []string
		_ = tx.QueryRow(r.Context(), `SELECT COALESCE(array_agg(role_code),'{}') FROM user_roles WHERE user_id::text=$1`, id).Scan(&before)
		if _, err := tx.Exec(r.Context(), `DELETE FROM user_roles WHERE user_id::text=$1`, id); err != nil {
			return err
		}
		for _, role := range in.Roles {
			if _, err := tx.Exec(r.Context(), `INSERT INTO user_roles (user_id, role_code, granted_by) VALUES ($1,$2,$3)`, id, role, actor.UserID); err != nil {
				return err
			}
		}
		// Privilege change: force re-authentication.
		if err := h.auth.RevokeAll(r.Context(), tx, id, ""); err != nil {
			return err
		}
		return audit.Log(r.Context(), tx, audit.Entry{Action: "user.roles_changed", EntityType: "user", EntityID: id, Metadata: map[string]any{"before": before, "after": in.Roles}})
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	httpx.NoContent(w)
}

func (h *Handler) CreateStaff(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Name  string   `json:"name"`
		Email string   `json:"email"`
		Roles []string `json:"roles"`
	}
	if err := httpx.Decode(w, r, &in); err != nil {
		fail(w, r, err)
		return
	}
	in.Email = strings.ToLower(strings.TrimSpace(in.Email))
	var v httpx.V
	v.Length("name", in.Name, 2, 120)
	v.Email("email", in.Email)
	if err := v.Err(); err != nil {
		fail(w, r, err)
		return
	}
	if err := validRoles(in.Roles); err != nil {
		fail(w, r, err)
		return
	}
	actor := authctx.From(r.Context())
	for _, x := range in.Roles {
		if x == "super_admin" && !actor.HasRole("super_admin") {
			fail(w, r, httpx.Forbidden("Only a super administrator can create super administrators"))
			return
		}
	}
	temp := "Tmp-" + security.RandomToken(12) + "7"
	hash, err := security.HashPassword(temp)
	if err != nil {
		fail(w, r, err)
		return
	}
	var id string
	err = h.db.InTx(r.Context(), func(tx pgx.Tx) error {
		if err := tx.QueryRow(r.Context(), `INSERT INTO users (email, name, password_hash, account_type, email_verified_at) VALUES ($1,$2,$3,'staff',now()) RETURNING id`,
			in.Email, strings.TrimSpace(in.Name), hash).Scan(&id); err != nil {
			if database.IsUniqueViolation(err, "") {
				return httpx.Conflict(httpx.CodeConflict, "A user with this email already exists")
			}
			return err
		}
		for _, role := range in.Roles {
			if _, err := tx.Exec(r.Context(), `INSERT INTO user_roles (user_id, role_code, granted_by) VALUES ($1,$2,$3)`, id, role, actor.UserID); err != nil {
				return err
			}
		}
		return audit.Log(r.Context(), tx, audit.Entry{Action: "staff.created", EntityType: "user", EntityID: id, Metadata: map[string]any{"roles": in.Roles}})
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	u, err := scanUser(h.db.QueryRow(r.Context(), userSelect+` WHERE u.id=$1`, id))
	if err != nil {
		fail(w, r, err)
		return
	}
	httpx.Created(w, map[string]any{"user": u, "temporary_password": temp})
}

func (h *Handler) Roles(w http.ResponseWriter, r *http.Request) {
	rows, err := h.db.Query(r.Context(), `SELECT ro.code, ro.name, ro.is_staff, ro.description,
		COALESCE(array_agg(rp.permission_code ORDER BY rp.permission_code) FILTER (WHERE rp.permission_code IS NOT NULL), '{}')
		FROM roles ro LEFT JOIN role_permissions rp ON rp.role_code=ro.code GROUP BY ro.code ORDER BY ro.is_staff, ro.code`)
	if err != nil {
		fail(w, r, err)
		return
	}
	defer rows.Close()
	type role struct {
		Code        string   `json:"code"`
		Name        string   `json:"name"`
		IsStaff     bool     `json:"is_staff"`
		Description string   `json:"description"`
		Permissions []string `json:"permissions"`
	}
	out := []role{}
	for rows.Next() {
		var x role
		if err := rows.Scan(&x.Code, &x.Name, &x.IsStaff, &x.Description, &x.Permissions); err != nil {
			fail(w, r, err)
			return
		}
		out = append(out, x)
	}
	perms := []map[string]string{}
	prow, err := h.db.Query(r.Context(), `SELECT code, description FROM permissions ORDER BY code`)
	if err == nil {
		defer prow.Close()
		for prow.Next() {
			var c, d string
			if prow.Scan(&c, &d) == nil {
				perms = append(perms, map[string]string{"code": c, "description": d})
			}
		}
	}
	httpx.OK(w, map[string]any{"roles": out, "permissions": perms})
}

// ---------- listing moderation ----------

func (h *Handler) Listings(w http.ResponseWriter, r *http.Request) {
	pg := httpx.Pagination(r, 20, 100)
	status := r.URL.Query().Get("status")
	if status == "" {
		status = "pending"
	} else if status == "all" {
		status = ""
	}
	out, total, err := h.listings.OwnerList(r.Context(), "", status, strings.TrimSpace(r.URL.Query().Get("q")), pg, true)
	if err != nil {
		fail(w, r, err)
		return
	}
	httpx.Paged(w, out, pg.Meta(total))
}

func (h *Handler) Listing(w http.ResponseWriter, r *http.Request) {
	out, err := h.listings.OwnerView(r.Context(), "", chi.URLParam(r, "id"), true)
	if err != nil {
		fail(w, r, err)
		return
	}
	httpx.OK(w, out)
}

// moderate applies a moderation decision atomically: state transition + history + audit + seller notification.
func (h *Handler) moderate(action string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			Reason string `json:"reason"`
		}
		if r.ContentLength != 0 {
			if err := httpx.Decode(w, r, &in); err != nil {
				fail(w, r, err)
				return
			}
		}
		in.Reason = strings.TrimSpace(in.Reason)
		if (action == "reject" || action == "suspend") && len([]rune(in.Reason)) < 5 {
			fail(w, r, httpx.Invalid(httpx.FieldError{Field: "reason", Message: "please give the seller a reason (5+ characters)"}))
			return
		}
		id := chi.URLParam(r, "id")
		actor := authctx.From(r.Context()).UserID
		ctx := r.Context()
		err := h.db.InTx(ctx, func(tx pgx.Tx) error {
			var status, title, sellerUser, email, name string
			err := tx.QueryRow(ctx, `SELECT l.status, l.title, sp.user_id, u.email, u.name FROM pet_listings l JOIN seller_profiles sp ON sp.id=l.seller_id
				JOIN users u ON u.id=sp.user_id WHERE l.id::text=$1 AND l.deleted_at IS NULL FOR UPDATE OF l`, id).Scan(&status, &title, &sellerUser, &email, &name)
			if database.IsNoRows(err) {
				return httpx.NotFound("Listing")
			}
			if err != nil {
				return err
			}
			allowed := map[string][]string{"approve": {"pending"}, "reject": {"pending"}, "suspend": {"approved", "pending"}, "reinstate": {"suspended"}}[action]
			ok := false
			for _, a := range allowed {
				ok = ok || a == status
			}
			if !ok {
				return httpx.Conflict(httpx.CodeConflict, "Cannot "+action+" a listing that is "+status)
			}
			switch action {
			case "approve", "reinstate":
				if err := listings.Approve(ctx, tx, h.settings.Int(ctx, "listings.expiry_days", 60), id, &actor); err != nil {
					return err
				}
				if action == "reinstate" {
					if _, err := tx.Exec(ctx, `UPDATE listing_moderation SET action='reinstated' WHERE id = (SELECT id FROM listing_moderation WHERE listing_id=$1 ORDER BY created_at DESC LIMIT 1)`, id); err != nil {
						return err
					}
				}
				if err := notifications.Create(ctx, tx, sellerUser, "listing_approved", "Your listing is live", title, map[string]any{"listing_id": id}); err != nil {
					return err
				}
				if err := notifications.EnqueueEmail(ctx, tx, email, "listing_approved", map[string]string{"name": name, "listing": title}); err != nil {
					return err
				}
			case "reject", "suspend":
				newStatus := map[string]string{"reject": "rejected", "suspend": "suspended"}[action]
				if _, err := tx.Exec(ctx, `UPDATE pet_listings SET status=$2, rejection_reason=$3, featured_until=NULL, updated_at=now() WHERE id::text=$1`, id, newStatus, in.Reason); err != nil {
					return err
				}
				if _, err := tx.Exec(ctx, `INSERT INTO listing_moderation (listing_id, action, moderator_id, reason) VALUES ($1,$2,$3,$4)`, id, newStatus, actor, in.Reason); err != nil {
					return err
				}
				if err := notifications.Create(ctx, tx, sellerUser, "listing_"+newStatus, "Your listing needs changes", title+": "+in.Reason, map[string]any{"listing_id": id}); err != nil {
					return err
				}
				if err := notifications.EnqueueEmail(ctx, tx, email, "listing_rejected", map[string]string{"name": name, "listing": title, "reason": in.Reason}); err != nil {
					return err
				}
			}
			return audit.Log(ctx, tx, audit.Entry{Action: "listing." + action, EntityType: "listing", EntityID: id, Metadata: map[string]any{"reason": in.Reason}})
		})
		if err != nil {
			fail(w, r, err)
			return
		}
		h.listings.Invalidate(ctx)
		httpx.NoContent(w)
	}
}

func (h *Handler) Approve() http.HandlerFunc          { return h.moderate("approve") }
func (h *Handler) Reject() http.HandlerFunc           { return h.moderate("reject") }
func (h *Handler) SuspendListing() http.HandlerFunc   { return h.moderate("suspend") }
func (h *Handler) ReinstateListing() http.HandlerFunc { return h.moderate("reinstate") }

// ---------- subscriptions & payments (read models) ----------

func (h *Handler) Subscriptions(w http.ResponseWriter, r *http.Request) {
	pg := httpx.Pagination(r, 25, 100)
	q := r.URL.Query()
	args := []any{statusParam(r), q.Get("audience")}
	where := ` WHERE ($1='' OR s.status=$1) AND ($2='' OR s.audience=$2)`
	var total int
	if err := h.db.QueryRow(r.Context(), `SELECT count(*) FROM subscriptions s`+where, args...).Scan(&total); err != nil {
		fail(w, r, err)
		return
	}
	rows, err := h.db.Query(r.Context(), `SELECT s.id, u.email, u.name, s.audience, p.name, s.status, s.starts_at, s.current_period_end
		FROM subscriptions s JOIN users u ON u.id=s.user_id JOIN subscription_plans p ON p.id=s.plan_id`+where+
		` ORDER BY s.created_at DESC LIMIT $3 OFFSET $4`, append(args, pg.PerPage, pg.Offset)...)
	if err != nil {
		fail(w, r, err)
		return
	}
	defer rows.Close()
	type sub struct {
		ID        string    `json:"id"`
		UserEmail string    `json:"user_email"`
		UserName  string    `json:"user_name"`
		Audience  string    `json:"audience"`
		PlanName  string    `json:"plan_name"`
		Status    string    `json:"status"`
		StartsAt  time.Time `json:"starts_at"`
		PeriodEnd time.Time `json:"current_period_end"`
	}
	out := []sub{}
	for rows.Next() {
		var x sub
		if err := rows.Scan(&x.ID, &x.UserEmail, &x.UserName, &x.Audience, &x.PlanName, &x.Status, &x.StartsAt, &x.PeriodEnd); err != nil {
			fail(w, r, err)
			return
		}
		out = append(out, x)
	}
	httpx.Paged(w, out, pg.Meta(total))
}

type adminPayment struct {
	ID                string           `json:"id"`
	Status            string           `json:"status"`
	Plan              map[string]any   `json:"plan"`
	SubtotalMinor     int64            `json:"subtotal_minor"`
	TaxMinor          int64            `json:"tax_minor"`
	AmountMinor       int64            `json:"amount_minor"`
	RefundedMinor     int64            `json:"refunded_minor"`
	Currency          string           `json:"currency"`
	Provider          string           `json:"provider"`
	FailureReason     *string          `json:"failure_reason"`
	InvoiceID         *string          `json:"invoice_id"`
	CreatedAt         time.Time        `json:"created_at"`
	PaidAt            *time.Time       `json:"paid_at"`
	UserEmail         string           `json:"user_email"`
	UserName          string           `json:"user_name"`
	ProviderOrderID   *string          `json:"provider_order_id"`
	ProviderPaymentID *string          `json:"provider_payment_id"`
	Refunds           []map[string]any `json:"refunds,omitempty"`
}

const adminPaymentSelect = `SELECT p.id, p.status, p.plan_snapshot->>'plan_id', p.plan_snapshot->>'name', p.plan_snapshot->>'audience', p.subtotal_minor, p.tax_minor,
	p.amount_minor, p.refunded_minor, p.currency, p.provider, p.failure_reason, (SELECT i.id::text FROM invoices i WHERE i.payment_id=p.id), p.created_at, p.paid_at,
	u.email, u.name, p.provider_order_id, p.provider_payment_id FROM payments p JOIN users u ON u.id=p.user_id`

func scanAdminPayment(row pgx.Row) (*adminPayment, error) {
	var p adminPayment
	var pid, pname, aud *string
	err := row.Scan(&p.ID, &p.Status, &pid, &pname, &aud, &p.SubtotalMinor, &p.TaxMinor, &p.AmountMinor, &p.RefundedMinor, &p.Currency, &p.Provider,
		&p.FailureReason, &p.InvoiceID, &p.CreatedAt, &p.PaidAt, &p.UserEmail, &p.UserName, &p.ProviderOrderID, &p.ProviderPaymentID)
	p.Plan = map[string]any{"id": pid, "name": pname, "audience": aud}
	return &p, err
}

func (h *Handler) Payments(w http.ResponseWriter, r *http.Request) {
	pg := httpx.Pagination(r, 25, 100)
	q := r.URL.Query()
	args := []any{statusParam(r), strings.TrimSpace(q.Get("q"))}
	where := ` WHERE ($1='' OR p.status=$1) AND ($2='' OR u.email ILIKE '%'||$2||'%' OR p.id::text=$2 OR p.provider_order_id=$2 OR p.provider_payment_id=$2)`
	var total int
	if err := h.db.QueryRow(r.Context(), `SELECT count(*) FROM payments p JOIN users u ON u.id=p.user_id`+where, args...).Scan(&total); err != nil {
		fail(w, r, err)
		return
	}
	rows, err := h.db.Query(r.Context(), adminPaymentSelect+where+` ORDER BY p.created_at DESC LIMIT $3 OFFSET $4`, append(args, pg.PerPage, pg.Offset)...)
	if err != nil {
		fail(w, r, err)
		return
	}
	defer rows.Close()
	out := []adminPayment{}
	for rows.Next() {
		p, err := scanAdminPayment(rows)
		if err != nil {
			fail(w, r, err)
			return
		}
		out = append(out, *p)
	}
	httpx.Paged(w, out, pg.Meta(total))
}

func (h *Handler) Payment(w http.ResponseWriter, r *http.Request) {
	p, err := scanAdminPayment(h.db.QueryRow(r.Context(), adminPaymentSelect+` WHERE p.id::text=$1`, chi.URLParam(r, "id")))
	if database.IsNoRows(err) {
		fail(w, r, httpx.NotFound("Payment"))
		return
	}
	if err != nil {
		fail(w, r, err)
		return
	}
	rows, err := h.db.Query(r.Context(), `SELECT r.id, r.amount_minor, r.reason, r.status, r.created_at, u.name FROM refunds r JOIN users u ON u.id=r.requested_by
		WHERE r.payment_id=$1 ORDER BY r.created_at`, p.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	defer rows.Close()
	p.Refunds = []map[string]any{}
	for rows.Next() {
		var id, reason, status, by string
		var amt int64
		var at time.Time
		if err := rows.Scan(&id, &amt, &reason, &status, &at, &by); err != nil {
			fail(w, r, err)
			return
		}
		p.Refunds = append(p.Refunds, map[string]any{"id": id, "payment_id": p.ID, "amount_minor": amt, "reason": reason, "status": status, "created_at": at, "requested_by": by})
	}
	httpx.OK(w, p)
}

// ---------- reports, disputes, abuse review ----------

func (h *Handler) Reports(w http.ResponseWriter, r *http.Request) {
	pg := httpx.Pagination(r, 25, 100)
	q := r.URL.Query()
	status := q.Get("status")
	if status == "" {
		status = "open"
	} else if status == "all" {
		status = ""
	}
	args := []any{status, q.Get("target_type")}
	where := ` WHERE ($1='' OR rp.status=$1) AND ($2='' OR rp.target_type=$2)`
	var total int
	if err := h.db.QueryRow(r.Context(), `SELECT count(*) FROM reports rp`+where, args...).Scan(&total); err != nil {
		fail(w, r, err)
		return
	}
	rows, err := h.db.Query(r.Context(), `SELECT rp.id, u.email, rp.target_type, rp.target_id,
		COALESCE(CASE rp.target_type WHEN 'listing' THEN (SELECT title FROM pet_listings WHERE id=rp.target_id)
			WHEN 'seller' THEN (SELECT display_name FROM seller_profiles WHERE id=rp.target_id)
			WHEN 'user' THEN (SELECT email::text FROM users WHERE id=rp.target_id)
			WHEN 'enquiry' THEN (SELECT 'Enquiry about ' || l.title FROM enquiries e JOIN pet_listings l ON l.id=e.listing_id WHERE e.id=rp.target_id) END, ''),
		rp.reason, rp.details, rp.status, rp.resolution, rp.created_at FROM reports rp JOIN users u ON u.id=rp.reporter_id`+where+
		` ORDER BY rp.created_at DESC LIMIT $3 OFFSET $4`, append(args, pg.PerPage, pg.Offset)...)
	if err != nil {
		fail(w, r, err)
		return
	}
	defer rows.Close()
	type rep struct {
		ID          string    `json:"id"`
		Reporter    string    `json:"reporter"`
		TargetType  string    `json:"target_type"`
		TargetID    string    `json:"target_id"`
		TargetLabel string    `json:"target_label"`
		Reason      string    `json:"reason"`
		Details     string    `json:"details"`
		Status      string    `json:"status"`
		Resolution  *string   `json:"resolution"`
		CreatedAt   time.Time `json:"created_at"`
	}
	out := []rep{}
	for rows.Next() {
		var x rep
		if err := rows.Scan(&x.ID, &x.Reporter, &x.TargetType, &x.TargetID, &x.TargetLabel, &x.Reason, &x.Details, &x.Status, &x.Resolution, &x.CreatedAt); err != nil {
			fail(w, r, err)
			return
		}
		out = append(out, x)
	}
	httpx.Paged(w, out, pg.Meta(total))
}

func (h *Handler) ResolveReport(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Outcome       string `json:"outcome"`
		Resolution    string `json:"resolution"`
		SuspendTarget bool   `json:"suspend_target"`
	}
	if err := httpx.Decode(w, r, &in); err != nil {
		fail(w, r, err)
		return
	}
	var v httpx.V
	v.OneOf("outcome", in.Outcome, "resolved", "dismissed")
	v.Length("resolution", in.Resolution, 3, 1000)
	if err := v.Err(); err != nil {
		fail(w, r, err)
		return
	}
	id := chi.URLParam(r, "id")
	ctx := r.Context()
	actor := authctx.From(ctx).UserID
	err := h.db.InTx(ctx, func(tx pgx.Tx) error {
		var targetType, targetID string
		err := tx.QueryRow(ctx, `UPDATE reports SET status=$2, resolution=$3, resolved_by=$4, resolved_at=now() WHERE id::text=$1 AND status IN ('open','reviewing')
			RETURNING target_type, target_id::text`, id, in.Outcome, in.Resolution, actor).Scan(&targetType, &targetID)
		if database.IsNoRows(err) {
			return httpx.NotFound("Open report")
		}
		if err != nil {
			return err
		}
		if in.SuspendTarget && in.Outcome == "resolved" {
			switch targetType {
			case "listing":
				if _, err := tx.Exec(ctx, `UPDATE pet_listings SET status='suspended', rejection_reason=$2, updated_at=now() WHERE id::text=$1 AND status IN ('approved','pending')`, targetID, in.Resolution); err != nil {
					return err
				}
				if _, err := tx.Exec(ctx, `INSERT INTO listing_moderation (listing_id, action, moderator_id, reason) VALUES ($1,'suspended',$2,$3)`, targetID, actor, in.Resolution); err != nil {
					return err
				}
			case "seller":
				if _, err := tx.Exec(ctx, `UPDATE seller_profiles SET verification_status='suspended', updated_at=now() WHERE id::text=$1`, targetID); err != nil {
					return err
				}
			case "user":
				if _, err := tx.Exec(ctx, `UPDATE users SET status='suspended', suspended_reason=$2 WHERE id::text=$1 AND account_type <> 'staff'`, targetID, in.Resolution); err != nil {
					return err
				}
				if err := h.auth.RevokeAll(ctx, tx, targetID, ""); err != nil {
					return err
				}
			case "enquiry":
				if _, err := tx.Exec(ctx, `UPDATE enquiries SET status='closed', closed_at=now() WHERE id::text=$1`, targetID); err != nil {
					return err
				}
			}
		}
		// Resolve sibling reports about the same target together.
		if _, err := tx.Exec(ctx, `UPDATE reports SET status=$3, resolution=$4, resolved_by=$5, resolved_at=now()
			WHERE target_type=$1 AND target_id::text=$2 AND status IN ('open','reviewing')`, targetType, targetID, in.Outcome, in.Resolution, actor); err != nil {
			return err
		}
		return audit.Log(ctx, tx, audit.Entry{Action: "report." + in.Outcome, EntityType: targetType, EntityID: targetID, Metadata: map[string]any{"report_id": id, "suspended": in.SuspendTarget}})
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	h.listings.Invalidate(ctx)
	httpx.NoContent(w)
}

func (h *Handler) Disputes(w http.ResponseWriter, r *http.Request) {
	pg := httpx.Pagination(r, 25, 100)
	status := statusParam(r)
	var total int
	if err := h.db.QueryRow(r.Context(), `SELECT count(*) FROM disputes WHERE ($1='' OR status=$1)`, status).Scan(&total); err != nil {
		fail(w, r, err)
		return
	}
	rows, err := h.db.Query(r.Context(), `SELECT d.id, u.email, d.kind, d.subject, d.message, d.status, d.resolution, d.listing_id, d.payment_id, d.enquiry_id, d.created_at
		FROM disputes d JOIN users u ON u.id=d.opened_by WHERE ($1='' OR d.status=$1) ORDER BY (d.status IN ('open','under_review')) DESC, d.created_at DESC LIMIT $2 OFFSET $3`,
		status, pg.PerPage, pg.Offset)
	if err != nil {
		fail(w, r, err)
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id, by, kind, subject, msg, st string
		var res, lid, pid, eid *string
		var at time.Time
		if err := rows.Scan(&id, &by, &kind, &subject, &msg, &st, &res, &lid, &pid, &eid, &at); err != nil {
			fail(w, r, err)
			return
		}
		out = append(out, map[string]any{"id": id, "opened_by": by, "kind": kind, "subject": subject, "message": msg, "status": st, "resolution": res,
			"listing_id": lid, "payment_id": pid, "enquiry_id": eid, "created_at": at})
	}
	httpx.Paged(w, out, pg.Meta(total))
}

func (h *Handler) ResolveDispute(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Outcome    string `json:"outcome"`
		Resolution string `json:"resolution"`
	}
	if err := httpx.Decode(w, r, &in); err != nil {
		fail(w, r, err)
		return
	}
	var v httpx.V
	v.OneOf("outcome", in.Outcome, "under_review", "resolved", "rejected")
	v.Length("resolution", in.Resolution, 3, 2000)
	if err := v.Err(); err != nil {
		fail(w, r, err)
		return
	}
	id := chi.URLParam(r, "id")
	ctx := r.Context()
	err := h.db.InTx(ctx, func(tx pgx.Tx) error {
		var opener string
		err := tx.QueryRow(ctx, `UPDATE disputes SET status=$2, resolution=$3, resolved_by=CASE WHEN $2<>'under_review' THEN $4::uuid END,
			resolved_at=CASE WHEN $2<>'under_review' THEN now() END, updated_at=now() WHERE id::text=$1 AND status IN ('open','under_review') RETURNING opened_by`,
			id, in.Outcome, in.Resolution, authctx.From(ctx).UserID).Scan(&opener)
		if database.IsNoRows(err) {
			return httpx.NotFound("Open dispute")
		}
		if err != nil {
			return err
		}
		if err := notifications.Create(ctx, tx, opener, "dispute_updated", "Update on your support case", in.Resolution, map[string]any{"dispute_id": id, "status": in.Outcome}); err != nil {
			return err
		}
		return audit.Log(ctx, tx, audit.Entry{Action: "dispute." + in.Outcome, EntityType: "dispute", EntityID: id})
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	httpx.NoContent(w)
}

// Enquiries exposes reported conversations to staff for abuse review. Message bodies are shown only
// here (reports.manage) and every view is audited.
func (h *Handler) Enquiries(w http.ResponseWriter, r *http.Request) {
	pg := httpx.Pagination(r, 20, 100)
	status := r.URL.Query().Get("status")
	if status == "" {
		status = "reported"
	} else if status == "all" {
		status = ""
	}
	var total int
	if err := h.db.QueryRow(r.Context(), `SELECT count(*) FROM enquiries WHERE ($1='' OR status=$1)`, status).Scan(&total); err != nil {
		fail(w, r, err)
		return
	}
	rows, err := h.db.Query(r.Context(), `SELECT e.id, e.status, l.title, bu.email, su.email, e.created_at,
		COALESCE((SELECT json_agg(json_build_object('sender', CASE WHEN m.sender_id=e.buyer_id THEN 'buyer' ELSE 'seller' END, 'body', m.body, 'created_at', m.created_at) ORDER BY m.created_at)
			FROM messages m JOIN conversations c ON c.id=m.conversation_id WHERE c.enquiry_id=e.id), '[]')
		FROM enquiries e JOIN pet_listings l ON l.id=e.listing_id JOIN users bu ON bu.id=e.buyer_id
		JOIN seller_profiles sp ON sp.id=e.seller_id JOIN users su ON su.id=sp.user_id
		WHERE ($1='' OR e.status=$1) ORDER BY e.last_message_at DESC LIMIT $2 OFFSET $3`, status, pg.PerPage, pg.Offset)
	if err != nil {
		fail(w, r, err)
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	ids := []string{}
	for rows.Next() {
		var id, st, title, buyer, seller string
		var at time.Time
		var msgs json.RawMessage
		if err := rows.Scan(&id, &st, &title, &buyer, &seller, &at, &msgs); err != nil {
			fail(w, r, err)
			return
		}
		ids = append(ids, id)
		out = append(out, map[string]any{"id": id, "status": st, "listing_title": title, "buyer_email": buyer, "seller_email": seller, "created_at": at, "messages": msgs})
	}
	rows.Close()
	if len(ids) > 0 {
		_ = audit.Log(r.Context(), h.db, audit.Entry{Action: "enquiry.abuse_review_viewed", EntityType: "enquiry", Metadata: map[string]any{"ids": ids}})
	}
	httpx.Paged(w, out, pg.Meta(total))
}

// ---------- settings, content, legal, templates ----------

func (h *Handler) Settings(w http.ResponseWriter, r *http.Request) {
	out, err := h.settings.List(r.Context(), false)
	if err != nil {
		fail(w, r, err)
		return
	}
	httpx.OK(w, out)
}

func (h *Handler) PutSetting(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Value json.RawMessage `json:"value"`
	}
	if err := httpx.Decode(w, r, &in); err != nil {
		fail(w, r, err)
		return
	}
	if len(in.Value) == 0 || !json.Valid(in.Value) {
		fail(w, r, httpx.Invalid(httpx.FieldError{Field: "value", Message: "is required"}))
		return
	}
	key := chi.URLParam(r, "key")
	ctx := r.Context()
	err := h.db.InTx(ctx, func(tx pgx.Tx) error {
		var before json.RawMessage
		if err := tx.QueryRow(ctx, `SELECT value FROM platform_settings WHERE key=$1 FOR UPDATE`, key).Scan(&before); err != nil {
			if database.IsNoRows(err) {
				return httpx.NotFound("Setting")
			}
			return err
		}
		if err := validateSetting(key, before, in.Value); err != nil {
			return err
		}
		if _, err := h.settings.Set(ctx, tx, key, in.Value, authctx.From(ctx).UserID); err != nil {
			return err
		}
		return audit.Log(ctx, tx, audit.Entry{Action: "setting.updated", EntityType: "setting", EntityID: key,
			Metadata: map[string]any{"before": before, "after": in.Value}})
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	h.listings.Invalidate(ctx)
	httpx.NoContent(w)
}

// validateSetting enforces that the new value has the same JSON type as the current one.
func validateSetting(key string, before, after json.RawMessage) error {
	kind := func(b json.RawMessage) string {
		var v any
		_ = json.Unmarshal(b, &v)
		switch v.(type) {
		case bool:
			return "boolean"
		case float64:
			return "number"
		case string:
			return "string"
		case []any:
			return "array"
		case map[string]any:
			return "object"
		}
		return "null"
	}
	if kb, ka := kind(before), kind(after); kb != ka {
		return httpx.Invalid(httpx.FieldError{Field: "value", Message: key + " must be a " + kb})
	}
	if key == "listings.on_subscription_expiry" {
		var s string
		_ = json.Unmarshal(after, &s)
		if s != "unpublish" && s != "keep" {
			return httpx.Invalid(httpx.FieldError{Field: "value", Message: "must be 'unpublish' or 'keep'"})
		}
	}
	return nil
}

func (h *Handler) GetContent(w http.ResponseWriter, r *http.Request) {
	var data json.RawMessage
	err := h.db.QueryRow(r.Context(), `SELECT data FROM content_blocks WHERE key=$1`, chi.URLParam(r, "key")).Scan(&data)
	if database.IsNoRows(err) {
		data = json.RawMessage(`{}`)
	} else if err != nil {
		fail(w, r, err)
		return
	}
	httpx.OK(w, data)
}

func (h *Handler) PutContent(w http.ResponseWriter, r *http.Request) {
	key := chi.URLParam(r, "key")
	if key != "home" && key != "faq" {
		fail(w, r, httpx.NotFound("Content block"))
		return
	}
	var data map[string]any
	if err := httpx.Decode(w, r, &data); err != nil {
		fail(w, r, err)
		return
	}
	b, _ := json.Marshal(data)
	ctx := r.Context()
	err := h.db.InTx(ctx, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `INSERT INTO content_blocks (key, data, updated_by) VALUES ($1,$2,$3)
			ON CONFLICT (key) DO UPDATE SET data=EXCLUDED.data, updated_by=EXCLUDED.updated_by, updated_at=now()`, key, b, authctx.From(ctx).UserID); err != nil {
			return err
		}
		return audit.Log(ctx, tx, audit.Entry{Action: "content.updated", EntityType: "content", EntityID: key})
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	httpx.NoContent(w)
}

func (h *Handler) Legal(w http.ResponseWriter, r *http.Request) {
	rows, err := h.db.Query(r.Context(), `SELECT id, slug, version, title, body_md, is_current, published_at, created_at FROM legal_policy_versions ORDER BY slug, version DESC`)
	if err != nil {
		fail(w, r, err)
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id, slug, title, body string
		var ver int
		var cur bool
		var pub *time.Time
		var created time.Time
		if err := rows.Scan(&id, &slug, &ver, &title, &body, &cur, &pub, &created); err != nil {
			fail(w, r, err)
			return
		}
		out = append(out, map[string]any{"id": id, "slug": slug, "version": ver, "title": title, "body_md": body, "is_current": cur, "published_at": pub, "created_at": created})
	}
	httpx.OK(w, out)
}

func (h *Handler) PublishLegal(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Title  string `json:"title"`
		BodyMD string `json:"body_md"`
	}
	if err := httpx.Decode(w, r, &in); err != nil {
		fail(w, r, err)
		return
	}
	slug := chi.URLParam(r, "slug")
	var v httpx.V
	v.OneOf("slug", slug, "privacy", "terms", "refund-policy", "seller-policy", "safety")
	v.Length("title", in.Title, 3, 140)
	v.Length("body_md", in.BodyMD, 20, 200000)
	if err := v.Err(); err != nil {
		fail(w, r, err)
		return
	}
	ctx := r.Context()
	var version int
	err := h.db.InTx(ctx, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext('legal:' || $1))`, slug); err != nil {
			return err
		}
		if err := tx.QueryRow(ctx, `SELECT COALESCE(max(version),0)+1 FROM legal_policy_versions WHERE slug=$1`, slug).Scan(&version); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE legal_policy_versions SET is_current=false WHERE slug=$1 AND is_current`, slug); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `INSERT INTO legal_policy_versions (slug, version, title, body_md, is_current, published_at, created_by) VALUES ($1,$2,$3,$4,true,now(),$5)`,
			slug, version, in.Title, in.BodyMD, authctx.From(ctx).UserID); err != nil {
			return err
		}
		return audit.Log(ctx, tx, audit.Entry{Action: "legal.published", EntityType: "legal", EntityID: slug, Metadata: map[string]any{"version": version}})
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	httpx.Created(w, map[string]any{"slug": slug, "version": version})
}

func (h *Handler) Templates(w http.ResponseWriter, r *http.Request) {
	rows, err := h.db.Query(r.Context(), `SELECT key, channel, subject, body, is_active, updated_at FROM notification_templates ORDER BY key, channel`)
	if err != nil {
		fail(w, r, err)
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var k, ch, subj, body string
		var active bool
		var at time.Time
		if err := rows.Scan(&k, &ch, &subj, &body, &active, &at); err != nil {
			fail(w, r, err)
			return
		}
		out = append(out, map[string]any{"key": k, "channel": ch, "subject": subj, "body": body, "is_active": active, "updated_at": at})
	}
	httpx.OK(w, map[string]any{"templates": out, "known_keys": notifications.TemplateKeys()})
}

func (h *Handler) PutTemplate(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Subject  string `json:"subject"`
		Body     string `json:"body"`
		IsActive *bool  `json:"is_active"`
	}
	if err := httpx.Decode(w, r, &in); err != nil {
		fail(w, r, err)
		return
	}
	key, channel := chi.URLParam(r, "key"), chi.URLParam(r, "channel")
	var v httpx.V
	v.OneOf("channel", channel, "in_app", "email", "sms")
	v.Length("body", in.Body, 5, 10000)
	if !notifications.IsTemplateKey(key) {
		v.Add("key", "is not a known template")
	}
	if err := v.Err(); err != nil {
		fail(w, r, err)
		return
	}
	if err := notifications.ValidateTemplate(in.Subject, in.Body); err != nil {
		fail(w, r, httpx.Invalid(httpx.FieldError{Field: "body", Message: err.Error()}))
		return
	}
	active := in.IsActive == nil || *in.IsActive
	ctx := r.Context()
	err := h.db.InTx(ctx, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `INSERT INTO notification_templates (key, channel, subject, body, is_active) VALUES ($1,$2,$3,$4,$5)
			ON CONFLICT (key, channel) DO UPDATE SET subject=EXCLUDED.subject, body=EXCLUDED.body, is_active=EXCLUDED.is_active, updated_at=now()`,
			key, channel, in.Subject, in.Body, active); err != nil {
			return err
		}
		return audit.Log(ctx, tx, audit.Entry{Action: "template.updated", EntityType: "template", EntityID: key + "/" + channel})
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	httpx.NoContent(w)
}

// ---------- audit logs & jobs ----------

func (h *Handler) AuditLogs(w http.ResponseWriter, r *http.Request) {
	pg := httpx.Pagination(r, 50, 100)
	q := r.URL.Query()
	args := []any{q.Get("action"), q.Get("actor_id"), q.Get("entity_type")}
	where := ` WHERE ($1='' OR a.action LIKE $1||'%') AND ($2='' OR a.actor_id::text=$2) AND ($3='' OR a.entity_type=$3)`
	var total int
	if err := h.db.QueryRow(r.Context(), `SELECT count(*) FROM audit_logs a`+where, args...).Scan(&total); err != nil {
		fail(w, r, err)
		return
	}
	rows, err := h.db.Query(r.Context(), `SELECT a.id, a.actor_id, u.email, a.actor_roles, a.action, a.entity_type, a.entity_id, a.metadata, a.ip, a.request_id, a.created_at
		FROM audit_logs a LEFT JOIN users u ON u.id=a.actor_id`+where+` ORDER BY a.id DESC LIMIT $4 OFFSET $5`, append(args, pg.PerPage, pg.Offset)...)
	if err != nil {
		fail(w, r, err)
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id int64
		var actor, email *string
		var roles []string
		var action, et, eid, ip, rid string
		var meta json.RawMessage
		var at time.Time
		if err := rows.Scan(&id, &actor, &email, &roles, &action, &et, &eid, &meta, &ip, &rid, &at); err != nil {
			fail(w, r, err)
			return
		}
		out = append(out, map[string]any{"id": id, "actor_id": actor, "actor_email": email, "actor_roles": roles, "action": action, "entity_type": et,
			"entity_id": eid, "metadata": meta, "ip": ip, "request_id": rid, "created_at": at})
	}
	httpx.Paged(w, out, pg.Meta(total))
}

func (h *Handler) Jobs(w http.ResponseWriter, r *http.Request) {
	pg := httpx.Pagination(r, 50, 100)
	status := statusParam(r)
	var total int
	if err := h.db.QueryRow(r.Context(), `SELECT count(*) FROM jobs WHERE ($1='' OR status=$1) AND kind <> 'reminder.marker'`, status).Scan(&total); err != nil {
		fail(w, r, err)
		return
	}
	rows, err := h.db.Query(r.Context(), `SELECT id, kind, status, attempts, max_attempts, run_at, last_error, created_at, finished_at FROM jobs
		WHERE ($1='' OR status=$1) AND kind <> 'reminder.marker' ORDER BY created_at DESC LIMIT $2 OFFSET $3`, status, pg.PerPage, pg.Offset)
	if err != nil {
		fail(w, r, err)
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id, kind, st string
		var att, max int
		var runAt, created time.Time
		var lastErr *string
		var fin *time.Time
		if err := rows.Scan(&id, &kind, &st, &att, &max, &runAt, &lastErr, &created, &fin); err != nil {
			fail(w, r, err)
			return
		}
		out = append(out, map[string]any{"id": id, "kind": kind, "status": st, "attempts": att, "max_attempts": max, "run_at": runAt, "last_error": lastErr, "created_at": created, "finished_at": fin})
	}
	httpx.Paged(w, out, pg.Meta(total))
}

func (h *Handler) RetryJob(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	if err := jobs.Retry(r.Context(), h.db, id); err != nil {
		fail(w, r, httpx.Conflict(httpx.CodeConflict, err.Error()))
		return
	}
	_ = audit.Log(r.Context(), h.db, audit.Entry{Action: "job.retried", EntityType: "job", EntityID: id})
	httpx.NoContent(w)
}
