-- Sellers, verification, catalogue and listings.
CREATE TABLE seller_profiles (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    slug                text NOT NULL UNIQUE,
    display_name        text NOT NULL,
    seller_type         text NOT NULL DEFAULT 'individual' CHECK (seller_type IN ('individual','business')),
    business_name       text,
    gst_number          text,
    bio                 text NOT NULL DEFAULT '',
    city                text NOT NULL DEFAULT '',
    state               text NOT NULL DEFAULT '',
    lat                 double precision,
    lng                 double precision,
    -- Contact details are PRIVATE: only returned by the authorised contact-unlock endpoint.
    contact_phone       text,
    contact_whatsapp    text,
    contact_email       text,
    logo_url            text,
    verification_status text NOT NULL DEFAULT 'unsubmitted'
        CHECK (verification_status IN ('unsubmitted','pending','approved','rejected','suspended')),
    verified_at         timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX seller_profiles_verif_idx ON seller_profiles (verification_status);

CREATE TABLE seller_verifications (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_id     uuid NOT NULL REFERENCES seller_profiles(id) ON DELETE CASCADE,
    status        text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','withdrawn')),
    jurisdiction_state text NOT NULL DEFAULT '',
    submitted_at  timestamptz NOT NULL DEFAULT now(),
    reviewed_by   uuid REFERENCES users(id),
    reviewed_at   timestamptz,
    reason        text,
    notes         text
);
CREATE INDEX seller_verifications_status_idx ON seller_verifications (status, submitted_at);
CREATE UNIQUE INDEX seller_verifications_one_pending ON seller_verifications (seller_id) WHERE status = 'pending';

-- Verification documents live in PRIVATE object storage; only the key is stored here.
CREATE TABLE seller_documents (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_id      uuid NOT NULL REFERENCES seller_profiles(id) ON DELETE CASCADE,
    kind           text NOT NULL CHECK (kind IN ('identity','business_registration','trade_licence','breeder_registration','address_proof','other')),
    storage_key    text NOT NULL UNIQUE,
    original_name  text NOT NULL,
    mime_type      text NOT NULL,
    size_bytes     bigint NOT NULL CHECK (size_bytes > 0),
    sha256         text NOT NULL,
    uploaded_at    timestamptz NOT NULL DEFAULT now(),
    retention_until timestamptz,
    deleted_at     timestamptz
);
CREATE INDEX seller_documents_seller_idx ON seller_documents (seller_id) WHERE deleted_at IS NULL;

CREATE TABLE categories (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    slug          text NOT NULL UNIQUE,
    name          text NOT NULL,
    icon          text NOT NULL DEFAULT 'paw',
    description   text NOT NULL DEFAULT '',
    sort_order    integer NOT NULL DEFAULT 0,
    is_active     boolean NOT NULL DEFAULT true,
    -- Jurisdiction rules, e.g. {"IN-MH":{"allowed":true,"requires_verified_seller":true}}.
    jurisdiction_rules jsonb NOT NULL DEFAULT '{}'::jsonb,
    requires_verified_seller boolean NOT NULL DEFAULT false,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE breeds (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id uuid NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
    slug        text NOT NULL,
    name        text NOT NULL,
    is_active   boolean NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (category_id, slug)
);
CREATE INDEX breeds_category_idx ON breeds (category_id) WHERE is_active;

CREATE TABLE pet_listings (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    slug               text NOT NULL UNIQUE,
    seller_id          uuid NOT NULL REFERENCES seller_profiles(id),
    category_id        uuid NOT NULL REFERENCES categories(id),
    breed_id           uuid REFERENCES breeds(id),
    title              text NOT NULL CHECK (char_length(title) BETWEEN 5 AND 140),
    description        text NOT NULL DEFAULT '',
    listing_type       text NOT NULL DEFAULT 'sale' CHECK (listing_type IN ('sale','adoption')),
    price_minor        bigint NOT NULL DEFAULT 0 CHECK (price_minor >= 0),
    currency           char(3) NOT NULL DEFAULT 'INR',
    age_months         integer CHECK (age_months IS NULL OR age_months BETWEEN 0 AND 600),
    gender             text NOT NULL DEFAULT 'unknown' CHECK (gender IN ('male','female','unknown')),
    colour             text NOT NULL DEFAULT '',
    vaccination_status text NOT NULL DEFAULT 'unspecified' CHECK (vaccination_status IN ('unspecified','none','partial','complete')),
    vaccination_notes  text NOT NULL DEFAULT '',
    health_notes       text NOT NULL DEFAULT '',
    dewormed           boolean,
    microchipped       boolean,
    city               text NOT NULL DEFAULT '',
    state              text NOT NULL DEFAULT '',
    lat                double precision,
    lng                double precision,
    availability       text NOT NULL DEFAULT 'available' CHECK (availability IN ('available','reserved','sold','unavailable')),
    status             text NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft','pending','approved','rejected','suspended','expired','archived')),
    rejection_reason   text,
    expired_reason     text,
    published_at       timestamptz,
    expires_at         timestamptz,
    featured_until     timestamptz,
    views_count        integer NOT NULL DEFAULT 0,
    favourites_count   integer NOT NULL DEFAULT 0,
    enquiries_count    integer NOT NULL DEFAULT 0,
    search_vector      tsvector GENERATED ALWAYS AS (
        setweight(to_tsvector('simple', coalesce(title,'')), 'A') ||
        setweight(to_tsvector('simple', coalesce(colour,'') || ' ' || coalesce(city,'')), 'B') ||
        setweight(to_tsvector('simple', coalesce(description,'')), 'C')) STORED,
    deleted_at         timestamptz,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now()
);
-- Public discovery path: approved, undeleted listings.
CREATE INDEX pet_listings_public_idx ON pet_listings (category_id, published_at DESC)
    WHERE status = 'approved' AND deleted_at IS NULL;
CREATE INDEX pet_listings_breed_idx ON pet_listings (breed_id) WHERE status = 'approved' AND deleted_at IS NULL;
CREATE INDEX pet_listings_price_idx ON pet_listings (price_minor) WHERE status = 'approved' AND deleted_at IS NULL;
CREATE INDEX pet_listings_geo_idx ON pet_listings (lat, lng) WHERE status = 'approved' AND deleted_at IS NULL;
CREATE INDEX pet_listings_city_idx ON pet_listings (lower(city)) WHERE status = 'approved' AND deleted_at IS NULL;
CREATE INDEX pet_listings_seller_idx ON pet_listings (seller_id, status);
CREATE INDEX pet_listings_status_idx ON pet_listings (status, updated_at DESC);
CREATE INDEX pet_listings_featured_idx ON pet_listings (featured_until) WHERE featured_until IS NOT NULL;
CREATE INDEX pet_listings_search_idx ON pet_listings USING gin (search_vector);
CREATE INDEX pet_listings_title_trgm ON pet_listings USING gin (title gin_trgm_ops);

CREATE TABLE listing_attributes (
    listing_id uuid NOT NULL REFERENCES pet_listings(id) ON DELETE CASCADE,
    key        text NOT NULL CHECK (key ~ '^[a-z][a-z0-9_]{0,39}$'),
    value      text NOT NULL CHECK (char_length(value) <= 200),
    PRIMARY KEY (listing_id, key)
);

CREATE TABLE listing_images (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id  uuid NOT NULL REFERENCES pet_listings(id) ON DELETE CASCADE,
    storage_key text NOT NULL UNIQUE,
    variants    jsonb NOT NULL DEFAULT '{}'::jsonb, -- {"thumb":key,"medium":key,"large":key}
    width       integer NOT NULL,
    height      integer NOT NULL,
    position    integer NOT NULL DEFAULT 0,
    is_cover    boolean NOT NULL DEFAULT false,
    alt_text    text NOT NULL DEFAULT '',
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX listing_images_listing_idx ON listing_images (listing_id, position);
CREATE UNIQUE INDEX listing_images_one_cover ON listing_images (listing_id) WHERE is_cover;

CREATE TABLE listing_moderation (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id   uuid NOT NULL REFERENCES pet_listings(id) ON DELETE CASCADE,
    action       text NOT NULL CHECK (action IN ('submitted','approved','rejected','suspended','reinstated','auto_flagged','expired')),
    moderator_id uuid REFERENCES users(id),
    reason       text,
    flags        jsonb NOT NULL DEFAULT '[]'::jsonb,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX listing_moderation_listing_idx ON listing_moderation (listing_id, created_at DESC);

CREATE TABLE favourites (
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    listing_id uuid NOT NULL REFERENCES pet_listings(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, listing_id)
);
CREATE INDEX favourites_listing_idx ON favourites (listing_id);

CREATE TABLE listing_views (
    id         bigserial PRIMARY KEY,
    listing_id uuid NOT NULL REFERENCES pet_listings(id) ON DELETE CASCADE,
    viewer_id  uuid REFERENCES users(id) ON DELETE SET NULL,
    visitor_hash text NOT NULL DEFAULT '',
    viewed_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX listing_views_listing_idx ON listing_views (listing_id, viewed_at DESC);
CREATE INDEX listing_views_viewer_idx ON listing_views (viewer_id, viewed_at DESC) WHERE viewer_id IS NOT NULL;
