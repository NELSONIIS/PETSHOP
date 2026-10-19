// Command worker runs background jobs (emails, webhook processing, subscription expiry,
// listing expiry, reconciliation, renewal reminders and cleanup) until SIGTERM, then drains.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"petora/internal/config"
	"petora/internal/httpserver"
	"petora/internal/worker"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintln(os.Stderr, "configuration error:\n"+err.Error())
		os.Exit(2)
	}
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)).With("service", "petora-worker", "env", cfg.Env))
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	a, err := httpserver.NewApp(ctx, cfg)
	if err != nil {
		slog.Error("startup failed", "err", err)
		os.Exit(1)
	}
	defer a.Close()
	worker.Run(ctx, a)
	slog.Info("worker stopped")
}
