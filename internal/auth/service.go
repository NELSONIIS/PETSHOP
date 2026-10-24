// Package auth implements registration, login, sessions, MFA and password flows.
//
// Strategy (one scheme, two transports):
//   - short-lived HS256 access token (15 min) bound to a server-side session row;
//   - opaque, rotating refresh token (30 days) stored only as a SHA-256 hash.
//   - Web: both tokens in HttpOnly cookies + double-submit CSRF token.
//   - Mobile (header X-Client: mobile): tokens returned in JSON, stored in the OS keystore.
//
// Every request re-validates the session and user status in the database, so suspension and
// logout take effect immediately.
package auth

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"
	"unicode"

	"github.com/jackc/pgx/v5"

	"petora/internal/audit"
	"petora/internal/authctx"
	"petora/internal/cache"
	"petora/internal/config"
	"petora/internal/database"
	"petora/internal/httpx"
	"petora/internal/notifications"
	"petora/internal/security"
)

const (
	maxFailedLogins = 5
	lockDuration    = 15 * time.Minute
	codeTTL         = 15 * time.Minute
	maxCodeAttempts = 5
	refreshGrace    = 10 * time.Second
)

type Service struct {
	cfg   config.Config
	db    *database.DB
	cache *cache.Cache
	box   *security.Box
}

func NewService(cfg config.Config, db *database.DB, c *cache.Cache) (*Service, error) {
	box, err := security.NewBox(cfg.DataEncryptionKey)
	if err != nil {
		return nil, err
	}
	return &Service{cfg: cfg, db: db, cache: c, box: box}, nil
}

type User struct {
	ID            string    `json:"id"`
	Email         string    `json:"email"`
	Phone         *string   `json:"phone,omitempty"`
	Name          string    `json:"name"`
	AccountType   string    `json:"account_type"`
	Roles         []string  `json:"roles"`
	Permissions   []string  `json:"permissions,omitempty"`
	EmailVerified bool      `json:"email_verified"`
	MFAEnabled    bool      `json:"mfa_enabled"`
	MFAVerified   bool      `json:"mfa_verified"`
	AvatarURL     *string   `json:"avatar_url,omitempty"`
	CreatedAt     time.Time `json:"created_at"`
}

type Tokens struct {
	AccessToken  string    `json:"access_token"`
	RefreshToken string    `json:"refresh_token"`
	ExpiresAt    time.Time `json:"expires_at"`
}

type ClientInfo struct {
	Kind      string // web | mobile
	UserAgent string
	IP        string
}

// ---------- registration ----------

type RegisterInput struct {
	Name        string `json:"name"`
	Email       string `json:"email"`
	Phone       string `json:"phone"`
	Password    string `json:"password"`
	Role        string `json:"role"` // buyer | seller
	AcceptTerms bool   `json:"accept_terms"`
}

func (in *RegisterInput) validate() error {
	var v httpx.V
	in.Email = strings.ToLower(strings.TrimSpace(in.Email))
	in.Name = strings.TrimSpace(in.Name)
	in.Phone = strings.ReplaceAll(strings.TrimSpace(in.Phone), " ", "")
	v.Length("name", in.Name, 2, 120)
	v.Email("email", in.Email)
	if in.Phone != "" {
		v.Phone("phone", in.Phone)
	}
	v.Password("password", in.Password)
	v.OneOf("role", in.Role, "buyer", "seller")
	if !in.AcceptTerms {
		v.Add("accept_terms", "you must accept the Terms of Service and Privacy Policy")
	}
	return v.Err()
}

func (s *Service) Register(ctx context.Context, in RegisterInput, ci ClientInfo) (*User, *Tokens, error) {
	if err := in.validate(); err != nil {
		return nil, nil, err
	}
	hash, err := security.HashPassword(in.Password)
	if err != nil {
		return nil, nil, err
	}
	var phone *string
	if in.Phone != "" {
		phone = &in.Phone
	}
	var userID string
	err = s.db.InTx(ctx, func(tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, `INSERT INTO users (email, phone, name, password_hash, account_type)
			VALUES ($1,$2,$3,$4,$5) RETURNING id`, in.Email, phone, in.Name, hash, in.Role).Scan(&userID); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `INSERT INTO user_roles (user_id, role_code) VALUES ($1,$2)`, userID, in.Role); err != nil {
			return err
		}
		if in.Role == "buyer" {
			if _, err := tx.Exec(ctx, `INSERT INTO buyer_profiles (user_id) VALUES ($1)`, userID); err != nil {
				return err
			}
		} else {
			slug := slugify(in.Name) + "-" + security.RandomToken(3)[:4]
			if _, err := tx.Exec(ctx, `INSERT INTO seller_profiles (user_id, slug, display_name, contact_email, contact_phone)
				VALUES ($1,$2,$3,$4,$5)`, userID, strings.ToLower(slug), in.Name, in.Email, phone); err != nil {
				return err
			}
		}
		return s.issueCode(ctx, tx, userID, in.Email, in.Name, "email_verify")
	})
	if err != nil {
		if database.IsUniqueViolation(err, "users_email_key") || database.IsUniqueViolation(err, "users_phone_key") {
			return nil, nil, httpx.Conflict(httpx.CodeConflict, "An account with this email or mobile number already exists. Try logging in or use 'Forgot password'.")
		}
		return nil, nil, err
	}
	u, err := s.loadUser(ctx, userID)
	if err != nil {
		return nil, nil, err
	}
	tok, err := s.startSession(ctx, u.ID, ci, false)
	return u, tok, err
}

// issueCode stores a hashed OTP and enqueues the email in the same transaction (outbox).
func (s *Service) issueCode(ctx context.Context, q database.Querier, userID, email, name, purpose string) error {
	code := security.NumericCode(6)
	if _, err := q.Exec(ctx, `UPDATE one_time_codes SET consumed_at = now() WHERE user_id=$1 AND purpose=$2 AND consumed_at IS NULL`, userID, purpose); err != nil {
		return err
	}
	if _, err := q.Exec(ctx, `INSERT INTO one_time_codes (user_id, purpose, code_hash, expires_at) VALUES ($1,$2,$3,$4)`,
		userID, purpose, security.SHA256(userID+":"+purpose+":"+code), time.Now().Add(codeTTL)); err != nil {
		return err
	}
	tpl := map[string]string{"email_verify": "email_verify", "password_reset": "password_reset"}[purpose]
	return notifications.EnqueueEmail(ctx, q, email, tpl, map[string]string{"name": name, "code": code})
}

func (s *Service) consumeCode(ctx context.Context, tx pgx.Tx, userID, purpose, code string) error {
	var id string
	var hash []byte
	var attempts int
	err := tx.QueryRow(ctx, `SELECT id, code_hash, attempts FROM one_time_codes
		WHERE user_id=$1 AND purpose=$2 AND consumed_at IS NULL AND expires_at > now()
		ORDER BY created_at DESC LIMIT 1 FOR UPDATE`, userID, purpose).Scan(&id, &hash, &attempts)
	if database.IsNoRows(err) {
		return httpx.BadRequest("The code is invalid or has expired. Request a new one.")
	}
	if err != nil {
		return err
	}
	if attempts >= maxCodeAttempts {
		return httpx.Err(429, httpx.CodeRateLimited, "Too many attempts. Request a new code.")
	}
	if !security.ConstantTimeEqual(string(hash), string(security.SHA256(userID+":"+purpose+":"+strings.TrimSpace(code)))) {
		_, _ = tx.Exec(ctx, `UPDATE one_time_codes SET attempts = attempts + 1 WHERE id=$1`, id)
		return httpx.BadRequest("The code is invalid or has expired. Request a new one.")
	}
	_, err = tx.Exec(ctx, `UPDATE one_time_codes SET consumed_at=now() WHERE id=$1`, id)
	return err
}

// ---------- login ----------

type LoginInput struct {
	Email    string `json:"email"`
	Password string `json:"password"`
	OTP      string `json:"otp"`
}

var errBadCreds = httpx.Unauthorized("Incorrect email or password")

func (s *Service) Login(ctx context.Context, in LoginInput, ci ClientInfo) (*User, *Tokens, error) {
	var v httpx.V
	in.Email = strings.ToLower(strings.TrimSpace(in.Email))
	v.Required("email", in.Email)
	v.Required("password", in.Password)
	if err := v.Err(); err != nil {
		return nil, nil, err
	}
	var (
		id, hash, status, accType string
		failed                    int
		lockedUntil               *time.Time
		mfaSecret                 *string
	)
	err := s.db.QueryRow(ctx, `SELECT id, password_hash, status, account_type, failed_login_count, locked_until, mfa_secret_enc
		FROM users WHERE email=$1`, in.Email).Scan(&id, &hash, &status, &accType, &failed, &lockedUntil, &mfaSecret)
	if database.IsNoRows(err) {
		security.DummyVerify(in.Password)
		return nil, nil, errBadCreds
	}
	if err != nil {
		return nil, nil, err
	}
	if lockedUntil != nil && lockedUntil.After(time.Now()) {
		return nil, nil, httpx.Err(429, httpx.CodeRateLimited, "Too many failed attempts. Try again later or reset your password.")
	}
	if !security.VerifyPassword(in.Password, hash) {
		s.recordFailure(ctx, id, failed, ci)
		return nil, nil, errBadCreds
	}
	switch status {
	case "suspended":
		return nil, nil, httpx.Err(403, httpx.CodeAccountSuspended, "This account is suspended. Contact support.")
	case "deleted":
		return nil, nil, errBadCreds
	}
	mfaVerified := false
	if accType == "staff" && mfaSecret != nil {
		if strings.TrimSpace(in.OTP) == "" {
			return nil, nil, httpx.Err(401, httpx.CodeMFARequired, "Enter the 6-digit code from your authenticator app")
		}
		secret, err := s.box.Open(*mfaSecret)
		if err != nil || !security.VerifyTOTP(secret, in.OTP, time.Now()) {
			s.recordFailure(ctx, id, failed, ci)
			return nil, nil, errBadCreds
		}
		mfaVerified = true
	}
	_, _ = s.db.Exec(ctx, `UPDATE users SET failed_login_count=0, locked_until=NULL, last_login_at=now() WHERE id=$1`, id)
	u, err := s.loadUser(ctx, id)
	if err != nil {
		return nil, nil, err
	}
	u.MFAVerified = mfaVerified
	tok, err := s.startSession(ctx, id, ci, mfaVerified)
	if err != nil {
		return nil, nil, err
	}
	s.auditAuth(ctx, id, "auth.login", ci, nil)
	return u, tok, nil
}

func (s *Service) recordFailure(ctx context.Context, id string, failed int, ci ClientInfo) {
	failed++
	if failed >= maxFailedLogins {
		_, _ = s.db.Exec(ctx, `UPDATE users SET failed_login_count=0, locked_until=$2 WHERE id=$1`, id, time.Now().Add(lockDuration))
		s.auditAuth(ctx, id, "auth.account_locked", ci, nil)
		return
	}
	_, _ = s.db.Exec(ctx, `UPDATE users SET failed_login_count=$2 WHERE id=$1`, id, failed)
	s.auditAuth(ctx, id, "auth.login_failed", ci, map[string]any{"count": failed})
}

func (s *Service) auditAuth(ctx context.Context, userID, action string, ci ClientInfo, meta map[string]any) {
	if meta == nil {
		meta = map[string]any{}
	}
	meta["user_agent"] = ci.UserAgent
	meta["client"] = ci.Kind
	b := ctx
	_, _ = s.db.Exec(b, `INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, metadata, ip, request_id)
		VALUES ($1,$2,'user',$1::text,$3,$4,$5)`, userID, action, meta, ci.IP, httpx.RequestID(ctx))
}

// ---------- sessions ----------

func (s *Service) startSession(ctx context.Context, userID string, ci ClientInfo, mfaVerified bool) (*Tokens, error) {
	refresh := security.RandomToken(32)
	var sid string
	err := s.db.QueryRow(ctx, `INSERT INTO sessions (user_id, refresh_hash, client, mfa_verified, user_agent, ip, expires_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING id`, userID, security.SHA256(refresh), ci.Kind, mfaVerified,
		truncate(ci.UserAgent, 300), ci.IP, time.Now().Add(s.cfg.RefreshTTL)).Scan(&sid)
	if err != nil {
		return nil, err
	}
	at, exp, err := s.signAccess(userID, sid)
	if err != nil {
		return nil, err
	}
	return &Tokens{AccessToken: at, RefreshToken: refresh, ExpiresAt: exp}, nil
}

// Refresh rotates the refresh token. Replaying a rotated token outside the grace window revokes the session.
func (s *Service) Refresh(ctx context.Context, refresh string, ci ClientInfo) (*User, *Tokens, error) {
	if refresh == "" {
		return nil, nil, httpx.Unauthorized("Session expired. Please log in again.")
	}
	h := security.SHA256(refresh)
	var tok *Tokens
	var userID string
	var mfaVerified bool
	err := s.db.InTx(ctx, func(tx pgx.Tx) error {
		var sid string
		var exp time.Time
		var revoked *time.Time
		err := tx.QueryRow(ctx, `SELECT id, user_id, expires_at, revoked_at, mfa_verified FROM sessions WHERE refresh_hash=$1 FOR UPDATE`, h).Scan(&sid, &userID, &exp, &revoked, &mfaVerified)
		if database.IsNoRows(err) {
			var psid string
			var rotated *time.Time
			perr := tx.QueryRow(ctx, `SELECT id, rotated_at FROM sessions WHERE prev_refresh_hash=$1`, h).Scan(&psid, &rotated)
			if perr == nil && (rotated == nil || time.Since(*rotated) > refreshGrace) {
				_, _ = tx.Exec(ctx, `UPDATE sessions SET revoked_at=now() WHERE id=$1 AND revoked_at IS NULL`, psid)
				_ = tx.Commit(ctx) // persist the revocation even though we return an error
				return errReuse
			}
			return httpx.Unauthorized("Session expired. Please log in again.")
		}
		if err != nil {
			return err
		}
		if revoked != nil || exp.Before(time.Now()) {
			return httpx.Unauthorized("Session expired. Please log in again.")
		}
		newRefresh := security.RandomToken(32)
		if _, err := tx.Exec(ctx, `UPDATE sessions SET prev_refresh_hash=refresh_hash, refresh_hash=$2, rotated_at=now(), last_used_at=now(), ip=$3
			WHERE id=$1`, sid, security.SHA256(newRefresh), ci.IP); err != nil {
			return err
		}
		at, e, err := s.signAccess(userID, sid)
		if err != nil {
			return err
		}
		tok = &Tokens{AccessToken: at, RefreshToken: newRefresh, ExpiresAt: e}
		return nil
	})
	if errors.Is(err, errReuse) {
		return nil, nil, httpx.Unauthorized("Session expired. Please log in again.")
	}
	if err != nil {
		return nil, nil, err
	}
	u, err := s.loadUser(ctx, userID)
	if err != nil {
		return nil, nil, err
	}
	if u == nil {
		return nil, nil, httpx.Unauthorized("Session expired. Please log in again.")
	}
	u.MFAVerified = mfaVerified
	return u, tok, nil
}

var errReuse = errors.New("refresh reuse detected")

func (s *Service) Logout(ctx context.Context, sessionID string) error {
	_, err := s.db.Exec(ctx, `UPDATE sessions SET revoked_at=now() WHERE id=$1 AND revoked_at IS NULL`, sessionID)
	return err
}

type SessionInfo struct {
	ID         string    `json:"id"`
	Client     string    `json:"client"`
	UserAgent  string    `json:"user_agent"`
	IP         string    `json:"ip"`
	CreatedAt  time.Time `json:"created_at"`
	LastUsedAt time.Time `json:"last_used_at"`
	Current    bool      `json:"current"`
}

func (s *Service) ListSessions(ctx context.Context, userID, current string) ([]SessionInfo, error) {
	rows, err := s.db.Query(ctx, `SELECT id, client, user_agent, ip, created_at, last_used_at FROM sessions
		WHERE user_id=$1 AND revoked_at IS NULL AND expires_at > now() ORDER BY last_used_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []SessionInfo{}
	for rows.Next() {
		var si SessionInfo
		if err := rows.Scan(&si.ID, &si.Client, &si.UserAgent, &si.IP, &si.CreatedAt, &si.LastUsedAt); err != nil {
			return nil, err
		}
		si.Current = si.ID == current
		out = append(out, si)
	}
	return out, rows.Err()
}

func (s *Service) RevokeSession(ctx context.Context, userID, sessionID string) error {
	tag, err := s.db.Exec(ctx, `UPDATE sessions SET revoked_at=now() WHERE id=$1 AND user_id=$2 AND revoked_at IS NULL`, sessionID, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return httpx.NotFound("Session")
	}
	return nil
}

func (s *Service) RevokeAll(ctx context.Context, q database.Querier, userID, exceptSession string) error {
	_, err := q.Exec(ctx, `UPDATE sessions SET revoked_at=now() WHERE user_id=$1 AND revoked_at IS NULL AND ($2 = '' OR id::text <> $2)`, userID, exceptSession)
	return err
}

// ---------- principal loading (used by middleware) ----------

// Authenticate validates an access token and loads the principal from the database.
func (s *Service) Authenticate(ctx context.Context, accessToken string) (*authctx.Principal, error) {
	uid, sid, err := s.parseAccess(accessToken)
	if err != nil {
		return nil, httpx.Unauthorized("Invalid or expired session")
	}
	var p authctx.Principal
	var status string
	var perms []string
	err = s.db.QueryRow(ctx, `
		SELECT u.id, u.email, u.name, u.account_type, u.status, u.email_verified_at IS NOT NULL,
		       u.mfa_enabled_at IS NOT NULL, s.mfa_verified,
		       COALESCE(array_agg(DISTINCT ur.role_code) FILTER (WHERE ur.role_code IS NOT NULL), '{}'),
		       COALESCE(array_agg(DISTINCT rp.permission_code) FILTER (WHERE rp.permission_code IS NOT NULL), '{}')
		FROM sessions s JOIN users u ON u.id = s.user_id
		LEFT JOIN user_roles ur ON ur.user_id = u.id
		LEFT JOIN role_permissions rp ON rp.role_code = ur.role_code
		WHERE s.id=$1 AND s.user_id=$2 AND s.revoked_at IS NULL AND s.expires_at > now()
		GROUP BY u.id, s.mfa_verified`, sid, uid).
		Scan(&p.UserID, &p.Email, &p.Name, &p.AccountType, &status, &p.EmailVerified, &p.MFAEnabled, &p.MFAVerified, &p.Roles, &perms)
	if database.IsNoRows(err) {
		return nil, httpx.Unauthorized("Invalid or expired session")
	}
	if err != nil {
		return nil, err
	}
	if status != "active" {
		return nil, httpx.Err(403, httpx.CodeAccountSuspended, "This account is suspended. Contact support.")
	}
	p.SessionID = sid
	p.Perms = make(map[string]bool, len(perms))
	for _, x := range perms {
		p.Perms[x] = true
	}
	return &p, nil
}

func (s *Service) loadUser(ctx context.Context, id string) (*User, error) {
	var u User
	var perms []string
	var mfaVerified bool
	err := s.db.QueryRow(ctx, `
		SELECT u.id, u.email, u.phone, u.name, u.account_type, u.email_verified_at IS NOT NULL, u.mfa_enabled_at IS NOT NULL,
		       u.avatar_url, u.created_at,
		       COALESCE(array_agg(DISTINCT ur.role_code) FILTER (WHERE ur.role_code IS NOT NULL), '{}'),
		       COALESCE(array_agg(DISTINCT rp.permission_code) FILTER (WHERE rp.permission_code IS NOT NULL), '{}')
		FROM users u LEFT JOIN user_roles ur ON ur.user_id=u.id LEFT JOIN role_permissions rp ON rp.role_code=ur.role_code
		WHERE u.id=$1 AND u.status='active' GROUP BY u.id`, id).
		Scan(&u.ID, &u.Email, &u.Phone, &u.Name, &u.AccountType, &u.EmailVerified, &u.MFAEnabled, &u.AvatarURL, &u.CreatedAt, &u.Roles, &perms)
	if database.IsNoRows(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	_ = mfaVerified
	if u.AccountType == "staff" {
		u.Permissions = perms
	}
	return &u, nil
}

// Me returns the current user's profile for the principal's session.
func (s *Service) Me(ctx context.Context, p *authctx.Principal) (*User, error) {
	u, err := s.loadUser(ctx, p.UserID)
	if err != nil {
		return nil, err
	}
	if u == nil {
		return nil, httpx.Unauthorized("Invalid or expired session")
	}
	u.MFAVerified = p.MFAVerified
	return u, nil
}

// ---------- verification / password ----------

func (s *Service) VerifyEmail(ctx context.Context, userID, code string) error {
	return s.db.InTx(ctx, func(tx pgx.Tx) error {
		if err := s.consumeCode(ctx, tx, userID, "email_verify", code); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `UPDATE users SET email_verified_at=COALESCE(email_verified_at, now()), updated_at=now() WHERE id=$1`, userID)
		return err
	})
}

func (s *Service) ResendVerification(ctx context.Context, p *authctx.Principal) error {
	if p.EmailVerified {
		return httpx.Conflict(httpx.CodeConflict, "Email is already verified")
	}
	return s.db.InTx(ctx, func(tx pgx.Tx) error { return s.issueCode(ctx, tx, p.UserID, p.Email, p.Name, "email_verify") })
}

// ForgotPassword always succeeds from the caller's point of view (no account enumeration).
func (s *Service) ForgotPassword(ctx context.Context, email string) error {
	email = strings.ToLower(strings.TrimSpace(email))
	var id, name string
	err := s.db.QueryRow(ctx, `SELECT id, name FROM users WHERE email=$1 AND status='active'`, email).Scan(&id, &name)
	if database.IsNoRows(err) {
		return nil
	}
	if err != nil {
		return err
	}
	return s.db.InTx(ctx, func(tx pgx.Tx) error { return s.issueCode(ctx, tx, id, email, name, "password_reset") })
}

func (s *Service) ResetPassword(ctx context.Context, email, code, newPassword string) error {
	var v httpx.V
	email = strings.ToLower(strings.TrimSpace(email))
	v.Password("password", newPassword)
	if err := v.Err(); err != nil {
		return err
	}
	var id string
	err := s.db.QueryRow(ctx, `SELECT id FROM users WHERE email=$1 AND status='active'`, email).Scan(&id)
	if database.IsNoRows(err) {
		return httpx.BadRequest("The code is invalid or has expired. Request a new one.")
	}
	if err != nil {
		return err
	}
	hash, err := security.HashPassword(newPassword)
	if err != nil {
		return err
	}
	return s.db.InTx(ctx, func(tx pgx.Tx) error {
		if err := s.consumeCode(ctx, tx, id, "password_reset", code); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE users SET password_hash=$2, failed_login_count=0, locked_until=NULL,
			email_verified_at=COALESCE(email_verified_at, now()), updated_at=now() WHERE id=$1`, id, hash); err != nil {
			return err
		}
		// Password reset ends every session.
		if err := s.RevokeAll(ctx, tx, id, ""); err != nil {
			return err
		}
		return audit.Log(ctx, tx, audit.Entry{Action: "auth.password_reset", EntityType: "user", EntityID: id})
	})
}

func (s *Service) ChangePassword(ctx context.Context, p *authctx.Principal, current, next string) error {
	var v httpx.V
	v.Password("new_password", next)
	if err := v.Err(); err != nil {
		return err
	}
	var hash string
	if err := s.db.QueryRow(ctx, `SELECT password_hash FROM users WHERE id=$1`, p.UserID).Scan(&hash); err != nil {
		return err
	}
	if !security.VerifyPassword(current, hash) {
		return httpx.Invalid(httpx.FieldError{Field: "current_password", Message: "is incorrect"})
	}
	nh, err := security.HashPassword(next)
	if err != nil {
		return err
	}
	return s.db.InTx(ctx, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `UPDATE users SET password_hash=$2, updated_at=now() WHERE id=$1`, p.UserID, nh); err != nil {
			return err
		}
		if err := s.RevokeAll(ctx, tx, p.UserID, p.SessionID); err != nil {
			return err
		}
		return audit.Log(ctx, tx, audit.Entry{Action: "auth.password_changed", EntityType: "user", EntityID: p.UserID})
	})
}

// ---------- MFA (TOTP) ----------

type MFASetup struct {
	Secret string `json:"secret"`
	URI    string `json:"otpauth_uri"`
}

// MFASetup generates a pending secret. It is stored encrypted but not "enabled" until confirmed.
func (s *Service) MFASetup(ctx context.Context, p *authctx.Principal) (*MFASetup, error) {
	if p.MFAEnabled {
		return nil, httpx.Conflict(httpx.CodeConflict, "MFA is already enabled")
	}
	secret := security.NewTOTPSecret()
	enc, err := s.box.Seal(secret)
	if err != nil {
		return nil, err
	}
	if _, err := s.db.Exec(ctx, `UPDATE users SET mfa_secret_enc=$2 WHERE id=$1 AND mfa_enabled_at IS NULL`, p.UserID, enc); err != nil {
		return nil, err
	}
	return &MFASetup{Secret: secret, URI: security.TOTPURI("PETORA", p.Email, secret)}, nil
}

func (s *Service) MFAEnable(ctx context.Context, p *authctx.Principal, code string) error {
	var enc *string
	if err := s.db.QueryRow(ctx, `SELECT mfa_secret_enc FROM users WHERE id=$1`, p.UserID).Scan(&enc); err != nil {
		return err
	}
	if enc == nil || p.MFAEnabled {
		return httpx.BadRequest("Start MFA setup first")
	}
	secret, err := s.box.Open(*enc)
	if err != nil || !security.VerifyTOTP(secret, code, time.Now()) {
		return httpx.Invalid(httpx.FieldError{Field: "code", Message: "is incorrect"})
	}
	return s.db.InTx(ctx, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `UPDATE users SET mfa_enabled_at=now() WHERE id=$1`, p.UserID); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE sessions SET mfa_verified=true WHERE id=$1`, p.SessionID); err != nil {
			return err
		}
		return audit.Log(ctx, tx, audit.Entry{Action: "auth.mfa_enabled", EntityType: "user", EntityID: p.UserID})
	})
}

// ---------- account deletion ----------

// DeleteAccount anonymises personal data immediately and revokes sessions. Financial records
// (payments, invoices) are retained as required by tax law, detached from identifying details.
func (s *Service) DeleteAccount(ctx context.Context, p *authctx.Principal, password string) error {
	var hash string
	if err := s.db.QueryRow(ctx, `SELECT password_hash FROM users WHERE id=$1`, p.UserID).Scan(&hash); err != nil {
		return err
	}
	if !security.VerifyPassword(password, hash) {
		return httpx.Invalid(httpx.FieldError{Field: "password", Message: "is incorrect"})
	}
	if p.IsStaff() {
		return httpx.Forbidden("Staff accounts must be removed by a super administrator")
	}
	return s.db.InTx(ctx, func(tx pgx.Tx) error {
		anon := "deleted+" + p.UserID + "@deleted.invalid"
		if _, err := tx.Exec(ctx, `UPDATE users SET status='deleted', email=$2, phone=NULL, name='Deleted user', avatar_url=NULL,
			mfa_secret_enc=NULL, password_hash='!', deleted_at=now(), updated_at=now() WHERE id=$1`, p.UserID, anon); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE seller_profiles SET display_name='Former seller', bio='', business_name=NULL, contact_phone=NULL,
			contact_whatsapp=NULL, contact_email=NULL, logo_url=NULL, verification_status='suspended' WHERE user_id=$1`, p.UserID); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE pet_listings SET status='archived', deleted_at=now(), updated_at=now()
			WHERE seller_id IN (SELECT id FROM seller_profiles WHERE user_id=$1) AND deleted_at IS NULL`, p.UserID); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE seller_documents SET deleted_at=now() WHERE seller_id IN (SELECT id FROM seller_profiles WHERE user_id=$1) AND deleted_at IS NULL`, p.UserID); err != nil {
			return err
		}
		for _, q := range []string{`DELETE FROM buyer_profiles WHERE user_id=$1`, `DELETE FROM favourites WHERE user_id=$1`, `DELETE FROM notifications WHERE user_id=$1`} {
			if _, err := tx.Exec(ctx, q, p.UserID); err != nil {
				return err
			}
		}
		if err := s.RevokeAll(ctx, tx, p.UserID, ""); err != nil {
			return err
		}
		return audit.Log(ctx, tx, audit.Entry{Action: "account.deleted", EntityType: "user", EntityID: p.UserID})
	})
}

// UpdateProfile changes name / phone / avatar.
type ProfileInput struct {
	Name  *string `json:"name"`
	Phone *string `json:"phone"`
}

func (s *Service) UpdateProfile(ctx context.Context, p *authctx.Principal, in ProfileInput) (*User, error) {
	var v httpx.V
	if in.Name != nil {
		*in.Name = strings.TrimSpace(*in.Name)
		v.Length("name", *in.Name, 2, 120)
	}
	if in.Phone != nil {
		*in.Phone = strings.ReplaceAll(strings.TrimSpace(*in.Phone), " ", "")
		if *in.Phone != "" {
			v.Phone("phone", *in.Phone)
		}
	}
	if err := v.Err(); err != nil {
		return nil, err
	}
	_, err := s.db.Exec(ctx, `UPDATE users SET name=COALESCE($2,name),
		phone = CASE WHEN $3::boolean THEN NULLIF($4,'') ELSE phone END, updated_at=now() WHERE id=$1`,
		p.UserID, in.Name, in.Phone != nil, ptrStr(in.Phone))
	if database.IsUniqueViolation(err, "users_phone_key") {
		return nil, httpx.Conflict(httpx.CodeConflict, "That phone number is already in use")
	}
	if err != nil {
		return nil, err
	}
	return s.Me(ctx, p)
}

// ---------- helpers ----------

func ptrStr(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

func truncate(s string, n int) string {
	if len(s) > n {
		return s[:n]
	}
	return s
}

func slugify(s string) string {
	var b strings.Builder
	dash := false
	for _, r := range strings.ToLower(s) {
		switch {
		case r < unicode.MaxASCII && (unicode.IsLetter(r) || unicode.IsDigit(r)):
			b.WriteRune(r)
			dash = false
		default:
			if !dash && b.Len() > 0 {
				b.WriteByte('-')
				dash = true
			}
		}
	}
	out := strings.Trim(b.String(), "-")
	if out == "" {
		out = "seller"
	}
	if len(out) > 40 {
		out = strings.Trim(out[:40], "-")
	}
	return out
}

func (s *Service) String() string { return fmt.Sprintf("auth.Service(%s)", s.cfg.Env) }

// BootstrapMFA enables TOTP with a fresh secret (used only by the non-production demo seeder).
func (s *Service) BootstrapMFA(ctx context.Context, userID string) (string, error) {
	secret := security.NewTOTPSecret()
	enc, err := s.box.Seal(secret)
	if err != nil {
		return "", err
	}
	_, err = s.db.Exec(ctx, `UPDATE users SET mfa_secret_enc=$2, mfa_enabled_at=now() WHERE id=$1`, userID, enc)
	return secret, err
}
