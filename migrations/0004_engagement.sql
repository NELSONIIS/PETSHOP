-- Enquiries, conversations, contact unlocks, notifications, reports, disputes.
CREATE TABLE contact_unlocks (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    buyer_id        uuid NOT NULL REFERENCES users(id),
    listing_id      uuid NOT NULL REFERENCES pet_listings(id),
    seller_id       uuid NOT NULL REFERENCES seller_profiles(id),
    subscription_id uuid NOT NULL REFERENCES subscriptions(id),
    created_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (buyer_id, listing_id)
);
CREATE INDEX contact_unlocks_subscription_idx ON contact_unlocks (subscription_id);

CREATE TABLE enquiries (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    buyer_id           uuid NOT NULL REFERENCES users(id),
    seller_id          uuid NOT NULL REFERENCES seller_profiles(id),
    listing_id         uuid NOT NULL REFERENCES pet_listings(id),
    status             text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','viewed','responded','closed','reported')),
    contact_unlock_id  uuid REFERENCES contact_unlocks(id),
    buyer_unread       integer NOT NULL DEFAULT 0,
    seller_unread      integer NOT NULL DEFAULT 0,
    last_message_at    timestamptz NOT NULL DEFAULT now(),
    viewed_at          timestamptz,
    first_response_at  timestamptz,
    closed_at          timestamptz,
    created_at         timestamptz NOT NULL DEFAULT now(),
    UNIQUE (buyer_id, listing_id)  -- duplicate-enquiry detection: one thread per buyer per listing
);
CREATE INDEX enquiries_buyer_idx ON enquiries (buyer_id, last_message_at DESC);
CREATE INDEX enquiries_seller_idx ON enquiries (seller_id, last_message_at DESC);
CREATE INDEX enquiries_status_idx ON enquiries (status);

CREATE TABLE conversations (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    enquiry_id  uuid NOT NULL UNIQUE REFERENCES enquiries(id) ON DELETE CASCADE,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE messages (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id       uuid NOT NULL REFERENCES users(id),
    body            text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 2000),
    created_at      timestamptz NOT NULL DEFAULT now(),
    read_at         timestamptz
);
CREATE INDEX messages_conv_idx ON messages (conversation_id, created_at);

CREATE TABLE notifications (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind       text NOT NULL,
    title      text NOT NULL,
    body       text NOT NULL DEFAULT '',
    data       jsonb NOT NULL DEFAULT '{}'::jsonb,
    read_at    timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX notifications_user_idx ON notifications (user_id, created_at DESC);
CREATE INDEX notifications_unread_idx ON notifications (user_id) WHERE read_at IS NULL;

CREATE TABLE notification_templates (
    key        text NOT NULL,
    channel    text NOT NULL CHECK (channel IN ('in_app','email','sms')),
    subject    text NOT NULL DEFAULT '',
    body       text NOT NULL,
    is_active  boolean NOT NULL DEFAULT true,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (key, channel)
);

CREATE TABLE reports (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id  uuid NOT NULL REFERENCES users(id),
    target_type  text NOT NULL CHECK (target_type IN ('listing','user','enquiry','seller')),
    target_id    uuid NOT NULL,
    reason       text NOT NULL CHECK (reason IN ('spam','scam','prohibited','misleading','animal_welfare','abuse','other')),
    details      text NOT NULL DEFAULT '',
    status       text NOT NULL DEFAULT 'open' CHECK (status IN ('open','reviewing','resolved','dismissed')),
    resolution   text,
    resolved_by  uuid REFERENCES users(id),
    resolved_at  timestamptz,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX reports_status_idx ON reports (status, created_at DESC);
CREATE INDEX reports_target_idx ON reports (target_type, target_id);
CREATE UNIQUE INDEX reports_dedupe ON reports (reporter_id, target_type, target_id) WHERE status IN ('open','reviewing');

CREATE TABLE disputes (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    opened_by    uuid NOT NULL REFERENCES users(id),
    kind         text NOT NULL CHECK (kind IN ('listing_appeal','payment','conduct','other')),
    listing_id   uuid REFERENCES pet_listings(id),
    payment_id   uuid REFERENCES payments(id),
    enquiry_id   uuid REFERENCES enquiries(id),
    subject      text NOT NULL,
    message      text NOT NULL,
    status       text NOT NULL DEFAULT 'open' CHECK (status IN ('open','under_review','resolved','rejected')),
    resolution   text,
    resolved_by  uuid REFERENCES users(id),
    resolved_at  timestamptz,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX disputes_status_idx ON disputes (status, created_at DESC);
CREATE INDEX disputes_user_idx ON disputes (opened_by, created_at DESC);
