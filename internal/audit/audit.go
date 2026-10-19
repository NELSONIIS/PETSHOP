// Package audit writes structured audit events for sensitive actions.
package audit

import (
	"context"
	"encoding/json"
	"log/slog"

	"petora/internal/authctx"
	"petora/internal/database"
	"petora/internal/httpx"
)

type Entry struct {
	Action     string
	EntityType string
	EntityID   string
	Metadata   map[string]any
	IP         string
}

// Log writes within q (pass a pgx.Tx so the audit row commits atomically with the change).
// The actor and request id are taken from ctx. Failures are logged, never swallowed silently
// for financial actions: callers inside a transaction should return the error.
func Log(ctx context.Context, q database.Querier, e Entry) error {
	var actor *string
	var roles []string
	if p := authctx.From(ctx); p != nil {
		actor = &p.UserID
		roles = p.Roles
	}
	if roles == nil {
		roles = []string{}
	}
	meta, _ := json.Marshal(e.Metadata)
	if e.Metadata == nil {
		meta = []byte("{}")
	}
	_, err := q.Exec(ctx, `INSERT INTO audit_logs (actor_id, actor_roles, action, entity_type, entity_id, metadata, ip, request_id)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`, actor, roles, e.Action, e.EntityType, e.EntityID, meta, e.IP, httpx.RequestID(ctx))
	if err != nil {
		slog.ErrorContext(ctx, "audit write failed", "action", e.Action, "err", err)
	}
	return err
}

// System logs an event with no human actor (workers, webhooks).
func System(ctx context.Context, q database.Querier, action, entityType, entityID string, meta map[string]any) {
	b, _ := json.Marshal(meta)
	if meta == nil {
		b = []byte("{}")
	}
	if _, err := q.Exec(ctx, `INSERT INTO audit_logs (action, entity_type, entity_id, metadata) VALUES ($1,$2,$3,$4)`,
		action, entityType, entityID, b); err != nil {
		slog.ErrorContext(ctx, "audit write failed", "action", action, "err", err)
	}
}

// ActorID returns the acting user's id from ctx, or nil for system actions.
func ActorID(ctx context.Context) *string {
	if p := authctx.From(ctx); p != nil {
		id := p.UserID
		return &id
	}
	return nil
}
