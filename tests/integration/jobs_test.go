package integration

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"petora/internal/jobs"
	"petora/internal/notifications"
	"petora/internal/worker"
)

type captureMailer struct{ sent []string }

func (c *captureMailer) Send(_ context.Context, to, subject, body string) error {
	c.sent = append(c.sent, to+"|"+subject+"|"+body)
	return nil
}

func TestJobRunnerDeliversRetriesAndDeadLetters(t *testing.T) {
	ctx := context.Background()
	exec(t, `UPDATE jobs SET status='succeeded' WHERE status IN ('queued','failed')`) // isolate from other tests' outbox rows
	must(notifications.EnqueueEmail(ctx, app.DB, "jobs@example.test", "email_verify", map[string]string{"name": "J", "code": "123456"}))
	must(jobs.Enqueue(ctx, app.DB, "test.flaky", map[string]int{"n": 1}, jobs.MaxAttempts(2)))
	must(jobs.Enqueue(ctx, app.DB, "test.once", nil, jobs.Dedupe("same-key")))
	must(jobs.Enqueue(ctx, app.DB, "test.once", nil, jobs.Dedupe("same-key"))) // deduplicated

	m := &captureMailer{}
	r := jobs.NewRunner(app.DB, app.Cache)
	r.Register("email.send", notifications.EmailHandler(app.DB, m))
	r.Register("test.flaky", func(context.Context, json.RawMessage) error { return errors.New("boom") })
	onceRuns := 0
	r.Register("test.once", func(context.Context, json.RawMessage) error { onceRuns++; return nil })

	runFor := func(d time.Duration) {
		cctx, cancel := context.WithTimeout(ctx, d)
		defer cancel()
		r.Run(cctx)
	}
	runFor(1500 * time.Millisecond)
	if len(m.sent) != 1 || onceRuns != 1 {
		t.Fatalf("expected 1 email and 1 deduplicated job run, got %d and %d", len(m.sent), onceRuns)
	}
	var redacted bool
	must(app.DB.QueryRow(ctx, `SELECT payload ? 'redacted' AND NOT payload ? 'vars' FROM jobs WHERE kind='email.send' AND payload->>'to'='jobs@example.test'`).Scan(&redacted))
	if !redacted {
		t.Fatal("delivered email payload must be redacted (contains OTP)")
	}
	// flaky job failed once and is scheduled with backoff; force it due and run again -> dead-lettered.
	exec(t, `UPDATE jobs SET run_at=now() WHERE kind='test.flaky'`)
	runFor(1500 * time.Millisecond)
	var status string
	var attempts int
	must(app.DB.QueryRow(ctx, `SELECT status, attempts FROM jobs WHERE kind='test.flaky'`).Scan(&status, &attempts))
	if status != "dead" || attempts != 2 {
		t.Fatalf("expected dead after 2 attempts, got %s/%d", status, attempts)
	}
	var id string
	must(app.DB.QueryRow(ctx, `SELECT id FROM jobs WHERE kind='test.flaky'`).Scan(&id))
	must(jobs.Retry(ctx, app.DB, id))
}

func TestSchedulerDedupesAcrossReplicas(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{}, 2)
	for i := 0; i < 2; i++ { // two "replicas"
		go func() { worker.Schedule(ctx, app); done <- struct{}{} }()
	}
	time.Sleep(300 * time.Millisecond)
	cancel()
	<-done
	<-done
	var n int
	must(app.DB.QueryRow(context.Background(), `SELECT count(*) FROM jobs WHERE kind='subscriptions.sweep' AND created_at > now() - interval '1 minute'`).Scan(&n))
	if n != 1 {
		t.Fatalf("two schedulers must enqueue one sweep per bucket, got %d", n)
	}
}
