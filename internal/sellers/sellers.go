// Package sellers owns seller profiles, verification and private verification documents.
package sellers

import (
	"context"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"petora/internal/audit"
	"petora/internal/database"
	"petora/internal/httpx"
	"petora/internal/media"
	"petora/internal/notifications"
	"petora/internal/settings"
	"petora/internal/storage"
)

type Service struct {
	db       *database.DB
	store    storage.Store
	settings *settings.Service
}

func New(db *database.DB, store storage.Store, st *settings.Service) *Service {
	return &Service{db: db, store: store, settings: st}
}

type Badge struct {
	ID          string  `json:"id"`
	Slug        string  `json:"slug"`
	DisplayName string  `json:"display_name"`
	SellerType  string  `json:"seller_type"`
	Verified    bool    `json:"verified"`
	City        string  `json:"city"`
	State       string  `json:"state"`
	LogoURL     *string `json:"logo_url"`
}

type Public struct {
	Badge
	Bio            string     `json:"bio"`
	MemberSince    time.Time  `json:"member_since"`
	ActiveListings int        `json:"active_listings"`
	VerifiedAt     *time.Time `json:"verified_at"`
}

// Owner includes private contact details — only ever returned to the seller themselves.
type Owner struct {
	Public
	BusinessName       *string  `json:"business_name"`
	GSTNumber          *string  `json:"gst_number"`
	ContactPhone       *string  `json:"contact_phone"`
	ContactWhatsApp    *string  `json:"contact_whatsapp"`
	ContactEmail       *string  `json:"contact_email"`
	VerificationStatus string   `json:"verification_status"`
	Lat                *float64 `json:"lat"`
	Lng                *float64 `json:"lng"`
}

func (s *Service) logoURL(key *string) *string {
	if key == nil || *key == "" {
		return nil
	}
	u := s.store.PublicURL(*key)
	return &u
}

const publicSelect = `SELECT sp.id, sp.slug, sp.display_name, sp.seller_type, sp.verification_status='approved', sp.city, sp.state, sp.logo_url,
	sp.bio, sp.created_at, sp.verified_at,
	(SELECT count(*) FROM pet_listings l WHERE l.seller_id=sp.id AND l.status='approved' AND l.deleted_at IS NULL AND l.availability IN ('available','reserved'))
	FROM seller_profiles sp JOIN users u ON u.id=sp.user_id AND u.status='active'`

func (s *Service) scanPublic(row pgx.Row) (*Public, error) {
	var p Public
	var logo *string
	if err := row.Scan(&p.ID, &p.Slug, &p.DisplayName, &p.SellerType, &p.Verified, &p.City, &p.State, &logo, &p.Bio, &p.MemberSince, &p.VerifiedAt, &p.ActiveListings); err != nil {
		return nil, err
	}
	p.LogoURL = s.logoURL(logo)
	return &p, nil
}

func (s *Service) GetPublic(ctx context.Context, slug string) (*Public, error) {
	p, err := s.scanPublic(s.db.QueryRow(ctx, publicSelect+` WHERE sp.slug=$1 AND sp.verification_status <> 'suspended'`, slug))
	if database.IsNoRows(err) {
		return nil, httpx.NotFound("Seller")
	}
	return p, err
}

func (s *Service) ListVerified(ctx context.Context, city string, pg httpx.Page) ([]Public, int, error) {
	var total int
	if err := s.db.QueryRow(ctx, `SELECT count(*) FROM seller_profiles sp JOIN users u ON u.id=sp.user_id AND u.status='active'
		WHERE sp.verification_status='approved' AND ($1='' OR lower(sp.city)=lower($1))`, city).Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := s.db.Query(ctx, publicSelect+` WHERE sp.verification_status='approved' AND ($1='' OR lower(sp.city)=lower($1))
		ORDER BY 11 DESC, sp.verified_at DESC NULLS LAST LIMIT $2 OFFSET $3`, city, pg.PerPage, pg.Offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := []Public{}
	for rows.Next() {
		p, err := s.scanPublic(rows)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, *p)
	}
	return out, total, rows.Err()
}

// ProfileIDForUser returns the seller profile id, or "" if the user has none.
func (s *Service) ProfileIDForUser(ctx context.Context, q database.Querier, userID string) (string, error) {
	var id string
	err := q.QueryRow(ctx, `SELECT id FROM seller_profiles WHERE user_id=$1`, userID).Scan(&id)
	if database.IsNoRows(err) {
		return "", nil
	}
	return id, err
}

func (s *Service) GetOwner(ctx context.Context, userID string) (*Owner, error) {
	var o Owner
	var logo *string
	err := s.db.QueryRow(ctx, `SELECT sp.id, sp.slug, sp.display_name, sp.seller_type, sp.verification_status='approved', sp.city, sp.state, sp.logo_url,
		sp.bio, sp.created_at, sp.verified_at, 0, sp.business_name, sp.gst_number, sp.contact_phone, sp.contact_whatsapp, sp.contact_email,
		sp.verification_status, sp.lat, sp.lng,
		(SELECT count(*) FROM pet_listings l WHERE l.seller_id=sp.id AND l.status='approved' AND l.deleted_at IS NULL AND l.availability IN ('available','reserved'))
		FROM seller_profiles sp WHERE sp.user_id=$1`, userID).
		Scan(&o.ID, &o.Slug, &o.DisplayName, &o.SellerType, &o.Verified, &o.City, &o.State, &logo, &o.Bio, &o.MemberSince, &o.VerifiedAt, &o.ActiveListings,
			&o.BusinessName, &o.GSTNumber, &o.ContactPhone, &o.ContactWhatsApp, &o.ContactEmail, &o.VerificationStatus, &o.Lat, &o.Lng, &o.ActiveListings)
	if database.IsNoRows(err) {
		return nil, httpx.NotFound("Seller profile")
	}
	o.LogoURL = s.logoURL(logo)
	return &o, err
}

type ProfileInput struct {
	DisplayName     *string  `json:"display_name"`
	SellerType      *string  `json:"seller_type"`
	BusinessName    *string  `json:"business_name"`
	GSTNumber       *string  `json:"gst_number"`
	Bio             *string  `json:"bio"`
	City            *string  `json:"city"`
	State           *string  `json:"state"`
	Address         *string  `json:"address,omitempty"`
	Lat             *float64 `json:"lat"`
	Lng             *float64 `json:"lng"`
	ContactPhone    *string  `json:"contact_phone"`
	ContactWhatsApp *string  `json:"contact_whatsapp"`
	ContactEmail    *string  `json:"contact_email"`
}

func trim(p *string) {
	if p != nil {
		*p = strings.TrimSpace(*p)
	}
}

func (s *Service) UpdateOwner(ctx context.Context, userID string, in ProfileInput) (*Owner, error) {
	for _, p := range []*string{in.DisplayName, in.SellerType, in.BusinessName, in.GSTNumber, in.Bio, in.City, in.State, in.ContactPhone, in.ContactWhatsApp, in.ContactEmail} {
		trim(p)
	}
	var v httpx.V
	if in.DisplayName != nil {
		v.Length("display_name", *in.DisplayName, 2, 80)
	}
	if in.SellerType != nil {
		v.OneOf("seller_type", *in.SellerType, "individual", "business")
	}
	if in.Bio != nil && len(*in.Bio) > 1000 {
		v.Add("bio", "must be at most 1000 characters")
	}
	if in.ContactPhone != nil && *in.ContactPhone != "" {
		v.Phone("contact_phone", strings.ReplaceAll(*in.ContactPhone, " ", ""))
	}
	if in.ContactWhatsApp != nil && *in.ContactWhatsApp != "" {
		v.Phone("contact_whatsapp", strings.ReplaceAll(*in.ContactWhatsApp, " ", ""))
	}
	if in.ContactEmail != nil && *in.ContactEmail != "" {
		v.Email("contact_email", *in.ContactEmail)
	}
	if in.Lat != nil && (*in.Lat < -90 || *in.Lat > 90) {
		v.Add("lat", "is out of range")
	}
	if in.Lng != nil && (*in.Lng < -180 || *in.Lng > 180) {
		v.Add("lng", "is out of range")
	}
	if err := v.Err(); err != nil {
		return nil, err
	}
	_, err := s.db.Exec(ctx, `UPDATE seller_profiles SET
		display_name=COALESCE($2,display_name), seller_type=COALESCE($3,seller_type), business_name=COALESCE($4,business_name),
		gst_number=COALESCE($5,gst_number), bio=COALESCE($6,bio), city=COALESCE($7,city), state=COALESCE($8,state),
		lat=COALESCE($9,lat), lng=COALESCE($10,lng), contact_phone=COALESCE($11,contact_phone),
		contact_whatsapp=COALESCE($12,contact_whatsapp), contact_email=COALESCE($13,contact_email), updated_at=now()
		WHERE user_id=$1`, userID, in.DisplayName, in.SellerType, in.BusinessName, in.GSTNumber, in.Bio, in.City, in.State, in.Lat, in.Lng,
		in.ContactPhone, in.ContactWhatsApp, in.ContactEmail)
	if err != nil {
		return nil, err
	}
	return s.GetOwner(ctx, userID)
}

func (s *Service) SetLogo(ctx context.Context, userID string, data []byte) (*Owner, error) {
	jpg, err := media.Square(data, 256)
	if err != nil {
		return nil, uploadErr(err)
	}
	o, err := s.GetOwner(ctx, userID)
	if err != nil {
		return nil, err
	}
	key := fmt.Sprintf("sellers/%s/logo-%s.jpg", o.ID, uuid.NewString()[:8])
	if err := s.store.Put(ctx, storage.Public, key, bytesReader(jpg), int64(len(jpg)), "image/jpeg"); err != nil {
		return nil, err
	}
	if _, err := s.db.Exec(ctx, `UPDATE seller_profiles SET logo_url=$2, updated_at=now() WHERE user_id=$1`, userID, key); err != nil {
		return nil, err
	}
	return s.GetOwner(ctx, userID)
}

func uploadErr(err error) error {
	switch err {
	case media.ErrTooLarge:
		return httpx.Err(413, httpx.CodeBadRequest, "File is too large")
	case media.ErrBadType:
		return httpx.Invalid(httpx.FieldError{Field: "file", Message: "unsupported file type"})
	default:
		msg := err.Error()
		if strings.HasPrefix(msg, "image could not be read: ") {
			msg = strings.TrimPrefix(msg, "image could not be read: ")
		}
		return httpx.Invalid(httpx.FieldError{Field: "file", Message: msg})
	}
}

// ---------- verification ----------

type Document struct {
	ID           string    `json:"id"`
	Kind         string    `json:"kind"`
	OriginalName string    `json:"original_name"`
	MimeType     string    `json:"mime_type"`
	SizeBytes    int64     `json:"size_bytes"`
	UploadedAt   time.Time `json:"uploaded_at"`
}

type VerificationStatus struct {
	Status       string     `json:"status"`
	SubmittedAt  *time.Time `json:"submitted_at"`
	ReviewedAt   *time.Time `json:"reviewed_at"`
	Reason       *string    `json:"reason"`
	Documents    []Document `json:"documents"`
	Requirements []string   `json:"requirements"`
}

func (s *Service) documents(ctx context.Context, sellerID string) ([]Document, error) {
	rows, err := s.db.Query(ctx, `SELECT id, kind, original_name, mime_type, size_bytes, uploaded_at FROM seller_documents
		WHERE seller_id=$1 AND deleted_at IS NULL ORDER BY uploaded_at`, sellerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Document{}
	for rows.Next() {
		var d Document
		if err := rows.Scan(&d.ID, &d.Kind, &d.OriginalName, &d.MimeType, &d.SizeBytes, &d.UploadedAt); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

func (s *Service) requirements(o *Owner, docs []Document) []string {
	var missing []string
	if o.City == "" || o.State == "" {
		missing = append(missing, "Add your city and state in your seller profile")
	}
	if o.ContactPhone == nil || *o.ContactPhone == "" {
		missing = append(missing, "Add a contact phone number")
	}
	has := map[string]bool{}
	for _, d := range docs {
		has[d.Kind] = true
	}
	if !has["identity"] {
		missing = append(missing, "Upload an identity document")
	}
	if o.SellerType == "business" {
		if o.BusinessName == nil || strings.TrimSpace(*o.BusinessName) == "" {
			missing = append(missing, "Add your business name")
		}
		if !has["business_registration"] && !has["trade_licence"] && !has["breeder_registration"] {
			missing = append(missing, "Upload a business registration, trade licence or breeder registration document")
		}
	}
	return missing
}

func (s *Service) Verification(ctx context.Context, userID string) (*VerificationStatus, error) {
	o, err := s.GetOwner(ctx, userID)
	if err != nil {
		return nil, err
	}
	docs, err := s.documents(ctx, o.ID)
	if err != nil {
		return nil, err
	}
	vs := &VerificationStatus{Status: o.VerificationStatus, Documents: docs, Requirements: []string{}}
	err = s.db.QueryRow(ctx, `SELECT submitted_at, reviewed_at, reason FROM seller_verifications WHERE seller_id=$1 ORDER BY submitted_at DESC LIMIT 1`, o.ID).
		Scan(&vs.SubmittedAt, &vs.ReviewedAt, &vs.Reason)
	if err != nil && !database.IsNoRows(err) {
		return nil, err
	}
	if o.VerificationStatus == "unsubmitted" || o.VerificationStatus == "rejected" {
		vs.Requirements = s.requirements(o, docs)
	}
	return vs, nil
}

func (s *Service) Submit(ctx context.Context, userID, jurisdiction string) (*VerificationStatus, error) {
	o, err := s.GetOwner(ctx, userID)
	if err != nil {
		return nil, err
	}
	switch o.VerificationStatus {
	case "pending":
		return nil, httpx.Conflict(httpx.CodeConflict, "Your verification is already under review")
	case "approved":
		return nil, httpx.Conflict(httpx.CodeConflict, "Your account is already verified")
	case "suspended":
		return nil, httpx.Forbidden("Your seller account is suspended. Contact support.")
	}
	docs, err := s.documents(ctx, o.ID)
	if err != nil {
		return nil, err
	}
	if missing := s.requirements(o, docs); len(missing) > 0 {
		details := make([]httpx.FieldError, len(missing))
		for i, m := range missing {
			details[i] = httpx.FieldError{Field: "verification", Message: m}
		}
		return nil, httpx.Invalid(details...)
	}
	if jurisdiction == "" {
		jurisdiction = o.State
	}
	err = s.db.InTx(ctx, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `INSERT INTO seller_verifications (seller_id, jurisdiction_state) VALUES ($1,$2)`, o.ID, jurisdiction); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE seller_profiles SET verification_status='pending', updated_at=now() WHERE id=$1`, o.ID); err != nil {
			return err
		}
		return audit.Log(ctx, tx, audit.Entry{Action: "seller.verification_submitted", EntityType: "seller", EntityID: o.ID})
	})
	if err != nil {
		return nil, err
	}
	return s.Verification(ctx, userID)
}

// UploadDocument stores a verification document in PRIVATE storage. Content type is sniffed, not trusted.
func (s *Service) UploadDocument(ctx context.Context, userID, kind, originalName string, data []byte) (*Document, error) {
	var v httpx.V
	v.OneOf("kind", kind, "identity", "business_registration", "trade_licence", "breeder_registration", "address_proof", "other")
	if err := v.Err(); err != nil {
		return nil, err
	}
	mt := media.SniffType(data)
	switch mt {
	case "application/pdf", "image/jpeg", "image/png":
	default:
		return nil, httpx.Invalid(httpx.FieldError{Field: "file", Message: "only PDF, JPEG or PNG documents are accepted"})
	}
	o, err := s.GetOwner(ctx, userID)
	if err != nil {
		return nil, err
	}
	if o.VerificationStatus == "pending" {
		return nil, httpx.Conflict(httpx.CodeConflict, "Documents cannot be changed while verification is under review")
	}
	var count int
	if err := s.db.QueryRow(ctx, `SELECT count(*) FROM seller_documents WHERE seller_id=$1 AND deleted_at IS NULL`, o.ID).Scan(&count); err != nil {
		return nil, err
	}
	if count >= 10 {
		return nil, httpx.Conflict(httpx.CodeLimitReached, "You can upload at most 10 documents")
	}
	id := uuid.NewString()
	key := fmt.Sprintf("sellers/%s/%s", o.ID, id) // no extension, no user-controlled path parts
	if err := s.store.Put(ctx, storage.Private, key, bytesReader(data), int64(len(data)), mt); err != nil {
		return nil, err
	}
	sum := sha256Hex(data)
	d := Document{ID: id, Kind: kind, OriginalName: media.SafeFilename(originalName), MimeType: mt, SizeBytes: int64(len(data))}
	err = s.db.QueryRow(ctx, `INSERT INTO seller_documents (id, seller_id, kind, storage_key, original_name, mime_type, size_bytes, sha256)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING uploaded_at`, id, o.ID, kind, key, d.OriginalName, mt, d.SizeBytes, sum).Scan(&d.UploadedAt)
	if err != nil {
		_ = s.store.Delete(ctx, storage.Private, key)
		return nil, err
	}
	return &d, nil
}

func (s *Service) DeleteDocument(ctx context.Context, userID, docID string) error {
	var key string
	var status string
	err := s.db.QueryRow(ctx, `SELECT d.storage_key, sp.verification_status FROM seller_documents d JOIN seller_profiles sp ON sp.id=d.seller_id
		WHERE d.id::text=$1 AND sp.user_id=$2 AND d.deleted_at IS NULL`, docID, userID).Scan(&key, &status)
	if database.IsNoRows(err) {
		return httpx.NotFound("Document")
	}
	if err != nil {
		return err
	}
	if status == "pending" {
		return httpx.Conflict(httpx.CodeConflict, "Documents cannot be changed while verification is under review")
	}
	if _, err := s.db.Exec(ctx, `UPDATE seller_documents SET deleted_at=now() WHERE id::text=$1`, docID); err != nil {
		return err
	}
	return s.store.Delete(ctx, storage.Private, key)
}

func (s *Service) ListDocuments(ctx context.Context, userID string) ([]Document, error) {
	o, err := s.GetOwner(ctx, userID)
	if err != nil {
		return nil, err
	}
	return s.documents(ctx, o.ID)
}

// ---------- admin ----------

type AdminVerification struct {
	ID                string     `json:"id"`
	SellerID          string     `json:"seller_id"`
	Seller            *Owner     `json:"seller"`
	UserEmail         string     `json:"user_email"`
	Status            string     `json:"status"`
	JurisdictionState string     `json:"jurisdiction_state"`
	SubmittedAt       time.Time  `json:"submitted_at"`
	ReviewedAt        *time.Time `json:"reviewed_at"`
	Reason            *string    `json:"reason"`
	Documents         []Document `json:"documents"`
}

func (s *Service) adminRow(ctx context.Context, row pgx.Row) (*AdminVerification, error) {
	var a AdminVerification
	var userID string
	if err := row.Scan(&a.ID, &a.SellerID, &userID, &a.UserEmail, &a.Status, &a.JurisdictionState, &a.SubmittedAt, &a.ReviewedAt, &a.Reason); err != nil {
		return nil, err
	}
	o, err := s.GetOwner(ctx, userID)
	if err != nil {
		return nil, err
	}
	a.Seller = o
	if a.Documents, err = s.documents(ctx, a.SellerID); err != nil {
		return nil, err
	}
	return &a, nil
}

const adminVerifSelect = `SELECT v.id, v.seller_id, sp.user_id, u.email, v.status, v.jurisdiction_state, v.submitted_at, v.reviewed_at, v.reason
	FROM seller_verifications v JOIN seller_profiles sp ON sp.id=v.seller_id JOIN users u ON u.id=sp.user_id`

func (s *Service) AdminList(ctx context.Context, status string, pg httpx.Page) ([]AdminVerification, int, error) {
	var total int
	if err := s.db.QueryRow(ctx, `SELECT count(*) FROM seller_verifications WHERE ($1='' OR status=$1)`, status).Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := s.db.Query(ctx, adminVerifSelect+` WHERE ($1='' OR v.status=$1) ORDER BY (v.status='pending') DESC, v.submitted_at DESC LIMIT $2 OFFSET $3`, status, pg.PerPage, pg.Offset)
	if err != nil {
		return nil, 0, err
	}
	type raw struct {
		a      AdminVerification
		userID string
	}
	var raws []raw
	for rows.Next() {
		var r raw
		if err := rows.Scan(&r.a.ID, &r.a.SellerID, &r.userID, &r.a.UserEmail, &r.a.Status, &r.a.JurisdictionState, &r.a.SubmittedAt, &r.a.ReviewedAt, &r.a.Reason); err != nil {
			rows.Close()
			return nil, 0, err
		}
		raws = append(raws, r)
	}
	rows.Close()
	out := make([]AdminVerification, 0, len(raws))
	for _, r := range raws {
		if r.a.Seller, err = s.GetOwner(ctx, r.userID); err != nil {
			return nil, 0, err
		}
		if r.a.Documents, err = s.documents(ctx, r.a.SellerID); err != nil {
			return nil, 0, err
		}
		out = append(out, r.a)
	}
	return out, total, nil
}

func (s *Service) AdminGet(ctx context.Context, id string) (*AdminVerification, error) {
	a, err := s.adminRow(ctx, s.db.QueryRow(ctx, adminVerifSelect+` WHERE v.id::text=$1`, id))
	if database.IsNoRows(err) {
		return nil, httpx.NotFound("Verification")
	}
	return a, err
}

// Decide approves or rejects a pending verification. Approval is the ONLY way a seller becomes "verified".
func (s *Service) Decide(ctx context.Context, id string, approve bool, text string) error {
	if !approve {
		var v httpx.V
		v.Length("reason", text, 5, 500)
		if err := v.Err(); err != nil {
			return err
		}
	}
	return s.db.InTx(ctx, func(tx pgx.Tx) error {
		var sellerID, userID, status, email, name string
		err := tx.QueryRow(ctx, `SELECT v.seller_id, sp.user_id, v.status, u.email, u.name FROM seller_verifications v
			JOIN seller_profiles sp ON sp.id=v.seller_id JOIN users u ON u.id=sp.user_id WHERE v.id::text=$1 FOR UPDATE OF v`, id).
			Scan(&sellerID, &userID, &status, &email, &name)
		if database.IsNoRows(err) {
			return httpx.NotFound("Verification")
		}
		if err != nil {
			return err
		}
		if status != "pending" {
			return httpx.Conflict(httpx.CodeConflict, "This verification has already been decided")
		}
		actor := audit.ActorID(ctx)
		newStatus, profileStatus, action := "rejected", "rejected", "seller.verification_rejected"
		if approve {
			newStatus, profileStatus, action = "approved", "approved", "seller.verification_approved"
		}
		var reason, notes *string
		if approve && text != "" {
			notes = &text
		} else if !approve {
			reason = &text
		}
		if _, err := tx.Exec(ctx, `UPDATE seller_verifications SET status=$2, reviewed_by=$3, reviewed_at=now(), reason=$4, notes=$5 WHERE id::text=$1`,
			id, newStatus, actor, reason, notes); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE seller_profiles SET verification_status=$2, verified_at=CASE WHEN $2='approved' THEN now() ELSE NULL END, updated_at=now() WHERE id=$1`,
			sellerID, profileStatus); err != nil {
			return err
		}
		// Retention: approved documents are kept while the seller is active; rejected ones are purged after 90 days.
		if approve {
			_, err = tx.Exec(ctx, `UPDATE seller_documents SET retention_until=NULL WHERE seller_id=$1`, sellerID)
		} else {
			_, err = tx.Exec(ctx, `UPDATE seller_documents SET retention_until=now() + interval '90 days' WHERE seller_id=$1 AND deleted_at IS NULL`, sellerID)
		}
		if err != nil {
			return err
		}
		if err := audit.Log(ctx, tx, audit.Entry{Action: action, EntityType: "seller", EntityID: sellerID}); err != nil {
			return err
		}
		if approve {
			if err := notifications.Create(ctx, tx, userID, "seller_verified", "You're a verified seller", "Your identity and business documents were approved.", nil); err != nil {
				return err
			}
			return notifications.EnqueueEmail(ctx, tx, email, "seller_verified", map[string]string{"name": name})
		}
		if err := notifications.Create(ctx, tx, userID, "seller_rejected", "Verification needs attention", text, nil); err != nil {
			return err
		}
		return notifications.EnqueueEmail(ctx, tx, email, "seller_rejected", map[string]string{"name": name, "reason": text})
	})
}

// OpenDocument streams a private document for staff review; every access is audited.
func (s *Service) OpenDocument(ctx context.Context, docID string) (io.ReadCloser, *Document, error) {
	var d Document
	var key, sellerID string
	err := s.db.QueryRow(ctx, `SELECT id, seller_id, kind, storage_key, original_name, mime_type, size_bytes, uploaded_at FROM seller_documents WHERE id::text=$1 AND deleted_at IS NULL`, docID).
		Scan(&d.ID, &sellerID, &d.Kind, &key, &d.OriginalName, &d.MimeType, &d.SizeBytes, &d.UploadedAt)
	if database.IsNoRows(err) {
		return nil, nil, httpx.NotFound("Document")
	}
	if err != nil {
		return nil, nil, err
	}
	rc, err := s.store.Get(ctx, storage.Private, key)
	if err != nil {
		return nil, nil, httpx.NotFound("Document")
	}
	_ = audit.Log(ctx, s.db, audit.Entry{Action: "seller.document_viewed", EntityType: "seller_document", EntityID: d.ID, Metadata: map[string]any{"seller_id": sellerID}})
	return rc, &d, nil
}

// PurgeExpiredDocuments deletes documents past their retention date (cleanup job).
func (s *Service) PurgeExpiredDocuments(ctx context.Context) (int, error) {
	rows, err := s.db.Query(ctx, `SELECT id, storage_key FROM seller_documents WHERE retention_until IS NOT NULL AND retention_until < now() AND deleted_at IS NULL LIMIT 200`)
	if err != nil {
		return 0, err
	}
	type d struct{ id, key string }
	var list []d
	for rows.Next() {
		var x d
		if err := rows.Scan(&x.id, &x.key); err != nil {
			rows.Close()
			return 0, err
		}
		list = append(list, x)
	}
	rows.Close()
	for _, x := range list {
		if err := s.store.Delete(ctx, storage.Private, x.key); err != nil {
			return 0, err
		}
		if _, err := s.db.Exec(ctx, `UPDATE seller_documents SET deleted_at=now() WHERE id=$1`, x.id); err != nil {
			return 0, err
		}
	}
	return len(list), nil
}
