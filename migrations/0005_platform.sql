-- Platform settings, audit log, legal versions, content blocks, durable jobs/outbox.
CREATE TABLE platform_settings (
    key        text PRIMARY KEY,
    value      jsonb NOT NULL,
    is_public  boolean NOT NULL DEFAULT false,
    updated_by uuid REFERENCES users(id),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE audit_logs (
    id          bigserial PRIMARY KEY,
    actor_id    uuid REFERENCES users(id) ON DELETE SET NULL,
    actor_roles text[] NOT NULL DEFAULT '{}',
    action      text NOT NULL,
    entity_type text NOT NULL DEFAULT '',
    entity_id   text NOT NULL DEFAULT '',
    metadata    jsonb NOT NULL DEFAULT '{}'::jsonb,
    ip          text NOT NULL DEFAULT '',
    request_id  text NOT NULL DEFAULT '',
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_logs_created_idx ON audit_logs (created_at DESC);
CREATE INDEX audit_logs_actor_idx ON audit_logs (actor_id, created_at DESC);
CREATE INDEX audit_logs_action_idx ON audit_logs (action, created_at DESC);
CREATE INDEX audit_logs_entity_idx ON audit_logs (entity_type, entity_id);

CREATE TABLE legal_policy_versions (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    slug         text NOT NULL CHECK (slug IN ('privacy','terms','refund-policy','seller-policy','safety')),
    version      integer NOT NULL CHECK (version > 0),
    title        text NOT NULL,
    body_md      text NOT NULL,
    is_current   boolean NOT NULL DEFAULT false,
    published_at timestamptz,
    created_by   uuid REFERENCES users(id),
    created_at   timestamptz NOT NULL DEFAULT now(),
    UNIQUE (slug, version)
);
CREATE UNIQUE INDEX legal_one_current ON legal_policy_versions (slug) WHERE is_current;

CREATE TABLE content_blocks (
    key        text PRIMARY KEY,   -- e.g. home.hero, faq
    data       jsonb NOT NULL,
    updated_by uuid REFERENCES users(id),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Durable job queue. Rows are inserted in the SAME transaction as the business change (transactional outbox);
-- workers claim with FOR UPDATE SKIP LOCKED. Redis is only a wake-up hint, never the source of truth.
CREATE TABLE jobs (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    kind         text NOT NULL,
    payload      jsonb NOT NULL DEFAULT '{}'::jsonb,
    status       text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','running','succeeded','failed','dead')),
    attempts     integer NOT NULL DEFAULT 0,
    max_attempts integer NOT NULL DEFAULT 8,
    run_at       timestamptz NOT NULL DEFAULT now(),
    locked_at    timestamptz,
    locked_by    text,
    dedupe_key   text UNIQUE,
    last_error   text,
    created_at   timestamptz NOT NULL DEFAULT now(),
    finished_at  timestamptz
);
CREATE INDEX jobs_claim_idx ON jobs (run_at) WHERE status IN ('queued','failed');
CREATE INDEX jobs_status_idx ON jobs (status, created_at DESC);
