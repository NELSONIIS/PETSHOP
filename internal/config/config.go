// Package config loads all runtime configuration from environment variables.
package config

import (
	"errors"
	"fmt"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	Env         string // development | staging | production
	BaseURL     string // public origin, e.g. https://petora.in
	HTTPAddr    string
	DatabaseURL string
	RedisURL    string

	JWTSecret         string
	DataEncryptionKey string // base64, 32 bytes — encrypts MFA secrets at rest
	AccessTTL         time.Duration
	RefreshTTL        time.Duration
	CookieSecure      bool
	AllowedOrigins    []string
	TrustProxy        bool

	FrontendDist string

	StorageDriver    string // local | s3
	StorageLocalPath string
	S3Endpoint       string
	S3Region         string
	S3AccessKey      string
	S3SecretKey      string
	S3PublicBucket   string
	S3PrivateBucket  string
	S3UseSSL         bool
	PublicMediaURL   string // base URL serving public media (CDN or /media)

	PaymentProvider       string // testmode | razorpay
	RazorpayKeyID         string
	RazorpayKeySecret     string
	RazorpayWebhookSecret string
	RazorpayAPIBase       string // overridable outside production only (tests / sandbox proxies)

	SMTPHost string
	SMTPPort int
	SMTPUser string
	SMTPPass string
	SMTPFrom string

	DefaultCurrency string
	LogLevel        string
}

func (c Config) IsProduction() bool { return c.Env == "production" }

func Load() (Config, error) {
	c := Config{
		Env:                   get("APP_ENV", "development"),
		BaseURL:               strings.TrimRight(get("APP_BASE_URL", "http://localhost:8080"), "/"),
		HTTPAddr:              get("HTTP_ADDR", ":8080"),
		DatabaseURL:           get("DATABASE_URL", ""),
		RedisURL:              get("REDIS_URL", ""),
		JWTSecret:             get("JWT_SECRET", ""),
		DataEncryptionKey:     get("DATA_ENCRYPTION_KEY", ""),
		AccessTTL:             dur("ACCESS_TOKEN_TTL", 15*time.Minute),
		RefreshTTL:            dur("REFRESH_TOKEN_TTL", 30*24*time.Hour),
		TrustProxy:            get("TRUST_PROXY", "false") == "true",
		FrontendDist:          get("FRONTEND_DIST", "frontend/dist"),
		StorageDriver:         get("STORAGE_DRIVER", "local"),
		StorageLocalPath:      get("STORAGE_LOCAL_PATH", "./data/storage"),
		S3Endpoint:            get("S3_ENDPOINT", ""),
		S3Region:              get("S3_REGION", "ap-south-1"),
		S3AccessKey:           get("S3_ACCESS_KEY", ""),
		S3SecretKey:           get("S3_SECRET_KEY", ""),
		S3PublicBucket:        get("S3_PUBLIC_BUCKET", "petora-public"),
		S3PrivateBucket:       get("S3_PRIVATE_BUCKET", "petora-private"),
		S3UseSSL:              get("S3_USE_SSL", "true") == "true",
		PaymentProvider:       get("PAYMENT_PROVIDER", "testmode"),
		RazorpayKeyID:         get("RAZORPAY_KEY_ID", ""),
		RazorpayKeySecret:     get("RAZORPAY_KEY_SECRET", ""),
		RazorpayWebhookSecret: get("RAZORPAY_WEBHOOK_SECRET", ""),
		RazorpayAPIBase:       strings.TrimRight(get("RAZORPAY_API_BASE", "https://api.razorpay.com/v1"), "/"),
		SMTPHost:              get("SMTP_HOST", ""),
		SMTPPort:              integer("SMTP_PORT", 587),
		SMTPUser:              get("SMTP_USER", ""),
		SMTPPass:              get("SMTP_PASS", ""),
		SMTPFrom:              get("SMTP_FROM", "PETORA <no-reply@petora.in>"),
		DefaultCurrency:       get("DEFAULT_CURRENCY", "INR"),
		LogLevel:              get("LOG_LEVEL", "info"),
	}
	c.PublicMediaURL = strings.TrimRight(get("PUBLIC_MEDIA_URL", c.BaseURL+"/media"), "/")
	if u, err := url.Parse(c.BaseURL); err == nil {
		c.CookieSecure = u.Scheme == "https"
	}
	origins := get("ALLOWED_ORIGINS", c.BaseURL)
	for _, o := range strings.Split(origins, ",") {
		if o = strings.TrimSpace(o); o != "" {
			c.AllowedOrigins = append(c.AllowedOrigins, strings.TrimRight(o, "/"))
		}
	}
	return c, c.validate()
}

func (c Config) validate() error {
	var errs []error
	if c.DatabaseURL == "" {
		errs = append(errs, errors.New("DATABASE_URL is required"))
	}
	switch c.Env {
	case "development", "staging", "production":
	default:
		errs = append(errs, fmt.Errorf("APP_ENV must be development, staging or production (got %q)", c.Env))
	}
	if len(c.JWTSecret) < 32 {
		errs = append(errs, errors.New("JWT_SECRET must be at least 32 characters"))
	}
	if len(c.DataEncryptionKey) == 0 {
		errs = append(errs, errors.New("DATA_ENCRYPTION_KEY is required (base64, 32 bytes)"))
	}
	if c.IsProduction() {
		if c.PaymentProvider == "testmode" {
			errs = append(errs, errors.New("PAYMENT_PROVIDER=testmode is forbidden in production"))
		}
		if !c.CookieSecure {
			errs = append(errs, errors.New("APP_BASE_URL must be https in production"))
		}
		if c.RedisURL == "" {
			errs = append(errs, errors.New("REDIS_URL is required in production"))
		}
	}
	if c.PaymentProvider == "razorpay" {
		if c.RazorpayKeyID == "" || c.RazorpayKeySecret == "" || c.RazorpayWebhookSecret == "" {
			errs = append(errs, errors.New("razorpay requires RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET and RAZORPAY_WEBHOOK_SECRET"))
		}
		if c.IsProduction() {
			if c.RazorpayAPIBase != "https://api.razorpay.com/v1" {
				errs = append(errs, errors.New("RAZORPAY_API_BASE cannot be overridden in production"))
			}
			if strings.HasPrefix(c.RazorpayKeyID, "rzp_test_") {
				errs = append(errs, errors.New("production requires live Razorpay keys (rzp_live_...), not rzp_test_ keys"))
			}
		}
	}
	if c.StorageDriver == "s3" && (c.S3Endpoint == "" || c.S3AccessKey == "" || c.S3SecretKey == "") {
		errs = append(errs, errors.New("s3 storage requires S3_ENDPOINT, S3_ACCESS_KEY and S3_SECRET_KEY"))
	}
	return errors.Join(errs...)
}

func get(k, def string) string {
	if v, ok := os.LookupEnv(k); ok && v != "" {
		return v
	}
	return def
}
func integer(k string, def int) int {
	if v, err := strconv.Atoi(get(k, "")); err == nil {
		return v
	}
	return def
}
func dur(k string, def time.Duration) time.Duration {
	if v, err := time.ParseDuration(get(k, "")); err == nil {
		return v
	}
	return def
}
