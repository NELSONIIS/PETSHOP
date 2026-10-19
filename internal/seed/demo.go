package seed

import (
	"bytes"
	"context"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"log/slog"
	"math"

	"github.com/jackc/pgx/v5"

	"petora/internal/authctx"
	"petora/internal/httpserver"
	"petora/internal/listings"
	"petora/internal/security"
)

const DemoPassword = "PetoraDemo2026!"

type demoUser struct {
	email, name, kind string
	roles             []string
}

var demoUsers = []demoUser{
	{"buyer@demo.petora.test", "Asha Buyer", "buyer", []string{"buyer"}},
	{"seller@demo.petora.test", "Ravi Kennels", "seller", []string{"seller"}},
	{"rescue@demo.petora.test", "Paws Rescue Pune", "seller", []string{"seller"}},
	{"admin@demo.petora.test", "Demo Super Admin", "staff", []string{"super_admin"}},
	{"moderator@demo.petora.test", "Demo Moderator", "staff", []string{"moderator"}},
	{"finance@demo.petora.test", "Demo Finance", "staff", []string{"finance"}},
}

type demoListing struct {
	seller, category, breed, title, desc, ltype, gender, city, state, vacc string
	price                                                                  int64
	age                                                                    int
	lat, lng                                                               float64
	hue                                                                    float64
}

var demoListings = []demoListing{
	{"seller", "dogs", "labrador-retriever", "Labrador Retriever puppy, 10 weeks", "Playful yellow Labrador puppy raised at home with the mother. First vaccination and deworming done; vet card available to see in person.", "sale", "male", "Pune", "Maharashtra", "partial", 1800000, 3, 18.5204, 73.8567, 45},
	{"seller", "dogs", "golden-retriever", "Golden Retriever female, 3 months", "Gentle golden girl, socialised with children. Vaccination record and deworming history available. Visit by appointment.", "sale", "female", "Mumbai", "Maharashtra", "partial", 2500000, 3, 19.0760, 72.8777, 40},
	{"seller", "dogs", "beagle", "Beagle puppy, tricolour", "Curious and friendly beagle pup. Parents can be seen. Second vaccination due next week.", "sale", "male", "Bengaluru", "Karnataka", "partial", 2200000, 2, 12.9716, 77.5946, 30},
	{"seller", "cats", "persian", "Persian kitten, white", "Calm Persian kitten, litter trained, eats dry and wet food. Vaccination record available.", "sale", "female", "Hyderabad", "Telangana", "complete", 1500000, 3, 17.3850, 78.4867, 200},
	{"seller", "birds", "cockatiel", "Hand-raised cockatiel pair", "Captive-bred, hand-raised cockatiel pair with cage. Not a protected species. Health check welcome.", "sale", "unknown", "Pune", "Maharashtra", "none", 650000, 8, 18.5600, 73.8000, 55},
	{"seller", "fish", "betta", "Halfmoon Betta, blue", "Healthy halfmoon betta, eating well. Local pickup only.", "sale", "male", "Pune", "Maharashtra", "none", 45000, 5, 18.5100, 73.9000, 210},
	{"rescue", "dogs", "indian-pariah-indie", "Indie pup for adoption — Bholu", "Rescued from a construction site, healthy and vaccinated. Looking for a loving home. Home check and adoption form required.", "adoption", "male", "Pune", "Maharashtra", "complete", 0, 4, 18.5300, 73.8400, 25},
	{"rescue", "cats", "indian-indie", "Two indie kittens for adoption", "Brother and sister kittens, dewormed, first vaccination done. Adopt together preferably.", "adoption", "unknown", "Pune", "Maharashtra", "partial", 0, 2, 18.5000, 73.8200, 15},
	{"rescue", "dogs", "mixed-breed", "Senior dog Rani needs a calm home", "Rani is 7, gentle, house-trained and fully vaccinated. Ideal for a quiet family.", "adoption", "female", "Mumbai", "Maharashtra", "complete", 0, 84, 19.1000, 72.9000, 35},
	{"rescue", "rabbits", "new-zealand-white", "Rabbit pair for adoption", "Two friendly rescued rabbits, litter trained. Hutch included.", "adoption", "unknown", "Pune", "Maharashtra", "none", 0, 12, 18.5500, 73.8700, 340},
}

func loadDemo(ctx context.Context, a *httpserver.App) error {
	if a.Payments.Provider().Name() != "testmode" {
		return fmt.Errorf("demo data needs PAYMENT_PROVIDER=testmode (it creates TEST-MODE subscriptions, never real payments)")
	}
	hash, err := security.HashPassword(DemoPassword)
	if err != nil {
		return err
	}
	ids := map[string]string{}
	for _, u := range demoUsers {
		var id string
		err := a.DB.QueryRow(ctx, `INSERT INTO users (email, name, password_hash, account_type, email_verified_at) VALUES ($1,$2,$3,$4,now())
			ON CONFLICT (email) DO UPDATE SET email=EXCLUDED.email RETURNING id`, u.email, u.name, hash, u.kind).Scan(&id)
		if err != nil {
			return err
		}
		ids[u.email] = id
		for _, r := range u.roles {
			if _, err := a.DB.Exec(ctx, `INSERT INTO user_roles (user_id, role_code) VALUES ($1,$2) ON CONFLICT DO NOTHING`, id, r); err != nil {
				return err
			}
		}
		switch u.kind {
		case "buyer":
			_, err = a.DB.Exec(ctx, `INSERT INTO buyer_profiles (user_id, city, state, lat, lng) VALUES ($1,'Pune','Maharashtra',18.5204,73.8567) ON CONFLICT DO NOTHING`, id)
		case "seller":
			slug := map[string]string{"seller@demo.petora.test": "ravi-kennels", "rescue@demo.petora.test": "paws-rescue-pune"}[u.email]
			stype := map[string]string{"seller@demo.petora.test": "business", "rescue@demo.petora.test": "individual"}[u.email]
			_, err = a.DB.Exec(ctx, `INSERT INTO seller_profiles (user_id, slug, display_name, seller_type, business_name, bio, city, state, lat, lng,
				contact_phone, contact_whatsapp, contact_email, verification_status, verified_at)
				VALUES ($1,$2,$3,$4,$5,$6,'Pune','Maharashtra',18.5204,73.8567,'+919800000001','+919800000001',$7,'approved',now()) ON CONFLICT (user_id) DO NOTHING`,
				id, slug, u.name, stype, u.name, "Demo seller profile (sample data).", u.email)
		case "staff":
			var enabled bool
			if err := a.DB.QueryRow(ctx, `SELECT mfa_enabled_at IS NOT NULL FROM users WHERE id=$1`, id).Scan(&enabled); err != nil {
				return err
			}
			if !enabled {
				secret, err := a.Auth.BootstrapMFA(ctx, id)
				if err != nil {
					return err
				}
				slog.Warn("DEMO staff account MFA secret (add to an authenticator app)", "email", u.email, "totp_secret", secret)
			}
		}
		if err != nil {
			return err
		}
	}
	// Test-mode subscriptions, created through the real checkout + test-complete path (labelled testmode).
	subscribe := func(email, accType, planCode, idem string) error {
		var planID string
		if err := a.DB.QueryRow(ctx, `SELECT id FROM subscription_plans WHERE code=$1`, planCode).Scan(&planID); err != nil {
			return err
		}
		if live, err := a.Subs.Live(ctx, a.DB, ids[email], accType, false); err != nil || live != nil {
			return err
		}
		p := &authctx.Principal{UserID: ids[email], AccountType: accType, EmailVerified: true}
		co, err := a.Payments.Checkout(ctx, p, planID, idem)
		if err != nil {
			return err
		}
		_, err = a.Payments.TestComplete(ctx, ids[email], co.Payment.ID, "success")
		return err
	}
	if err := subscribe("seller@demo.petora.test", "seller", "seller_pro", "demo-seed-seller-pro-0001"); err != nil {
		return fmt.Errorf("demo seller subscription: %w", err)
	}
	if err := subscribe("rescue@demo.petora.test", "seller", "seller_pro", "demo-seed-rescue-pro-0001"); err != nil {
		return fmt.Errorf("demo rescue subscription: %w", err)
	}
	var have int
	if err := a.DB.QueryRow(ctx, `SELECT count(*) FROM pet_listings`).Scan(&have); err != nil || have > 0 {
		slog.Info("demo listings already present; skipping")
		return err
	}
	for i, d := range demoListings {
		uid := ids[d.seller+"@demo.petora.test"]
		var catID, breedID string
		if err := a.DB.QueryRow(ctx, `SELECT c.id, b.id FROM categories c JOIN breeds b ON b.category_id=c.id WHERE c.slug=$1 AND b.slug=$2`, d.category, d.breed).Scan(&catID, &breedID); err != nil {
			return fmt.Errorf("demo listing %d category: %w", i, err)
		}
		age, lat, lng := d.age, d.lat, d.lng
		in := listings.Input{Title: d.title, Description: d.desc, CategoryID: catID, BreedID: &breedID, ListingType: d.ltype, PriceMinor: d.price,
			AgeMonths: &age, Gender: d.gender, VaccinationStatus: d.vacc, City: d.city, State: d.state, Lat: &lat, Lng: &lng,
			Attributes: map[string]string{"temperament": "friendly"}}
		if d.ltype == "sale" && d.category == "dogs" {
			in.Dewormed = ptr(true)
		}
		o, err := a.Listings.Create(ctx, a.Subs, uid, in)
		if err != nil {
			return fmt.Errorf("demo listing %q: %w", d.title, err)
		}
		for j := 0; j < 2; j++ {
			if _, err := a.Listings.AddImage(ctx, uid, o.ID, placeholder(d.hue+float64(j*25), j)); err != nil {
				return err
			}
		}
		if _, err := a.Listings.Submit(ctx, a.Subs, uid, o.ID); err != nil {
			return fmt.Errorf("submit demo listing %q: %w", d.title, err)
		}
		if i < len(demoListings)-1 { // leave one listing pending for the moderation demo
			if err := a.DB.InTx(ctx, func(tx pgx.Tx) error { return listings.Approve(ctx, tx, 60, o.ID, nil) }); err != nil {
				return err
			}
		}
	}
	a.Listings.Invalidate(ctx)
	slog.Warn("DEMO DATA LOADED (sample content, test-mode subscriptions only)", "password", DemoPassword,
		"accounts", "buyer@ / seller@ / rescue@ / admin@ / moderator@ / finance@ demo.petora.test")
	return nil
}

func ptr[T any](v T) *T { return &v }

// placeholder renders a neutral tinted card image so demo listings exercise the real image pipeline.
func placeholder(hue float64, variant int) []byte {
	const w, h = 960, 720
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	base := hsl(hue, 0.35, 0.82)
	accent := hsl(hue, 0.30, 0.62)
	cx, cy := float64(w)/2, float64(h)/2+20
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			t := float64(y) / h
			c := mix(base, hsl(hue+20, 0.30, 0.90), t)
			// paw print: one pad + four toes
			dx, dy := float64(x)-cx, float64(y)-cy
			if (dx*dx)/(120*120)+(dy*dy)/(95*95) < 1 {
				c = accent
			}
			for k, off := range [][2]float64{{-130, -150}, {-45, -205}, {45, -205}, {130, -150}} {
				_ = k
				ex, ey := dx-off[0], dy-off[1]
				if ex*ex+ey*ey < 48*48 {
					c = accent
				}
			}
			if variant == 1 && math.Mod(float64(x+y), 80) < 2 {
				c = mix(c, accent, 0.3)
			}
			img.Set(x, y, c)
		}
	}
	var buf bytes.Buffer
	_ = png.Encode(&buf, img)
	return buf.Bytes()
}

func mix(a, b color.RGBA, t float64) color.RGBA {
	l := func(x, y uint8) uint8 { return uint8(float64(x)*(1-t) + float64(y)*t) }
	return color.RGBA{l(a.R, b.R), l(a.G, b.G), l(a.B, b.B), 255}
}

func hsl(h, s, l float64) color.RGBA {
	h = math.Mod(h, 360) / 360
	q := l * (1 + s)
	if l >= 0.5 {
		q = l + s - l*s
	}
	p := 2*l - q
	conv := func(t float64) uint8 {
		if t < 0 {
			t++
		}
		if t > 1 {
			t--
		}
		var v float64
		switch {
		case t < 1.0/6:
			v = p + (q-p)*6*t
		case t < 0.5:
			v = q
		case t < 2.0/3:
			v = p + (q-p)*(2.0/3-t)*6
		default:
			v = p
		}
		return uint8(math.Round(v * 255))
	}
	return color.RGBA{conv(h + 1.0/3), conv(h), conv(h - 1.0/3), 255}
}
