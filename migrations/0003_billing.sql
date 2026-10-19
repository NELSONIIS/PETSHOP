-- Plans, subscriptions, payments, refunds, invoices. Money is integer minor units + currency.
CREATE TABLE subscription_plans (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code               text NOT NULL UNIQUE,
    audience           text NOT NULL CHECK (audience IN ('buyer','seller')),
    name               text NOT NULL,
    description        text NOT NULL DEFAULT '',
    price_minor        bigint NOT NULL CHECK (price_minor >= 0),   -- tax-exclusive
    currency           char(3) NOT NULL DEFAULT 'INR',
    promo_price_minor  bigint CHECK (promo_price_minor IS NULL OR promo_price_minor >= 0),
    promo_starts_at    timestamptz,
    promo_ends_at      timestamptz,
    billing_interval   text NOT NULL CHECK (billing_interval IN ('month','quarter','year')),
    interval_count     integer NOT NULL DEFAULT 1 CHECK (interval_count BETWEEN 1 AND 36),
    tax_rate_bps       integer NOT NULL DEFAULT 0 CHECK (tax_rate_bps BETWEEN 0 AND 10000),
    trial_days         integer NOT NULL DEFAULT 0 CHECK (trial_days >= 0),
    grace_days         integer NOT NULL DEFAULT 0 CHECK (grace_days >= 0),
    renewal_window_days integer NOT NULL DEFAULT 7 CHECK (renewal_window_days >= 0),
    auto_renew         boolean NOT NULL DEFAULT false,  -- no stored-mandate charging; reminders only
    cancellation_policy text NOT NULL DEFAULT 'end_of_period' CHECK (cancellation_policy IN ('end_of_period','immediate')),
    refund_window_days integer NOT NULL DEFAULT 0 CHECK (refund_window_days >= 0),
    refund_policy      text NOT NULL DEFAULT '',
    is_active          boolean NOT NULL DEFAULT true,
    sort_order         integer NOT NULL DEFAULT 0,
    features           jsonb NOT NULL DEFAULT '[]'::jsonb,  -- marketing bullet list
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now()
);

-- Feature entitlements. NULL int_value = unlimited for numeric keys.
-- Keys: listing_limit, contact_unlocks, enquiries, analytics, featured_slots.
CREATE TABLE plan_entitlements (
    plan_id    uuid NOT NULL REFERENCES subscription_plans(id) ON DELETE CASCADE,
    key        text NOT NULL CHECK (key IN ('listing_limit','contact_unlocks','enquiries','analytics','featured_slots')),
    int_value  integer CHECK (int_value IS NULL OR int_value >= 0),
    bool_value boolean,
    PRIMARY KEY (plan_id, key)
);

CREATE TABLE payments (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL REFERENCES users(id),
    plan_id             uuid NOT NULL REFERENCES subscription_plans(id),
    provider            text NOT NULL,
    provider_order_id   text,
    provider_payment_id text,
    status              text NOT NULL DEFAULT 'created'
        CHECK (status IN ('created','pending','succeeded','failed','cancelled','refunded','partially_refunded')),
    subtotal_minor      bigint NOT NULL CHECK (subtotal_minor >= 0),
    tax_minor           bigint NOT NULL CHECK (tax_minor >= 0),
    amount_minor        bigint NOT NULL CHECK (amount_minor >= 0),
    refunded_minor      bigint NOT NULL DEFAULT 0 CHECK (refunded_minor >= 0),
    currency            char(3) NOT NULL,
    idempotency_key     text NOT NULL,
    failure_reason      text,
    plan_snapshot       jsonb NOT NULL DEFAULT '{}'::jsonb,
    subscription_id     uuid,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    paid_at             timestamptz,
    CHECK (amount_minor = subtotal_minor + tax_minor),
    CHECK (refunded_minor <= amount_minor),
    UNIQUE (user_id, idempotency_key)
);
CREATE UNIQUE INDEX payments_provider_order_idx ON payments (provider, provider_order_id) WHERE provider_order_id IS NOT NULL;
CREATE UNIQUE INDEX payments_provider_payment_idx ON payments (provider, provider_payment_id) WHERE provider_payment_id IS NOT NULL;
CREATE INDEX payments_user_idx ON payments (user_id, created_at DESC);
CREATE INDEX payments_status_idx ON payments (status, created_at DESC);

CREATE TABLE subscriptions (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL REFERENCES users(id),
    plan_id             uuid NOT NULL REFERENCES subscription_plans(id),
    audience            text NOT NULL CHECK (audience IN ('buyer','seller')),
    status              text NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','grace','expired','cancelled','superseded','refunded')),
    starts_at           timestamptz NOT NULL,
    current_period_end  timestamptz NOT NULL,
    grace_ends_at       timestamptz NOT NULL,
    cancel_at_period_end boolean NOT NULL DEFAULT false,
    cancelled_at        timestamptz,
    entitlements        jsonb NOT NULL DEFAULT '{}'::jsonb,  -- snapshot at activation
    contact_unlocks_used integer NOT NULL DEFAULT 0,
    enquiries_used      integer NOT NULL DEFAULT 0,
    payment_id          uuid REFERENCES payments(id),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);
-- One live subscription per user per audience: the same entitlement cannot be bought twice.
CREATE UNIQUE INDEX subscriptions_one_live ON subscriptions (user_id, audience) WHERE status IN ('active','grace');
CREATE UNIQUE INDEX subscriptions_payment_unique ON subscriptions (payment_id) WHERE payment_id IS NOT NULL;
CREATE INDEX subscriptions_expiry_idx ON subscriptions (current_period_end) WHERE status IN ('active','grace');
ALTER TABLE payments ADD CONSTRAINT payments_subscription_fk FOREIGN KEY (subscription_id) REFERENCES subscriptions(id);

CREATE TABLE payment_webhook_events (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider        text NOT NULL,
    event_id        text NOT NULL,
    event_type      text NOT NULL,
    payload         jsonb NOT NULL,
    status          text NOT NULL DEFAULT 'received' CHECK (status IN ('received','processed','failed','ignored')),
    attempts        integer NOT NULL DEFAULT 0,
    error           text,
    received_at     timestamptz NOT NULL DEFAULT now(),
    processed_at    timestamptz,
    UNIQUE (provider, event_id)
);

CREATE TABLE refunds (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id         uuid NOT NULL REFERENCES payments(id),
    amount_minor       bigint NOT NULL CHECK (amount_minor > 0),
    reason             text NOT NULL,
    status             text NOT NULL DEFAULT 'requested' CHECK (status IN ('requested','processing','succeeded','failed')),
    provider_refund_id text,
    idempotency_key    text NOT NULL UNIQUE,
    requested_by       uuid NOT NULL REFERENCES users(id),
    failure_reason     text,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX refunds_payment_idx ON refunds (payment_id);

CREATE SEQUENCE invoice_number_seq START 1;
CREATE TABLE invoices (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    number        text NOT NULL UNIQUE,
    payment_id    uuid NOT NULL UNIQUE REFERENCES payments(id),
    user_id       uuid NOT NULL REFERENCES users(id),
    bill_to_name  text NOT NULL,
    bill_to_email text NOT NULL,
    lines         jsonb NOT NULL,
    subtotal_minor bigint NOT NULL,
    tax_minor     bigint NOT NULL,
    total_minor   bigint NOT NULL,
    currency      char(3) NOT NULL,
    issued_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX invoices_user_idx ON invoices (user_id, issued_at DESC);
