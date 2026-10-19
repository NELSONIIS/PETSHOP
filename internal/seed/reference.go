// Package seed loads idempotent reference data and (non-production only) demo data.
package seed

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"strings"

	"github.com/jackc/pgx/v5"

	"petora/internal/catalog"
	"petora/internal/httpserver"
	"petora/internal/security"
)

type setting struct {
	key    string
	value  any
	public bool
}

var defaultSettings = []setting{
	{"brand.name", "PETORA", true},
	{"brand.logo_url", "", true},
	{"platform.currency", "INR", true},
	{"platform.timezone", "Asia/Kolkata", true},
	{"seo.title", "PETORA — Find your next companion", true},
	{"seo.description", "Discover pets from verified sellers and rescues across India. Browse free; unlock seller contact with a membership.", true},
	{"maintenance.enabled", false, true},
	{"maintenance.message", "PETORA is undergoing scheduled maintenance. Please check back soon.", true},
	{"listings.auto_approve", false, false},
	{"listings.require_verified_seller", false, true},
	{"listings.min_images", 1, true},
	{"listings.max_images", 8, true},
	{"listings.expiry_days", 60, true},
	{"listings.on_subscription_expiry", "unpublish", true},
	{"uploads.max_image_mb", 8, true},
	{"uploads.max_doc_mb", 10, true},
	{"contacts.retain_after_expiry", true, true},
	{"enquiries.daily_limit_per_buyer", 20, false},
	{"reports.auto_suspend_threshold", 5, false},
	{"notifications.renewal_reminder_days", []string{"7", "3", "1"}, false},
	{"safety.prohibited_keywords", []string{"star tortoise", "indian star", "ringneck", "alexandrine", "munia", "hill myna", "monkey", "macaque",
		"langur", "pangolin", "owl", "turtle", "tortoise", "mongoose", "slow loris", "ivory", "exotic cub", "wild caught"}, false},
	{"safety.prohibited_rules", "Wild and protected species (Wild Life (Protection) Act, 1972), animals under 8 weeks, and listings by unregistered breeders/pet shops where registration is required are not permitted.", true},
	{"support.email", "support@petora.in", true},
	{"invoice.seller_details", "PETORA (legal entity name, address and GSTIN to be configured)", false},
}

type cat struct {
	slug, name, icon, desc string
	active, verified       bool
	breeds                 []string
}

var categories = []cat{
	{"dogs", "Dogs", "dog", "Puppies and adult dogs from breeders, owners and rescues.", true, false,
		[]string{"Labrador Retriever", "Golden Retriever", "German Shepherd", "Beagle", "Pug", "Shih Tzu", "Indian Pariah (Indie)", "Rottweiler",
			"Siberian Husky", "Pomeranian", "Dachshund", "Doberman", "Cocker Spaniel", "Boxer", "Great Dane", "Rajapalayam", "Mudhol Hound", "Mixed breed"}},
	{"cats", "Cats", "cat", "Kittens and cats for adoption and sale.", true, false,
		[]string{"Persian", "Siamese", "Maine Coon", "Bengal", "British Shorthair", "Ragdoll", "Indian (Indie)", "Mixed breed"}},
	{"birds", "Birds", "bird", "Captive-bred exotic birds only. Native Indian species are protected and prohibited.", true, true,
		[]string{"Budgerigar", "Cockatiel", "Lovebird", "Zebra Finch", "Canary", "African Grey Parrot", "Sun Conure"}},
	{"fish", "Fish", "fish", "Aquarium fish.", true, false, []string{"Goldfish", "Guppy", "Betta", "Angelfish", "Koi", "Molly", "Tetra"}},
	{"rabbits", "Rabbits", "rabbit", "Rabbits from responsible owners and breeders.", true, false, []string{"Holland Lop", "Netherland Dwarf", "New Zealand White", "Lionhead"}},
	{"small-pets", "Small pets", "hamster", "Hamsters, guinea pigs and other small companions.", true, false, []string{"Syrian Hamster", "Dwarf Hamster", "Guinea Pig", "Gerbil"}},
	{"reptiles", "Reptiles", "lizard", "Disabled by default: most native reptiles are protected. Enable only with legal review and documentation rules.", false, true,
		[]string{"Leopard Gecko", "Bearded Dragon", "Ball Python"}},
}

type plan struct {
	code, audience, name, desc, interval string
	price                                int64
	grace, refundDays, sort              int
	ents                                 map[string]any
	features                             []string
}

// Prices are launch placeholders; admins change them in the portal. Tax 18% (GST) is configurable per plan.
var plans = []plan{
	{"buyer_basic", "buyer", "Buyer Basic", "Unlock seller contacts for a month.", "month", 19900, 0, 7, 1,
		map[string]any{"contact_unlocks": 10, "enquiries": 20, "analytics": false, "listing_limit": 0, "featured_slots": 0},
		[]string{"10 seller contact unlocks", "20 enquiries", "Saved searches & favourites"}},
	{"buyer_plus", "buyer", "Buyer Plus", "Unlimited contact unlocks for three months.", "quarter", 49900, 0, 7, 2,
		map[string]any{"contact_unlocks": nil, "enquiries": 100, "analytics": false, "listing_limit": 0, "featured_slots": 0},
		[]string{"Unlimited contact unlocks", "100 enquiries", "Priority support"}},
	{"seller_starter", "seller", "Seller Starter", "For individuals rehoming or occasionally selling.", "month", 49900, 3, 0, 1,
		map[string]any{"listing_limit": 3, "analytics": false, "featured_slots": 0, "contact_unlocks": 0, "enquiries": 0},
		[]string{"Up to 3 active listings", "Enquiry inbox", "Verification badge (after approval)"}},
	{"seller_pro", "seller", "Seller Pro", "For registered breeders and active sellers.", "month", 149900, 7, 0, 2,
		map[string]any{"listing_limit": 15, "analytics": true, "featured_slots": 2, "contact_unlocks": 0, "enquiries": 0},
		[]string{"Up to 15 active listings", "Listing analytics", "2 featured listings"}},
	{"seller_business", "seller", "Seller Business", "For pet shops and kennels, billed yearly.", "year", 1199900, 7, 0, 3,
		map[string]any{"listing_limit": 100, "analytics": true, "featured_slots": 10, "contact_unlocks": 0, "enquiries": 0},
		[]string{"Up to 100 active listings", "Listing analytics", "10 featured listings", "Business profile"}},
}

// Run loads reference data idempotently (never overwrites admin edits) and optionally demo data.
func Run(ctx context.Context, a *httpserver.App, demo bool) error {
	err := a.DB.InTx(ctx, func(tx pgx.Tx) error {
		for _, s := range defaultSettings {
			b, _ := json.Marshal(s.value)
			if _, err := tx.Exec(ctx, `INSERT INTO platform_settings (key, value, is_public) VALUES ($1,$2,$3) ON CONFLICT (key) DO NOTHING`, s.key, b, s.public); err != nil {
				return err
			}
		}
		for i, c := range categories {
			var id string
			if err := tx.QueryRow(ctx, `INSERT INTO categories (slug, name, icon, description, sort_order, is_active, requires_verified_seller)
				VALUES ($1,$2,$3,$4,$5,$6,$7) ON CONFLICT (slug) DO UPDATE SET slug=EXCLUDED.slug RETURNING id`,
				c.slug, c.name, c.icon, c.desc, i*10, c.active, c.verified).Scan(&id); err != nil {
				return err
			}
			for _, b := range c.breeds {
				if _, err := tx.Exec(ctx, `INSERT INTO breeds (category_id, slug, name) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING`, id, catalog.Slugify(b), b); err != nil {
					return err
				}
			}
		}
		for _, p := range plans {
			feat, _ := json.Marshal(p.features)
			var id string
			err := tx.QueryRow(ctx, `INSERT INTO subscription_plans (code, audience, name, description, price_minor, billing_interval, tax_rate_bps,
				grace_days, refund_window_days, refund_policy, sort_order, features)
				VALUES ($1,$2,$3,$4,$5,$6,1800,$7,$8,$9,$10,$11) ON CONFLICT (code) DO NOTHING RETURNING id`,
				p.code, p.audience, p.name, p.desc, p.price, p.interval, p.grace, p.refundDays, refundText(p), p.sort, feat).Scan(&id)
			if errors.Is(err, pgx.ErrNoRows) {
				continue // already present: keep admin's configuration
			}
			if err != nil {
				return err
			}
			for k, v := range p.ents {
				var iv *int
				var bv *bool
				switch x := v.(type) {
				case bool:
					bv = &x
				case int:
					iv = &x
				}
				if _, err := tx.Exec(ctx, `INSERT INTO plan_entitlements (plan_id, key, int_value, bool_value) VALUES ($1,$2,$3,$4)`, id, k, iv, bv); err != nil {
					return err
				}
			}
		}
		for slug, page := range legalPages {
			if _, err := tx.Exec(ctx, `INSERT INTO legal_policy_versions (slug, version, title, body_md, is_current, published_at)
				SELECT $1, 1, $2, $3, true, now() WHERE NOT EXISTS (SELECT 1 FROM legal_policy_versions WHERE slug=$1)`, slug, page[0], page[1]); err != nil {
				return err
			}
		}
		for key, data := range contentBlocks {
			b, _ := json.Marshal(data)
			if _, err := tx.Exec(ctx, `INSERT INTO content_blocks (key, data) VALUES ($1,$2) ON CONFLICT (key) DO NOTHING`, key, b); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return err
	}
	a.Cache.DelPrefix(ctx, "catalog:")
	a.Cache.DelPrefix(ctx, "plans:")
	slog.Info("reference data loaded")
	if demo {
		if a.Config.IsProduction() {
			return errors.New("refusing to load demo data in production")
		}
		return loadDemo(ctx, a)
	}
	return nil
}

func refundText(p plan) string {
	if p.refundDays > 0 {
		return fmt.Sprintf("Full refund within %d days of purchase if no seller contacts were unlocked. Otherwise non-refundable.", p.refundDays)
	}
	return "Non-refundable once activated. Cancel any time to stop renewal reminders; benefits continue until the end of the paid period."
}

// CreateAdmin creates the first super administrator. MFA is enrolled at first login.
func CreateAdmin(ctx context.Context, a *httpserver.App, email, name, password string) error {
	email = strings.ToLower(strings.TrimSpace(email))
	if email == "" || name == "" || len(password) < 12 {
		return errors.New("ADMIN_EMAIL, ADMIN_NAME and ADMIN_PASSWORD (12+ chars) are required")
	}
	hash, err := security.HashPassword(password)
	if err != nil {
		return err
	}
	return a.DB.InTx(ctx, func(tx pgx.Tx) error {
		var id string
		if err := tx.QueryRow(ctx, `INSERT INTO users (email, name, password_hash, account_type, email_verified_at) VALUES ($1,$2,$3,'staff',now()) RETURNING id`,
			email, name, hash).Scan(&id); err != nil {
			return fmt.Errorf("create admin: %w", err)
		}
		if _, err := tx.Exec(ctx, `INSERT INTO user_roles (user_id, role_code) VALUES ($1,'super_admin')`, id); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `INSERT INTO audit_logs (action, entity_type, entity_id) VALUES ('staff.bootstrap_admin','user',$1)`, id)
		slog.Info("super administrator created; enrol MFA at first login", "email", email)
		return err
	})
}
