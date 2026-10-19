-- Identity, RBAC, sessions, one-time codes.
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE roles (
    code        text PRIMARY KEY,
    name        text NOT NULL,
    is_staff    boolean NOT NULL DEFAULT false,
    description text NOT NULL DEFAULT ''
);

CREATE TABLE permissions (
    code        text PRIMARY KEY,
    description text NOT NULL
);

CREATE TABLE role_permissions (
    role_code       text NOT NULL REFERENCES roles(code) ON DELETE CASCADE,
    permission_code text NOT NULL REFERENCES permissions(code) ON DELETE CASCADE,
    PRIMARY KEY (role_code, permission_code)
);

CREATE TABLE users (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email                 citext NOT NULL UNIQUE,
    phone                 text UNIQUE,
    name                  text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 120),
    password_hash         text NOT NULL,
    account_type          text NOT NULL CHECK (account_type IN ('buyer','seller','staff')),
    status                text NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','deleted')),
    email_verified_at     timestamptz,
    phone_verified_at     timestamptz,
    avatar_url            text,
    mfa_secret_enc        text,
    mfa_enabled_at        timestamptz,
    failed_login_count    integer NOT NULL DEFAULT 0,
    locked_until          timestamptz,
    last_login_at         timestamptz,
    suspended_reason      text,
    deletion_requested_at timestamptz,
    deleted_at            timestamptz,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX users_account_type_idx ON users (account_type, status);
CREATE INDEX users_created_idx ON users (created_at DESC);

CREATE TABLE user_roles (
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_code  text NOT NULL REFERENCES roles(code),
    granted_by uuid REFERENCES users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, role_code)
);

-- Refresh-token sessions. The refresh token rotates in place on every use; the previous hash is kept
-- so that replay of an already-rotated token (theft indicator) revokes the whole session.
CREATE TABLE sessions (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    refresh_hash      bytea NOT NULL UNIQUE,
    prev_refresh_hash bytea,
    rotated_at        timestamptz,
    client            text NOT NULL DEFAULT 'web' CHECK (client IN ('web','mobile')),
    mfa_verified      boolean NOT NULL DEFAULT false,
    user_agent        text NOT NULL DEFAULT '',
    ip                text NOT NULL DEFAULT '',
    created_at        timestamptz NOT NULL DEFAULT now(),
    last_used_at      timestamptz NOT NULL DEFAULT now(),
    expires_at        timestamptz NOT NULL,
    revoked_at        timestamptz
);
CREATE INDEX sessions_user_idx ON sessions (user_id) WHERE revoked_at IS NULL;
CREATE INDEX sessions_prev_idx ON sessions (prev_refresh_hash) WHERE prev_refresh_hash IS NOT NULL;

CREATE TABLE one_time_codes (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    purpose     text NOT NULL CHECK (purpose IN ('email_verify','phone_verify','password_reset')),
    code_hash   bytea NOT NULL,
    attempts    integer NOT NULL DEFAULT 0,
    expires_at  timestamptz NOT NULL,
    consumed_at timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX one_time_codes_lookup_idx ON one_time_codes (user_id, purpose, created_at DESC);

CREATE TABLE buyer_profiles (
    user_id       uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    city          text NOT NULL DEFAULT '',
    state         text NOT NULL DEFAULT '',
    lat           double precision,
    lng           double precision,
    radius_km     integer NOT NULL DEFAULT 50 CHECK (radius_km BETWEEN 1 AND 1000),
    notify_email  boolean NOT NULL DEFAULT true,
    notify_sms    boolean NOT NULL DEFAULT false,
    notify_push   boolean NOT NULL DEFAULT true,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE user_blocks (
    blocker_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (blocker_id, blocked_id),
    CHECK (blocker_id <> blocked_id)
);
