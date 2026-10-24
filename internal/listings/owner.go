package listings

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"petora/internal/audit"
	"petora/internal/catalog"
	"petora/internal/database"
	"petora/internal/httpx"
	"petora/internal/media"
	"petora/internal/security"
	"petora/internal/storage"
	"petora/internal/subscriptions"
)

var attrKeyRe = regexp.MustCompile(`^[a-z][a-z0-9_]{0,39}$`)

func (in *Input) normalise() {
	in.Title = strings.TrimSpace(in.Title)
	in.Description = strings.TrimSpace(in.Description)
	in.City, in.State, in.Colour = strings.TrimSpace(in.City), strings.TrimSpace(in.State), strings.TrimSpace(in.Colour)
	if in.Gender == "" {
		in.Gender = "unknown"
	}
	if in.VaccinationStatus == "" {
		in.VaccinationStatus = "unspecified"
	}
	if in.BreedID != nil && *in.BreedID == "" {
		in.BreedID = nil
	}
	if in.ListingType == "adoption" {
		in.PriceMinor = 0
	}
}

func (s *Service) validateInput(ctx context.Context, q database.Querier, in *Input) error {
	in.normalise()
	var v httpx.V
	v.Length("title", in.Title, 5, 140)
	if len([]rune(in.Description)) > 5000 {
		v.Add("description", "must be at most 5000 characters")
	}
	v.OneOf("listing_type", in.ListingType, "sale", "adoption")
	v.OneOf("gender", in.Gender, "male", "female", "unknown")
	v.OneOf("vaccination_status", in.VaccinationStatus, "unspecified", "none", "partial", "complete")
	if in.ListingType == "sale" {
		v.Range("price_minor", in.PriceMinor, 100, 100_000_000_00) // ₹1 – ₹1 crore
	}
	if in.AgeMonths != nil {
		v.Range("age_months", int64(*in.AgeMonths), 0, 600)
	}
	if in.Lat != nil && (*in.Lat < -90 || *in.Lat > 90) {
		v.Add("lat", "is out of range")
	}
	if in.Lng != nil && (*in.Lng < -180 || *in.Lng > 180) {
		v.Add("lng", "is out of range")
	}
	for _, f := range []struct{ name, val string }{{"vaccination_notes", in.VaccinationNotes}, {"health_notes", in.HealthNotes}} {
		if len([]rune(f.val)) > 2000 {
			v.Add(f.name, "must be at most 2000 characters")
		}
	}
	if len(in.Attributes) > 20 {
		v.Add("attributes", "at most 20 attributes")
	}
	for k, val := range in.Attributes {
		if !attrKeyRe.MatchString(k) || len([]rune(val)) > 200 {
			v.Add("attributes."+k, "key must be snake_case and value at most 200 characters")
		}
	}
	var active bool
	err := q.QueryRow(ctx, `SELECT is_active FROM categories WHERE id::text=$1`, in.CategoryID).Scan(&active)
	if database.IsNoRows(err) || (err == nil && !active) {
		v.Add("category_id", "is not an available category")
	} else if err != nil {
		return err
	}
	if in.BreedID != nil {
		var ok bool
		if err := q.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM breeds WHERE id::text=$1 AND category_id::text=$2 AND is_active)`, *in.BreedID, in.CategoryID).Scan(&ok); err != nil {
			return err
		}
		if !ok {
			v.Add("breed_id", "does not belong to the selected category")
		}
	}
	return v.Err()
}

type sellerCtx struct {
	ProfileID, VerificationStatus string
}

func (s *Service) sellerFor(ctx context.Context, q database.Querier, userID string) (*sellerCtx, error) {
	var sc sellerCtx
	err := q.QueryRow(ctx, `SELECT id, verification_status FROM seller_profiles WHERE user_id=$1`, userID).Scan(&sc.ProfileID, &sc.VerificationStatus)
	if database.IsNoRows(err) {
		return nil, httpx.Forbidden("A seller profile is required")
	}
	if err != nil {
		return nil, err
	}
	if sc.VerificationStatus == "suspended" {
		return nil, httpx.Forbidden("Your seller account is suspended. Contact support.")
	}
	return &sc, nil
}

func subscriptionRequired() error {
	return httpx.Err(402, httpx.CodeSubscriptionRequired, "An active seller subscription is required. Choose a plan to continue.")
}

// requireSellerSub returns the live seller subscription or a 402.
func requireSellerSub(ctx context.Context, subs *subscriptions.Service, q database.Querier, userID string, lock bool) (*subscriptions.Subscription, error) {
	sub, err := subs.Live(ctx, q, userID, "seller", lock)
	if err != nil {
		return nil, err
	}
	if sub == nil {
		return nil, subscriptionRequired()
	}
	return sub, nil
}

func (s *Service) Create(ctx context.Context, subs *subscriptions.Service, userID string, in Input) (*Owner, error) {
	var id string
	err := s.db.InTx(ctx, func(tx pgx.Tx) error {
		sc, err := s.sellerFor(ctx, tx, userID)
		if err != nil {
			return err
		}
		// Lock the subscription row so concurrent creates cannot both squeeze under the allowance.
		sub, err := requireSellerSub(ctx, subs, tx, userID, true)
		if err != nil {
			return err
		}
		limit, unlimited, _ := sub.Limit("listing_limit")
		if !unlimited {
			used, err := subscriptions.CountSellerListings(ctx, tx, userID)
			if err != nil {
				return err
			}
			if used >= limit {
				return httpx.Conflict(httpx.CodeLimitReached, fmt.Sprintf("Your %s plan allows %d active listings. Mark a pet as sold, archive a listing or upgrade.", sub.PlanName, limit))
			}
		}
		if err := s.validateInput(ctx, tx, &in); err != nil {
			return err
		}
		slug := catalog.Slugify(in.Title)
		if slug == "" {
			slug = "pet"
		}
		slug += "-" + strings.ToLower(security.RandomToken(4)[:6])
		if err := tx.QueryRow(ctx, `INSERT INTO pet_listings (slug, seller_id, category_id, breed_id, title, description, listing_type, price_minor,
			age_months, gender, colour, vaccination_status, vaccination_notes, health_notes, dewormed, microchipped, city, state, lat, lng)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20) RETURNING id`,
			slug, sc.ProfileID, in.CategoryID, in.BreedID, in.Title, in.Description, in.ListingType, in.PriceMinor, in.AgeMonths, in.Gender,
			in.Colour, in.VaccinationStatus, in.VaccinationNotes, in.HealthNotes, in.Dewormed, in.Microchipped, in.City, in.State, in.Lat, in.Lng).Scan(&id); err != nil {
			return err
		}
		return writeAttributes(ctx, tx, id, in.Attributes)
	})
	if err != nil {
		return nil, err
	}
	return s.OwnerView(ctx, userID, id, false)
}

func writeAttributes(ctx context.Context, tx pgx.Tx, id string, attrs map[string]string) error {
	if _, err := tx.Exec(ctx, `DELETE FROM listing_attributes WHERE listing_id=$1`, id); err != nil {
		return err
	}
	for k, v := range attrs {
		if strings.TrimSpace(v) == "" {
			continue
		}
		if _, err := tx.Exec(ctx, `INSERT INTO listing_attributes (listing_id, key, value) VALUES ($1,$2,$3)`, id, k, strings.TrimSpace(v)); err != nil {
			return err
		}
	}
	return nil
}

// lockOwned locks a listing row the user owns and returns its status.
func lockOwned(ctx context.Context, tx pgx.Tx, userID, listingID string) (status string, err error) {
	err = tx.QueryRow(ctx, `SELECT l.status FROM pet_listings l JOIN seller_profiles sp ON sp.id=l.seller_id
		WHERE l.id::text=$1 AND sp.user_id=$2 AND l.deleted_at IS NULL FOR UPDATE OF l`, listingID, userID).Scan(&status)
	if database.IsNoRows(err) {
		return "", httpx.NotFound("Listing")
	}
	return status, err
}

// remoderate sends an approved listing back to the queue after content changes (prevents bait-and-switch).
func remoderate(ctx context.Context, tx pgx.Tx, id, status, why string) error {
	if status != "approved" {
		return nil
	}
	if _, err := tx.Exec(ctx, `UPDATE pet_listings SET status='pending', updated_at=now() WHERE id=$1`, id); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `INSERT INTO listing_moderation (listing_id, action, reason) VALUES ($1,'submitted',$2)`, id, why)
	return err
}

func (s *Service) Update(ctx context.Context, userID, id string, in Input) (*Owner, error) {
	err := s.db.InTx(ctx, func(tx pgx.Tx) error {
		status, err := lockOwned(ctx, tx, userID, id)
		if err != nil {
			return err
		}
		if status == "suspended" || status == "archived" {
			return httpx.Forbidden("This listing cannot be edited")
		}
		if err := s.validateInput(ctx, tx, &in); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE pet_listings SET category_id=$2, breed_id=$3, title=$4, description=$5, listing_type=$6, price_minor=$7,
			age_months=$8, gender=$9, colour=$10, vaccination_status=$11, vaccination_notes=$12, health_notes=$13, dewormed=$14, microchipped=$15,
			city=$16, state=$17, lat=$18, lng=$19, updated_at=now() WHERE id=$1`, id, in.CategoryID, in.BreedID, in.Title, in.Description, in.ListingType,
			in.PriceMinor, in.AgeMonths, in.Gender, in.Colour, in.VaccinationStatus, in.VaccinationNotes, in.HealthNotes, in.Dewormed, in.Microchipped,
			in.City, in.State, in.Lat, in.Lng); err != nil {
			return err
		}
		if err := writeAttributes(ctx, tx, id, in.Attributes); err != nil {
			return err
		}
		return remoderate(ctx, tx, id, status, "Edited by seller")
	})
	if err != nil {
		return nil, err
	}
	s.Invalidate(ctx)
	return s.OwnerView(ctx, userID, id, false)
}

func (s *Service) Archive(ctx context.Context, userID, id string) error {
	err := s.db.InTx(ctx, func(tx pgx.Tx) error {
		if _, err := lockOwned(ctx, tx, userID, id); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `UPDATE pet_listings SET status='archived', deleted_at=now(), updated_at=now() WHERE id=$1`, id)
		return err
	})
	if err == nil {
		s.Invalidate(ctx)
	}
	return err
}

func (s *Service) SetAvailability(ctx context.Context, userID, id, availability string) (*Owner, error) {
	var v httpx.V
	v.OneOf("availability", availability, "available", "reserved", "sold", "unavailable")
	if err := v.Err(); err != nil {
		return nil, err
	}
	if _, err := s.db.Exec(ctx, `UPDATE pet_listings l SET availability=$3, updated_at=now() FROM seller_profiles sp
		WHERE sp.id=l.seller_id AND l.id::text=$1 AND sp.user_id=$2 AND l.deleted_at IS NULL`, id, userID, availability); err != nil {
		return nil, err
	}
	s.Invalidate(ctx)
	return s.OwnerView(ctx, userID, id, false)
}

// ---------- submission / moderation entry ----------

func (s *Service) missing(ctx context.Context, q database.Querier, id string) ([]string, error) {
	var (
		desc, city, state, vacc, ltype, sellerCity, sellerState string
		price                                                   int64
		images                                                  int
		phone                                                   *string
	)
	err := q.QueryRow(ctx, `SELECT l.description, l.city, l.state, l.vaccination_status, l.listing_type, l.price_minor,
		(SELECT count(*) FROM listing_images i WHERE i.listing_id=l.id), sp.city, sp.state, sp.contact_phone
		FROM pet_listings l JOIN seller_profiles sp ON sp.id=l.seller_id WHERE l.id=$1`, id).
		Scan(&desc, &city, &state, &vacc, &ltype, &price, &images, &sellerCity, &sellerState, &phone)
	if err != nil {
		return nil, err
	}
	var m []string
	minImages := s.settings.Int(ctx, "listings.min_images", 1)
	if images < minImages {
		m = append(m, fmt.Sprintf("Add at least %d photo(s)", minImages))
	}
	if len([]rune(strings.TrimSpace(desc))) < 30 {
		m = append(m, "Write a description of at least 30 characters")
	}
	if city == "" || state == "" {
		m = append(m, "Set the pet's city and state")
	}
	if vacc == "unspecified" {
		m = append(m, "Declare the vaccination status (choose 'none' if not vaccinated)")
	}
	if ltype == "sale" && price <= 0 {
		m = append(m, "Set a price")
	}
	if phone == nil || *phone == "" {
		m = append(m, "Add a contact phone number to your seller profile")
	}
	return m, nil
}

// Submit moves a listing into moderation. Returns the auto flags raised (for tests/UI).
func (s *Service) Submit(ctx context.Context, subs *subscriptions.Service, userID, id string) (*Owner, error) {
	err := s.db.InTx(ctx, func(tx pgx.Tx) error {
		status, err := lockOwned(ctx, tx, userID, id)
		if err != nil {
			return err
		}
		switch status {
		case "draft", "rejected", "expired":
		case "pending":
			return httpx.Conflict(httpx.CodeConflict, "This listing is already awaiting review")
		case "approved":
			return httpx.Conflict(httpx.CodeConflict, "This listing is already live")
		default:
			return httpx.Forbidden("This listing cannot be submitted")
		}
		sc, err := s.sellerFor(ctx, tx, userID)
		if err != nil {
			return err
		}
		if _, err := requireSellerSub(ctx, subs, tx, userID, false); err != nil {
			return err
		}
		missing, err := s.missing(ctx, tx, id)
		if err != nil {
			return err
		}
		if len(missing) > 0 {
			d := make([]httpx.FieldError, len(missing))
			for i, m := range missing {
				d[i] = httpx.FieldError{Field: "listing", Message: m}
			}
			return httpx.Invalid(d...)
		}
		var reqVerified bool
		var rules []byte
		var title, desc, state string
		if err := tx.QueryRow(ctx, `SELECT c.requires_verified_seller, c.jurisdiction_rules, l.title, l.description, l.state FROM pet_listings l
			JOIN categories c ON c.id=l.category_id WHERE l.id=$1`, id).Scan(&reqVerified, &rules, &title, &desc, &state); err != nil {
			return err
		}
		// Jurisdiction rules, keyed by lower-case state name.
		var jr map[string]struct {
			Allowed                *bool `json:"allowed"`
			RequiresVerifiedSeller bool  `json:"requires_verified_seller"`
		}
		_ = json.Unmarshal(rules, &jr)
		if r, ok := jr[strings.ToLower(strings.TrimSpace(state))]; ok {
			if r.Allowed != nil && !*r.Allowed {
				return httpx.Forbidden("Listings in this category are not permitted in " + state)
			}
			reqVerified = reqVerified || r.RequiresVerifiedSeller
		}
		if (reqVerified || s.settings.Bool(ctx, "listings.require_verified_seller", false)) && sc.VerificationStatus != "approved" {
			return httpx.Err(403, httpx.CodeVerificationRequired, "Seller verification is required before publishing in this category")
		}
		flags, err := s.autoFlags(ctx, tx, id, sc.ProfileID, title, desc)
		if err != nil {
			return err
		}
		flagsJSON, _ := json.Marshal(flags)
		if _, err := tx.Exec(ctx, `INSERT INTO listing_moderation (listing_id, action, flags) VALUES ($1,'submitted',$2)`, id, flagsJSON); err != nil {
			return err
		}
		auto := s.settings.Bool(ctx, "listings.auto_approve", false) && len(flags) == 0 && sc.VerificationStatus == "approved"
		if !auto {
			_, err = tx.Exec(ctx, `UPDATE pet_listings SET status='pending', rejection_reason=NULL, expired_reason=NULL, updated_at=now() WHERE id=$1`, id)
			return err
		}
		return Approve(ctx, tx, s.settings.Int(ctx, "listings.expiry_days", 60), id, nil)
	})
	if err != nil {
		return nil, err
	}
	s.Invalidate(ctx)
	return s.OwnerView(ctx, userID, id, false)
}

// autoFlags runs cheap trust & safety heuristics. Flags force manual review; they never auto-reject.
func (s *Service) autoFlags(ctx context.Context, q database.Querier, id, sellerID, title, desc string) ([]string, error) {
	flags := []string{}
	text := strings.ToLower(title + " " + desc)
	for _, kw := range s.settings.Strings(ctx, "safety.prohibited_keywords", nil) {
		if kw = strings.ToLower(strings.TrimSpace(kw)); kw != "" && strings.Contains(text, kw) {
			flags = append(flags, "prohibited_keyword:"+kw)
		}
	}
	if regexp.MustCompile(`(\+?91[\s-]?)?[6-9]\d{4}[\s-]?\d{5}`).MatchString(text) || strings.Contains(text, "@") {
		flags = append(flags, "contact_details_in_text")
	}
	var dupTitle, dupDesc bool
	if err := q.QueryRow(ctx, `SELECT
		EXISTS (SELECT 1 FROM pet_listings WHERE seller_id=$2 AND id<>$1 AND lower(title)=lower($3) AND deleted_at IS NULL AND status IN ('pending','approved')),
		EXISTS (SELECT 1 FROM pet_listings WHERE seller_id<>$2 AND length($4) > 60 AND description=$4 AND deleted_at IS NULL AND status IN ('pending','approved'))`,
		id, sellerID, title, desc).Scan(&dupTitle, &dupDesc); err != nil {
		return nil, err
	}
	if dupTitle {
		flags = append(flags, "possible_duplicate_of_own_listing")
	}
	if dupDesc {
		flags = append(flags, "description_copied_from_another_seller")
	}
	return flags, nil
}

// Approve publishes a listing (shared by moderators and auto-approval). Must run in a transaction.
func Approve(ctx context.Context, tx pgx.Tx, expiryDays int, id string, moderator *string) error {
	var userID string
	var featuredSlots int
	var unlimited bool
	err := tx.QueryRow(ctx, `UPDATE pet_listings l SET status='approved', rejection_reason=NULL, expired_reason=NULL,
		published_at=COALESCE(l.published_at, now()), expires_at=now() + make_interval(days => $2), updated_at=now()
		FROM seller_profiles sp WHERE sp.id=l.seller_id AND l.id=$1 RETURNING sp.user_id`, id, expiryDays).Scan(&userID)
	if err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `INSERT INTO listing_moderation (listing_id, action, moderator_id) VALUES ($1,'approved',$2)`, id, moderator); err != nil {
		return err
	}
	// Featured placement: plans with featured_slots get their newest approved listings featured automatically.
	var ents []byte
	if err := tx.QueryRow(ctx, `SELECT COALESCE((SELECT entitlements FROM subscriptions WHERE user_id=$1 AND audience='seller' AND status IN ('active','grace')), '{}')`, userID).Scan(&ents); err != nil {
		return err
	}
	var m map[string]json.RawMessage
	_ = json.Unmarshal(ents, &m)
	if raw, ok := m["featured_slots"]; ok {
		if string(raw) == "null" {
			unlimited = true
		} else {
			_ = json.Unmarshal(raw, &featuredSlots)
		}
	}
	if unlimited || featuredSlots > 0 {
		var used int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM pet_listings l JOIN seller_profiles sp ON sp.id=l.seller_id
			WHERE sp.user_id=$1 AND l.featured_until > now() AND l.status='approved' AND l.id<>$2`, userID, id).Scan(&used); err != nil {
			return err
		}
		if unlimited || used < featuredSlots {
			if _, err := tx.Exec(ctx, `UPDATE pet_listings SET featured_until=expires_at WHERE id=$1`, id); err != nil {
				return err
			}
		}
	}
	audit.System(ctx, tx, "listing.approved", "listing", id, map[string]any{"auto": moderator == nil})
	return nil
}

// ---------- owner reads ----------

func (s *Service) OwnerView(ctx context.Context, userID, id string, asStaff bool) (*Owner, error) {
	d, sellerUser, err := s.loadDetail(ctx, id, "", false)
	if err != nil {
		return nil, err
	}
	if !asStaff && sellerUser != userID {
		return nil, httpx.NotFound("Listing")
	}
	o := &Owner{Detail: *d}
	err = s.db.QueryRow(ctx, `SELECT status, rejection_reason, expired_reason, favourites_count, enquiries_count, expires_at, created_at, updated_at, lat, lng
		FROM pet_listings WHERE id=$1`, d.ID).Scan(&o.Status, &o.RejectionReason, &o.ExpiredReason, &o.FavouritesCount, &o.EnquiriesCount, &o.ExpiresAt,
		&o.CreatedAt, &o.UpdatedAt, &o.Lat, &o.Lng)
	if err != nil {
		return nil, err
	}
	rows, err := s.db.Query(ctx, `SELECT m.action, m.reason, m.flags, u.name, m.created_at FROM listing_moderation m
		LEFT JOIN users u ON u.id=m.moderator_id WHERE m.listing_id=$1 ORDER BY m.created_at DESC LIMIT 50`, d.ID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	o.Moderation = []ModerationEvent{}
	for rows.Next() {
		var e ModerationEvent
		var mod *string
		if err := rows.Scan(&e.Action, &e.Reason, &e.Flags, &mod, &e.CreatedAt); err != nil {
			return nil, err
		}
		if asStaff {
			e.Moderator = mod // moderator identity is not disclosed to sellers
		}
		o.Moderation = append(o.Moderation, e)
	}
	rows.Close()
	o.MissingForSubmission = []string{}
	if o.Status == "draft" || o.Status == "rejected" || o.Status == "expired" {
		if o.MissingForSubmission, err = s.missing(ctx, s.db, d.ID); err != nil {
			return nil, err
		}
		if o.MissingForSubmission == nil {
			o.MissingForSubmission = []string{}
		}
	}
	return o, nil
}

// OwnerList powers the seller's listing tabs and the admin moderation queue (sellerUserID == "" => all).
func (s *Service) OwnerList(ctx context.Context, sellerUserID, status, search string, pg httpx.Page, asStaff bool) ([]Owner, int, error) {
	q := &qb{}
	where := []string{"l.deleted_at IS NULL"}
	if sellerUserID != "" {
		where = append(where, "sp.user_id="+q.arg(sellerUserID))
	}
	switch status {
	case "":
	case "sold":
		where = append(where, "l.availability IN ('sold','unavailable')")
	default:
		where = append(where, "l.status="+q.arg(status))
		if sellerUserID != "" && status == "approved" {
			where = append(where, "l.availability IN ('available','reserved')")
		}
	}
	if search != "" {
		where = append(where, "(lower(l.title) LIKE "+q.arg("%"+strings.ToLower(search)+"%")+" OR l.id::text="+q.arg(search)+")")
	}
	w := " WHERE " + strings.Join(where, " AND ")
	var total int
	if err := s.db.QueryRow(ctx, `SELECT count(*) FROM pet_listings l JOIN seller_profiles sp ON sp.id=l.seller_id`+w, q.args...).Scan(&total); err != nil {
		return nil, 0, err
	}
	order := " ORDER BY l.updated_at DESC"
	if status == "pending" {
		order = " ORDER BY l.updated_at ASC" // oldest first in the moderation queue
	}
	rows, err := s.db.Query(ctx, `SELECT l.id FROM pet_listings l JOIN seller_profiles sp ON sp.id=l.seller_id`+w+order+
		" LIMIT "+q.arg(pg.PerPage)+" OFFSET "+q.arg(pg.Offset), q.args...)
	if err != nil {
		return nil, 0, err
	}
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return nil, 0, err
		}
		ids = append(ids, id)
	}
	rows.Close()
	out := make([]Owner, 0, len(ids))
	for _, id := range ids {
		o, err := s.OwnerView(ctx, sellerUserID, id, asStaff || sellerUserID == "")
		if err != nil {
			return nil, 0, err
		}
		out = append(out, *o)
	}
	return out, total, nil
}

// ---------- images ----------

func (s *Service) AddImage(ctx context.Context, userID, listingID string, data []byte) (*Image, error) {
	max := s.settings.Int(ctx, "listings.max_images", 8)
	variants, err := media.ProcessImage(data)
	if err != nil {
		switch err {
		case media.ErrBadType:
			return nil, httpx.Invalid(httpx.FieldError{Field: "file", Message: "only JPEG, PNG or WebP images are accepted"})
		default:
			msg := err.Error()
			if strings.HasPrefix(msg, "image could not be read: ") {
				msg = strings.TrimPrefix(msg, "image could not be read: ")
			}
			return nil, httpx.Invalid(httpx.FieldError{Field: "file", Message: msg})
		}
	}
	imageID := uuid.NewString()
	keys := map[string]string{}
	var w, h int
	for _, v := range variants {
		key := fmt.Sprintf("listings/%s/%s_%s.jpg", listingID, imageID, v.Name)
		keys[v.Name] = key
		if v.Name == "large" {
			w, h = v.Width, v.Height
		}
	}
	// Ownership/limit checks before writing any bytes.
	var status string
	var count int
	err = s.db.QueryRow(ctx, `SELECT l.status, (SELECT count(*) FROM listing_images i WHERE i.listing_id=l.id) FROM pet_listings l
		JOIN seller_profiles sp ON sp.id=l.seller_id WHERE l.id::text=$1 AND sp.user_id=$2 AND l.deleted_at IS NULL`, listingID, userID).Scan(&status, &count)
	if database.IsNoRows(err) {
		return nil, httpx.NotFound("Listing")
	}
	if err != nil {
		return nil, err
	}
	if status == "suspended" {
		return nil, httpx.Forbidden("This listing cannot be edited")
	}
	if count >= max {
		return nil, httpx.Conflict(httpx.CodeLimitReached, fmt.Sprintf("A listing can have at most %d photos", max))
	}
	for _, v := range variants {
		if err := s.store.Put(ctx, storage.Public, keys[v.Name], bytes.NewReader(v.Data), int64(len(v.Data)), "image/jpeg"); err != nil {
			return nil, err
		}
	}
	vj, _ := json.Marshal(keys)
	err = s.db.InTx(ctx, func(tx pgx.Tx) error {
		st, err := lockOwned(ctx, tx, userID, listingID)
		if err != nil {
			return err
		}
		var n int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM listing_images WHERE listing_id::text=$1`, listingID).Scan(&n); err != nil {
			return err
		}
		if n >= max {
			return httpx.Conflict(httpx.CodeLimitReached, fmt.Sprintf("A listing can have at most %d photos", max))
		}
		if _, err := tx.Exec(ctx, `INSERT INTO listing_images (id, listing_id, storage_key, variants, width, height, position, is_cover)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`, imageID, listingID, keys["large"], vj, w, h, n, n == 0); err != nil {
			return err
		}
		return remoderate(ctx, tx, listingID, st, "Photos changed")
	})
	if err != nil {
		for _, k := range keys {
			_ = s.store.Delete(ctx, storage.Public, k)
		}
		return nil, err
	}
	s.Invalidate(ctx)
	imgs, err := s.images(ctx, listingID)
	if err != nil {
		return nil, err
	}
	for _, im := range imgs {
		if im.ID == imageID {
			return &im, nil
		}
	}
	return nil, httpx.NotFound("Image")
}

func (s *Service) DeleteImage(ctx context.Context, userID, listingID, imageID string) error {
	var keys map[string]string
	err := s.db.InTx(ctx, func(tx pgx.Tx) error {
		st, err := lockOwned(ctx, tx, userID, listingID)
		if err != nil {
			return err
		}
		var raw []byte
		var wasCover bool
		err = tx.QueryRow(ctx, `DELETE FROM listing_images WHERE id::text=$1 AND listing_id::text=$2 RETURNING variants, is_cover`, imageID, listingID).Scan(&raw, &wasCover)
		if database.IsNoRows(err) {
			return httpx.NotFound("Image")
		}
		if err != nil {
			return err
		}
		_ = json.Unmarshal(raw, &keys)
		if wasCover {
			if _, err := tx.Exec(ctx, `UPDATE listing_images SET is_cover=true WHERE id = (SELECT id FROM listing_images WHERE listing_id::text=$1 ORDER BY position LIMIT 1)`, listingID); err != nil {
				return err
			}
		}
		if st == "approved" {
			var left int
			if err := tx.QueryRow(ctx, `SELECT count(*) FROM listing_images WHERE listing_id::text=$1`, listingID).Scan(&left); err != nil {
				return err
			}
			if left < s.settings.Int(ctx, "listings.min_images", 1) {
				return httpx.Conflict(httpx.CodeConflict, "A live listing must keep at least one photo")
			}
		}
		return nil
	})
	if err != nil {
		return err
	}
	for _, k := range keys {
		_ = s.store.Delete(ctx, storage.Public, k)
	}
	s.Invalidate(ctx)
	return nil
}

func (s *Service) SetCover(ctx context.Context, userID, listingID, imageID string) error {
	err := s.db.InTx(ctx, func(tx pgx.Tx) error {
		if _, err := lockOwned(ctx, tx, userID, listingID); err != nil {
			return err
		}
		var ok bool
		if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM listing_images WHERE id::text=$1 AND listing_id::text=$2)`, imageID, listingID).Scan(&ok); err != nil {
			return err
		}
		if !ok {
			return httpx.NotFound("Image")
		}
		if _, err := tx.Exec(ctx, `UPDATE listing_images SET is_cover=false WHERE listing_id::text=$1 AND is_cover`, listingID); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `UPDATE listing_images SET is_cover=true WHERE id::text=$1`, imageID)
		return err
	})
	if err == nil {
		s.Invalidate(ctx)
	}
	return err
}

func (s *Service) Reorder(ctx context.Context, userID, listingID string, ids []string) error {
	err := s.db.InTx(ctx, func(tx pgx.Tx) error {
		if _, err := lockOwned(ctx, tx, userID, listingID); err != nil {
			return err
		}
		var n int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM listing_images WHERE listing_id::text=$1`, listingID).Scan(&n); err != nil {
			return err
		}
		seen := map[string]bool{}
		for _, id := range ids {
			seen[id] = true
		}
		if len(ids) != n || len(seen) != n {
			return httpx.Invalid(httpx.FieldError{Field: "image_ids", Message: "must list every image of the listing exactly once"})
		}
		for i, id := range ids {
			tag, err := tx.Exec(ctx, `UPDATE listing_images SET position=$3 WHERE id::text=$1 AND listing_id::text=$2`, id, listingID, i)
			if err != nil {
				return err
			}
			if tag.RowsAffected() != 1 {
				return httpx.Invalid(httpx.FieldError{Field: "image_ids", Message: "contains an image from another listing"})
			}
		}
		return nil
	})
	if err == nil {
		s.Invalidate(ctx)
	}
	return err
}

// ExpireListings marks listings past their own expiry date (independent of subscriptions).
func (s *Service) ExpireListings(ctx context.Context) (int, error) {
	tag, err := s.db.Exec(ctx, `WITH exp AS (UPDATE pet_listings SET status='expired', expired_reason='listing_period', featured_until=NULL, updated_at=now()
		WHERE status='approved' AND expires_at IS NOT NULL AND expires_at <= now() RETURNING id)
		INSERT INTO listing_moderation (listing_id, action, reason) SELECT id, 'expired', 'Listing period ended' FROM exp`)
	if err != nil {
		return 0, err
	}
	if tag.RowsAffected() > 0 {
		s.Invalidate(ctx)
	}
	return int(tag.RowsAffected()), nil
}
