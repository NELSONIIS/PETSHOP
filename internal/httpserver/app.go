// Package httpserver wires services into the HTTP router and serves the SPA.
package httpserver

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"

	"petora/internal/admin"
	"petora/internal/auth"
	"petora/internal/cache"
	"petora/internal/catalog"
	"petora/internal/config"
	"petora/internal/database"
	"petora/internal/enquiries"
	"petora/internal/listings"
	"petora/internal/mail"
	"petora/internal/payments"
	"petora/internal/sellers"
	"petora/internal/settings"
	"petora/internal/storage"
	"petora/internal/subscriptions"
)

type pgxTx = pgx.Tx

// App is the dependency container shared by the API server and the worker.
type App struct {
	Config    config.Config
	DB        *database.DB
	Cache     *cache.Cache
	Store     storage.Store
	Mailer    mail.Mailer
	Settings  *settings.Service
	Auth      *auth.Service
	Catalog   *catalog.Service
	Sellers   *sellers.Service
	Listings  *listings.Service
	Subs      *subscriptions.Service
	Payments  *payments.Service
	Enquiries *enquiries.Service
	Admin     *admin.Handler
}

func NewApp(ctx context.Context, cfg config.Config) (*App, error) {
	db, err := database.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		return nil, err
	}
	c, err := cache.New(cfg.RedisURL)
	if err != nil {
		return nil, fmt.Errorf("redis: %w", err)
	}
	store, err := storage.New(cfg)
	if err != nil {
		return nil, fmt.Errorf("storage: %w", err)
	}
	var provider payments.Provider
	switch cfg.PaymentProvider {
	case "razorpay":
		provider = payments.NewRazorpay(cfg.RazorpayKeyID, cfg.RazorpayKeySecret, cfg.RazorpayWebhookSecret, cfg.RazorpayAPIBase)
	case "testmode":
		provider = payments.NewTestMode(cfg.JWTSecret)
	default:
		return nil, fmt.Errorf("unknown PAYMENT_PROVIDER %q", cfg.PaymentProvider)
	}
	a := &App{Config: cfg, DB: db, Cache: c, Store: store, Mailer: mail.New(cfg)}
	a.Settings = settings.New(db)
	if a.Auth, err = auth.NewService(cfg, db, c); err != nil {
		return nil, err
	}
	a.Catalog = catalog.New(db, c)
	a.Sellers = sellers.New(db, store, a.Settings)
	a.Listings = listings.New(db, c, store, a.Settings, a.Sellers)
	a.Subs = subscriptions.NewService(db, c, a.Settings, cfg.BaseURL)
	a.Payments = payments.NewService(cfg, db, c, provider, a.Subs)
	a.Enquiries = enquiries.New(db, c, a.Settings, a.Subs, a.Listings, store, cfg.BaseURL)
	a.Admin = admin.New(db, a.Auth, a.Listings, a.Settings)
	return a, nil
}

func (a *App) Close() {
	a.Cache.Close()
	a.DB.Close()
}
