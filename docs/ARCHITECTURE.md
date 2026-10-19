# PETORA architecture

## Overview

```
                 Internet (HTTPS :443)
                        │
                ┌───────▼────────┐   edge network
                │  Caddy (proxy) │   automatic TLS, HSTS, gzip/zstd, 12 MB body cap
                └───────┬────────┘
     backend network (internal: no internet egress)
        ┌───────────────┼──────────────────────────────┐
┌───────▼────────┐ ┌────▼─────┐  ┌──────────┐  ┌───────▼───────┐
│ web-api (Go)   │ │ worker   │  │ postgres │  │ redis         │
│ /api/v1, SPA,  │ │ (Go)     │  │ 16       │  │ cache, rate   │
│ /media         │ │ jobs +   │  │ source of│  │ limits, job   │
└───────┬────────┘ │ scheduler│  │ truth    │  │ wake-ups      │
        │          └────┬─────┘  └──────────┘  └───────────────┘
        └── object storage: local volume or S3-compatible (public + private buckets)
```

* **One domain.** `https://petora.in` serves the React SPA, `/api/v1/*` and `/media/*` from the same Go binary (`cmd/api`). No separate web server is needed: Go serves `frontend/dist` with SPA fallback and immutable caching for hashed `/assets/*`. That's why there is no `Dockerfile.web`: the frontend is compiled inside the main `Dockerfile`.
* **One worker binary** (`cmd/worker`) runs the durable job queue and the periodic scheduler. Set `WORKER_INLINE=true` to run it inside the API process for single-container hosting.
* **The Android app** (Flutter, `mobile/`) and the web app use the same `/api/v1` contract (`docs/openapi.yaml`). A contract test (`tests/integration/contract_test.go`) fails if routes and spec diverge.

## Repository layout

| Path | Purpose |
|---|---|
| `cmd/api` | HTTP server + `migrate`, `setup`, `seed [--demo]`, `create-admin`, `healthcheck` subcommands |
| `cmd/worker` | Background job runner + scheduler |
| `internal/config` | Environment configuration and production guard-rails (e.g. test-mode payments refused in production) |
| `internal/httpx` | Response envelope, typed API errors, strict JSON decoding, validation, pagination |
| `internal/middleware` | Request ID, real IP, logging, panic recovery, security headers, CORS, origin check, CSRF, authentication, RBAC, rate limiting, maintenance mode |
| `internal/auth` | Registration, login, rotating refresh sessions, email verification, password reset, TOTP MFA, account deletion |
| `internal/authctx` | The authenticated principal (roles + permissions) in request context |
| `internal/catalog` | Categories and breeds (with jurisdiction rules) |
| `internal/sellers` | Seller profiles, verification workflow, private documents |
| `internal/listings` | Search, detail, owner workflow, images, favourites, views, analytics, moderation approval |
| `internal/subscriptions` | Plans, entitlements, activation, renewal, upgrades, grace, expiry, reminders |
| `internal/payments` | Provider abstraction (Razorpay, test mode), checkout, verification, webhooks, refunds, invoices, reconciliation |
| `internal/enquiries` | Contact unlock, enquiry threads, blocks, reports, disputes, buyer/seller dashboards |
| `internal/admin` | Administration API (dashboard, users/staff/roles, moderation, finance, reports, settings, CMS, audit, jobs) |
| `internal/notifications` | In-app notifications, email templates (admin-overridable), email job handler |
| `internal/jobs` | Durable Postgres queue / transactional outbox |
| `internal/storage`, `internal/media` | Object storage drivers; upload sniffing, decompression-bomb limits, EXIF-stripping re-encode, variants |
| `internal/audit`, `internal/settings`, `internal/cache`, `internal/security`, `internal/mail` | Cross-cutting services |
| `internal/seed` | Idempotent reference data; demo data (refused in production) |
| `migrations/` | Versioned SQL, applied by the embedded migrator under an advisory lock |
| `frontend/` | React + TypeScript + Vite + Tailwind web app (public site, buyer/seller portals, admin portal) |
| `mobile/` | Flutter Android app (buyer + seller) |
| `deployments/` | Caddyfile, Postgres role bootstrap, backup/restore scripts, backup image |
| `tests/integration` | End-to-end API tests against real Postgres (+ Redis) |

## Request lifecycle

`RequestID → RealIP → Logger → Recoverer → SecurityHeaders → (API) CORS → OriginCheck → Authenticate → CSRF → Maintenance → RateLimit → route guards (RequireAuth / RequireAccountType / RequireStaffMFA / RequirePerm / RequireVerifiedEmail) → handler → service → SQL`

* Handlers decode strictly: unknown JSON fields are rejected, which also prevents mass assignment. Bodies are capped at 1 MiB, and uploads have explicit caps.
* Services enforce business rules. Prices, entitlements, roles and payment states are always computed or looked up server-side.
* Every SQL statement is parameterised. Dynamic search SQL is assembled from fixed fragments with positional arguments (`listings.qb`).
* Errors map to stable codes. Unknown errors become a generic `500 internal_error` with the request ID, and details are logged, never returned.

## Authentication strategy

There is one scheme with two transports, documented in `internal/auth/service.go` and in the OpenAPI description.

* Access token: an HS256 JWT valid for 15 minutes, bound to a server-side `sessions` row. **Every request revalidates the session and user status in Postgres**, so logout, suspension, password changes and role changes take effect immediately.
* Refresh token: 32 random bytes, stored only as a SHA-256 hash, rotated in place on every use. Replaying a rotated token outside a 10-second race window revokes the session (theft detection).
* Web: HttpOnly cookies (`petora_at` with `SameSite=Lax`; `petora_rt` with path `/api/v1/auth` and `SameSite=Strict`), a readable `petora_csrf` cookie with double-submit `X-CSRF-Token`, and an `Origin` allow-list for unsafe methods.
* Mobile: `X-Client: mobile` makes tokens come back in JSON. The app stores them in Android Keystore-backed secure storage and refreshes single-flight.
* Staff must enrol TOTP MFA. `/admin/*` requires an MFA-verified session. MFA seeds are AES-256-GCM encrypted at rest.
* Brute-force controls: per-IP rate limits (Redis) plus a per-account lock of 15 minutes after 5 failures (Postgres). Unknown emails get a dummy password hash so timing doesn't reveal which accounts exist.

## Authorisation model

| Actor | Mechanism |
|---|---|
| Public visitor | Only `PublicPredicate` data: approved, available listings from active, non-suspended sellers with a live seller subscription |
| Buyer | `account_type = buyer`; contact and enquiries also need a live buyer subscription with remaining allowance |
| Seller | `account_type = seller`; ownership is checked on every listing, document and enquiry query (`sp.user_id = $principal`) |
| Moderator / Finance / Support / Super admin | Staff roles → permissions (`role_permissions`); every admin route declares one permission |

Insecure direct object reference (IDOR) protection is structural. Owner and party filters are part of the SQL `WHERE` clause, and a missing row returns `404`, so responses never reveal whether a resource exists.

## Money, subscriptions and payments

* Money is `bigint` minor units plus a `char(3)` currency. Tax is computed as `(price × bps + 5000) / 10000` using integer arithmetic only.
* Checkout snapshots the plan (price, tax, interval, entitlements) on the payment. Activation uses the snapshot, so later admin edits never change what a customer bought.
* **Finalisation happens in one place:** `payments.finalizeSuccess`. It runs one transaction holding a `FOR UPDATE` lock on the payment row, and does four things: verifies the amount, creates the invoice (financial-year numbering), activates the subscription, and audits. The unique index on `subscriptions.payment_id` together with the payment status check make it idempotent. Verify, webhook and reconciliation paths all converge here.
* **One live subscription per user per audience** is enforced by a partial unique index. Buying the same plan mid-term returns `409 already_subscribed`. Renewal is only allowed within the renewal window and extends the term seamlessly. A different plan supersedes the current one: an immediate upgrade or downgrade, with no proration.
* Webhooks: the signature is checked over the raw body. The normalised event is stored once (`UNIQUE(provider, event_id)`) and a `webhook.process` job is enqueued in the same transaction (outbox). The event is also processed inline, and is safe to repeat.
* Ambiguous provider responses (timeouts, authorised-but-not-captured) leave the payment `pending`. Reconciliation every 10 minutes asks the provider about stale orders, and abandoned orders are cancelled after 24 hours.
* Refunds reserve the amount inside a locked transaction, so concurrent refunds can't exceed the payment, and then call the provider. A definitive rejection releases the reservation. A full refund ends the subscription it bought.

## Entitlement policies (configurable in Admin → Settings)

| Setting | Default | Behaviour |
|---|---|---|
| `listings.on_subscription_expiry` | `unpublish` | When a seller's subscription leaves grace, approved listings become `expired` (reason `subscription`) and leave search. They're restored automatically on renewal if still within their own listing period. `keep` leaves them live until their own expiry. |
| `contacts.retain_after_expiry` | `true` | Contacts a buyer already unlocked remain viewable after the membership expires. New unlocks always require a live membership with remaining allowance. With `false`, previously unlocked contacts need an active membership again; re-unlocking them doesn't consume allowance. |
| Plan `grace_days` | per plan | Seller listings stay visible during grace. |
| `listings.expiry_days` | 60 | Listing validity after approval. |
| `listings.auto_approve` | `false` | Only applies to verified sellers whose listing raised no automatic flags. |
| `reports.auto_suspend_threshold` | 5 | Distinct open reports that hide a listing pending review. |

Listing allowance counts the seller's live listings: `draft`, `pending`, `approved`, `rejected` and `suspended`, while still available or reserved. Sold, unavailable, expired and archived listings free a slot.

## Background processing

* `jobs` is both queue and outbox. Producers insert rows in the same transaction as the business change. Workers claim with `FOR UPDATE SKIP LOCKED` and retry with exponential backoff (30 s → 1 h). Jobs dead-letter after `max_attempts`, and admins can inspect and retry them in Admin → Jobs. Jobs lost by a crashed worker are reclaimed after 5 minutes. Delivered email payloads are redacted because they may contain one-time codes.
* The scheduler enqueues periodic jobs keyed by time bucket (`dedupe_key`), so any number of worker replicas produce exactly one run per period:

| Job | Period | What it does |
|---|---|---|
| `subscriptions.sweep` | 1 min | active → grace → expired, plus the listing policy |
| `listings.expire` | 10 min | expires listings past their listing period |
| `payments.reconcile` | 10 min | settles stale open payments with the provider |
| `reminders.renewal` | 1 h | renewal reminders 7, 3 and 1 days before expiry, deduplicated |
| `cleanup.daily` | 24 h | purges expired documents, codes, sessions, old jobs, views and read notifications |

* Redis is only a wake-up hint (pub/sub), a cache and a rate-limit store. If Redis is down, the API keeps working: the cache misses, rate limits fail open, and workers poll every 3 seconds.

## Caching and invalidation

| Key | TTL | Invalidated by |
|---|---|---|
| `pets:list:<hash>` (anonymous search pages) | 60 s | any visibility change: approve/reject/suspend, edits, availability, images, subscription activation/expiry/refund, seller suspension, settings change (`pets:` prefix) |
| `catalog:public` | 2 min | category/breed admin changes, seed |
| `plans:<audience>` | 5 min | plan create/update |
| settings (in-process) | 10 s | local drop on write; other replicas converge within 10 s |

Entitlement checks never use the cache. They always read the `subscriptions` row, locked when consuming allowance.

## Data model highlights

* 41 tables across 6 migrations. All primary keys are UUIDs except the append-only `audit_logs` and `listing_views` tables. Every timestamp is `timestamptz`, and sessions run with `timezone=UTC` and a 15 s statement timeout.
* Integrity is enforced in the database, not just in the application:
  * `CHECK` constraints on every status column;
  * `amount = subtotal + tax` and `refunded ≤ amount`;
  * partial unique indexes: one live subscription per user per audience, one cover image per listing, one pending verification per seller, deduplicated open reports.
* `pet_listings.search_vector` is a generated `tsvector` with a GIN index and a trigram index on the title. Partial indexes on `status='approved' AND deleted_at IS NULL` support category, breed, price, geo and city filters.
* Deletion: listings are archived (soft-deleted) and excluded by `PublicPredicate`. Account deletion anonymises personal data immediately and keeps financial records. Rejected verification documents are purged after 90 days.
