package enquiries

import (
	"context"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"petora/internal/audit"
	"petora/internal/authctx"
	"petora/internal/database"
	"petora/internal/httpx"
	"petora/internal/subscriptions"
)

// ---------- blocks ----------

type BlockedUser struct {
	UserID    string    `json:"user_id"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"created_at"`
}

func (s *Service) Block(ctx context.Context, p *authctx.Principal, target string) error {
	if target == p.UserID {
		return httpx.BadRequest("You cannot block yourself")
	}
	_, err := s.db.Exec(ctx, `INSERT INTO user_blocks (blocker_id, blocked_id) SELECT $1, id FROM users WHERE id::text=$2 AND account_type <> 'staff' ON CONFLICT DO NOTHING`, p.UserID, target)
	return err
}

func (s *Service) Unblock(ctx context.Context, p *authctx.Principal, target string) error {
	_, err := s.db.Exec(ctx, `DELETE FROM user_blocks WHERE blocker_id=$1 AND blocked_id::text=$2`, p.UserID, target)
	return err
}

func (s *Service) Blocks(ctx context.Context, p *authctx.Principal) ([]BlockedUser, error) {
	rows, err := s.db.Query(ctx, `SELECT u.id, COALESCE(sp.display_name, split_part(u.name,' ',1)), b.created_at FROM user_blocks b
		JOIN users u ON u.id=b.blocked_id LEFT JOIN seller_profiles sp ON sp.user_id=u.id WHERE b.blocker_id=$1 ORDER BY b.created_at DESC`, p.UserID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []BlockedUser{}
	for rows.Next() {
		var b BlockedUser
		if err := rows.Scan(&b.UserID, &b.Name, &b.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, b)
	}
	return out, rows.Err()
}

// ---------- reports ----------

type ReportInput struct {
	TargetType string `json:"target_type"`
	TargetID   string `json:"target_id"`
	Reason     string `json:"reason"`
	Details    string `json:"details"`
}

func (s *Service) Report(ctx context.Context, p *authctx.Principal, in ReportInput) (string, error) {
	var v httpx.V
	v.OneOf("target_type", in.TargetType, "listing", "seller", "user", "enquiry")
	v.OneOf("reason", in.Reason, "spam", "scam", "prohibited", "misleading", "animal_welfare", "abuse", "other")
	v.Required("target_id", in.TargetID)
	in.Details = strings.TrimSpace(in.Details)
	if len([]rune(in.Details)) > 2000 {
		v.Add("details", "must be at most 2000 characters")
	}
	if in.Reason == "other" && len([]rune(in.Details)) < 10 {
		v.Add("details", "please describe the problem")
	}
	if err := v.Err(); err != nil {
		return "", err
	}
	var id string
	err := s.db.InTx(ctx, func(tx pgx.Tx) error {
		var exists bool
		var q string
		switch in.TargetType {
		case "listing":
			q = `SELECT EXISTS (SELECT 1 FROM pet_listings WHERE id::text=$1 AND deleted_at IS NULL)`
		case "seller":
			q = `SELECT EXISTS (SELECT 1 FROM seller_profiles WHERE id::text=$1)`
		case "user":
			q = `SELECT EXISTS (SELECT 1 FROM users WHERE id::text=$1 AND status <> 'deleted')`
		case "enquiry": // only a party to the conversation may report it
			q = `SELECT EXISTS (SELECT 1 FROM enquiries e JOIN seller_profiles sp ON sp.id=e.seller_id WHERE e.id::text=$1 AND (e.buyer_id=$2 OR sp.user_id=$2))`
		}
		args := []any{in.TargetID}
		if in.TargetType == "enquiry" {
			args = append(args, p.UserID)
		}
		if err := tx.QueryRow(ctx, q, args...).Scan(&exists); err != nil {
			return err
		}
		if !exists {
			return httpx.NotFound("Reported item")
		}
		if err := tx.QueryRow(ctx, `INSERT INTO reports (reporter_id, target_type, target_id, reason, details) VALUES ($1,$2,$3,$4,$5) RETURNING id`,
			p.UserID, in.TargetType, in.TargetID, in.Reason, in.Details).Scan(&id); err != nil {
			if database.IsUniqueViolation(err, "reports_dedupe") {
				return httpx.Conflict(httpx.CodeConflict, "You have already reported this. Our team is reviewing it.")
			}
			return err
		}
		if in.TargetType == "enquiry" {
			if _, err := tx.Exec(ctx, `UPDATE enquiries SET status='reported' WHERE id::text=$1`, in.TargetID); err != nil {
				return err
			}
		}
		// Safety valve: enough distinct open reports hide a listing until a moderator reviews it.
		if in.TargetType == "listing" {
			var open int
			if err := tx.QueryRow(ctx, `SELECT count(DISTINCT reporter_id) FROM reports WHERE target_type='listing' AND target_id::text=$1 AND status IN ('open','reviewing')`, in.TargetID).Scan(&open); err != nil {
				return err
			}
			if open >= s.settings.Int(ctx, "reports.auto_suspend_threshold", 5) {
				tag, err := tx.Exec(ctx, `UPDATE pet_listings SET status='suspended', updated_at=now() WHERE id::text=$1 AND status='approved'`, in.TargetID)
				if err != nil {
					return err
				}
				if tag.RowsAffected() > 0 {
					if _, err := tx.Exec(ctx, `INSERT INTO listing_moderation (listing_id, action, reason) VALUES ($1,'suspended','Automatically hidden after multiple reports')`, in.TargetID); err != nil {
						return err
					}
					s.listings.Invalidate(ctx)
				}
			}
		}
		return audit.Log(ctx, tx, audit.Entry{Action: "report.created", EntityType: in.TargetType, EntityID: in.TargetID, Metadata: map[string]any{"reason": in.Reason}})
	})
	return id, err
}

// ---------- disputes ----------

type Dispute struct {
	ID         string    `json:"id"`
	OpenedBy   string    `json:"opened_by"`
	Kind       string    `json:"kind"`
	Subject    string    `json:"subject"`
	Message    string    `json:"message"`
	Status     string    `json:"status"`
	Resolution *string   `json:"resolution"`
	ListingID  *string   `json:"listing_id"`
	PaymentID  *string   `json:"payment_id"`
	EnquiryID  *string   `json:"enquiry_id"`
	CreatedAt  time.Time `json:"created_at"`
}

type DisputeInput struct {
	Kind      string  `json:"kind"`
	Subject   string  `json:"subject"`
	Message   string  `json:"message"`
	ListingID *string `json:"listing_id"`
	PaymentID *string `json:"payment_id"`
	EnquiryID *string `json:"enquiry_id"`
}

func (s *Service) OpenDispute(ctx context.Context, p *authctx.Principal, in DisputeInput) (*Dispute, error) {
	var v httpx.V
	v.OneOf("kind", in.Kind, "listing_appeal", "payment", "conduct", "other")
	v.Length("subject", in.Subject, 5, 140)
	v.Length("message", in.Message, 20, 4000)
	if in.Kind == "listing_appeal" && in.ListingID == nil {
		v.Add("listing_id", "is required for a listing appeal")
	}
	if in.Kind == "payment" && in.PaymentID == nil {
		v.Add("payment_id", "is required for a payment dispute")
	}
	if err := v.Err(); err != nil {
		return nil, err
	}
	// Referenced records must belong to the caller.
	checks := []struct {
		id *string
		q  string
	}{
		{in.ListingID, `SELECT EXISTS (SELECT 1 FROM pet_listings l JOIN seller_profiles sp ON sp.id=l.seller_id WHERE l.id::text=$1 AND sp.user_id=$2)`},
		{in.PaymentID, `SELECT EXISTS (SELECT 1 FROM payments WHERE id::text=$1 AND user_id=$2)`},
		{in.EnquiryID, `SELECT EXISTS (SELECT 1 FROM enquiries e JOIN seller_profiles sp ON sp.id=e.seller_id WHERE e.id::text=$1 AND (e.buyer_id=$2 OR sp.user_id=$2))`},
	}
	for _, c := range checks {
		if c.id == nil {
			continue
		}
		var ok bool
		if err := s.db.QueryRow(ctx, c.q, *c.id, p.UserID).Scan(&ok); err != nil {
			return nil, err
		}
		if !ok {
			return nil, httpx.NotFound("Referenced record")
		}
	}
	var d Dispute
	err := s.db.QueryRow(ctx, `INSERT INTO disputes (opened_by, kind, listing_id, payment_id, enquiry_id, subject, message)
		VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING id, opened_by, kind, subject, message, status, resolution, listing_id, payment_id, enquiry_id, created_at`,
		p.UserID, in.Kind, in.ListingID, in.PaymentID, in.EnquiryID, strings.TrimSpace(in.Subject), strings.TrimSpace(in.Message)).
		Scan(&d.ID, &d.OpenedBy, &d.Kind, &d.Subject, &d.Message, &d.Status, &d.Resolution, &d.ListingID, &d.PaymentID, &d.EnquiryID, &d.CreatedAt)
	return &d, err
}

func (s *Service) MyDisputes(ctx context.Context, p *authctx.Principal) ([]Dispute, error) {
	rows, err := s.db.Query(ctx, `SELECT id, opened_by, kind, subject, message, status, resolution, listing_id, payment_id, enquiry_id, created_at
		FROM disputes WHERE opened_by=$1 ORDER BY created_at DESC LIMIT 100`, p.UserID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Dispute{}
	for rows.Next() {
		var d Dispute
		if err := rows.Scan(&d.ID, &d.OpenedBy, &d.Kind, &d.Subject, &d.Message, &d.Status, &d.Resolution, &d.ListingID, &d.PaymentID, &d.EnquiryID, &d.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

// ---------- dashboards ----------

type BuyerDashboard struct {
	Favourites       int                   `json:"favourites"`
	Enquiries        int                   `json:"enquiries"`
	UnreadReplies    int                   `json:"unread_replies"`
	UnlockedContacts int                   `json:"unlocked_contacts"`
	Subscription     *subscriptions.Status `json:"subscription"`
	RecentEnquiries  []Summary             `json:"recent_enquiries"`
}

func (s *Service) BuyerDashboard(ctx context.Context, p *authctx.Principal) (*BuyerDashboard, error) {
	var d BuyerDashboard
	if err := s.db.QueryRow(ctx, `SELECT (SELECT count(*) FROM favourites WHERE user_id=$1), (SELECT count(*) FROM enquiries WHERE buyer_id=$1),
		(SELECT COALESCE(sum(buyer_unread),0) FROM enquiries WHERE buyer_id=$1), (SELECT count(*) FROM contact_unlocks WHERE buyer_id=$1)`, p.UserID).
		Scan(&d.Favourites, &d.Enquiries, &d.UnreadReplies, &d.UnlockedContacts); err != nil {
		return nil, err
	}
	var err error
	if d.Subscription, err = s.subs.StatusFor(ctx, p.UserID, "buyer"); err != nil {
		return nil, err
	}
	if d.RecentEnquiries, _, err = s.List(ctx, p, "buyer", "", false, httpx.Page{Page: 1, PerPage: 5}); err != nil {
		return nil, err
	}
	return &d, nil
}

type SellerDashboard struct {
	Listings           map[string]int        `json:"listings"`
	Views30d           int                   `json:"views_30d"`
	EnquiriesTotal     int                   `json:"enquiries_total"`
	UnreadEnquiries    int                   `json:"unread_enquiries"`
	VerificationStatus string                `json:"verification_status"`
	Subscription       *subscriptions.Status `json:"subscription"`
	RecentEnquiries    []Summary             `json:"recent_enquiries"`
}

func (s *Service) SellerDashboard(ctx context.Context, p *authctx.Principal) (*SellerDashboard, error) {
	d := SellerDashboard{Listings: map[string]int{"draft": 0, "pending": 0, "approved": 0, "rejected": 0, "suspended": 0, "expired": 0, "sold": 0}}
	rows, err := s.db.Query(ctx, `SELECT CASE WHEN l.availability IN ('sold','unavailable') THEN 'sold' ELSE l.status END, count(*)
		FROM pet_listings l JOIN seller_profiles sp ON sp.id=l.seller_id WHERE sp.user_id=$1 AND l.deleted_at IS NULL GROUP BY 1`, p.UserID)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var k string
		var n int
		if err := rows.Scan(&k, &n); err != nil {
			rows.Close()
			return nil, err
		}
		d.Listings[k] = n
	}
	rows.Close()
	if err := s.db.QueryRow(ctx, `SELECT sp.verification_status,
		(SELECT count(*) FROM listing_views v JOIN pet_listings l ON l.id=v.listing_id WHERE l.seller_id=sp.id AND v.viewed_at > now() - interval '30 days'),
		(SELECT count(*) FROM enquiries e WHERE e.seller_id=sp.id),
		(SELECT count(*) FROM enquiries e WHERE e.seller_id=sp.id AND e.seller_unread > 0)
		FROM seller_profiles sp WHERE sp.user_id=$1`, p.UserID).Scan(&d.VerificationStatus, &d.Views30d, &d.EnquiriesTotal, &d.UnreadEnquiries); err != nil {
		if database.IsNoRows(err) {
			return nil, httpx.NotFound("Seller profile")
		}
		return nil, err
	}
	if d.Subscription, err = s.subs.StatusFor(ctx, p.UserID, "seller"); err != nil {
		return nil, err
	}
	if d.RecentEnquiries, _, err = s.List(ctx, p, "seller", "", false, httpx.Page{Page: 1, PerPage: 5}); err != nil {
		return nil, err
	}
	return &d, nil
}
