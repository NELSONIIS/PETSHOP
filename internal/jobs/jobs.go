// Package jobs is a durable Postgres-backed queue that doubles as the transactional outbox.
// Enqueue inside the business transaction; workers claim rows with FOR UPDATE SKIP LOCKED.
// Redis (when available) is only used to wake workers early — polling guarantees progress without it.
package jobs

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"sync"
	"time"

	"petora/internal/cache"
	"petora/internal/database"
)

const wakeChannel = "petora:jobs"

type Option func(*opts)
type opts struct {
	runAt       time.Time
	dedupe      string
	maxAttempts int
}

func RunAt(t time.Time) Option { return func(o *opts) { o.runAt = t } }
func Dedupe(key string) Option { return func(o *opts) { o.dedupe = key } }
func MaxAttempts(n int) Option { return func(o *opts) { o.maxAttempts = n } }

// Enqueue inserts a job using q (pass a pgx.Tx to make it atomic with your change).
// A duplicate dedupe key is silently ignored, making enqueue idempotent.
func Enqueue(ctx context.Context, q database.Querier, kind string, payload any, options ...Option) error {
	o := opts{runAt: time.Now().UTC(), maxAttempts: 8}
	for _, f := range options {
		f(&o)
	}
	b, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	var dedupe *string
	if o.dedupe != "" {
		dedupe = &o.dedupe
	}
	_, err = q.Exec(ctx, `INSERT INTO jobs (kind, payload, run_at, max_attempts, dedupe_key)
		VALUES ($1,$2,$3,$4,$5) ON CONFLICT (dedupe_key) DO NOTHING`, kind, b, o.runAt, o.maxAttempts, dedupe)
	return err
}

type Handler func(ctx context.Context, payload json.RawMessage) error

type Runner struct {
	db       *database.DB
	cache    *cache.Cache
	handlers map[string]Handler
	id       string
	poll     time.Duration
	conc     int
}

func NewRunner(db *database.DB, c *cache.Cache) *Runner {
	host, _ := os.Hostname()
	return &Runner{db: db, cache: c, handlers: map[string]Handler{}, id: fmt.Sprintf("%s-%d", host, os.Getpid()),
		poll: 3 * time.Second, conc: 4}
}

func (r *Runner) Register(kind string, h Handler) { r.handlers[kind] = h }

// Wake nudges workers after a commit (best effort).
func Wake(ctx context.Context, c *cache.Cache) { c.Notify(ctx, wakeChannel) }

type job struct {
	ID       string
	Kind     string
	Payload  json.RawMessage
	Attempts int
	Max      int
}

// Run blocks until ctx is cancelled, then waits for in-flight jobs (graceful shutdown).
func (r *Runner) Run(ctx context.Context) {
	wake, _ := r.cache.Subscribe(ctx, wakeChannel)
	var wg sync.WaitGroup
	sem := make(chan struct{}, r.conc)
	t := time.NewTicker(r.poll)
	defer t.Stop()
	slog.Info("job runner started", "id", r.id)
	for {
		for {
			n, err := r.claimAndDispatch(ctx, &wg, sem)
			if err != nil {
				slog.Error("job claim failed", "err", err)
			}
			if n == 0 || err != nil || ctx.Err() != nil {
				break
			}
		}
		select {
		case <-ctx.Done():
			slog.Info("job runner draining")
			wg.Wait()
			return
		case <-t.C:
		case <-wake:
		}
	}
}

func (r *Runner) claimAndDispatch(ctx context.Context, wg *sync.WaitGroup, sem chan struct{}) (int, error) {
	if ctx.Err() != nil {
		return 0, nil
	}
	// Reclaim jobs whose worker died mid-flight.
	_, _ = r.db.Exec(ctx, `UPDATE jobs SET status='failed', last_error='worker lost lock', locked_at=NULL, locked_by=NULL
		WHERE status='running' AND locked_at < now() - interval '5 minutes'`)
	free := cap(sem) - len(sem)
	if free == 0 {
		return 0, nil
	}
	rows, err := r.db.Query(ctx, `
		UPDATE jobs SET status='running', locked_at=now(), locked_by=$1, attempts=attempts+1
		WHERE id IN (SELECT id FROM jobs WHERE status IN ('queued','failed') AND run_at <= now()
		             ORDER BY run_at LIMIT $2 FOR UPDATE SKIP LOCKED)
		RETURNING id, kind, payload, attempts, max_attempts`, r.id, free)
	if err != nil {
		return 0, err
	}
	var batch []job
	for rows.Next() {
		var j job
		if err := rows.Scan(&j.ID, &j.Kind, &j.Payload, &j.Attempts, &j.Max); err != nil {
			rows.Close()
			return 0, err
		}
		batch = append(batch, j)
	}
	rows.Close()
	for _, j := range batch {
		sem <- struct{}{}
		wg.Add(1)
		go func(j job) {
			defer wg.Done()
			defer func() { <-sem }()
			r.execute(j)
		}(j)
	}
	return len(batch), nil
}

func (r *Runner) execute(j job) {
	// Use a fresh context: a shutdown signal must not abort a job halfway; we wait via the WaitGroup.
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	h, ok := r.handlers[j.Kind]
	var err error
	if !ok {
		err = fmt.Errorf("no handler for job kind %q", j.Kind)
	} else {
		err = safeCall(ctx, h, j.Payload)
	}
	if err == nil {
		// Email payloads can carry one-time codes: redact them once delivered.
		_, uerr := r.db.Exec(ctx, `UPDATE jobs SET status='succeeded', finished_at=now(), locked_at=NULL, last_error=NULL,
			payload = CASE WHEN kind='email.send' THEN jsonb_build_object('to', payload->'to', 'template', payload->'template', 'redacted', true) ELSE payload END
			WHERE id=$1`, j.ID)
		if uerr != nil {
			slog.Error("job completion update failed", "job", j.ID, "err", uerr)
		}
		return
	}
	status, delay := "failed", Backoff(j.Attempts)
	if j.Attempts >= j.Max {
		status = "dead" // dead-letter: stays in the table for inspection and manual retry
		slog.Error("job dead-lettered", "job", j.ID, "kind", j.Kind, "err", err)
	} else {
		slog.Warn("job failed; will retry", "job", j.ID, "kind", j.Kind, "attempt", j.Attempts, "err", err)
	}
	_, _ = r.db.Exec(ctx, `UPDATE jobs SET status=$2, last_error=$3, run_at=now()+$4::interval, locked_at=NULL, locked_by=NULL,
		finished_at=CASE WHEN $2='dead' THEN now() END WHERE id=$1`, j.ID, status, truncate(err.Error(), 1000), fmt.Sprintf("%d seconds", int(delay.Seconds())))
}

func safeCall(ctx context.Context, h Handler, p json.RawMessage) (err error) {
	defer func() {
		if rec := recover(); rec != nil {
			err = fmt.Errorf("panic: %v", rec)
		}
	}()
	return h(ctx, p)
}

// Backoff is exponential: 30s, 1m, 2m, 4m … capped at 1h.
func Backoff(attempt int) time.Duration {
	if attempt < 1 {
		attempt = 1
	}
	d := 30 * time.Second << (attempt - 1)
	if d > time.Hour || d <= 0 {
		d = time.Hour
	}
	return d
}

// Retry puts a dead job back in the queue (admin action).
func Retry(ctx context.Context, db *database.DB, id string) error {
	tag, err := db.Exec(ctx, `UPDATE jobs SET status='queued', attempts=0, run_at=now(), last_error=NULL, finished_at=NULL WHERE id=$1 AND status IN ('dead','failed')`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errors.New("job not retryable")
	}
	return nil
}

func truncate(s string, n int) string {
	if len(s) > n {
		return s[:n]
	}
	return s
}
