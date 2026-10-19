package subscriptions

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"petora/internal/audit"
	"petora/internal/database"
	"petora/internal/httpx"
	"petora/internal/notifications"
)

type Subscription struct {
	ID                 string
	UserID             string
	PlanID             string
	PlanCode           string
	PlanName           string
	Audience           string
	Status             string
	StartsAt           time.Time
	PeriodEnd          time.Time
	GraceEndsAt        time.Time
	CancelAtPeriodEnd  bool
	Entitlements       map[string]json.RawMessage
	UnlocksUsed        int
	EnquiriesUsed      int
	RenewalWindowDays  int
	CancellationPolicy string
}

// Limit returns (limit, unlimited, granted) for a numeric entitlement from the snapshot taken at purchase.
func (sub *Subscription) Limit(key string) (limit int, unlimited, granted bool) {
	raw, ok := sub.Entitlements[key]
	if !ok {
		return 0, false, false
	}
	if string(raw) == "null" {
		return 0, true, true
	}
	if err := json.Unmarshal(raw, &limit); err != nil {
		return 0, false, false
	}
	return limit, false, limit > 0
}

func (sub *Subscription) Flag(key string) bool {
	var b bool
	if raw, ok := sub.Entitlements[key]; ok {
		_ = json.Unmarshal(raw, &b)
	}
	return b
}

const subCols = `s.id, s.user_id, s.plan_id, p.code, p.name, s.audience, s.status, s.starts_at, s.current_period_end, s.grace_ends_at,
	s.cancel_at_period_end, s.entitlements, s.contact_unlocks_used, s.enquiries_used, p.renewal_window_days, p.cancellation_policy`

func scanSub(row pgx.Row) (*Subscription, error) {
	var sub Subscription
	var ents []byte
	err := row.Scan(&sub.ID, &sub.UserID, &sub.PlanID, &sub.PlanCode, &sub.PlanName, &sub.Audience, &sub.Status, &sub.StartsAt, &sub.PeriodEnd,
		&sub.GraceEndsAt, &sub.CancelAtPeriodEnd, &ents, &sub.UnlocksUsed, &sub.EnquiriesUsed, &sub.RenewalWindowDays, &sub.CancellationPolicy)
	if err != nil {
		return nil, err
	}
	_ = json.Unmarshal(ents, &sub.Entitlements)
	if sub.Entitlements == nil {
		sub.Entitlements = map[string]json.RawMessage{}
	}
	return &sub, nil
}

// Live returns the user's active-or-grace subscription for the audience, or nil. forUpdate locks the row.
func (s *Service) Live(ctx context.Context, q database.Querier, userID, audience string, forUpdate bool) (*Subscription, error) {
	lock := ""
	if forUpdate {
		lock = " FOR UPDATE OF s"
	}
	sub, err := scanSub(q.QueryRow(ctx, `SELECT `+subCols+` FROM subscriptions s JOIN subscription_plans p ON p.id=s.plan_id
		WHERE s.user_id=$1 AND s.audience=$2 AND s.status IN ('active','grace')`+lock, userID, audience))
	if database.IsNoRows(err) {
		return nil, nil
	}
	return sub, err
}

// Latest returns the newest subscription in any state (to explain expired status in the UI).
func (s *Service) Latest(ctx context.Context, userID, audience string) (*Subscription, error) {
	sub, err := scanSub(s.db.QueryRow(ctx, `SELECT `+subCols+` FROM subscriptions s JOIN subscription_plans p ON p.id=s.plan_id
		WHERE s.user_id=$1 AND s.audience=$2 ORDER BY s.created_at DESC LIMIT 1`, userID, audience))
	if database.IsNoRows(err) {
		return nil, nil
	}
	return sub, err
}

func addInterval(t time.Time, interval string, count int) time.Time {
	switch interval {
	case "year":
		return t.AddDate(count, 0, 0)
	case "quarter":
		return t.AddDate(0, 3*count, 0)
	default:
		return t.AddDate(0, count, 0)
	}
}

// PlanSnapshot is stored on the payment at checkout so activation uses exactly what was sold.
type PlanSnapshot struct {
	PlanID          string                     `json:"plan_id"`
	Code            string                     `json:"code"`
	Name            string                     `json:"name"`
	Audience        string                     `json:"audience"`
	BillingInterval string                     `json:"billing_interval"`
	IntervalCount   int                        `json:"interval_count"`
	TrialDays       int                        `json:"trial_days"`
	GraceDays       int                        `json:"grace_days"`
	Entitlements    map[string]json.RawMessage `json:"entitlements"`
}

func (p *Plan) Snapshot() PlanSnapshot {
	ents := map[string]json.RawMessage{}
	for k, v := range p.Entitlements {
		b, _ := json.Marshal(v)
		ents[k] = b
	}
	return PlanSnapshot{PlanID: p.ID, Code: p.Code, Name: p.Name, Audience: p.Audience, BillingInterval: p.BillingInterval,
		IntervalCount: p.IntervalCount, TrialDays: p.TrialDays, GraceDays: p.GraceDays, Entitlements: ents}
}

// CanPurchase enforces "the same entitlement must not be charged twice".
//   - no live subscription                          -> allowed
//   - same plan, inside the renewal window          -> allowed (renewal extends the term)
//   - same plan, outside the window                 -> 409 already_subscribed
//   - different plan                                -> allowed (upgrade/downgrade supersedes, no proration)
func (s *Service) CanPurchase(ctx context.Context, q database.Querier, userID string, plan *Plan) error {
	live, err := s.Live(ctx, q, userID, plan.Audience, false)
	if err != nil || live == nil {
		return err
	}
	if live.PlanID != plan.ID {
		return nil
	}
	if live.Status == "grace" || !time.Now().Before(live.PeriodEnd.AddDate(0, 0, -live.RenewalWindowDays)) {
		return nil
	}
	return httpx.Conflict("already_subscribed", fmt.Sprintf("You already have an active %s plan until %s. You can renew within %d days of expiry.",
		plan.Name, live.PeriodEnd.Format("2 Jan 2006"), live.RenewalWindowDays))
}

// Activate turns a succeeded payment into a subscription. It must run inside the payment-finalising transaction.
// Idempotent: subscriptions.payment_id is unique, so a payment can never activate twice.
func (s *Service) Activate(ctx context.Context, tx pgx.Tx, paymentID, userID string, snap PlanSnapshot, userName, userEmail, invoiceNo string) (subID string, err error) {
	var existing string
	if err := tx.QueryRow(ctx, `SELECT COALESCE((SELECT id::text FROM subscriptions WHERE payment_id=$1), '')`, paymentID).Scan(&existing); err != nil {
		return "", err
	}
	if existing != "" {
		return existing, nil
	}
	now := time.Now().UTC()
	start := now
	var prior *Subscription
	if prior, err = s.Live(ctx, tx, userID, snap.Audience, true); err != nil {
		return "", err
	}
	renewal := prior != nil && prior.PlanID == snap.PlanID && prior.Status == "active" && prior.PeriodEnd.After(now)
	if renewal {
		start = prior.PeriodEnd // term continues seamlessly
	}
	periodEnd := addInterval(start, snap.BillingInterval, snap.IntervalCount)
	if snap.TrialDays > 0 {
		var had bool
		if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM subscriptions WHERE user_id=$1 AND audience=$2)`, userID, snap.Audience).Scan(&had); err != nil {
			return "", err
		}
		if !had { // bonus days apply to the first-ever purchase only
			periodEnd = periodEnd.AddDate(0, 0, snap.TrialDays)
		}
	}
	graceEnd := periodEnd.AddDate(0, 0, snap.GraceDays)
	if prior != nil {
		if _, err := tx.Exec(ctx, `UPDATE subscriptions SET status='superseded', updated_at=now() WHERE id=$1`, prior.ID); err != nil {
			return "", err
		}
	}
	ents, _ := json.Marshal(snap.Entitlements)
	if err := tx.QueryRow(ctx, `INSERT INTO subscriptions (user_id, plan_id, audience, status, starts_at, current_period_end, grace_ends_at, entitlements, payment_id)
		VALUES ($1,$2,$3,'active',$4,$5,$6,$7,$8) RETURNING id`, userID, snap.PlanID, snap.Audience, now, periodEnd, graceEnd, ents, paymentID).Scan(&subID); err != nil {
		return "", err
	}
	if snap.Audience == "seller" {
		// Re-publish listings that were hidden only because the previous subscription lapsed.
		tag, err := tx.Exec(ctx, `UPDATE pet_listings SET status='approved', expired_reason=NULL, updated_at=now()
			WHERE status='expired' AND expired_reason='subscription' AND (expires_at IS NULL OR expires_at > now())
			  AND seller_id IN (SELECT id FROM seller_profiles WHERE user_id=$1)`, userID)
		if err != nil {
			return "", err
		}
		if tag.RowsAffected() > 0 {
			s.cache.DelPrefix(ctx, "pets:")
		}
	}
	if err := notifications.Create(ctx, tx, userID, "subscription_activated", "Your "+snap.Name+" plan is active",
		"Valid until "+periodEnd.Format("2 Jan 2006")+".", map[string]any{"subscription_id": subID}); err != nil {
		return "", err
	}
	if err := notifications.EnqueueEmail(ctx, tx, userEmail, "subscription_activated", map[string]string{
		"name": userName, "plan": snap.Name, "until": periodEnd.Format("2 Jan 2006"), "invoice": invoiceNo}); err != nil {
		return "", err
	}
	audit.System(ctx, tx, "subscription.activated", "subscription", subID, map[string]any{"user_id": userID, "plan": snap.Code, "payment_id": paymentID, "renewal": renewal})
	return subID, nil
}

// ---------- cancellation ----------

func (s *Service) Cancel(ctx context.Context, userID, subID string) error {
	return s.db.InTx(ctx, func(tx pgx.Tx) error {
		sub, err := scanSub(tx.QueryRow(ctx, `SELECT `+subCols+` FROM subscriptions s JOIN subscription_plans p ON p.id=s.plan_id
			WHERE s.id::text=$1 AND s.user_id=$2 AND s.status IN ('active','grace') FOR UPDATE OF s`, subID, userID))
		if database.IsNoRows(err) {
			return httpx.NotFound("Subscription")
		}
		if err != nil {
			return err
		}
		if sub.CancellationPolicy == "immediate" {
			if _, err := tx.Exec(ctx, `UPDATE subscriptions SET status='cancelled', cancelled_at=now(), updated_at=now() WHERE id=$1`, sub.ID); err != nil {
				return err
			}
			if sub.Audience == "seller" {
				if err := s.applyListingPolicy(ctx, tx, sub.UserID); err != nil {
					return err
				}
			}
		} else {
			if _, err := tx.Exec(ctx, `UPDATE subscriptions SET cancel_at_period_end=true, cancelled_at=now(), updated_at=now() WHERE id=$1`, sub.ID); err != nil {
				return err
			}
		}
		return audit.Log(ctx, tx, audit.Entry{Action: "subscription.cancelled", EntityType: "subscription", EntityID: sub.ID,
			Metadata: map[string]any{"policy": sub.CancellationPolicy}})
	})
}

// ---------- expiry ----------

// applyListingPolicy implements settings key listings.on_subscription_expiry:
//
//	"unpublish" (default): approved listings become 'expired' (reason 'subscription') and disappear from search;
//	                       they come back automatically when the seller renews.
//	"keep":                listings stay published until their own expiry date.
func (s *Service) applyListingPolicy(ctx context.Context, tx pgx.Tx, sellerUserID string) error {
	if s.settings.String(ctx, "listings.on_subscription_expiry", "unpublish") != "unpublish" {
		return nil
	}
	rows, err := tx.Query(ctx, `UPDATE pet_listings SET status='expired', expired_reason='subscription', updated_at=now()
		WHERE status='approved' AND seller_id IN (SELECT id FROM seller_profiles WHERE user_id=$1) RETURNING id`, sellerUserID)
	if err != nil {
		return err
	}
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return err
		}
		ids = append(ids, id)
	}
	rows.Close()
	for _, id := range ids {
		if _, err := tx.Exec(ctx, `INSERT INTO listing_moderation (listing_id, action, reason) VALUES ($1,'expired','Seller subscription ended')`, id); err != nil {
			return err
		}
	}
	return nil
}

// SweepExpiry advances subscription states. Safe to run concurrently (row locks + SKIP LOCKED) and repeatedly.
func (s *Service) SweepExpiry(ctx context.Context) (moved int, err error) {
	for {
		n := 0
		err = s.db.InTx(ctx, func(tx pgx.Tx) error {
			rows, err := tx.Query(ctx, `SELECT `+subCols+`, u.email, u.name FROM subscriptions s
				JOIN subscription_plans p ON p.id=s.plan_id JOIN users u ON u.id=s.user_id
				WHERE (s.status='active' AND s.current_period_end <= now()) OR (s.status='grace' AND s.grace_ends_at <= now())
				ORDER BY s.current_period_end LIMIT 50 FOR UPDATE OF s SKIP LOCKED`)
			if err != nil {
				return err
			}
			type item struct {
				sub         *Subscription
				email, name string
			}
			var items []item
			for rows.Next() {
				var sub Subscription
				var ents []byte
				var it item
				if err := rows.Scan(&sub.ID, &sub.UserID, &sub.PlanID, &sub.PlanCode, &sub.PlanName, &sub.Audience, &sub.Status, &sub.StartsAt, &sub.PeriodEnd,
					&sub.GraceEndsAt, &sub.CancelAtPeriodEnd, &ents, &sub.UnlocksUsed, &sub.EnquiriesUsed, &sub.RenewalWindowDays, &sub.CancellationPolicy,
					&it.email, &it.name); err != nil {
					rows.Close()
					return err
				}
				it.sub = &sub
				items = append(items, it)
			}
			rows.Close()
			for _, it := range items {
				sub := it.sub
				now := time.Now()
				toGrace := sub.Status == "active" && !sub.CancelAtPeriodEnd && now.Before(sub.GraceEndsAt)
				if toGrace {
					if _, err := tx.Exec(ctx, `UPDATE subscriptions SET status='grace', updated_at=now() WHERE id=$1`, sub.ID); err != nil {
						return err
					}
					if err := notifications.Create(ctx, tx, sub.UserID, "subscription_grace", "Your plan has ended — grace period",
						"Renew by "+sub.GraceEndsAt.Format("2 Jan 2006")+" to keep your benefits.", map[string]any{"subscription_id": sub.ID}); err != nil {
						return err
					}
				} else {
					if _, err := tx.Exec(ctx, `UPDATE subscriptions SET status='expired', updated_at=now() WHERE id=$1`, sub.ID); err != nil {
						return err
					}
					detail := ""
					if sub.Audience == "seller" {
						if err := s.applyListingPolicy(ctx, tx, sub.UserID); err != nil {
							return err
						}
						if s.settings.String(ctx, "listings.on_subscription_expiry", "unpublish") == "unpublish" {
							detail = "Your listings are hidden until you renew; they will be restored automatically."
						}
					} else if !s.settings.Bool(ctx, "contacts.retain_after_expiry", true) {
						detail = "Contacts you unlocked are no longer available until you renew."
					} else {
						detail = "Contacts you already unlocked remain available to you."
					}
					if err := notifications.Create(ctx, tx, sub.UserID, "subscription_expired", "Your "+sub.PlanName+" plan has expired", detail,
						map[string]any{"subscription_id": sub.ID}); err != nil {
						return err
					}
					if err := notifications.EnqueueEmail(ctx, tx, it.email, "subscription_expired", map[string]string{
						"name": it.name, "plan": sub.PlanName, "detail": detail, "url": s.baseURL + "/pricing"}); err != nil {
						return err
					}
				}
				audit.System(ctx, tx, "subscription.state_changed", "subscription", sub.ID, map[string]any{"from": sub.Status, "to_grace": toGrace})
				n++
			}
			return nil
		})
		if err != nil {
			return moved, err
		}
		moved += n
		if n == 0 {
			break
		}
	}
	if moved > 0 {
		s.cache.DelPrefix(ctx, "pets:")
	}
	return moved, nil
}

// QueueRenewalReminders enqueues one reminder per subscription per configured lead time (deduplicated).
func (s *Service) QueueRenewalReminders(ctx context.Context) error {
	days := s.settings.Strings(ctx, "notifications.renewal_reminder_days", nil)
	leads := []int{7, 3, 1}
	if len(days) > 0 {
		leads = leads[:0]
		for _, d := range days {
			var n int
			if _, err := fmt.Sscanf(d, "%d", &n); err == nil && n > 0 {
				leads = append(leads, n)
			}
		}
	}
	for _, lead := range leads {
		rows, err := s.db.Query(ctx, `SELECT s.id, s.user_id, u.email, u.name, p.name, s.current_period_end
			FROM subscriptions s JOIN users u ON u.id=s.user_id JOIN subscription_plans p ON p.id=s.plan_id
			WHERE s.status='active' AND NOT s.cancel_at_period_end
			  AND s.current_period_end > now() + make_interval(days => $1 - 1) AND s.current_period_end <= now() + make_interval(days => $1)`, lead)
		if err != nil {
			return err
		}
		type r struct {
			id, uid, email, name, plan string
			end                        time.Time
		}
		var list []r
		for rows.Next() {
			var x r
			if err := rows.Scan(&x.id, &x.uid, &x.email, &x.name, &x.plan, &x.end); err != nil {
				rows.Close()
				return err
			}
			list = append(list, x)
		}
		rows.Close()
		for _, x := range list {
			key := fmt.Sprintf("renew:%s:%d", x.id, lead)
			err := s.db.InTx(ctx, func(tx pgx.Tx) error {
				var inserted bool
				if err := tx.QueryRow(ctx, `WITH ins AS (INSERT INTO jobs (kind, payload, status, finished_at, dedupe_key) VALUES ('reminder.marker','{}','succeeded',now(),$1) ON CONFLICT (dedupe_key) DO NOTHING RETURNING 1)
					SELECT EXISTS (SELECT 1 FROM ins)`, key).Scan(&inserted); err != nil || !inserted {
					return err
				}
				when := fmt.Sprintf("in %d days", lead)
				if lead == 1 {
					when = "tomorrow"
				}
				if err := notifications.Create(ctx, tx, x.uid, "subscription_expiring", "Your "+x.plan+" plan expires "+when,
					"Renew before "+x.end.Format("2 Jan 2006")+" to keep your benefits.", map[string]any{"subscription_id": x.id}); err != nil {
					return err
				}
				return notifications.EnqueueEmail(ctx, tx, x.email, "subscription_expiring", map[string]string{
					"name": x.name, "plan": x.plan, "until": x.end.Format("2 Jan 2006"), "when": when, "url": s.baseURL + "/pricing"})
			})
			if err != nil {
				return err
			}
		}
	}
	return nil
}

// ---------- status for API ----------

type PlanRef struct {
	ID   string `json:"id"`
	Code string `json:"code"`
	Name string `json:"name"`
}
type SubView struct {
	ID                string    `json:"id"`
	Status            string    `json:"status"`
	Plan              PlanRef   `json:"plan"`
	StartsAt          time.Time `json:"starts_at"`
	CurrentPeriodEnd  time.Time `json:"current_period_end"`
	GraceEndsAt       time.Time `json:"grace_ends_at"`
	CancelAtPeriodEnd bool      `json:"cancel_at_period_end"`
	CanRenew          bool      `json:"can_renew"`
}
type EntView struct {
	ListingLimit       *int `json:"listing_limit"`
	ListingsUsed       int  `json:"listings_used"`
	ContactUnlocks     *int `json:"contact_unlocks"`
	ContactUnlocksUsed int  `json:"contact_unlocks_used"`
	Enquiries          *int `json:"enquiries"`
	EnquiriesUsed      int  `json:"enquiries_used"`
	Analytics          bool `json:"analytics"`
}
type Status struct {
	Audience     string   `json:"audience"`
	Active       bool     `json:"active"`
	Subscription *SubView `json:"subscription"`
	Entitlements EntView  `json:"entitlements"`
}

// CountSellerListings is the allowance metric: live (not sold/expired/archived) listings of the seller.
func CountSellerListings(ctx context.Context, q database.Querier, sellerUserID string) (int, error) {
	var n int
	err := q.QueryRow(ctx, `SELECT count(*) FROM pet_listings l JOIN seller_profiles sp ON sp.id=l.seller_id
		WHERE sp.user_id=$1 AND l.deleted_at IS NULL AND l.status IN ('draft','pending','approved','rejected','suspended')
		  AND l.availability IN ('available','reserved')`, sellerUserID).Scan(&n)
	return n, err
}

func (s *Service) StatusFor(ctx context.Context, userID, audience string) (*Status, error) {
	st := &Status{Audience: audience}
	sub, err := s.Live(ctx, s.db, userID, audience, false)
	if err != nil {
		return nil, err
	}
	if sub == nil {
		if sub, err = s.Latest(ctx, userID, audience); err != nil {
			return nil, err
		}
	} else {
		st.Active = true
	}
	if audience == "seller" {
		if st.Entitlements.ListingsUsed, err = CountSellerListings(ctx, s.db, userID); err != nil {
			return nil, err
		}
	}
	if sub == nil {
		return st, nil
	}
	st.Subscription = &SubView{ID: sub.ID, Status: sub.Status, Plan: PlanRef{sub.PlanID, sub.PlanCode, sub.PlanName}, StartsAt: sub.StartsAt,
		CurrentPeriodEnd: sub.PeriodEnd, GraceEndsAt: sub.GraceEndsAt, CancelAtPeriodEnd: sub.CancelAtPeriodEnd,
		CanRenew: !time.Now().Before(sub.PeriodEnd.AddDate(0, 0, -sub.RenewalWindowDays)) && (sub.Status == "active" || sub.Status == "grace" || sub.Status == "expired")}
	opt := func(key string) *int { // nil = unlimited, 0 = not granted by the plan
		l, unlimited, _ := sub.Limit(key)
		if unlimited {
			return nil
		}
		return &l
	}
	st.Entitlements.ListingLimit = opt("listing_limit")
	st.Entitlements.ContactUnlocks = opt("contact_unlocks")
	st.Entitlements.Enquiries = opt("enquiries")
	st.Entitlements.ContactUnlocksUsed = sub.UnlocksUsed
	st.Entitlements.EnquiriesUsed = sub.EnquiriesUsed
	st.Entitlements.Analytics = sub.Flag("analytics")
	return st, nil
}
