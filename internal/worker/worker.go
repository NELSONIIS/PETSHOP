// Package worker registers background job handlers and the periodic scheduler.
package worker

import (
	"context"
	"encoding/json"
	"log/slog"
	"time"

	"petora/internal/httpserver"
	"petora/internal/jobs"
	"petora/internal/notifications"
)

type periodic struct {
	kind  string
	every time.Duration
}

var schedule = []periodic{
	{"subscriptions.sweep", time.Minute},
	{"listings.expire", 10 * time.Minute},
	{"payments.reconcile", 10 * time.Minute},
	{"reminders.renewal", time.Hour},
	{"cleanup.daily", 24 * time.Hour},
}

// Register wires every job kind to its handler.
func Register(a *httpserver.App, r *jobs.Runner) {
	r.Register("email.send", notifications.EmailHandler(a.DB, a.Mailer))
	r.Register("webhook.process", a.Payments.JobHandler())
	r.Register("subscriptions.sweep", func(ctx context.Context, _ json.RawMessage) error {
		n, err := a.Subs.SweepExpiry(ctx)
		if n > 0 {
			slog.Info("subscriptions advanced", "count", n)
		}
		return err
	})
	r.Register("listings.expire", func(ctx context.Context, _ json.RawMessage) error {
		_, err := a.Listings.ExpireListings(ctx)
		return err
	})
	r.Register("payments.reconcile", func(ctx context.Context, _ json.RawMessage) error {
		n, err := a.Payments.Reconcile(ctx)
		if n > 0 {
			slog.Info("payments reconciled", "count", n)
		}
		return err
	})
	r.Register("reminders.renewal", func(ctx context.Context, _ json.RawMessage) error { return a.Subs.QueueRenewalReminders(ctx) })
	r.Register("cleanup.daily", func(ctx context.Context, _ json.RawMessage) error {
		if n, err := a.Sellers.PurgeExpiredDocuments(ctx); err != nil {
			return err
		} else if n > 0 {
			slog.Info("purged expired verification documents", "count", n)
		}
		for _, q := range []string{
			`DELETE FROM one_time_codes WHERE expires_at < now() - interval '1 day'`,
			`DELETE FROM sessions WHERE (revoked_at IS NOT NULL AND revoked_at < now() - interval '30 days') OR expires_at < now() - interval '1 day'`,
			`DELETE FROM jobs WHERE status='succeeded' AND finished_at < now() - interval '30 days'`,
			`DELETE FROM listing_views WHERE viewed_at < now() - interval '400 days'`,
			`DELETE FROM notifications WHERE read_at IS NOT NULL AND read_at < now() - interval '180 days'`,
		} {
			if _, err := a.DB.Exec(ctx, q); err != nil {
				return err
			}
		}
		return nil
	})
}

// Schedule enqueues periodic jobs. The dedupe key is the time bucket, so any number of worker replicas
// produce exactly one job per period.
func Schedule(ctx context.Context, a *httpserver.App) {
	tick := func() {
		now := time.Now().UTC()
		for _, p := range schedule {
			bucket := now.Truncate(p.every).Format("200601021504")
			if err := jobs.Enqueue(ctx, a.DB, p.kind, map[string]string{"bucket": bucket}, jobs.Dedupe("sched:"+p.kind+":"+bucket), jobs.MaxAttempts(3)); err != nil {
				slog.Error("schedule enqueue failed", "kind", p.kind, "err", err)
			}
		}
	}
	tick()
	t := time.NewTicker(30 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			tick()
		}
	}
}

// Run starts scheduler + runner and blocks until ctx is cancelled (graceful drain included).
func Run(ctx context.Context, a *httpserver.App) {
	r := jobs.NewRunner(a.DB, a.Cache)
	Register(a, r)
	go Schedule(ctx, a)
	r.Run(ctx)
}
