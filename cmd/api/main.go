// Command api runs the PETORA HTTP server and operational subcommands.
//
//	api serve                 start the HTTP server (default)
//	api migrate               apply database migrations
//	api setup                 migrate + load reference data
//	api seed [--demo]         load reference data (idempotent); --demo adds sample data (non-production only)
//	api healthcheck           exit 0 if the local server answers /healthz
//	api create-admin          create a super administrator (ADMIN_EMAIL, ADMIN_NAME, ADMIN_PASSWORD env vars)
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"petora/internal/config"
	"petora/internal/database"
	"petora/internal/httpserver"
	"petora/internal/seed"
	"petora/internal/worker"
	"petora/migrations"
)

func main() {
	cmd := "serve"
	args := os.Args[1:]
	if len(args) > 0 {
		cmd, args = args[0], args[1:]
	}
	if cmd == "healthcheck" { // container HEALTHCHECK (distroless images have no curl); needs no config
		os.Exit(healthcheck())
	}
	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintln(os.Stderr, "configuration error:\n"+err.Error())
		os.Exit(2)
	}
	setupLogging(cfg)
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	switch cmd {
	case "serve":
		err = serve(ctx, cfg)
	case "migrate":
		err = migrate(ctx, cfg)
	case "setup": // migrate + idempotent reference seed (used by the compose migrate job)
		if err = migrate(ctx, cfg); err == nil {
			err = withApp(ctx, cfg, func(a *httpserver.App) error { return seed.Run(ctx, a, false) })
		}
	case "seed":
		fs := flag.NewFlagSet("seed", flag.ExitOnError)
		demo := fs.Bool("demo", false, "add demo data (refused in production)")
		_ = fs.Parse(args)
		err = withApp(ctx, cfg, func(a *httpserver.App) error { return seed.Run(ctx, a, *demo) })
	case "create-admin":
		err = withApp(ctx, cfg, func(a *httpserver.App) error {
			return seed.CreateAdmin(ctx, a, os.Getenv("ADMIN_EMAIL"), os.Getenv("ADMIN_NAME"), os.Getenv("ADMIN_PASSWORD"))
		})
	default:
		err = fmt.Errorf("unknown command %q (serve | migrate | seed | create-admin)", cmd)
	}
	if err != nil {
		slog.Error("fatal", "err", err)
		os.Exit(1)
	}
}

func healthcheck() int {
	addr := os.Getenv("HTTP_ADDR")
	if addr == "" || addr[0] == ':' {
		addr = "127.0.0.1" + addr
		if addr == "127.0.0.1" {
			addr += ":8080"
		}
	}
	c := http.Client{Timeout: 3 * time.Second}
	res, err := c.Get("http://" + addr + "/healthz")
	if err != nil || res.StatusCode != http.StatusOK {
		return 1
	}
	res.Body.Close()
	return 0
}

func setupLogging(cfg config.Config) {
	lvl := slog.LevelInfo
	_ = lvl.UnmarshalText([]byte(cfg.LogLevel))
	var h slog.Handler = slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: lvl})
	if cfg.Env == "development" && os.Getenv("LOG_FORMAT") != "json" {
		h = slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: lvl})
	}
	slog.SetDefault(slog.New(h).With("service", "petora-api", "env", cfg.Env))
}

func migrate(ctx context.Context, cfg config.Config) error {
	db, err := database.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer db.Close()
	applied, err := database.Migrate(ctx, db, migrations.FS)
	slog.Info("migrations complete", "applied", len(applied))
	return err
}

func withApp(ctx context.Context, cfg config.Config, fn func(*httpserver.App) error) error {
	a, err := httpserver.NewApp(ctx, cfg)
	if err != nil {
		return err
	}
	defer a.Close()
	return fn(a)
}

func serve(ctx context.Context, cfg config.Config) error {
	if os.Getenv("AUTO_MIGRATE") == "true" {
		if err := migrate(ctx, cfg); err != nil {
			return err
		}
	}
	a, err := httpserver.NewApp(ctx, cfg)
	if err != nil {
		return err
	}
	defer a.Close()
	if cfg.PaymentProvider == "testmode" {
		slog.Warn("PAYMENT PROVIDER IS TESTMODE: no real payments are processed")
	}
	srv := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           a.Router(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       60 * time.Second, // uploads
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
		MaxHeaderBytes:    64 << 10,
	}
	workerDone := make(chan struct{})
	if os.Getenv("WORKER_INLINE") == "true" { // single-container deployments
		go func() { worker.Run(ctx, a); close(workerDone) }()
	} else {
		close(workerDone)
	}
	errc := make(chan error, 1)
	go func() {
		slog.Info("http server listening", "addr", cfg.HTTPAddr, "base_url", cfg.BaseURL)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errc <- err
		}
		close(errc)
	}()
	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
	}
	slog.Info("shutting down")
	sctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()
	err = srv.Shutdown(sctx)
	<-workerDone
	return err
}
