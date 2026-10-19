// Package settings exposes admin-configurable platform settings with a short in-process cache.
// Replicas converge within cacheTTL after an admin change (local cache is dropped immediately).
package settings

import (
	"context"
	"encoding/json"
	"sync"
	"time"

	"petora/internal/database"
)

const cacheTTL = 10 * time.Second

type Service struct {
	db *database.DB
	mu sync.RWMutex
	at time.Time
	m  map[string]json.RawMessage
}

func New(db *database.DB) *Service { return &Service{db: db} }

func (s *Service) load(ctx context.Context) map[string]json.RawMessage {
	s.mu.RLock()
	if s.m != nil && time.Since(s.at) < cacheTTL {
		m := s.m
		s.mu.RUnlock()
		return m
	}
	s.mu.RUnlock()
	rows, err := s.db.Query(ctx, `SELECT key, value FROM platform_settings`)
	if err != nil {
		s.mu.RLock()
		defer s.mu.RUnlock()
		return s.m // stale is better than failing
	}
	defer rows.Close()
	m := map[string]json.RawMessage{}
	for rows.Next() {
		var k string
		var v json.RawMessage
		if rows.Scan(&k, &v) == nil {
			m[k] = v
		}
	}
	s.mu.Lock()
	s.m, s.at = m, time.Now()
	s.mu.Unlock()
	return m
}

func (s *Service) Invalidate() { s.mu.Lock(); s.m = nil; s.mu.Unlock() }

func (s *Service) Bool(ctx context.Context, key string, def bool) bool {
	var v bool
	if raw, ok := s.load(ctx)[key]; ok && json.Unmarshal(raw, &v) == nil {
		return v
	}
	return def
}
func (s *Service) Int(ctx context.Context, key string, def int) int {
	var v int
	if raw, ok := s.load(ctx)[key]; ok && json.Unmarshal(raw, &v) == nil {
		return v
	}
	return def
}
func (s *Service) String(ctx context.Context, key, def string) string {
	var v string
	if raw, ok := s.load(ctx)[key]; ok && json.Unmarshal(raw, &v) == nil {
		return v
	}
	return def
}
func (s *Service) Strings(ctx context.Context, key string, def []string) []string {
	var v []string
	if raw, ok := s.load(ctx)[key]; ok && json.Unmarshal(raw, &v) == nil {
		return v
	}
	return def
}

type Setting struct {
	Key       string          `json:"key"`
	Value     json.RawMessage `json:"value"`
	IsPublic  bool            `json:"is_public"`
	UpdatedAt time.Time       `json:"updated_at"`
}

func (s *Service) List(ctx context.Context, publicOnly bool) ([]Setting, error) {
	q := `SELECT key, value, is_public, updated_at FROM platform_settings`
	if publicOnly {
		q += ` WHERE is_public`
	}
	rows, err := s.db.Query(ctx, q+` ORDER BY key`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Setting{}
	for rows.Next() {
		var st Setting
		if err := rows.Scan(&st.Key, &st.Value, &st.IsPublic, &st.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, st)
	}
	return out, rows.Err()
}

// Set upserts a value. Unknown keys are rejected so typos cannot create dead settings.
func (s *Service) Set(ctx context.Context, q database.Querier, key string, value json.RawMessage, actor string) (bool, error) {
	tag, err := q.Exec(ctx, `UPDATE platform_settings SET value=$2, updated_by=$3, updated_at=now() WHERE key=$1`, key, value, actor)
	if err != nil {
		return false, err
	}
	s.Invalidate()
	return tag.RowsAffected() == 1, nil
}
