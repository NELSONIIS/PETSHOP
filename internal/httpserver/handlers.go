package httpserver

import (
	"encoding/json"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"petora/internal/audit"
	"petora/internal/authctx"
	"petora/internal/catalog"
	"petora/internal/database"
	"petora/internal/enquiries"
	"petora/internal/httpx"
	"petora/internal/listings"
	"petora/internal/media"
	"petora/internal/middleware"
	"petora/internal/notifications"
	"petora/internal/sellers"
	"petora/internal/subscriptions"
)

type handlers struct {
	*App
}

func viewerID(r *http.Request) string {
	if p := authctx.From(r.Context()); p != nil {
		return p.UserID
	}
	return ""
}

func id(r *http.Request) string { return chi.URLParam(r, "id") }

func respond(w http.ResponseWriter, r *http.Request, v any, err error) {
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.OK(w, v)
}

func noContent(w http.ResponseWriter, r *http.Request, err error) {
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.NoContent(w)
}

// ---------- public catalog / listings / sellers ----------

func (h handlers) categories(w http.ResponseWriter, r *http.Request) {
	out, err := h.Catalog.List(r.Context(), false)
	respond(w, r, out, err)
}

func (h handlers) category(w http.ResponseWriter, r *http.Request) {
	out, err := h.Catalog.GetBySlug(r.Context(), chi.URLParam(r, "slug"))
	respond(w, r, out, err)
}

func (h handlers) searchPets(w http.ResponseWriter, r *http.Request) {
	pg := httpx.Pagination(r, 20, 50)
	p, err := listings.ParseSearch(r.URL.Query(), pg)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	out, total, err := h.Listings.Search(r.Context(), p, viewerID(r))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Paged(w, out, pg.Meta(total))
}

func (h handlers) pet(w http.ResponseWriter, r *http.Request) {
	out, err := h.Listings.PublicDetail(r.Context(), id(r), authctx.From(r.Context()))
	respond(w, r, out, err)
}

func (h handlers) similar(w http.ResponseWriter, r *http.Request) {
	out, err := h.Listings.Similar(r.Context(), id(r), viewerID(r))
	respond(w, r, out, err)
}

func (h handlers) view(w http.ResponseWriter, r *http.Request) {
	noContent(w, r, h.Listings.RecordView(r.Context(), id(r), viewerID(r), middleware.ClientIP(r), r.UserAgent()))
}

func (h handlers) sellersList(w http.ResponseWriter, r *http.Request) {
	pg := httpx.Pagination(r, 20, 50)
	out, total, err := h.Sellers.ListVerified(r.Context(), r.URL.Query().Get("city"), pg)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Paged(w, out, pg.Meta(total))
}

func (h handlers) seller(w http.ResponseWriter, r *http.Request) {
	out, err := h.Sellers.GetPublic(r.Context(), chi.URLParam(r, "slug"))
	respond(w, r, out, err)
}

func (h handlers) sellerPets(w http.ResponseWriter, r *http.Request) {
	pg := httpx.Pagination(r, 20, 50)
	p, err := listings.ParseSearch(r.URL.Query(), pg)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	p.SellerSlug = chi.URLParam(r, "slug")
	out, total, err := h.Listings.Search(r.Context(), p, viewerID(r))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Paged(w, out, pg.Meta(total))
}

// ---------- site: config, content, legal, support ----------

func (h handlers) config(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	pub, err := h.Settings.List(ctx, true)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	m := map[string]json.RawMessage{}
	for _, s := range pub {
		m[s.Key] = s.Value
	}
	out := map[string]any{
		"brand_name":             h.Settings.String(ctx, "brand.name", "PETORA"),
		"currency":               h.Settings.String(ctx, "platform.currency", h.Config.DefaultCurrency),
		"maintenance":            h.Settings.Bool(ctx, "maintenance.enabled", false),
		"payment_provider":       h.Payments.Provider().Name(),
		"max_images_per_listing": h.Settings.Int(ctx, "listings.max_images", 8),
		"max_image_mb":           h.Settings.Int(ctx, "uploads.max_image_mb", 8),
		"environment":            h.Config.Env,
		"settings":               m,
	}
	if h.Payments.Provider().Name() == "razorpay" {
		out["razorpay_key_id"] = h.Payments.Provider().PublicKey()
	}
	httpx.OK(w, out)
}

func (h handlers) content(w http.ResponseWriter, r *http.Request) {
	key := chi.URLParam(r, "key")
	if key != "home" && key != "faq" {
		httpx.Fail(w, r, httpx.NotFound("Content"))
		return
	}
	var data json.RawMessage
	err := h.DB.QueryRow(r.Context(), `SELECT data FROM content_blocks WHERE key=$1`, key).Scan(&data)
	if database.IsNoRows(err) {
		data, err = json.RawMessage(`{}`), nil
	}
	respond(w, r, data, err)
}

func (h handlers) legal(w http.ResponseWriter, r *http.Request) {
	var out struct {
		Slug        string    `json:"slug"`
		Title       string    `json:"title"`
		Version     int       `json:"version"`
		BodyMD      string    `json:"body_md"`
		PublishedAt time.Time `json:"published_at"`
	}
	err := h.DB.QueryRow(r.Context(), `SELECT slug, title, version, body_md, published_at FROM legal_policy_versions WHERE slug=$1 AND is_current`,
		chi.URLParam(r, "slug")).Scan(&out.Slug, &out.Title, &out.Version, &out.BodyMD, &out.PublishedAt)
	if database.IsNoRows(err) {
		err = httpx.NotFound("Page")
	}
	respond(w, r, out, err)
}

func (h handlers) supportContact(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Name    string `json:"name"`
		Email   string `json:"email"`
		Subject string `json:"subject"`
		Message string `json:"message"`
	}
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	var v httpx.V
	v.Length("name", in.Name, 2, 120)
	v.Email("email", strings.TrimSpace(in.Email))
	v.Length("message", in.Message, 10, 4000)
	if len(in.Subject) > 140 {
		v.Add("subject", "is too long")
	}
	if err := v.Err(); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	to := h.Settings.String(r.Context(), "support.email", "support@petora.in")
	body := "From: " + in.Name + " <" + strings.TrimSpace(in.Email) + ">\nSubject: " + in.Subject + "\n\n" + in.Message
	err := h.DB.InTx(r.Context(), func(tx pgxTx) error {
		if err := notifications.EnqueueEmail(r.Context(), tx, to, "support_contact", map[string]string{"body": body, "subject": in.Subject}); err != nil {
			return err
		}
		return audit.Log(r.Context(), tx, audit.Entry{Action: "support.contact", EntityType: "support", Metadata: map[string]any{"email": in.Email, "subject": in.Subject}, IP: middleware.ClientIP(r)})
	})
	noContent(w, r, err)
}

// ---------- notifications ----------

type notification struct {
	ID        string          `json:"id"`
	Kind      string          `json:"kind"`
	Title     string          `json:"title"`
	Body      string          `json:"body"`
	Data      json.RawMessage `json:"data"`
	Read      bool            `json:"read"`
	CreatedAt time.Time       `json:"created_at"`
}

func (h handlers) notifications(w http.ResponseWriter, r *http.Request) {
	uid := viewerID(r)
	pg := httpx.Pagination(r, 20, 50)
	unread := r.URL.Query().Get("unread") == "true"
	var total int
	if err := h.DB.QueryRow(r.Context(), `SELECT count(*) FROM notifications WHERE user_id=$1 AND (NOT $2 OR read_at IS NULL)`, uid, unread).Scan(&total); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	rows, err := h.DB.Query(r.Context(), `SELECT id, kind, title, body, data, read_at IS NOT NULL, created_at FROM notifications
		WHERE user_id=$1 AND (NOT $2 OR read_at IS NULL) ORDER BY created_at DESC LIMIT $3 OFFSET $4`, uid, unread, pg.PerPage, pg.Offset)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	defer rows.Close()
	out := []notification{}
	for rows.Next() {
		var n notification
		if err := rows.Scan(&n.ID, &n.Kind, &n.Title, &n.Body, &n.Data, &n.Read, &n.CreatedAt); err != nil {
			httpx.Fail(w, r, err)
			return
		}
		out = append(out, n)
	}
	httpx.Paged(w, out, pg.Meta(total))
}

func (h handlers) unreadCount(w http.ResponseWriter, r *http.Request) {
	var n int
	err := h.DB.QueryRow(r.Context(), `SELECT count(*) FROM notifications WHERE user_id=$1 AND read_at IS NULL`, viewerID(r)).Scan(&n)
	respond(w, r, map[string]int{"count": n}, err)
}

func (h handlers) markRead(w http.ResponseWriter, r *http.Request) {
	_, err := h.DB.Exec(r.Context(), `UPDATE notifications SET read_at=now() WHERE id::text=$1 AND user_id=$2 AND read_at IS NULL`, id(r), viewerID(r))
	noContent(w, r, err)
}

func (h handlers) markAllRead(w http.ResponseWriter, r *http.Request) {
	_, err := h.DB.Exec(r.Context(), `UPDATE notifications SET read_at=now() WHERE user_id=$1 AND read_at IS NULL`, viewerID(r))
	noContent(w, r, err)
}

// ---------- favourites / buyer ----------

func (h handlers) favourites(w http.ResponseWriter, r *http.Request) {
	pg := httpx.Pagination(r, 20, 50)
	out, total, err := h.Listings.Favourites(r.Context(), viewerID(r), pg)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Paged(w, out, pg.Meta(total))
}

func (h handlers) addFavourite(w http.ResponseWriter, r *http.Request) {
	var in struct {
		ListingID string `json:"listing_id"`
	}
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	noContent(w, r, h.Listings.AddFavourite(r.Context(), viewerID(r), in.ListingID))
}

func (h handlers) removeFavourite(w http.ResponseWriter, r *http.Request) {
	noContent(w, r, h.Listings.RemoveFavourite(r.Context(), viewerID(r), chi.URLParam(r, "listingId")))
}

func (h handlers) recentlyViewed(w http.ResponseWriter, r *http.Request) {
	out, err := h.Listings.RecentlyViewed(r.Context(), viewerID(r))
	respond(w, r, out, err)
}

type buyerProfile struct {
	City        string   `json:"city"`
	State       string   `json:"state"`
	Lat         *float64 `json:"lat"`
	Lng         *float64 `json:"lng"`
	RadiusKm    int      `json:"radius_km"`
	NotifyEmail bool     `json:"notify_email"`
	NotifySMS   bool     `json:"notify_sms"`
	NotifyPush  bool     `json:"notify_push"`
}

func (h handlers) loadBuyerProfile(r *http.Request) (*buyerProfile, error) {
	var b buyerProfile
	_, err := h.DB.Exec(r.Context(), `INSERT INTO buyer_profiles (user_id) VALUES ($1) ON CONFLICT DO NOTHING`, viewerID(r))
	if err != nil {
		return nil, err
	}
	err = h.DB.QueryRow(r.Context(), `SELECT city, state, lat, lng, radius_km, notify_email, notify_sms, notify_push FROM buyer_profiles WHERE user_id=$1`, viewerID(r)).
		Scan(&b.City, &b.State, &b.Lat, &b.Lng, &b.RadiusKm, &b.NotifyEmail, &b.NotifySMS, &b.NotifyPush)
	return &b, err
}

func (h handlers) buyerProfile(w http.ResponseWriter, r *http.Request) {
	out, err := h.loadBuyerProfile(r)
	respond(w, r, out, err)
}

func (h handlers) putBuyerProfile(w http.ResponseWriter, r *http.Request) {
	var in buyerProfile
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	var v httpx.V
	if in.RadiusKm == 0 {
		in.RadiusKm = 50
	}
	v.Range("radius_km", int64(in.RadiusKm), 1, 1000)
	if in.Lat != nil && (*in.Lat < -90 || *in.Lat > 90) {
		v.Add("lat", "is out of range")
	}
	if in.Lng != nil && (*in.Lng < -180 || *in.Lng > 180) {
		v.Add("lng", "is out of range")
	}
	if len(in.City) > 80 || len(in.State) > 80 {
		v.Add("city", "is too long")
	}
	if err := v.Err(); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	if _, err := h.DB.Exec(r.Context(), `INSERT INTO buyer_profiles (user_id, city, state, lat, lng, radius_km, notify_email, notify_sms, notify_push)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) ON CONFLICT (user_id) DO UPDATE SET city=EXCLUDED.city, state=EXCLUDED.state, lat=EXCLUDED.lat, lng=EXCLUDED.lng,
		radius_km=EXCLUDED.radius_km, notify_email=EXCLUDED.notify_email, notify_sms=EXCLUDED.notify_sms, notify_push=EXCLUDED.notify_push, updated_at=now()`,
		viewerID(r), strings.TrimSpace(in.City), strings.TrimSpace(in.State), in.Lat, in.Lng, in.RadiusKm, in.NotifyEmail, in.NotifySMS, in.NotifyPush); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	h.buyerProfile(w, r)
}

func (h handlers) buyerDashboard(w http.ResponseWriter, r *http.Request) {
	out, err := h.Enquiries.BuyerDashboard(r.Context(), authctx.From(r.Context()))
	respond(w, r, out, err)
}

func (h handlers) contactUnlock(w http.ResponseWriter, r *http.Request) {
	out, err := h.Enquiries.Unlock(r.Context(), authctx.From(r.Context()), id(r))
	respond(w, r, out, err)
}

func (h handlers) createEnquiry(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Message string `json:"message"`
		Body    string `json:"body"`
	}
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	msg := in.Message
	if msg == "" {
		msg = in.Body
	}
	out, err := h.Enquiries.Create(r.Context(), authctx.From(r.Context()), id(r), msg)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Created(w, out)
}

func (h handlers) listEnquiries(side string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		pg := httpx.Pagination(r, 20, 50)
		out, total, err := h.Enquiries.List(r.Context(), authctx.From(r.Context()), side, r.URL.Query().Get("status"), r.URL.Query().Get("unread") == "true", pg)
		if err != nil {
			httpx.Fail(w, r, err)
			return
		}
		httpx.Paged(w, out, pg.Meta(total))
	}
}

func (h handlers) getEnquiry(side string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		out, err := h.Enquiries.Get(r.Context(), authctx.From(r.Context()), id(r), side)
		respond(w, r, out, err)
	}
}

func (h handlers) replyEnquiry(side string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			Body    string `json:"body"`
			Message string `json:"message"`
		}
		if err := httpx.Decode(w, r, &in); err != nil {
			httpx.Fail(w, r, err)
			return
		}
		b := in.Body
		if b == "" {
			b = in.Message
		}
		out, err := h.Enquiries.Reply(r.Context(), authctx.From(r.Context()), id(r), side, b)
		if err != nil {
			httpx.Fail(w, r, err)
			return
		}
		httpx.Created(w, out)
	}
}

func (h handlers) closeEnquiry(side string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		noContent(w, r, h.Enquiries.Close(r.Context(), authctx.From(r.Context()), id(r), side))
	}
}

func (h handlers) report(w http.ResponseWriter, r *http.Request) {
	var in enquiries.ReportInput
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	rid, err := h.Enquiries.Report(r.Context(), authctx.From(r.Context()), in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Created(w, map[string]string{"id": rid})
}

func (h handlers) blocks(w http.ResponseWriter, r *http.Request) {
	out, err := h.Enquiries.Blocks(r.Context(), authctx.From(r.Context()))
	respond(w, r, out, err)
}

func (h handlers) block(w http.ResponseWriter, r *http.Request) {
	var in struct {
		UserID string `json:"user_id"`
	}
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	noContent(w, r, h.Enquiries.Block(r.Context(), authctx.From(r.Context()), in.UserID))
}

func (h handlers) unblock(w http.ResponseWriter, r *http.Request) {
	noContent(w, r, h.Enquiries.Unblock(r.Context(), authctx.From(r.Context()), chi.URLParam(r, "userId")))
}

func (h handlers) disputes(w http.ResponseWriter, r *http.Request) {
	out, err := h.Enquiries.MyDisputes(r.Context(), authctx.From(r.Context()))
	respond(w, r, out, err)
}

func (h handlers) openDispute(w http.ResponseWriter, r *http.Request) {
	var in enquiries.DisputeInput
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	out, err := h.Enquiries.OpenDispute(r.Context(), authctx.From(r.Context()), in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Created(w, out)
}

// ---------- seller ----------

func (h handlers) sellerDashboard(w http.ResponseWriter, r *http.Request) {
	out, err := h.Enquiries.SellerDashboard(r.Context(), authctx.From(r.Context()))
	respond(w, r, out, err)
}

func (h handlers) sellerProfile(w http.ResponseWriter, r *http.Request) {
	out, err := h.Sellers.GetOwner(r.Context(), viewerID(r))
	respond(w, r, out, err)
}

func (h handlers) putSellerProfile(w http.ResponseWriter, r *http.Request) {
	var in sellers.ProfileInput
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	out, err := h.Sellers.UpdateOwner(r.Context(), viewerID(r), in)
	if err == nil {
		h.Listings.Invalidate(r.Context())
	}
	respond(w, r, out, err)
}

// readFile parses a multipart upload with a hard size cap; oversized requests are rejected before buffering.
func readFile(w http.ResponseWriter, r *http.Request, limit int64) ([]byte, string, error) {
	r.Body = http.MaxBytesReader(w, r.Body, limit+64<<10)
	if err := r.ParseMultipartForm(limit + 64<<10); err != nil {
		return nil, "", httpx.Err(413, httpx.CodeBadRequest, "Upload too large or malformed (max "+strconv.FormatInt(limit>>20, 10)+" MB)")
	}
	f, hdr, err := r.FormFile("file")
	if err != nil {
		return nil, "", httpx.Invalid(httpx.FieldError{Field: "file", Message: "is required"})
	}
	defer f.Close()
	b, err := media.ReadUpload(f, limit)
	if err == media.ErrTooLarge {
		return nil, "", httpx.Err(413, httpx.CodeBadRequest, "File is too large (max "+strconv.FormatInt(limit>>20, 10)+" MB)")
	}
	if err != nil {
		return nil, "", httpx.Invalid(httpx.FieldError{Field: "file", Message: "could not be read"})
	}
	return b, hdr.Filename, nil
}

func (h handlers) sellerLogo(w http.ResponseWriter, r *http.Request) {
	b, _, err := readFile(w, r, 5<<20)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	out, err := h.Sellers.SetLogo(r.Context(), viewerID(r), b)
	respond(w, r, out, err)
}

func (h handlers) verification(w http.ResponseWriter, r *http.Request) {
	out, err := h.Sellers.Verification(r.Context(), viewerID(r))
	respond(w, r, out, err)
}

func (h handlers) submitVerification(w http.ResponseWriter, r *http.Request) {
	var in struct {
		JurisdictionState string `json:"jurisdiction_state"`
	}
	if r.ContentLength != 0 {
		if err := httpx.Decode(w, r, &in); err != nil {
			httpx.Fail(w, r, err)
			return
		}
	}
	out, err := h.Sellers.Submit(r.Context(), viewerID(r), in.JurisdictionState)
	respond(w, r, out, err)
}

func (h handlers) documents(w http.ResponseWriter, r *http.Request) {
	out, err := h.Sellers.ListDocuments(r.Context(), viewerID(r))
	respond(w, r, out, err)
}

func (h handlers) uploadDocument(w http.ResponseWriter, r *http.Request) {
	limit := int64(h.Settings.Int(r.Context(), "uploads.max_doc_mb", 10)) << 20
	b, name, err := readFile(w, r, limit)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	out, err := h.Sellers.UploadDocument(r.Context(), viewerID(r), r.FormValue("kind"), name, b)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Created(w, out)
}

func (h handlers) deleteDocument(w http.ResponseWriter, r *http.Request) {
	noContent(w, r, h.Sellers.DeleteDocument(r.Context(), viewerID(r), id(r)))
}

func (h handlers) sellerListings(w http.ResponseWriter, r *http.Request) {
	pg := httpx.Pagination(r, 20, 50)
	out, total, err := h.Listings.OwnerList(r.Context(), viewerID(r), r.URL.Query().Get("status"), "", pg, false)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Paged(w, out, pg.Meta(total))
}

func (h handlers) createListing(w http.ResponseWriter, r *http.Request) {
	var in listings.Input
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	out, err := h.Listings.Create(r.Context(), h.Subs, viewerID(r), in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Created(w, out)
}

func (h handlers) sellerListing(w http.ResponseWriter, r *http.Request) {
	out, err := h.Listings.OwnerView(r.Context(), viewerID(r), id(r), false)
	respond(w, r, out, err)
}

func (h handlers) updateListing(w http.ResponseWriter, r *http.Request) {
	var in listings.Input
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	out, err := h.Listings.Update(r.Context(), viewerID(r), id(r), in)
	respond(w, r, out, err)
}

func (h handlers) archiveListing(w http.ResponseWriter, r *http.Request) {
	noContent(w, r, h.Listings.Archive(r.Context(), viewerID(r), id(r)))
}

func (h handlers) submitListing(w http.ResponseWriter, r *http.Request) {
	out, err := h.Listings.Submit(r.Context(), h.Subs, viewerID(r), id(r))
	respond(w, r, out, err)
}

func (h handlers) availability(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Availability string `json:"availability"`
	}
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	out, err := h.Listings.SetAvailability(r.Context(), viewerID(r), id(r), in.Availability)
	respond(w, r, out, err)
}

func (h handlers) uploadImage(w http.ResponseWriter, r *http.Request) {
	limit := int64(h.Settings.Int(r.Context(), "uploads.max_image_mb", 8)) << 20
	b, _, err := readFile(w, r, limit)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	out, err := h.Listings.AddImage(r.Context(), viewerID(r), id(r), b)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Created(w, out)
}

func (h handlers) reorderImages(w http.ResponseWriter, r *http.Request) {
	var in struct {
		ImageIDs []string `json:"image_ids"`
	}
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	noContent(w, r, h.Listings.Reorder(r.Context(), viewerID(r), id(r), in.ImageIDs))
}

func (h handlers) setCover(w http.ResponseWriter, r *http.Request) {
	noContent(w, r, h.Listings.SetCover(r.Context(), viewerID(r), id(r), chi.URLParam(r, "imageId")))
}

func (h handlers) deleteImage(w http.ResponseWriter, r *http.Request) {
	noContent(w, r, h.Listings.DeleteImage(r.Context(), viewerID(r), id(r), chi.URLParam(r, "imageId")))
}

func (h handlers) listingAnalytics(w http.ResponseWriter, r *http.Request) {
	sub, err := h.Subs.Live(r.Context(), h.DB, viewerID(r), "seller", false)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	if sub == nil || !sub.Flag("analytics") {
		httpx.Fail(w, r, httpx.Err(402, httpx.CodeSubscriptionRequired, "Listing analytics are included in plans with analytics. Upgrade to view them."))
		return
	}
	days, _ := strconv.Atoi(r.URL.Query().Get("days"))
	out, err := h.Listings.ListingAnalytics(r.Context(), viewerID(r), id(r), days)
	respond(w, r, out, err)
}

// ---------- admin adapters for catalog / plans / verification ----------

func (h handlers) adminCategories(w http.ResponseWriter, r *http.Request) {
	out, err := h.Catalog.List(r.Context(), true)
	respond(w, r, out, err)
}

func (h handlers) adminCreateCategory(w http.ResponseWriter, r *http.Request) {
	var in catalog.CategoryInput
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	cid, err := h.Catalog.CreateCategory(r.Context(), in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Created(w, map[string]string{"id": cid})
}

func (h handlers) adminUpdateCategory(w http.ResponseWriter, r *http.Request) {
	var in catalog.CategoryInput
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	respond(w, r, map[string]string{"id": id(r)}, h.Catalog.UpdateCategory(r.Context(), id(r), in))
}

func (h handlers) adminCreateBreed(w http.ResponseWriter, r *http.Request) {
	var in catalog.BreedInput
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	bid, err := h.Catalog.CreateBreed(r.Context(), id(r), in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Created(w, map[string]string{"id": bid})
}

func (h handlers) adminUpdateBreed(w http.ResponseWriter, r *http.Request) {
	var in catalog.BreedInput
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	respond(w, r, map[string]string{"id": id(r)}, h.Catalog.UpdateBreed(r.Context(), id(r), in))
}

func (h handlers) adminPlans(w http.ResponseWriter, r *http.Request) {
	out, err := h.Subs.ListPlans(r.Context(), r.URL.Query().Get("audience"), false)
	respond(w, r, out, err)
}

func (h handlers) adminCreatePlan(w http.ResponseWriter, r *http.Request) {
	var in subscriptions.PlanInput
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	out, err := h.Subs.CreatePlan(r.Context(), in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Created(w, out)
}

func (h handlers) adminUpdatePlan(w http.ResponseWriter, r *http.Request) {
	var in subscriptions.PlanInput
	if err := httpx.Decode(w, r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	out, err := h.Subs.UpdatePlan(r.Context(), id(r), in)
	respond(w, r, out, err)
}

func (h handlers) adminVerifications(w http.ResponseWriter, r *http.Request) {
	pg := httpx.Pagination(r, 20, 100)
	status := r.URL.Query().Get("status")
	if status == "all" {
		status = ""
	}
	out, total, err := h.Sellers.AdminList(r.Context(), status, pg)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.Paged(w, out, pg.Meta(total))
}

func (h handlers) adminVerification(w http.ResponseWriter, r *http.Request) {
	out, err := h.Sellers.AdminGet(r.Context(), id(r))
	respond(w, r, out, err)
}

func (h handlers) adminDecide(approve bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			Notes  string `json:"notes"`
			Reason string `json:"reason"`
		}
		if r.ContentLength != 0 {
			if err := httpx.Decode(w, r, &in); err != nil {
				httpx.Fail(w, r, err)
				return
			}
		}
		text := in.Reason
		if approve {
			text = in.Notes
		}
		err := h.Sellers.Decide(r.Context(), id(r), approve, strings.TrimSpace(text))
		if err == nil {
			h.Listings.Invalidate(r.Context())
		}
		noContent(w, r, err)
	}
}

func (h handlers) adminDocument(w http.ResponseWriter, r *http.Request) {
	rc, d, err := h.Sellers.OpenDocument(r.Context(), id(r))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	defer rc.Close()
	w.Header().Set("Content-Type", d.MimeType)
	w.Header().Set("Content-Disposition", `attachment; filename="`+d.OriginalName+`"`)
	w.Header().Set("Cache-Control", "no-store, private")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Content-Security-Policy", "default-src 'none'; sandbox")
	_, _ = io.Copy(w, rc)
}
