// Package authctx carries the authenticated principal through request contexts.
package authctx

import "context"

type Principal struct {
	UserID        string
	SessionID     string
	AccountType   string // buyer | seller | staff
	Email         string
	Name          string
	Roles         []string
	Perms         map[string]bool
	MFAEnabled    bool
	MFAVerified   bool // true when this session passed MFA (admin sessions)
	EmailVerified bool
}

type ctxKey struct{}

func With(ctx context.Context, p *Principal) context.Context {
	return context.WithValue(ctx, ctxKey{}, p)
}
func From(ctx context.Context) *Principal {
	p, _ := ctx.Value(ctxKey{}).(*Principal)
	return p
}

func (p *Principal) HasRole(role string) bool {
	if p == nil {
		return false
	}
	for _, r := range p.Roles {
		if r == role {
			return true
		}
	}
	return false
}
func (p *Principal) Can(perm string) bool { return p != nil && p.Perms[perm] }
func (p *Principal) IsStaff() bool        { return p != nil && p.AccountType == "staff" }
