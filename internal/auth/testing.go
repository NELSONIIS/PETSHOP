package auth

import (
	"context"

	"petora/internal/security"
)

// ChangePasswordForTest creates (or resets) a staff account WITHOUT MFA. It exists so tests can prove
// that MFA-less staff are locked out of the admin API; it refuses to run in production.
func (s *Service) ChangePasswordForTest(ctx context.Context, email, password string) error {
	if s.cfg.IsProduction() {
		return nil
	}
	h, err := security.HashPassword(password)
	if err != nil {
		return err
	}
	var id string
	if err := s.db.QueryRow(ctx, `INSERT INTO users (email, name, password_hash, account_type, email_verified_at) VALUES ($1,'No MFA staff',$2,'staff',now())
		ON CONFLICT (email) DO UPDATE SET password_hash=EXCLUDED.password_hash RETURNING id`, email, h).Scan(&id); err != nil {
		return err
	}
	_, err = s.db.Exec(ctx, `INSERT INTO user_roles (user_id, role_code) VALUES ($1,'super_admin') ON CONFLICT DO NOTHING`, id)
	return err
}
