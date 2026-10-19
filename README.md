# PETORA — pet marketplace (web · Android · API)

PETORA is a subscription-based pet marketplace for India.

- **Buyers** browse free and buy a membership to unlock seller contact details and send enquiries.
- **Sellers** verify their identity, subscribe, and publish moderated listings.
- **Staff** run everything from an MFA-protected admin portal.

| Part | Stack | Location |
|---|---|---|
| API + web server + worker | Go 1.26, chi, pgx, PostgreSQL 16, Redis 7 | `cmd/`, `internal/`, `migrations/` |
| Web marketplace, seller & admin portals | React 18, TypeScript, Vite, Tailwind, TanStack Query, RHF + Zod | `frontend/` |
| Android app (buyer + seller) | Flutter, Riverpod, Dio, GoRouter, secure storage | `mobile/` |
| API contract | OpenAPI 3 | `docs/openapi.yaml` |
| Deployment | Docker, Compose, Caddy (HTTPS), encrypted backups | `Dockerfile`, `docker-compose.yml`, `deployments/` |

Documentation:

| Topic | File |
|---|---|
| Architecture | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Design system | [docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md) |
| Screen inventory | [docs/SCREENS.md](docs/SCREENS.md) |
| Deployment | [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) |
| Security | [docs/SECURITY.md](docs/SECURITY.md) |
| Production checklist | [docs/PRODUCTION_CHECKLIST.md](docs/PRODUCTION_CHECKLIST.md) |
| Known limitations | [docs/KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md) |
| Android build | [mobile/README.md](mobile/README.md) |

## Local development

Prerequisites: Go 1.26+, Node 22+, PostgreSQL 16, Redis 7 (or `docker compose -f docker-compose.dev.yml up -d`), and the Flutter stable SDK for the app.

```bash
# 1. configure (example values for the dev compose services)
cat > .env.dev.local <<EOF
APP_ENV=development
APP_BASE_URL=http://localhost:8080
DATABASE_URL=postgres://petora:petora@localhost:5432/petora_dev?sslmode=disable
REDIS_URL=redis://localhost:6379/0
JWT_SECRET=$(openssl rand -base64 48)
DATA_ENCRYPTION_KEY=$(openssl rand -base64 32)
PAYMENT_PROVIDER=testmode
STORAGE_DRIVER=local
STORAGE_LOCAL_PATH=./data/storage
ALLOWED_ORIGINS=http://localhost:8080,http://localhost:5173
EOF

# 2. database + reference data + demo data (demo is refused in production)
make migrate seed-demo        # prints demo staff TOTP secrets; password for all demo users: PetoraDemo2026!

# 3. run
make run                      # API + SPA on :8080
make worker                   # background jobs (emails are logged in development)
cd frontend && npm ci && npm run dev   # Vite on :5173, proxies /api and /media to :8080

# 4. Android (emulator talks to the host via 10.0.2.2)
cd mobile && flutter pub get && flutter run --dart-define=APP_ENV=dev
```

Demo accounts (development only):
- `buyer@demo.petora.test` has no membership, so it shows the locked-contact flow.
- `seller@demo.petora.test` and `rescue@demo.petora.test` are verified sellers.
- `admin@`, `moderator@` and `finance@demo.petora.test` are staff with MFA. Generate a code with `go run ./tools/totp <secret>`.

**Payments use Razorpay.** Production requires Razorpay live keys (`PAYMENT_PROVIDER=razorpay`; see `docs/DEPLOYMENT.md` §4).

Local development without Razorpay keys can use `PAYMENT_PROVIDER=testmode`. The UI then shows a *TEST MODE – no real charge* banner and no real payment is processed. With `rzp_test_` keys, development uses real Razorpay test checkout instead.

## Tests

| Command | What it runs |
|---|---|
| `make test-unit` | Go unit tests: security, pricing, entitlements, payment signatures, media, HTTP helpers |
| `make test-integration` | End-to-end API tests on a real Postgres + Redis; **drops the `TEST_DATABASE_URL` schema** |
| `make lint` | gofmt + go vet |
| `cd frontend && npm run lint && npm run typecheck && npm test && npm run build` | web checks |
| `cd mobile && flutter analyze && flutter test` | Flutter checks |

The integration suite covers the end-to-end scenarios of the brief:

- buyer browse → contact locked → test checkout → server activation → unlock → enquiry → seller reply;
- IDOR protection on enquiries and listings;
- seller verification → subscription → plan limits → moderation → expiry/grace → restoration on renewal;
- contact-retention policy;
- duplicate and forged webhooks;
- refund/configuration RBAC and MFA enforcement;
- refresh-token reuse detection, CSRF and the login rate limit;
- suspension hiding content;
- search filters;
- job retry and dead-letter;
- scheduler dedupe;
- a contract test that the router and `docs/openapi.yaml` match exactly.

## Production

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md). In short: `cp .env.example .env`, fill in the secrets, then `docker compose --profile prod up -d --build`, then `docker compose run --rm web-api create-admin`.

The app refuses to start in production with test-mode payments, plain HTTP or missing secrets.
