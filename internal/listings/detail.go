package listings

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"time"

	"petora/internal/authctx"
	"petora/internal/database"
	"petora/internal/httpx"
)

// loadDetail returns the full listing. publicOnly applies PublicPredicate.
func (s *Service) loadDetail(ctx context.Context, idOrSlug, viewer string, publicOnly bool) (*Detail, string, error) {
	q := &qb{}
	cond := "(l.id::text=" + q.arg(idOrSlug) + " OR l.slug=" + q.arg(idOrSlug) + ") AND l.deleted_at IS NULL"
	if publicOnly {
		cond += " AND " + PublicPredicate
	}
	sel := cardSelect(q, viewer, nil, nil)
	row := s.db.QueryRow(ctx, sel+`, l.description, l.colour, l.vaccination_notes, l.health_notes, l.dewormed, l.microchipped, l.views_count, sp.user_id`+
		baseFrom+" WHERE "+cond, q.args...)
	var d Detail
	var bID, bSlug, bName *string
	var cov []byte
	var logo *string
	var sellerUser string
	err := row.Scan(&d.ID, &d.Slug, &d.Title, &d.ListingType, &d.PriceMinor, &d.Currency, &d.AgeMonths, &d.Gender, &d.City, &d.State,
		&d.Category.ID, &d.Category.Slug, &d.Category.Name, &bID, &bSlug, &bName, &cov,
		&d.Seller.ID, &d.Seller.Slug, &d.Seller.DisplayName, &d.Seller.SellerType, &d.Seller.Verified, &d.Seller.City, &d.Seller.State, &logo,
		&d.Availability, &d.VaccinationStatus, &d.Featured, &d.IsFavourite, &d.DistanceKm, &d.PublishedAt,
		&d.Description, &d.Colour, &d.VaccinationNotes, &d.HealthNotes, &d.Dewormed, &d.Microchipped, &d.ViewsCount, &sellerUser)
	if database.IsNoRows(err) {
		return nil, "", httpx.NotFound("Pet")
	}
	if err != nil {
		return nil, "", err
	}
	if bID != nil {
		d.Breed = &Ref{*bID, *bSlug, *bName}
	}
	d.Cover = s.variants(cov)
	if logo != nil && *logo != "" {
		u := s.store.PublicURL(*logo)
		d.Seller.LogoURL = &u
	}
	if d.Images, err = s.images(ctx, d.ID); err != nil {
		return nil, "", err
	}
	if d.Attributes, err = s.attributes(ctx, d.ID); err != nil {
		return nil, "", err
	}
	d.Disclaimer = Disclaimer
	return &d, sellerUser, nil
}

func (s *Service) images(ctx context.Context, listingID string) ([]Image, error) {
	rows, err := s.db.Query(ctx, `SELECT id, variants, width, height, position, is_cover, alt_text FROM listing_images WHERE listing_id=$1 ORDER BY is_cover DESC, position`, listingID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Image{}
	for rows.Next() {
		var im Image
		var raw []byte
		if err := rows.Scan(&im.ID, &raw, &im.Width, &im.Height, &im.Position, &im.IsCover, &im.AltText); err != nil {
			return nil, err
		}
		if v := s.variants(raw); v != nil {
			im.Thumb, im.Medium, im.Large = v.Thumb, v.Medium, v.Large
		}
		out = append(out, im)
	}
	return out, rows.Err()
}

func (s *Service) attributes(ctx context.Context, listingID string) (map[string]string, error) {
	rows, err := s.db.Query(ctx, `SELECT key, value FROM listing_attributes WHERE listing_id=$1 ORDER BY key`, listingID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]string{}
	for rows.Next() {
		var k, v string
		if err := rows.Scan(&k, &v); err != nil {
			return nil, err
		}
		out[k] = v
	}
	return out, rows.Err()
}

// ContactUnlocked reports whether viewer may currently see this listing's contact details again
// without consuming allowance (prior unlock + retention policy).
func (s *Service) ContactUnlocked(ctx context.Context, q database.Querier, buyerID, listingID string) (bool, error) {
	var ok bool
	retain := s.settings.Bool(ctx, "contacts.retain_after_expiry", true)
	err := q.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM contact_unlocks cu WHERE cu.buyer_id=$1 AND cu.listing_id=$2
		AND ($3 OR EXISTS (SELECT 1 FROM subscriptions s WHERE s.user_id=$1 AND s.audience='buyer' AND s.status IN ('active','grace'))))`,
		buyerID, listingID, retain).Scan(&ok)
	return ok, err
}

// PublicDetail is GET /pets/{id}. Owners and staff may preview non-public listings.
func (s *Service) PublicDetail(ctx context.Context, idOrSlug string, p *authctx.Principal) (*Detail, error) {
	viewer := ""
	if p != nil {
		viewer = p.UserID
	}
	d, _, err := s.loadDetail(ctx, idOrSlug, viewer, true)
	if err != nil {
		var nf *httpx.APIError
		if p == nil || !asAPI(err, &nf) || nf.Status != 404 {
			return nil, err
		}
		// Preview for the owning seller or moderators.
		pd, owner, err2 := s.loadDetail(ctx, idOrSlug, viewer, false)
		if err2 != nil || (owner != p.UserID && !p.Can("listings.moderate")) {
			return nil, err
		}
		d = pd
	}
	if d.SellerProfile, err = s.sellers.GetPublic(ctx, d.Seller.Slug); err != nil {
		d.SellerProfile = nil
	}
	d.Contact.RequiresMembership = true
	if p != nil && p.AccountType == "buyer" {
		if d.Contact.Unlocked, err = s.ContactUnlocked(ctx, s.db, p.UserID, d.ID); err != nil {
			return nil, err
		}
	}
	return d, nil
}

func asAPI(err error, target **httpx.APIError) bool {
	if e, ok := err.(*httpx.APIError); ok {
		*target = e
		return true
	}
	return false
}

func (s *Service) Similar(ctx context.Context, id, viewer string) ([]Card, error) {
	var catID string
	var breedID *string
	err := s.db.QueryRow(ctx, `SELECT category_id, breed_id FROM pet_listings WHERE id::text=$1 OR slug=$1`, id).Scan(&catID, &breedID)
	if database.IsNoRows(err) {
		return nil, httpx.NotFound("Pet")
	}
	if err != nil {
		return nil, err
	}
	q := &qb{}
	where := " WHERE " + PublicPredicate + " AND l.category_id=" + q.arg(catID) + " AND l.id::text <> " + q.arg(id) + " AND l.slug <> " + q.arg(id)
	order := " ORDER BY l.published_at DESC"
	if breedID != nil {
		order = " ORDER BY (l.breed_id = " + q.arg(*breedID) + ") DESC NULLS LAST, l.published_at DESC"
	}
	sel := cardSelect(q, viewer, nil, nil)
	rows, err := s.db.Query(ctx, sel+baseFrom+where+order+" LIMIT 8", q.args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Card{}
	for rows.Next() {
		c, err := s.scanCard(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *c)
	}
	return out, rows.Err()
}

// RecordView stores at most one view per listing per visitor per UTC day.
func (s *Service) RecordView(ctx context.Context, id string, viewer, ip, ua string) error {
	day := time.Now().UTC().Format("2006-01-02")
	h := sha256.Sum256([]byte(ip + "|" + ua + "|" + day))
	visitor := hex.EncodeToString(h[:16])
	var viewerPtr *string
	if viewer != "" {
		viewerPtr = &viewer
	}
	_, err := s.db.Exec(ctx, `WITH target AS (
			SELECT l.id FROM pet_listings l `+joinsForPredicate+` WHERE (l.id::text=$1 OR l.slug=$1) AND `+PublicPredicate+`),
		ins AS (
			INSERT INTO listing_views (listing_id, viewer_id, visitor_hash)
			SELECT t.id, $2::uuid, $3 FROM target t
			WHERE NOT EXISTS (SELECT 1 FROM listing_views v WHERE v.listing_id=t.id AND v.viewed_at >= date_trunc('day', now())
				AND (($2::uuid IS NOT NULL AND v.viewer_id=$2::uuid) OR v.visitor_hash=$3))
			RETURNING listing_id)
		UPDATE pet_listings SET views_count=views_count+1 WHERE id IN (SELECT listing_id FROM ins)`, id, viewerPtr, visitor)
	return err
}

const joinsForPredicate = `JOIN categories c ON c.id=l.category_id JOIN seller_profiles sp ON sp.id=l.seller_id JOIN users su ON su.id=sp.user_id`

func (s *Service) RecentlyViewed(ctx context.Context, viewer string) ([]Card, error) {
	q := &qb{}
	v := q.arg(viewer)
	sel := cardSelect(q, viewer, nil, nil)
	rows, err := s.db.Query(ctx, sel+`, rv.last`+baseFrom+`
		JOIN (SELECT listing_id, max(viewed_at) AS last FROM listing_views WHERE viewer_id=`+v+` GROUP BY listing_id) rv ON rv.listing_id=l.id
		WHERE `+PublicPredicate+` ORDER BY rv.last DESC LIMIT 20`, q.args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Card{}
	for rows.Next() {
		var last time.Time
		c, err := s.scanCardExtra(rows, &last)
		if err != nil {
			return nil, err
		}
		out = append(out, *c)
	}
	return out, rows.Err()
}

// scanCardExtra scans a card followed by extra trailing columns.
func (s *Service) scanCardExtra(row interface{ Scan(...any) error }, extra ...any) (*Card, error) {
	var c Card
	var bID, bSlug, bName *string
	var cov []byte
	var logo *string
	dest := []any{&c.ID, &c.Slug, &c.Title, &c.ListingType, &c.PriceMinor, &c.Currency, &c.AgeMonths, &c.Gender, &c.City, &c.State,
		&c.Category.ID, &c.Category.Slug, &c.Category.Name, &bID, &bSlug, &bName, &cov,
		&c.Seller.ID, &c.Seller.Slug, &c.Seller.DisplayName, &c.Seller.SellerType, &c.Seller.Verified, &c.Seller.City, &c.Seller.State, &logo,
		&c.Availability, &c.VaccinationStatus, &c.Featured, &c.IsFavourite, &c.DistanceKm, &c.PublishedAt}
	if err := row.Scan(append(dest, extra...)...); err != nil {
		return nil, err
	}
	if bID != nil {
		c.Breed = &Ref{*bID, *bSlug, *bName}
	}
	c.Cover = s.variants(cov)
	if logo != nil && *logo != "" {
		u := s.store.PublicURL(*logo)
		c.Seller.LogoURL = &u
	}
	return &c, nil
}

// ---------- favourites ----------

func (s *Service) AddFavourite(ctx context.Context, userID, listingID string) error {
	tag, err := s.db.Exec(ctx, `WITH target AS (SELECT l.id FROM pet_listings l `+joinsForPredicate+` WHERE l.id::text=$2 AND `+PublicPredicate+`),
		ins AS (INSERT INTO favourites (user_id, listing_id) SELECT $1, id FROM target ON CONFLICT DO NOTHING RETURNING listing_id)
		UPDATE pet_listings SET favourites_count=favourites_count+1 WHERE id IN (SELECT listing_id FROM ins)`, userID, listingID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		var exists bool
		if err := s.db.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM favourites WHERE user_id=$1 AND listing_id::text=$2)`, userID, listingID).Scan(&exists); err != nil {
			return err
		}
		if !exists {
			return httpx.NotFound("Pet")
		}
	}
	return nil
}

func (s *Service) RemoveFavourite(ctx context.Context, userID, listingID string) error {
	_, err := s.db.Exec(ctx, `WITH del AS (DELETE FROM favourites WHERE user_id=$1 AND listing_id::text=$2 RETURNING listing_id)
		UPDATE pet_listings SET favourites_count=GREATEST(favourites_count-1,0) WHERE id IN (SELECT listing_id FROM del)`, userID, listingID)
	return err
}

func (s *Service) Favourites(ctx context.Context, userID string, pg httpx.Page) ([]Card, int, error) {
	var total int
	if err := s.db.QueryRow(ctx, `SELECT count(*) FROM favourites f JOIN pet_listings l ON l.id=f.listing_id `+joinsForPredicate+`
		WHERE f.user_id=$1 AND `+PublicPredicate, userID).Scan(&total); err != nil {
		return nil, 0, err
	}
	q := &qb{}
	u := q.arg(userID)
	sel := cardSelect(q, userID, nil, nil)
	rows, err := s.db.Query(ctx, sel+`, fv.created_at`+baseFrom+` JOIN favourites fv ON fv.listing_id=l.id AND fv.user_id=`+u+`
		WHERE `+PublicPredicate+` ORDER BY fv.created_at DESC LIMIT `+q.arg(pg.PerPage)+` OFFSET `+q.arg(pg.Offset), q.args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := []Card{}
	for rows.Next() {
		var at time.Time
		c, err := s.scanCardExtra(rows, &at)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, *c)
	}
	return out, total, rows.Err()
}

// ---------- analytics ----------

type Analytics struct {
	ViewsTotal      int        `json:"views_total"`
	FavouritesTotal int        `json:"favourites_total"`
	EnquiriesTotal  int        `json:"enquiries_total"`
	Series          []DayViews `json:"series"`
}
type DayViews struct {
	Date  string `json:"date"`
	Views int    `json:"views"`
}

func (s *Service) ListingAnalytics(ctx context.Context, sellerUserID, listingID string, days int) (*Analytics, error) {
	if days <= 0 || days > 90 {
		days = 30
	}
	var a Analytics
	err := s.db.QueryRow(ctx, `SELECT l.views_count, l.favourites_count, l.enquiries_count FROM pet_listings l JOIN seller_profiles sp ON sp.id=l.seller_id
		WHERE l.id::text=$1 AND sp.user_id=$2 AND l.deleted_at IS NULL`, listingID, sellerUserID).Scan(&a.ViewsTotal, &a.FavouritesTotal, &a.EnquiriesTotal)
	if database.IsNoRows(err) {
		return nil, httpx.NotFound("Listing")
	}
	if err != nil {
		return nil, err
	}
	rows, err := s.db.Query(ctx, `SELECT to_char(d, 'YYYY-MM-DD'), COALESCE((SELECT count(*) FROM listing_views v WHERE v.listing_id::text=$1
		AND v.viewed_at >= d AND v.viewed_at < d + interval '1 day'), 0)
		FROM generate_series(date_trunc('day', now()) - make_interval(days => $2 - 1), date_trunc('day', now()), interval '1 day') d ORDER BY d`, listingID, days)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	a.Series = []DayViews{}
	for rows.Next() {
		var d DayViews
		if err := rows.Scan(&d.Date, &d.Views); err != nil {
			return nil, err
		}
		a.Series = append(a.Series, d)
	}
	return &a, rows.Err()
}
