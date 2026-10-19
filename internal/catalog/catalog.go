// Package catalog manages categories and breeds.
package catalog

import (
	"context"
	"encoding/json"
	"strings"
	"time"
	"unicode"

	"github.com/jackc/pgx/v5"

	"petora/internal/audit"
	"petora/internal/cache"
	"petora/internal/database"
	"petora/internal/httpx"
)

type Service struct {
	db    *database.DB
	cache *cache.Cache
}

func New(db *database.DB, c *cache.Cache) *Service { return &Service{db: db, cache: c} }

type Breed struct {
	ID       string `json:"id"`
	Slug     string `json:"slug"`
	Name     string `json:"name"`
	IsActive bool   `json:"is_active"`
}

type Category struct {
	ID                     string          `json:"id"`
	Slug                   string          `json:"slug"`
	Name                   string          `json:"name"`
	Icon                   string          `json:"icon"`
	Description            string          `json:"description"`
	SortOrder              int             `json:"sort_order"`
	IsActive               bool            `json:"is_active"`
	RequiresVerifiedSeller bool            `json:"requires_verified_seller"`
	JurisdictionRules      json.RawMessage `json:"jurisdiction_rules,omitempty"`
	ListingCount           int             `json:"listing_count"`
	Breeds                 []Breed         `json:"breeds"`
}

const cacheKeyPublic = "catalog:public"

func (s *Service) List(ctx context.Context, admin bool) ([]Category, error) {
	var out []Category
	if !admin && s.cache.GetJSON(ctx, cacheKeyPublic, &out) {
		return out, nil
	}
	where := "WHERE c.is_active"
	if admin {
		where = ""
	}
	rows, err := s.db.Query(ctx, `SELECT c.id, c.slug, c.name, c.icon, c.description, c.sort_order, c.is_active, c.requires_verified_seller, c.jurisdiction_rules,
		(SELECT count(*) FROM pet_listings l WHERE l.category_id=c.id AND l.status='approved' AND l.deleted_at IS NULL AND l.availability IN ('available','reserved'))
		FROM categories c `+where+` ORDER BY c.sort_order, c.name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out = []Category{}
	idx := map[string]int{}
	for rows.Next() {
		var c Category
		if err := rows.Scan(&c.ID, &c.Slug, &c.Name, &c.Icon, &c.Description, &c.SortOrder, &c.IsActive, &c.RequiresVerifiedSeller, &c.JurisdictionRules, &c.ListingCount); err != nil {
			return nil, err
		}
		c.Breeds = []Breed{}
		if !admin {
			c.JurisdictionRules = nil
		}
		idx[c.ID] = len(out)
		out = append(out, c)
	}
	rows.Close()
	bw := "WHERE b.is_active"
	if admin {
		bw = ""
	}
	brows, err := s.db.Query(ctx, `SELECT b.category_id, b.id, b.slug, b.name, b.is_active FROM breeds b `+bw+` ORDER BY b.name`)
	if err != nil {
		return nil, err
	}
	defer brows.Close()
	for brows.Next() {
		var cid string
		var b Breed
		if err := brows.Scan(&cid, &b.ID, &b.Slug, &b.Name, &b.IsActive); err != nil {
			return nil, err
		}
		if i, ok := idx[cid]; ok {
			out[i].Breeds = append(out[i].Breeds, b)
		}
	}
	if !admin {
		s.cache.SetJSON(ctx, cacheKeyPublic, out, 2*time.Minute)
	}
	return out, brows.Err()
}

func (s *Service) GetBySlug(ctx context.Context, slug string) (*Category, error) {
	all, err := s.List(ctx, false)
	if err != nil {
		return nil, err
	}
	for i := range all {
		if all[i].Slug == slug {
			return &all[i], nil
		}
	}
	return nil, httpx.NotFound("Category")
}

func (s *Service) invalidate(ctx context.Context) { s.cache.Del(ctx, cacheKeyPublic) }

type CategoryInput struct {
	Slug                   string          `json:"slug"`
	Name                   string          `json:"name"`
	Icon                   string          `json:"icon"`
	Description            string          `json:"description"`
	SortOrder              int             `json:"sort_order"`
	IsActive               *bool           `json:"is_active"`
	RequiresVerifiedSeller bool            `json:"requires_verified_seller"`
	JurisdictionRules      json.RawMessage `json:"jurisdiction_rules"`
}

func (in *CategoryInput) validate() error {
	var v httpx.V
	in.Name = strings.TrimSpace(in.Name)
	v.Length("name", in.Name, 2, 60)
	if in.Slug == "" {
		in.Slug = Slugify(in.Name)
	}
	in.Slug = Slugify(in.Slug)
	if in.Slug == "" {
		v.Add("slug", "is invalid")
	}
	if in.Icon == "" {
		in.Icon = "paw"
	}
	if len(in.JurisdictionRules) == 0 {
		in.JurisdictionRules = json.RawMessage(`{}`)
	} else {
		var m map[string]map[string]any
		if json.Unmarshal(in.JurisdictionRules, &m) != nil {
			v.Add("jurisdiction_rules", `must be an object like {"maharashtra":{"allowed":false}}`)
		}
	}
	return v.Err()
}

func (s *Service) CreateCategory(ctx context.Context, in CategoryInput) (string, error) {
	if err := in.validate(); err != nil {
		return "", err
	}
	active := true
	if in.IsActive != nil {
		active = *in.IsActive
	}
	var id string
	err := s.db.InTx(ctx, func(tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, `INSERT INTO categories (slug, name, icon, description, sort_order, is_active, requires_verified_seller, jurisdiction_rules)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id`, in.Slug, in.Name, in.Icon, in.Description, in.SortOrder, active, in.RequiresVerifiedSeller, in.JurisdictionRules).Scan(&id); err != nil {
			return err
		}
		return audit.Log(ctx, tx, audit.Entry{Action: "category.created", EntityType: "category", EntityID: id, Metadata: map[string]any{"slug": in.Slug}})
	})
	if database.IsUniqueViolation(err, "categories_slug_key") {
		return "", httpx.Conflict(httpx.CodeConflict, "A category with this slug already exists")
	}
	s.invalidate(ctx)
	return id, err
}

func (s *Service) UpdateCategory(ctx context.Context, id string, in CategoryInput) error {
	if err := in.validate(); err != nil {
		return err
	}
	err := s.db.InTx(ctx, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `UPDATE categories SET slug=$2, name=$3, icon=$4, description=$5, sort_order=$6,
			is_active=COALESCE($7,is_active), requires_verified_seller=$8, jurisdiction_rules=$9, updated_at=now() WHERE id::text=$1`,
			id, in.Slug, in.Name, in.Icon, in.Description, in.SortOrder, in.IsActive, in.RequiresVerifiedSeller, in.JurisdictionRules)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return httpx.NotFound("Category")
		}
		return audit.Log(ctx, tx, audit.Entry{Action: "category.updated", EntityType: "category", EntityID: id})
	})
	if database.IsUniqueViolation(err, "categories_slug_key") {
		return httpx.Conflict(httpx.CodeConflict, "A category with this slug already exists")
	}
	s.invalidate(ctx)
	s.cache.DelPrefix(ctx, "pets:")
	return err
}

type BreedInput struct {
	Name     string `json:"name"`
	IsActive *bool  `json:"is_active"`
}

func (s *Service) CreateBreed(ctx context.Context, categoryID string, in BreedInput) (string, error) {
	in.Name = strings.TrimSpace(in.Name)
	var v httpx.V
	v.Length("name", in.Name, 2, 80)
	if err := v.Err(); err != nil {
		return "", err
	}
	active := in.IsActive == nil || *in.IsActive
	var id string
	err := s.db.InTx(ctx, func(tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, `INSERT INTO breeds (category_id, slug, name, is_active) VALUES ($1,$2,$3,$4) RETURNING id`,
			categoryID, Slugify(in.Name), in.Name, active).Scan(&id); err != nil {
			return err
		}
		return audit.Log(ctx, tx, audit.Entry{Action: "breed.created", EntityType: "breed", EntityID: id})
	})
	if database.IsUniqueViolation(err, "") {
		return "", httpx.Conflict(httpx.CodeConflict, "This breed already exists in the category")
	}
	if err != nil && strings.Contains(err.Error(), "violates foreign key") {
		return "", httpx.NotFound("Category")
	}
	s.invalidate(ctx)
	return id, err
}

func (s *Service) UpdateBreed(ctx context.Context, id string, in BreedInput) error {
	in.Name = strings.TrimSpace(in.Name)
	if in.Name != "" {
		var v httpx.V
		v.Length("name", in.Name, 2, 80)
		if err := v.Err(); err != nil {
			return err
		}
	}
	err := s.db.InTx(ctx, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `UPDATE breeds SET name=COALESCE(NULLIF($2,''),name), slug=CASE WHEN $2<>'' THEN $3 ELSE slug END,
			is_active=COALESCE($4,is_active) WHERE id::text=$1`, id, in.Name, Slugify(in.Name), in.IsActive)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return httpx.NotFound("Breed")
		}
		return audit.Log(ctx, tx, audit.Entry{Action: "breed.updated", EntityType: "breed", EntityID: id})
	})
	s.invalidate(ctx)
	return err
}

// Slugify lower-cases and hyphenates ASCII words.
func Slugify(s string) string {
	var b strings.Builder
	dash := false
	for _, r := range strings.ToLower(s) {
		if r < unicode.MaxASCII && (unicode.IsLetter(r) || unicode.IsDigit(r)) {
			b.WriteRune(r)
			dash = false
		} else if !dash && b.Len() > 0 {
			b.WriteByte('-')
			dash = true
		}
	}
	out := strings.Trim(b.String(), "-")
	if len(out) > 60 {
		out = strings.Trim(out[:60], "-")
	}
	return out
}
