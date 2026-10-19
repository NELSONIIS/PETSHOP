// Package enquiries implements contact unlocking, buyer↔seller enquiry threads, blocking,
// reports, disputes and the buyer/seller dashboards.
//
// Contact details (phone/WhatsApp/email) are read ONLY in Unlock, after entitlement checks.
package enquiries

import (
	"context"
	"regexp"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"petora/internal/audit"
	"petora/internal/authctx"
	"petora/internal/cache"
	"petora/internal/database"
	"petora/internal/httpx"
	"petora/internal/listings"
	"petora/internal/notifications"
	"petora/internal/settings"
	"petora/internal/storage"
	"petora/internal/subscriptions"
)

type Service struct {
	db       *database.DB
	cache    *cache.Cache
	settings *settings.Service
	subs     *subscriptions.Service
	listings *listings.Service
	store    storage.Store
	baseURL  string
}

func New(db *database.DB, c *cache.Cache, st *settings.Service, subs *subscriptions.Service, ls *listings.Service, store storage.Store, baseURL string) *Service {
	return &Service{db: db, cache: c, settings: st, subs: subs, listings: ls, store: store, baseURL: baseURL}
}

type Contact struct {
	SellerName       string    `json:"seller_name"`
	Phone            *string   `json:"phone"`
	WhatsApp         *string   `json:"whatsapp"`
	Email            *string   `json:"email"`
	UnlockedAt       time.Time `json:"unlocked_at"`
	RemainingUnlocks *int      `json:"remaining_unlocks"`
}

func (s *Service) membershipRequired(ctx context.Context, msg, reason string) error {
	plans, _ := s.subs.ListPlans(ctx, "buyer", true)
	type sp struct {
		ID         string `json:"id"`
		Name       string `json:"name"`
		TotalMinor int64  `json:"total_minor"`
		Currency   string `json:"currency"`
	}
	sugg := []sp{}
	for _, p := range plans {
		sugg = append(sugg, sp{p.ID, p.Name, p.TotalMinor, p.Currency})
	}
	e := httpx.Err(402, httpx.CodeMembershipRequired, msg)
	e.Extra = map[string]any{"reason": reason, "suggested_plans": sugg}
	return e
}

type publicListing struct {
	ID, SellerID, SellerUserID, Title, Slug, Availability string
}

func (s *Service) publicListing(ctx context.Context, q database.Querier, idOrSlug string) (*publicListing, error) {
	var l publicListing
	err := q.QueryRow(ctx, `SELECT l.id, l.seller_id, sp.user_id, l.title, l.slug, l.availability FROM pet_listings l
		JOIN categories c ON c.id=l.category_id JOIN seller_profiles sp ON sp.id=l.seller_id JOIN users su ON su.id=sp.user_id
		WHERE (l.id::text=$1 OR l.slug=$1) AND `+listings.PublicPredicate, idOrSlug).Scan(&l.ID, &l.SellerID, &l.SellerUserID, &l.Title, &l.Slug, &l.Availability)
	if database.IsNoRows(err) {
		return nil, httpx.NotFound("Pet")
	}
	return &l, err
}

func blocked(ctx context.Context, q database.Querier, a, b string) (bool, error) {
	var x bool
	err := q.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM user_blocks WHERE (blocker_id=$1 AND blocked_id=$2) OR (blocker_id=$2 AND blocked_id=$1))`, a, b).Scan(&x)
	return x, err
}

func requireBuyer(p *authctx.Principal) error {
	if p.AccountType != "buyer" {
		return httpx.Forbidden("Only buyer accounts can contact sellers")
	}
	return nil
}

// Unlock returns seller contact details if (a) the buyer unlocked this listing before and the retention
// policy allows it, or (b) the buyer holds a live membership with unlocks remaining — in which case one
// unlock is recorded and counted. It never charges: payment happens only through checkout.
func (s *Service) Unlock(ctx context.Context, p *authctx.Principal, listingRef string) (*Contact, error) {
	if err := requireBuyer(p); err != nil {
		return nil, err
	}
	var c Contact
	err := s.db.InTx(ctx, func(tx pgx.Tx) error {
		l, err := s.publicListing(ctx, tx, listingRef)
		if err != nil {
			return err
		}
		if b, err := blocked(ctx, tx, p.UserID, l.SellerUserID); err != nil {
			return err
		} else if b {
			return httpx.Forbidden("You cannot contact this seller")
		}
		already, err := s.listings.ContactUnlocked(ctx, tx, p.UserID, l.ID)
		if err != nil {
			return err
		}
		sub, err := s.subs.Live(ctx, tx, p.UserID, "buyer", true)
		if err != nil {
			return err
		}
		if already {
			if err := tx.QueryRow(ctx, `SELECT created_at FROM contact_unlocks WHERE buyer_id=$1 AND listing_id=$2`, p.UserID, l.ID).Scan(&c.UnlockedAt); err != nil {
				return err
			}
		} else {
			if sub == nil {
				return s.membershipRequired(ctx, "A PETORA membership is required to view seller contact details.", "no_membership")
			}
			limit, unlimited, _ := sub.Limit("contact_unlocks")
			var existed bool
			if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM contact_unlocks WHERE buyer_id=$1 AND listing_id=$2)`, p.UserID, l.ID).Scan(&existed); err != nil {
				return err
			}
			if !existed { // a previously-unlocked contact (retention off, now renewed) does not consume again
				if !unlimited && sub.UnlocksUsed >= limit {
					return s.membershipRequired(ctx, "You have used all contact unlocks in your plan. Upgrade or renew to unlock more.", "quota_exhausted")
				}
				if _, err := tx.Exec(ctx, `INSERT INTO contact_unlocks (buyer_id, listing_id, seller_id, subscription_id) VALUES ($1,$2,$3,$4)`,
					p.UserID, l.ID, l.SellerID, sub.ID); err != nil {
					return err
				}
				if _, err := tx.Exec(ctx, `UPDATE subscriptions SET contact_unlocks_used=contact_unlocks_used+1, updated_at=now() WHERE id=$1`, sub.ID); err != nil {
					return err
				}
				sub.UnlocksUsed++
				audit.System(ctx, tx, "contact.unlocked", "listing", l.ID, map[string]any{"buyer_id": p.UserID, "subscription_id": sub.ID})
			}
			if err := tx.QueryRow(ctx, `SELECT created_at FROM contact_unlocks WHERE buyer_id=$1 AND listing_id=$2`, p.UserID, l.ID).Scan(&c.UnlockedAt); err != nil {
				return err
			}
		}
		if sub != nil {
			if limit, unlimited, _ := sub.Limit("contact_unlocks"); !unlimited {
				rem := max(limit-sub.UnlocksUsed, 0)
				c.RemainingUnlocks = &rem
			}
		} else {
			z := 0
			c.RemainingUnlocks = &z
		}
		return tx.QueryRow(ctx, `SELECT display_name, contact_phone, contact_whatsapp, contact_email FROM seller_profiles WHERE id=$1`, l.SellerID).
			Scan(&c.SellerName, &c.Phone, &c.WhatsApp, &c.Email)
	})
	if err != nil {
		return nil, err
	}
	return &c, nil
}

// ---------- enquiries ----------

type ListingRef struct {
	ID           string             `json:"id"`
	Slug         string             `json:"slug"`
	Title        string             `json:"title"`
	Cover        *listings.Variants `json:"cover"`
	Availability string             `json:"availability"`
}
type Counterparty struct {
	UserID string  `json:"user_id"` // for blocking; never accompanied by contact details
	Name   string  `json:"name"`
	Slug   *string `json:"slug"`
}
type Summary struct {
	ID            string       `json:"id"`
	Status        string       `json:"status"`
	Listing       ListingRef   `json:"listing"`
	Counterparty  Counterparty `json:"counterparty"`
	LastMessage   string       `json:"last_message"`
	LastMessageAt time.Time    `json:"last_message_at"`
	Unread        int          `json:"unread"`
	CreatedAt     time.Time    `json:"created_at"`
}
type Message struct {
	ID        string     `json:"id"`
	SenderID  string     `json:"sender_id"`
	Mine      bool       `json:"mine"`
	Body      string     `json:"body"`
	CreatedAt time.Time  `json:"created_at"`
	ReadAt    *time.Time `json:"read_at"`
}
type Detail struct {
	Summary
	Messages        []Message  `json:"messages"`
	FirstResponseAt *time.Time `json:"first_response_at"`
	ContactUnlocked bool       `json:"contact_unlocked"`
}

var urlRe = regexp.MustCompile(`(?i)(https?://|www\.)`)

func validateBody(body string) (string, error) {
	body = strings.TrimSpace(body)
	var v httpx.V
	v.Length("message", body, 2, 2000)
	if len(urlRe.FindAllString(body, -1)) > 2 {
		v.Add("message", "contains too many links")
	}
	return body, v.Err()
}

func (s *Service) Create(ctx context.Context, p *authctx.Principal, listingRef, body string) (*Summary, error) {
	if err := requireBuyer(p); err != nil {
		return nil, err
	}
	body, err := validateBody(body)
	if err != nil {
		return nil, err
	}
	if len([]rune(body)) < 5 {
		return nil, httpx.Invalid(httpx.FieldError{Field: "message", Message: "must be at least 5 characters"})
	}
	var id string
	err = s.db.InTx(ctx, func(tx pgx.Tx) error {
		l, err := s.publicListing(ctx, tx, listingRef)
		if err != nil {
			return err
		}
		if l.SellerUserID == p.UserID {
			return httpx.BadRequest("You cannot enquire about your own listing")
		}
		if b, err := blocked(ctx, tx, p.UserID, l.SellerUserID); err != nil {
			return err
		} else if b {
			return httpx.Forbidden("You cannot contact this seller")
		}
		var existing string
		if err := tx.QueryRow(ctx, `SELECT COALESCE((SELECT id::text FROM enquiries WHERE buyer_id=$1 AND listing_id=$2),'')`, p.UserID, l.ID).Scan(&existing); err != nil {
			return err
		}
		if existing != "" {
			e := httpx.Conflict(httpx.CodeConflict, "You already have an enquiry for this pet. Continue the conversation there.")
			e.Extra = map[string]string{"enquiry_id": existing}
			return e
		}
		var today int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM enquiries WHERE buyer_id=$1 AND created_at > now() - interval '24 hours'`, p.UserID).Scan(&today); err != nil {
			return err
		}
		if today >= s.settings.Int(ctx, "enquiries.daily_limit_per_buyer", 20) {
			return httpx.Err(429, httpx.CodeRateLimited, "You have reached today's enquiry limit. Please try again tomorrow.")
		}
		sub, err := s.subs.Live(ctx, tx, p.UserID, "buyer", true)
		if err != nil {
			return err
		}
		if sub == nil {
			return s.membershipRequired(ctx, "A PETORA membership is required to send enquiries.", "no_membership")
		}
		if limit, unlimited, _ := sub.Limit("enquiries"); !unlimited && sub.EnquiriesUsed >= limit {
			return s.membershipRequired(ctx, "You have used all enquiries in your plan. Upgrade or renew to send more.", "quota_exhausted")
		}
		var unlockID *string
		_ = tx.QueryRow(ctx, `SELECT id::text FROM contact_unlocks WHERE buyer_id=$1 AND listing_id=$2`, p.UserID, l.ID).Scan(&unlockID)
		if err := tx.QueryRow(ctx, `INSERT INTO enquiries (buyer_id, seller_id, listing_id, contact_unlock_id, seller_unread) VALUES ($1,$2,$3,$4,1) RETURNING id`,
			p.UserID, l.SellerID, l.ID, unlockID).Scan(&id); err != nil {
			if database.IsUniqueViolation(err, "") {
				return httpx.Conflict(httpx.CodeConflict, "You already have an enquiry for this pet.")
			}
			return err
		}
		var conv string
		if err := tx.QueryRow(ctx, `INSERT INTO conversations (enquiry_id) VALUES ($1) RETURNING id`, id).Scan(&conv); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `INSERT INTO messages (conversation_id, sender_id, body) VALUES ($1,$2,$3)`, conv, p.UserID, body); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE pet_listings SET enquiries_count=enquiries_count+1 WHERE id=$1`, l.ID); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE subscriptions SET enquiries_used=enquiries_used+1, updated_at=now() WHERE id=$1`, sub.ID); err != nil {
			return err
		}
		var sellerEmail, sellerName string
		if err := tx.QueryRow(ctx, `SELECT email, name FROM users WHERE id=$1`, l.SellerUserID).Scan(&sellerEmail, &sellerName); err != nil {
			return err
		}
		if err := notifications.Create(ctx, tx, l.SellerUserID, "enquiry_received", "New enquiry: "+l.Title, firstName(p.Name)+" sent you a message.",
			map[string]any{"enquiry_id": id, "listing_id": l.ID}); err != nil {
			return err
		}
		return notifications.EnqueueEmail(ctx, tx, sellerEmail, "enquiry_received", map[string]string{"name": sellerName, "listing": l.Title,
			"url": s.baseURL + "/seller/enquiries/" + id})
	})
	if err != nil {
		return nil, err
	}
	d, err := s.get(ctx, p, id, "buyer", false)
	if err != nil {
		return nil, err
	}
	return &d.Summary, nil
}

func firstName(n string) string {
	if f := strings.Fields(n); len(f) > 0 {
		return f[0]
	}
	return "A buyer"
}

const summarySelect = `SELECT e.id, e.status, l.id, l.slug, l.title, cov.variants, l.availability,
	CASE WHEN $2::text='buyer' THEN sp.display_name ELSE split_part(bu.name,' ',1) END,
	CASE WHEN $2::text='buyer' THEN sp.slug END, CASE WHEN $2::text='buyer' THEN sp.user_id ELSE e.buyer_id END,
	COALESCE((SELECT m.body FROM messages m WHERE m.conversation_id=cv.id ORDER BY m.created_at DESC LIMIT 1),''),
	e.last_message_at, CASE WHEN $2::text='buyer' THEN e.buyer_unread ELSE e.seller_unread END, e.created_at,
	e.first_response_at, e.contact_unlock_id IS NOT NULL, cv.id
	FROM enquiries e JOIN pet_listings l ON l.id=e.listing_id JOIN seller_profiles sp ON sp.id=e.seller_id
	JOIN users bu ON bu.id=e.buyer_id JOIN conversations cv ON cv.enquiry_id=e.id
	LEFT JOIN LATERAL (SELECT i.variants FROM listing_images i WHERE i.listing_id=l.id ORDER BY i.is_cover DESC, i.position LIMIT 1) cov ON true`

// partyFilter restricts rows to the caller's side; it is the IDOR guard for every enquiry read.
func partyFilter(side string) string {
	if side == "buyer" {
		return " e.buyer_id=$1 "
	}
	return " sp.user_id=$1 "
}

func (s *Service) scanSummary(row pgx.Row, d *Detail, conv *string) error {
	var cov []byte
	if err := row.Scan(&d.ID, &d.Status, &d.Listing.ID, &d.Listing.Slug, &d.Listing.Title, &cov, &d.Listing.Availability,
		&d.Counterparty.Name, &d.Counterparty.Slug, &d.Counterparty.UserID, &d.LastMessage, &d.LastMessageAt, &d.Unread, &d.CreatedAt,
		&d.FirstResponseAt, &d.ContactUnlocked, conv); err != nil {
		return err
	}
	d.Listing.Cover = s.listings.CoverFromRaw(cov)
	if len([]rune(d.LastMessage)) > 140 {
		d.LastMessage = string([]rune(d.LastMessage)[:140]) + "…"
	}
	return nil
}

func (s *Service) List(ctx context.Context, p *authctx.Principal, side, status string, unreadOnly bool, pg httpx.Page) ([]Summary, int, error) {
	where := " WHERE" + partyFilter(side) + ` AND ($3::text='' OR e.status=$3) AND (NOT $4::boolean OR CASE WHEN $2::text='buyer' THEN e.buyer_unread ELSE e.seller_unread END > 0)`
	var total int
	if err := s.db.QueryRow(ctx, `SELECT count(*) FROM enquiries e JOIN seller_profiles sp ON sp.id=e.seller_id`+where,
		p.UserID, side, status, unreadOnly).Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := s.db.Query(ctx, summarySelect+where+` ORDER BY e.last_message_at DESC LIMIT $5 OFFSET $6`, p.UserID, side, status, unreadOnly, pg.PerPage, pg.Offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := []Summary{}
	for rows.Next() {
		var d Detail
		var conv string
		if err := s.scanSummary(rows, &d, &conv); err != nil {
			return nil, 0, err
		}
		out = append(out, d.Summary)
	}
	return out, total, rows.Err()
}

// get loads a thread for a party; markRead clears the caller's unread counter.
func (s *Service) get(ctx context.Context, p *authctx.Principal, id, side string, markRead bool) (*Detail, error) {
	var d Detail
	var conv string
	err := s.scanSummary(s.db.QueryRow(ctx, summarySelect+" WHERE"+partyFilter(side)+" AND e.id::text=$3", p.UserID, side, id), &d, &conv)
	if database.IsNoRows(err) {
		return nil, httpx.NotFound("Enquiry") // same response whether it exists or not: no IDOR oracle
	}
	if err != nil {
		return nil, err
	}
	if markRead {
		col := "buyer_unread"
		if side == "seller" {
			col = "seller_unread"
		}
		if _, err := s.db.Exec(ctx, `UPDATE enquiries SET `+col+`=0, viewed_at=CASE WHEN $2='seller' THEN COALESCE(viewed_at, now()) ELSE viewed_at END,
			status=CASE WHEN $2='seller' AND status='pending' THEN 'viewed' ELSE status END WHERE id=$1`, d.ID, side); err != nil {
			return nil, err
		}
		if _, err := s.db.Exec(ctx, `UPDATE messages SET read_at=now() WHERE conversation_id=$1 AND sender_id<>$2 AND read_at IS NULL`, conv, p.UserID); err != nil {
			return nil, err
		}
		if side == "seller" && d.Status == "pending" {
			d.Status = "viewed"
		}
		d.Unread = 0
	}
	rows, err := s.db.Query(ctx, `SELECT id, sender_id, body, created_at, read_at FROM messages WHERE conversation_id=$1 ORDER BY created_at LIMIT 500`, conv)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	d.Messages = []Message{}
	for rows.Next() {
		var m Message
		if err := rows.Scan(&m.ID, &m.SenderID, &m.Body, &m.CreatedAt, &m.ReadAt); err != nil {
			return nil, err
		}
		m.Mine = m.SenderID == p.UserID
		d.Messages = append(d.Messages, m)
	}
	return &d, rows.Err()
}

func (s *Service) Get(ctx context.Context, p *authctx.Principal, id, side string) (*Detail, error) {
	return s.get(ctx, p, id, side, true)
}

func (s *Service) Reply(ctx context.Context, p *authctx.Principal, id, side, body string) (*Message, error) {
	body, err := validateBody(body)
	if err != nil {
		return nil, err
	}
	var m Message
	err = s.db.InTx(ctx, func(tx pgx.Tx) error {
		var status, conv, buyerID, sellerUser, title, listingID string
		err := tx.QueryRow(ctx, `SELECT e.status, cv.id, e.buyer_id, sp.user_id, l.title, l.id FROM enquiries e
			JOIN conversations cv ON cv.enquiry_id=e.id JOIN seller_profiles sp ON sp.id=e.seller_id JOIN pet_listings l ON l.id=e.listing_id
			WHERE e.id::text=$2 AND `+partyFilter(side)+` FOR UPDATE OF e`, p.UserID, id).Scan(&status, &conv, &buyerID, &sellerUser, &title, &listingID)
		if database.IsNoRows(err) {
			return httpx.NotFound("Enquiry")
		}
		if err != nil {
			return err
		}
		if status == "closed" || status == "reported" {
			return httpx.Conflict(httpx.CodeConflict, "This conversation is closed")
		}
		if b, err := blocked(ctx, tx, buyerID, sellerUser); err != nil {
			return err
		} else if b {
			return httpx.Forbidden("You cannot message this user")
		}
		if err := tx.QueryRow(ctx, `INSERT INTO messages (conversation_id, sender_id, body) VALUES ($1,$2,$3) RETURNING id, sender_id, body, created_at`,
			conv, p.UserID, body).Scan(&m.ID, &m.SenderID, &m.Body, &m.CreatedAt); err != nil {
			return err
		}
		m.Mine = true
		recipient, unreadCol, kind, url := sellerUser, "seller_unread", "enquiry_message", s.baseURL+"/seller/enquiries/"+id
		newStatus := "status"
		if side == "seller" {
			recipient, unreadCol, kind, url = buyerID, "buyer_unread", "enquiry_reply", s.baseURL+"/buyer/enquiries/"+id
			newStatus = "'responded'"
		}
		if _, err := tx.Exec(ctx, `UPDATE enquiries SET `+unreadCol+`=`+unreadCol+`+1, last_message_at=now(), status=`+newStatus+`,
			first_response_at=CASE WHEN $2 THEN COALESCE(first_response_at, now()) ELSE first_response_at END WHERE id::text=$1`, id, side == "seller"); err != nil {
			return err
		}
		if err := notifications.Create(ctx, tx, recipient, kind, "New message about "+title, truncate(body, 120), map[string]any{"enquiry_id": id, "listing_id": listingID}); err != nil {
			return err
		}
		if side == "seller" {
			var email, name, seller string
			if err := tx.QueryRow(ctx, `SELECT u.email, u.name, sp.display_name FROM users u, seller_profiles sp WHERE u.id=$1 AND sp.user_id=$2`, buyerID, sellerUser).Scan(&email, &name, &seller); err != nil {
				return err
			}
			return notifications.EnqueueEmail(ctx, tx, email, "enquiry_reply", map[string]string{"name": name, "seller": seller, "listing": title, "url": url})
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return &m, nil
}

func (s *Service) Close(ctx context.Context, p *authctx.Principal, id, side string) error {
	tag, err := s.db.Exec(ctx, `UPDATE enquiries e SET status='closed', closed_at=now() FROM seller_profiles sp
		WHERE sp.id=e.seller_id AND e.id::text=$2 AND `+partyFilter(side)+` AND e.status <> 'closed'`, p.UserID, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		if _, err := s.get(ctx, p, id, side, false); err != nil {
			return err
		}
	}
	return nil
}

func truncate(s string, n int) string {
	if r := []rune(s); len(r) > n {
		return string(r[:n]) + "…"
	}
	return s
}
