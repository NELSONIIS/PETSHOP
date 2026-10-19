// Package subscriptions owns plans, entitlements and the subscription lifecycle
// (activation, renewal, upgrade, cancellation, grace and expiry).
package subscriptions

import (
	"context"
	"encoding/json"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"petora/internal/audit"
	"petora/internal/cache"
	"petora/internal/database"
	"petora/internal/httpx"
	"petora/internal/settings"
)

type Service struct {
	db       *database.DB
	cache    *cache.Cache
	settings *settings.Service
	baseURL  string
}

func NewService(db *database.DB, c *cache.Cache, st *settings.Service, baseURL string) *Service {
	return &Service{db: db, cache: c, settings: st, baseURL: baseURL}
}

var entitlementKeys = []string{"listing_limit", "contact_unlocks", "enquiries", "analytics", "featured_slots"}
var boolKeys = map[string]bool{"analytics": true}

type Plan struct {
	ID                 string         `json:"id"`
	Code               string         `json:"code"`
	Audience           string         `json:"audience"`
	Name               string         `json:"name"`
	Description        string         `json:"description"`
	PriceMinor         int64          `json:"price_minor"`
	PromoPriceMinor    *int64         `json:"promo_price_minor"`
	PromoStartsAt      *time.Time     `json:"promo_starts_at,omitempty"`
	PromoEndsAt        *time.Time     `json:"promo_ends_at"`
	EffectivePrice     int64          `json:"effective_price_minor"`
	TaxRateBps         int            `json:"tax_rate_bps"`
	TaxMinor           int64          `json:"tax_minor"`
	TotalMinor         int64          `json:"total_minor"`
	Currency           string         `json:"currency"`
	BillingInterval    string         `json:"billing_interval"`
	IntervalCount      int            `json:"interval_count"`
	TrialDays          int            `json:"trial_days"`
	GraceDays          int            `json:"grace_days"`
	RenewalWindowDays  int            `json:"renewal_window_days"`
	AutoRenew          bool           `json:"auto_renew"`
	CancellationPolicy string         `json:"cancellation_policy"`
	RefundWindowDays   int            `json:"refund_window_days"`
	RefundPolicy       string         `json:"refund_policy"`
	IsActive           bool           `json:"is_active"`
	SortOrder          int            `json:"sort_order"`
	Features           []string       `json:"features"`
	Entitlements       map[string]any `json:"entitlements"`
}

const planCols = `p.id, p.code, p.audience, p.name, p.description, p.price_minor, p.promo_price_minor, p.promo_starts_at, p.promo_ends_at,
	p.currency, p.billing_interval, p.interval_count, p.tax_rate_bps, p.trial_days, p.grace_days, p.renewal_window_days, p.auto_renew,
	p.cancellation_policy, p.refund_window_days, p.refund_policy, p.is_active, p.sort_order, p.features,
	COALESCE((SELECT jsonb_object_agg(e.key, CASE WHEN e.bool_value IS NOT NULL THEN to_jsonb(e.bool_value) ELSE to_jsonb(e.int_value) END)
	          FROM plan_entitlements e WHERE e.plan_id = p.id), '{}'::jsonb)`

func scanPlan(row pgx.Row) (*Plan, error) {
	var p Plan
	var features, ents []byte
	err := row.Scan(&p.ID, &p.Code, &p.Audience, &p.Name, &p.Description, &p.PriceMinor, &p.PromoPriceMinor, &p.PromoStartsAt, &p.PromoEndsAt,
		&p.Currency, &p.BillingInterval, &p.IntervalCount, &p.TaxRateBps, &p.TrialDays, &p.GraceDays, &p.RenewalWindowDays, &p.AutoRenew,
		&p.CancellationPolicy, &p.RefundWindowDays, &p.RefundPolicy, &p.IsActive, &p.SortOrder, &features, &ents)
	if err != nil {
		return nil, err
	}
	_ = json.Unmarshal(features, &p.Features)
	if p.Features == nil {
		p.Features = []string{}
	}
	p.Entitlements = map[string]any{}
	_ = json.Unmarshal(ents, &p.Entitlements)
	for _, k := range entitlementKeys { // normalise: explicit key for every entitlement
		if _, ok := p.Entitlements[k]; !ok {
			if boolKeys[k] {
				p.Entitlements[k] = false
			} else {
				p.Entitlements[k] = 0
			}
		}
	}
	p.compute(time.Now())
	return &p, nil
}

// compute derives the promotional price and tax. Integer maths only.
func (p *Plan) compute(now time.Time) {
	p.EffectivePrice = p.PriceMinor
	if p.PromoPriceMinor != nil &&
		(p.PromoStartsAt == nil || !p.PromoStartsAt.After(now)) &&
		(p.PromoEndsAt == nil || p.PromoEndsAt.After(now)) {
		p.EffectivePrice = *p.PromoPriceMinor
	}
	p.TaxMinor = (p.EffectivePrice*int64(p.TaxRateBps) + 5000) / 10000
	p.TotalMinor = p.EffectivePrice + p.TaxMinor
}

func (s *Service) ListPlans(ctx context.Context, audience string, activeOnly bool) ([]Plan, error) {
	var out []Plan
	cacheKey := "plans:" + audience
	if activeOnly && s.cache.GetJSON(ctx, cacheKey, &out) {
		for i := range out {
			out[i].compute(time.Now())
		}
		return out, nil
	}
	q := `SELECT ` + planCols + ` FROM subscription_plans p WHERE ($1 = '' OR p.audience = $1)`
	if activeOnly {
		q += ` AND p.is_active`
	}
	rows, err := s.db.Query(ctx, q+` ORDER BY p.audience, p.sort_order, p.price_minor`, audience)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out = []Plan{}
	for rows.Next() {
		p, err := scanPlan(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *p)
	}
	if activeOnly {
		s.cache.SetJSON(ctx, cacheKey, out, 5*time.Minute)
	}
	return out, rows.Err()
}

func (s *Service) GetPlan(ctx context.Context, q database.Querier, id string) (*Plan, error) {
	p, err := scanPlan(q.QueryRow(ctx, `SELECT `+planCols+` FROM subscription_plans p WHERE p.id::text = $1`, id))
	if database.IsNoRows(err) {
		return nil, httpx.NotFound("Plan")
	}
	return p, err
}

type PlanInput struct {
	Code               string                     `json:"code"`
	Audience           string                     `json:"audience"`
	Name               string                     `json:"name"`
	Description        string                     `json:"description"`
	PriceMinor         int64                      `json:"price_minor"`
	Currency           string                     `json:"currency"`
	PromoPriceMinor    *int64                     `json:"promo_price_minor"`
	PromoStartsAt      *time.Time                 `json:"promo_starts_at"`
	PromoEndsAt        *time.Time                 `json:"promo_ends_at"`
	BillingInterval    string                     `json:"billing_interval"`
	IntervalCount      int                        `json:"interval_count"`
	TaxRateBps         int                        `json:"tax_rate_bps"`
	TrialDays          int                        `json:"trial_days"`
	GraceDays          int                        `json:"grace_days"`
	RenewalWindowDays  *int                       `json:"renewal_window_days"`
	AutoRenew          bool                       `json:"auto_renew"`
	CancellationPolicy string                     `json:"cancellation_policy"`
	RefundWindowDays   int                        `json:"refund_window_days"`
	RefundPolicy       string                     `json:"refund_policy"`
	IsActive           *bool                      `json:"is_active"`
	SortOrder          int                        `json:"sort_order"`
	Features           []string                   `json:"features"`
	Entitlements       map[string]json.RawMessage `json:"entitlements"`
}

func (in *PlanInput) validate(creating bool) error {
	var v httpx.V
	in.Code = strings.ToLower(strings.TrimSpace(in.Code))
	in.Name = strings.TrimSpace(in.Name)
	if creating {
		v.Required("code", in.Code)
		v.OneOf("audience", in.Audience, "buyer", "seller")
	}
	v.Length("name", in.Name, 2, 80)
	v.Range("price_minor", in.PriceMinor, 0, 100_000_000)
	v.OneOf("billing_interval", in.BillingInterval, "month", "quarter", "year")
	if in.IntervalCount == 0 {
		in.IntervalCount = 1
	}
	v.Range("interval_count", int64(in.IntervalCount), 1, 36)
	v.Range("tax_rate_bps", int64(in.TaxRateBps), 0, 10000)
	v.Range("trial_days", int64(in.TrialDays), 0, 365)
	v.Range("grace_days", int64(in.GraceDays), 0, 90)
	v.Range("refund_window_days", int64(in.RefundWindowDays), 0, 365)
	if in.Currency == "" {
		in.Currency = "INR"
	}
	if len(in.Currency) != 3 {
		v.Add("currency", "must be a 3-letter ISO code")
	}
	if in.CancellationPolicy == "" {
		in.CancellationPolicy = "end_of_period"
	}
	v.OneOf("cancellation_policy", in.CancellationPolicy, "end_of_period", "immediate")
	if in.PromoPriceMinor != nil {
		if *in.PromoPriceMinor < 0 || *in.PromoPriceMinor > in.PriceMinor {
			v.Add("promo_price_minor", "must be between 0 and the list price")
		}
		if in.PromoStartsAt != nil && in.PromoEndsAt != nil && !in.PromoEndsAt.After(*in.PromoStartsAt) {
			v.Add("promo_ends_at", "must be after the promotion start")
		}
	}
	for k, raw := range in.Entitlements {
		ok := false
		for _, kk := range entitlementKeys {
			ok = ok || kk == k
		}
		if !ok {
			v.Add("entitlements."+k, "is not a known entitlement")
			continue
		}
		if boolKeys[k] {
			var b bool
			if json.Unmarshal(raw, &b) != nil {
				v.Add("entitlements."+k, "must be true or false")
			}
		} else if string(raw) != "null" {
			var n int
			if json.Unmarshal(raw, &n) != nil || n < 0 {
				v.Add("entitlements."+k, "must be a non-negative integer or null (unlimited)")
			}
		}
	}
	if in.Features == nil {
		in.Features = []string{}
	}
	return v.Err()
}

func (s *Service) invalidatePlans(ctx context.Context) { s.cache.DelPrefix(ctx, "plans:") }

func (s *Service) CreatePlan(ctx context.Context, in PlanInput) (*Plan, error) {
	if err := in.validate(true); err != nil {
		return nil, err
	}
	var id string
	err := s.db.InTx(ctx, func(tx pgx.Tx) error {
		active := true
		if in.IsActive != nil {
			active = *in.IsActive
		}
		window := 7
		if in.RenewalWindowDays != nil {
			window = *in.RenewalWindowDays
		}
		feat, _ := json.Marshal(in.Features)
		if err := tx.QueryRow(ctx, `INSERT INTO subscription_plans
			(code, audience, name, description, price_minor, currency, promo_price_minor, promo_starts_at, promo_ends_at, billing_interval,
			 interval_count, tax_rate_bps, trial_days, grace_days, renewal_window_days, auto_renew, cancellation_policy, refund_window_days,
			 refund_policy, is_active, sort_order, features)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22) RETURNING id`,
			in.Code, in.Audience, in.Name, in.Description, in.PriceMinor, in.Currency, in.PromoPriceMinor, in.PromoStartsAt, in.PromoEndsAt,
			in.BillingInterval, in.IntervalCount, in.TaxRateBps, in.TrialDays, in.GraceDays, window, in.AutoRenew, in.CancellationPolicy,
			in.RefundWindowDays, in.RefundPolicy, active, in.SortOrder, feat).Scan(&id); err != nil {
			return err
		}
		if err := writeEntitlements(ctx, tx, id, in.Entitlements); err != nil {
			return err
		}
		return audit.Log(ctx, tx, audit.Entry{Action: "plan.created", EntityType: "plan", EntityID: id, Metadata: map[string]any{"code": in.Code, "price_minor": in.PriceMinor}})
	})
	if database.IsUniqueViolation(err, "subscription_plans_code_key") {
		return nil, httpx.Conflict(httpx.CodeConflict, "A plan with this code already exists")
	}
	if err != nil {
		return nil, err
	}
	s.invalidatePlans(ctx)
	return s.GetPlan(ctx, s.db, id)
}

func (s *Service) UpdatePlan(ctx context.Context, id string, in PlanInput) (*Plan, error) {
	if err := in.validate(false); err != nil {
		return nil, err
	}
	err := s.db.InTx(ctx, func(tx pgx.Tx) error {
		cur, err := s.GetPlan(ctx, tx, id)
		if err != nil {
			return err
		}
		active := cur.IsActive
		if in.IsActive != nil {
			active = *in.IsActive
		}
		window := cur.RenewalWindowDays
		if in.RenewalWindowDays != nil {
			window = *in.RenewalWindowDays
		}
		feat, _ := json.Marshal(in.Features)
		// Code and audience are immutable: subscriptions and invoices reference them.
		if _, err := tx.Exec(ctx, `UPDATE subscription_plans SET name=$2, description=$3, price_minor=$4, currency=$5, promo_price_minor=$6,
			promo_starts_at=$7, promo_ends_at=$8, billing_interval=$9, interval_count=$10, tax_rate_bps=$11, trial_days=$12, grace_days=$13,
			renewal_window_days=$14, auto_renew=$15, cancellation_policy=$16, refund_window_days=$17, refund_policy=$18, is_active=$19,
			sort_order=$20, features=$21, updated_at=now() WHERE id=$1`,
			id, in.Name, in.Description, in.PriceMinor, in.Currency, in.PromoPriceMinor, in.PromoStartsAt, in.PromoEndsAt, in.BillingInterval,
			in.IntervalCount, in.TaxRateBps, in.TrialDays, in.GraceDays, window, in.AutoRenew, in.CancellationPolicy, in.RefundWindowDays,
			in.RefundPolicy, active, in.SortOrder, feat); err != nil {
			return err
		}
		if in.Entitlements != nil {
			if err := writeEntitlements(ctx, tx, id, in.Entitlements); err != nil {
				return err
			}
		}
		return audit.Log(ctx, tx, audit.Entry{Action: "plan.updated", EntityType: "plan", EntityID: id,
			Metadata: map[string]any{"before_price_minor": cur.PriceMinor, "after_price_minor": in.PriceMinor, "active": active}})
	})
	if err != nil {
		return nil, err
	}
	s.invalidatePlans(ctx)
	return s.GetPlan(ctx, s.db, id)
}

func writeEntitlements(ctx context.Context, tx pgx.Tx, planID string, ents map[string]json.RawMessage) error {
	for _, k := range entitlementKeys {
		raw, present := ents[k]
		var intVal *int
		var boolVal *bool
		switch {
		case boolKeys[k]:
			b := false
			if present {
				_ = json.Unmarshal(raw, &b)
			}
			boolVal = &b
		case present && string(raw) == "null": // unlimited
		default:
			n := 0
			if present {
				_ = json.Unmarshal(raw, &n)
			}
			intVal = &n
		}
		if _, err := tx.Exec(ctx, `INSERT INTO plan_entitlements (plan_id, key, int_value, bool_value) VALUES ($1,$2,$3,$4)
			ON CONFLICT (plan_id, key) DO UPDATE SET int_value=EXCLUDED.int_value, bool_value=EXCLUDED.bool_value`, planID, k, intVal, boolVal); err != nil {
			return err
		}
	}
	return nil
}
