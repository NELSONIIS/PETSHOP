// Package integration runs end-to-end API tests against a real PostgreSQL (and Redis when available).
//
//	TEST_DATABASE_URL=postgres://petora@localhost:5433/petora_test?sslmode=disable \
//	TEST_REDIS_URL=redis://localhost:6380/15 go test ./tests/integration/ -v
//
// The database's public schema is DROPPED and recreated: never point this at real data.
package integration

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"io"
	"log/slog"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"petora/internal/config"
	"petora/internal/database"
	"petora/internal/httpserver"
	"petora/internal/security"
	"petora/internal/seed"
	"petora/migrations"
)

var (
	app *httpserver.App
	srv *httptest.Server
)

func TestMain(m *testing.M) {
	dbURL := os.Getenv("TEST_DATABASE_URL")
	if dbURL == "" {
		fmt.Println("TEST_DATABASE_URL not set; skipping integration tests")
		os.Exit(0)
	}
	if !strings.Contains(dbURL, "test") {
		fmt.Println("refusing: TEST_DATABASE_URL must point at a database whose name contains 'test'")
		os.Exit(1)
	}
	if os.Getenv("TEST_VERBOSE") == "" {
		slog.SetDefault(slog.New(slog.NewTextHandler(io.Discard, nil)))
	}
	ctx := context.Background()
	db, err := database.Connect(ctx, dbURL)
	must(err)
	_, err = db.Exec(ctx, `DROP SCHEMA public CASCADE; CREATE SCHEMA public;`)
	must(err)
	_, err = database.Migrate(ctx, db, migrations.FS)
	must(err)
	db.Close()

	storageDir, _ := os.MkdirTemp("", "petora-test-storage")
	defer os.RemoveAll(storageDir)
	env := map[string]string{
		"APP_ENV": "development", "APP_BASE_URL": "http://petora.test", "DATABASE_URL": dbURL, "REDIS_URL": os.Getenv("TEST_REDIS_URL"),
		"JWT_SECRET": "test-secret-test-secret-test-secret-123456", "DATA_ENCRYPTION_KEY": "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=",
		"PAYMENT_PROVIDER": "testmode", "STORAGE_DRIVER": "local", "STORAGE_LOCAL_PATH": storageDir,
		"ALLOWED_ORIGINS": "http://petora.test", "FRONTEND_DIST": storageDir,
	}
	for k, v := range env {
		os.Setenv(k, v)
	}
	cfg, err := config.Load()
	must(err)
	app, err = httpserver.NewApp(ctx, cfg)
	must(err)
	if app.Cache.Enabled() {
		app.Cache.DelPrefix(ctx, "")
	}
	must(seed.Run(ctx, app, false))
	srv = httptest.NewServer(app.Router())
	code := m.Run()
	srv.Close()
	app.Close()
	os.Exit(code)
}

// resetRateLimits clears limiter counters: every test request comes from 127.0.0.1.
func resetRateLimits() { app.Cache.DelPrefix(context.Background(), "rl:") }

func must(err error) {
	if err != nil {
		panic(err)
	}
}

// ---------- client ----------

type client struct {
	t       *testing.T
	access  string
	refresh string
	userID  string
	email   string
	cookies *cookieJar
	csrf    string
}

type resp struct {
	Status int
	Body   map[string]any
	Raw    []byte
}

func (r resp) data() map[string]any {
	d, _ := r.Body["data"].(map[string]any)
	return d
}
func (r resp) list() []any {
	l, _ := r.Body["data"].([]any)
	return l
}
func (r resp) code() string {
	if e, ok := r.Body["error"].(map[string]any); ok {
		s, _ := e["code"].(string)
		return s
	}
	return ""
}

func newClient(t *testing.T) *client { return &client{t: t} }

func (c *client) do(method, path string, body any, hdr ...string) resp {
	c.t.Helper()
	var rd io.Reader
	ct := "application/json"
	switch b := body.(type) {
	case nil:
	case *multipartBody:
		rd, ct = b.buf, b.ct
	default:
		raw, _ := json.Marshal(b)
		rd = bytes.NewReader(raw)
	}
	req, _ := http.NewRequest(method, srv.URL+"/api/v1"+path, rd)
	if body != nil {
		req.Header.Set("Content-Type", ct)
	}
	if c.cookies == nil {
		req.Header.Set("X-Client", "mobile")
		if c.access != "" {
			req.Header.Set("Authorization", "Bearer "+c.access)
		}
	} else {
		for _, ck := range c.cookies.list {
			req.AddCookie(ck)
		}
		if c.csrf != "" {
			req.Header.Set("X-CSRF-Token", c.csrf)
		}
	}
	for i := 0; i+1 < len(hdr); i += 2 {
		req.Header.Set(hdr[i], hdr[i+1])
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		c.t.Fatal(err)
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(res.Body)
	if c.cookies != nil {
		c.cookies.absorb(res.Cookies())
	}
	out := resp{Status: res.StatusCode, Raw: raw}
	_ = json.Unmarshal(raw, &out.Body)
	return out
}

func (c *client) must(status int, r resp) resp {
	c.t.Helper()
	if r.Status != status {
		c.t.Fatalf("expected HTTP %d, got %d: %s", status, r.Status, string(r.Raw))
	}
	return r
}

type cookieJar struct{ list []*http.Cookie }

func (j *cookieJar) absorb(cs []*http.Cookie) {
	for _, c := range cs {
		out := j.list[:0]
		for _, e := range j.list {
			if e.Name != c.Name {
				out = append(out, e)
			}
		}
		j.list = out
		if c.MaxAge >= 0 && c.Value != "" {
			j.list = append(j.list, c)
		}
	}
}

var seq int

func uniqueEmail(prefix string) string {
	seq++
	return fmt.Sprintf("%s%d-%d@example.test", prefix, seq, time.Now().UnixNano()%1e6)
}

const password = "Correct-horse-42"

// register creates and email-verifies a user (code read from the email outbox, as the mail worker would send it).
func register(t *testing.T, role string) *client {
	t.Helper()
	resetRateLimits()
	c := newClient(t)
	c.email = uniqueEmail(role)
	r := c.must(201, c.do("POST", "/auth/register", map[string]any{"name": "Test " + role, "email": c.email, "password": password,
		"role": role, "accept_terms": true, "phone": fmt.Sprintf("+9198%08d", seq*7919%100000000)}))
	d := r.data()
	c.access, c.refresh = d["access_token"].(string), d["refresh_token"].(string)
	c.userID = d["user"].(map[string]any)["id"].(string)
	c.must(204, c.do("POST", "/auth/verify-email", map[string]any{"code": outboxCode(t, c.email, "email_verify")}))
	return c
}

func outboxCode(t *testing.T, email, template string) string {
	t.Helper()
	var code string
	err := app.DB.QueryRow(context.Background(), `SELECT payload->'vars'->>'code' FROM jobs WHERE kind='email.send'
		AND payload->>'to'=$1 AND payload->>'template'=$2 ORDER BY created_at DESC LIMIT 1`, email, template).Scan(&code)
	if err != nil {
		t.Fatalf("no %s email for %s: %v", template, email, err)
	}
	return code
}

// staff creates an MFA-enrolled staff user with the given roles and logs in with a TOTP code.
func staff(t *testing.T, roles ...string) *client {
	t.Helper()
	resetRateLimits()
	ctx := context.Background()
	email := uniqueEmail("staff")
	hash, _ := security.HashPassword(password)
	var id string
	must(app.DB.QueryRow(ctx, `INSERT INTO users (email, name, password_hash, account_type, email_verified_at) VALUES ($1,'Staff',$2,'staff',now()) RETURNING id`, email, hash).Scan(&id))
	for _, r := range roles {
		_, err := app.DB.Exec(ctx, `INSERT INTO user_roles (user_id, role_code) VALUES ($1,$2)`, id, r)
		must(err)
	}
	secret, err := app.Auth.BootstrapMFA(ctx, id)
	must(err)
	c := newClient(t)
	c.email, c.userID = email, id
	r := c.do("POST", "/auth/login", map[string]any{"email": email, "password": password})
	if r.code() != "mfa_required" {
		t.Fatalf("staff login without OTP should demand MFA, got %d %s", r.Status, r.Raw)
	}
	d := c.must(200, c.do("POST", "/auth/login", map[string]any{"email": email, "password": password, "otp": security.TOTPCode(secret, time.Now())})).data()
	if d["user"].(map[string]any)["mfa_verified"] != true {
		t.Fatal("login response must report the session as MFA-verified")
	}
	c.access, c.refresh = d["access_token"].(string), d["refresh_token"].(string)
	return c
}

func planID(t *testing.T, code string) string {
	t.Helper()
	var id string
	must(app.DB.QueryRow(context.Background(), `SELECT id FROM subscription_plans WHERE code=$1`, code).Scan(&id))
	return id
}

// subscribe performs checkout + test-mode completion and returns the payment id.
func subscribe(t *testing.T, c *client, plan string) string {
	t.Helper()
	co := c.must(201, c.do("POST", "/subscriptions/checkout", map[string]any{"plan_id": planID(t, plan), "idempotency_key": fmt.Sprintf("idem-%s-%d", plan, time.Now().UnixNano())})).data()
	pid := co["payment"].(map[string]any)["id"].(string)
	if co["test_mode"] != true {
		t.Fatal("checkout should flag test_mode")
	}
	p := c.must(200, c.do("POST", "/payments/"+pid+"/test-complete", map[string]any{"outcome": "success"})).data()
	if p["status"] != "succeeded" {
		t.Fatalf("payment not succeeded: %v", p)
	}
	return pid
}

type multipartBody struct {
	buf *bytes.Buffer
	ct  string
}

func fileBody(field, name string, data []byte, extra map[string]string) *multipartBody {
	var b bytes.Buffer
	w := multipart.NewWriter(&b)
	for k, v := range extra {
		_ = w.WriteField(k, v)
	}
	fw, _ := w.CreateFormFile(field, name)
	_, _ = fw.Write(data)
	_ = w.Close()
	return &multipartBody{&b, w.FormDataContentType()}
}

func pngBytes(w, h int) []byte {
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			img.Set(x, y, color.RGBA{uint8(x), uint8(y), 120, 255})
		}
	}
	var buf bytes.Buffer
	_ = png.Encode(&buf, img)
	return buf.Bytes()
}

var pdfBytes = []byte("%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n")

// verifiedSeller registers a seller, completes verification via a moderator and subscribes to plan.
func verifiedSeller(t *testing.T, mod *client, plan string) *client {
	t.Helper()
	s := register(t, "seller")
	s.must(200, s.do("PUT", "/seller/profile", map[string]any{"city": "Pune", "state": "Maharashtra", "contact_phone": "+919811112222", "contact_whatsapp": "+919811112222"}))
	s.must(201, s.do("POST", "/seller/documents", fileBody("file", "id.pdf", pdfBytes, map[string]string{"kind": "identity"})))
	s.must(200, s.do("POST", "/seller/verification/submit", map[string]any{}))
	list := mod.must(200, mod.do("GET", "/admin/sellers/verifications?status=pending&per_page=100", nil)).list()
	var vid string
	for _, it := range list {
		m := it.(map[string]any)
		if m["user_email"] == s.email {
			vid = m["id"].(string)
		}
	}
	if vid == "" {
		t.Fatal("verification not in queue")
	}
	mod.must(204, mod.do("POST", "/admin/sellers/verifications/"+vid+"/approve", map[string]any{"notes": "ok"}))
	if plan != "" {
		subscribe(t, s, plan)
	}
	return s
}

func categoryID(t *testing.T, slug string) string {
	t.Helper()
	var id string
	must(app.DB.QueryRow(context.Background(), `SELECT id FROM categories WHERE slug=$1`, slug).Scan(&id))
	return id
}

func listingInput(t *testing.T, title string) map[string]any {
	return map[string]any{"title": title, "description": "A healthy and playful companion raised at home with care and love.",
		"category_id": categoryID(t, "dogs"), "listing_type": "sale", "price_minor": 1500000, "age_months": 3, "gender": "male",
		"vaccination_status": "partial", "city": "Pune", "state": "Maharashtra", "lat": 18.52, "lng": 73.85}
}

// publishedListing creates, illustrates, submits and approves a listing; returns its id.
func publishedListing(t *testing.T, s, mod *client, title string) string {
	t.Helper()
	l := s.must(201, s.do("POST", "/seller/listings", listingInput(t, title))).data()
	id := l["id"].(string)
	s.must(201, s.do("POST", "/seller/listings/"+id+"/images", fileBody("file", "dog.png", pngBytes(400, 300), nil)))
	sub := s.must(200, s.do("POST", "/seller/listings/"+id+"/submit", nil)).data()
	if sub["status"] != "pending" {
		t.Fatalf("expected pending after submit, got %v", sub["status"])
	}
	mod.must(204, mod.do("POST", "/admin/listings/"+id+"/approve", nil))
	return id
}

func publicIDs(t *testing.T, query string) map[string]bool {
	t.Helper()
	c := newClient(t)
	out := map[string]bool{}
	for _, it := range c.must(200, c.do("GET", "/pets?per_page=50&"+query, nil)).list() {
		out[it.(map[string]any)["id"].(string)] = true
	}
	return out
}

func exec(t *testing.T, q string, args ...any) {
	t.Helper()
	if _, err := app.DB.Exec(context.Background(), q, args...); err != nil {
		t.Fatal(err)
	}
}
