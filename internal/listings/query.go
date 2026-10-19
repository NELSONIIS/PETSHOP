package listings

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"petora/internal/cache"
	"petora/internal/database"
	"petora/internal/httpx"
	"petora/internal/sellers"
	"petora/internal/settings"
	"petora/internal/storage"
)

type Service struct {
	db       *database.DB
	cache    *cache.Cache
	store    storage.Store
	settings *settings.Service
	sellers  *sellers.Service
}

func New(db *database.DB, c *cache.Cache, store storage.Store, st *settings.Service, sel *sellers.Service) *Service {
	return &Service{db: db, cache: c, store: store, settings: st, sellers: sel}
}

// PublicPredicate is the single definition of "publicly visible". Every public read uses it, so a
// suspended seller, lapsed subscription, deleted or unapproved listing can never leak into discovery.
const PublicPredicate = `l.status='approved' AND l.deleted_at IS NULL AND l.availability IN ('available','reserved') AND c.is_active
	AND su.status='active' AND sp.verification_status <> 'suspended'
	AND EXISTS (SELECT 1 FROM subscriptions s WHERE s.user_id=sp.user_id AND s.audience='seller' AND s.status IN ('active','grace'))`

const baseFrom = ` FROM pet_listings l
	JOIN categories c ON c.id=l.category_id
	LEFT JOIN breeds b ON b.id=l.breed_id
	JOIN seller_profiles sp ON sp.id=l.seller_id
	JOIN users su ON su.id=sp.user_id
	LEFT JOIN LATERAL (SELECT i.variants FROM listing_images i WHERE i.listing_id=l.id ORDER BY i.is_cover DESC, i.position LIMIT 1) cov ON true`

// qb collects positional arguments for dynamically-built (still fully parameterised) SQL.
type qb struct{ args []any }

func (q *qb) arg(v any) string { q.args = append(q.args, v); return "$" + strconv.Itoa(len(q.args)) }

func cardSelect(q *qb, viewer string, lat, lng *float64) string {
	fav := "false"
	if viewer != "" {
		fav = "EXISTS (SELECT 1 FROM favourites f WHERE f.listing_id=l.id AND f.user_id=" + q.arg(viewer) + ")"
	}
	dist := "NULL::float8"
	if lat != nil && lng != nil {
		dist = haversine(q.arg(*lat), q.arg(*lng))
	}
	return `SELECT l.id, l.slug, l.title, l.listing_type, l.price_minor, l.currency, l.age_months, l.gender, l.city, l.state,
		c.id, c.slug, c.name, b.id, b.slug, b.name, cov.variants,
		sp.id, sp.slug, sp.display_name, sp.seller_type, sp.verification_status='approved', sp.city, sp.state, sp.logo_url,
		l.availability, l.vaccination_status, COALESCE(l.featured_until > now(), false), ` + fav + `, ` + dist + `, l.published_at`
}

func haversine(lat, lng string) string {
	return fmt.Sprintf(`CASE WHEN l.lat IS NULL THEN NULL ELSE 6371 * acos(LEAST(1, GREATEST(-1,
		cos(radians(%[1]s::float8)) * cos(radians(l.lat)) * cos(radians(l.lng) - radians(%[2]s::float8)) +
		sin(radians(%[1]s::float8)) * sin(radians(l.lat))))) END`, lat, lng)
}

func (s *Service) scanCard(row pgx.Row) (*Card, error) {
	var c Card
	var bID, bSlug, bName *string
	var cov []byte
	var logo *string
	err := row.Scan(&c.ID, &c.Slug, &c.Title, &c.ListingType, &c.PriceMinor, &c.Currency, &c.AgeMonths, &c.Gender, &c.City, &c.State,
		&c.Category.ID, &c.Category.Slug, &c.Category.Name, &bID, &bSlug, &bName, &cov,
		&c.Seller.ID, &c.Seller.Slug, &c.Seller.DisplayName, &c.Seller.SellerType, &c.Seller.Verified, &c.Seller.City, &c.Seller.State, &logo,
		&c.Availability, &c.VaccinationStatus, &c.Featured, &c.IsFavourite, &c.DistanceKm, &c.PublishedAt)
	if err != nil {
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
	if c.DistanceKm != nil {
		d := math.Round(*c.DistanceKm*10) / 10
		c.DistanceKm = &d
	}
	return &c, nil
}

func (s *Service) variants(raw []byte) *Variants {
	if len(raw) == 0 {
		return nil
	}
	var m map[string]string
	if json.Unmarshal(raw, &m) != nil || m["large"] == "" {
		return nil
	}
	return &Variants{Thumb: s.store.PublicURL(m["thumb"]), Medium: s.store.PublicURL(m["medium"]), Large: s.store.PublicURL(m["large"])}
}

// SearchParams mirrors GET /pets query parameters.
type SearchParams struct {
	Q, Category, Breed, Gender, City, State, SellerType, ListingType, Vaccination, Availability, Sort, SellerSlug string
	MinPrice, MaxPrice, MinAge, MaxAge                                                                            *int64
	Lat, Lng                                                                                                      *float64
	RadiusKm, ListedWithinDays                                                                                    int
	Verified, Featured                                                                                            *bool
	Page                                                                                                          httpx.Page
}

func ParseSearch(v url.Values, pg httpx.Page) (SearchParams, error) {
	p := SearchParams{Q: strings.TrimSpace(v.Get("q")), Category: v.Get("category"), Breed: v.Get("breed"), Gender: v.Get("gender"),
		City: strings.TrimSpace(v.Get("city")), State: strings.TrimSpace(v.Get("state")), SellerType: v.Get("seller_type"),
		ListingType: v.Get("listing_type"), Vaccination: v.Get("vaccination"), Availability: v.Get("availability"), Sort: v.Get("sort"), Page: pg}
	var val httpx.V
	intp := func(k string) *int64 {
		if s := v.Get(k); s != "" {
			n, err := strconv.ParseInt(s, 10, 64)
			if err != nil || n < 0 {
				val.Add(k, "must be a non-negative integer")
				return nil
			}
			return &n
		}
		return nil
	}
	floatp := func(k string, lim float64) *float64 {
		if s := v.Get(k); s != "" {
			f, err := strconv.ParseFloat(s, 64)
			if err != nil || math.Abs(f) > lim {
				val.Add(k, "is out of range")
				return nil
			}
			return &f
		}
		return nil
	}
	boolp := func(k string) *bool {
		switch v.Get(k) {
		case "true", "1":
			b := true
			return &b
		case "false", "0":
			b := false
			return &b
		}
		return nil
	}
	p.MinPrice, p.MaxPrice, p.MinAge, p.MaxAge = intp("min_price"), intp("max_price"), intp("min_age_months"), intp("max_age_months")
	p.Lat, p.Lng = floatp("lat", 90), floatp("lng", 180)
	if r := intp("radius_km"); r != nil {
		p.RadiusKm = int(min(*r, 1000))
	}
	if d := intp("listed_within_days"); d != nil {
		p.ListedWithinDays = int(min(*d, 365))
	}
	p.Verified, p.Featured = boolp("verified_seller"), boolp("featured")
	check := func(k, val2 string, allowed ...string) {
		if val2 != "" {
			val.OneOf(k, val2, allowed...)
		}
	}
	check("gender", p.Gender, "male", "female", "unknown")
	check("seller_type", p.SellerType, "individual", "business")
	check("listing_type", p.ListingType, "sale", "adoption")
	check("vaccination", p.Vaccination, "complete", "partial", "none")
	check("availability", p.Availability, "available", "reserved")
	check("sort", p.Sort, "newest", "price_asc", "price_desc", "relevance", "nearest")
	if p.RadiusKm > 0 && (p.Lat == nil || p.Lng == nil) {
		val.Add("radius_km", "requires lat and lng")
	}
	if p.Sort == "nearest" && (p.Lat == nil || p.Lng == nil) {
		val.Add("sort", "nearest requires lat and lng")
	}
	if len(p.Q) > 100 {
		val.Add("q", "is too long")
	}
	return p, val.Err()
}

var tokenRe = regexp.MustCompile(`[\p{L}\p{N}]+`)

// prefixQuery converts free text into a safe prefix tsquery ("lab pup" -> "lab:* & pup:*").
func prefixQuery(q string) string {
	toks := tokenRe.FindAllString(strings.ToLower(q), 6)
	for i, t := range toks {
		toks[i] = t + ":*"
	}
	return strings.Join(toks, " & ")
}

func (s *Service) Search(ctx context.Context, p SearchParams, viewer string) ([]Card, int, error) {
	type cached struct {
		Cards []Card
		Total int
	}
	var key string
	if viewer == "" { // anonymous results are identical for everyone: cache briefly
		key = "pets:list:" + hashParams(p)
		var c cached
		if s.cache.GetJSON(ctx, key, &c) {
			return c.Cards, c.Total, nil
		}
	}
	q := &qb{}
	where := []string{PublicPredicate}
	rank := ""
	if p.Q != "" {
		if tq := prefixQuery(p.Q); tq != "" {
			a := q.arg(tq)
			like := q.arg("%" + strings.ToLower(p.Q) + "%")
			where = append(where, "(l.search_vector @@ to_tsquery('simple',"+a+") OR lower(b.name) LIKE "+like+" OR lower(c.name) LIKE "+like+")")
			rank = "ts_rank(l.search_vector, to_tsquery('simple'," + a + "))"
		}
	}
	if p.Category != "" {
		where = append(where, "c.slug="+q.arg(p.Category))
	}
	if p.Breed != "" {
		a := q.arg(p.Breed)
		where = append(where, "(b.id::text="+a+" OR b.slug="+a+")")
	}
	if p.SellerSlug != "" {
		where = append(where, "sp.slug="+q.arg(p.SellerSlug))
	}
	if p.MinPrice != nil {
		where = append(where, "l.price_minor >= "+q.arg(*p.MinPrice))
	}
	if p.MaxPrice != nil {
		where = append(where, "l.price_minor <= "+q.arg(*p.MaxPrice))
	}
	if p.MinAge != nil {
		where = append(where, "l.age_months >= "+q.arg(*p.MinAge))
	}
	if p.MaxAge != nil {
		where = append(where, "l.age_months <= "+q.arg(*p.MaxAge))
	}
	for col, val := range map[string]string{"l.gender": p.Gender, "sp.seller_type": p.SellerType, "l.listing_type": p.ListingType,
		"l.vaccination_status": p.Vaccination, "l.availability": p.Availability} {
		if val != "" {
			where = append(where, col+"="+q.arg(val))
		}
	}
	if p.City != "" {
		where = append(where, "lower(l.city)=lower("+q.arg(p.City)+")")
	}
	if p.State != "" {
		where = append(where, "lower(l.state)=lower("+q.arg(p.State)+")")
	}
	if p.Verified != nil && *p.Verified {
		where = append(where, "sp.verification_status='approved'")
	}
	if p.Featured != nil && *p.Featured {
		where = append(where, "l.featured_until > now()")
	}
	if p.ListedWithinDays > 0 {
		where = append(where, "l.published_at >= now() - make_interval(days => "+q.arg(p.ListedWithinDays)+")")
	}
	if p.RadiusKm > 0 && p.Lat != nil && p.Lng != nil {
		// Bounding box (index-friendly) then exact great-circle distance.
		dLat := float64(p.RadiusKm) / 111.0
		dLng := float64(p.RadiusKm) / (111.0 * math.Max(0.01, math.Cos(*p.Lat*math.Pi/180)))
		where = append(where, fmt.Sprintf("l.lat BETWEEN %s AND %s AND l.lng BETWEEN %s AND %s",
			q.arg(*p.Lat-dLat), q.arg(*p.Lat+dLat), q.arg(*p.Lng-dLng), q.arg(*p.Lng+dLng)))
		where = append(where, haversine(q.arg(*p.Lat), q.arg(*p.Lng))+" <= "+q.arg(float64(p.RadiusKm)))
	}
	whereSQL := " WHERE " + strings.Join(where, " AND ")
	nWhere := len(q.args) // the count query must receive exactly the WHERE arguments
	sel := cardSelect(q, viewer, p.Lat, p.Lng)
	order := " ORDER BY l.published_at DESC NULLS LAST, l.id"
	switch p.Sort {
	case "price_asc":
		order = " ORDER BY l.price_minor ASC, l.published_at DESC, l.id"
	case "price_desc":
		order = " ORDER BY l.price_minor DESC, l.published_at DESC, l.id"
	case "relevance":
		if rank != "" {
			order = " ORDER BY " + rank + " DESC, l.published_at DESC, l.id"
		}
	case "nearest":
		order = " ORDER BY 30 ASC NULLS LAST, l.id"
	}
	var total int
	if err := s.db.QueryRow(ctx, "SELECT count(*)"+baseFrom+whereSQL, q.args[:nWhere]...).Scan(&total); err != nil {
		return nil, 0, err
	}
	limit, offset := q.arg(p.Page.PerPage), q.arg(p.Page.Offset)
	rows, err := s.db.Query(ctx, sel+baseFrom+whereSQL+order+" LIMIT "+limit+" OFFSET "+offset, q.args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := []Card{}
	for rows.Next() {
		c, err := s.scanCard(rows)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, *c)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	if key != "" {
		s.cache.SetJSON(ctx, key, cached{out, total}, 60*time.Second)
	}
	return out, total, nil
}

func hashParams(p SearchParams) string {
	b, _ := json.Marshal(p)
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:12])
}

// Invalidate drops cached public listing pages (call after any visibility-affecting change).
func (s *Service) Invalidate(ctx context.Context) { s.cache.DelPrefix(ctx, "pets:") }

// CoverFromRaw converts a stored variants JSON into public URLs (used by other modules).
func (s *Service) CoverFromRaw(raw []byte) *Variants { return s.variants(raw) }
