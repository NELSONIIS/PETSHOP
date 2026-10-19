# Security checklist

✅ = implemented and covered by an automated test · ☑ = implemented, not automatically tested · ⚠ = operator action required

## Application
| Control | Status | Where / test |
|---|---|---|
| Server-side validation on every input; strict JSON (unknown fields rejected, 1 MiB cap) | ✅ | `httpx.Decode`, `httpx_test.go` |
| Parameterised SQL everywhere (no string-built values) | ✅ | hostile search query test in `TestSearchFilters` |
| Password hashing: argon2id (64 MiB, t=2), per-hash salt | ✅ | `security_test.go` |
| Login brute-force: IP rate limit + 15 min account lock after 5 failures; timing-safe unknown-user path | ✅ | `TestSessionSecurity`, `TestLoginRateLimit` |
| Refresh-token rotation + replay detection → session revoked | ✅ | `TestSessionSecurity` |
| Immediate revocation (logout, suspension, password/role change) — sessions checked on every request | ✅ | `TestSuspensionHidesContent`, `TestSessionSecurity` |
| HttpOnly/Secure/SameSite cookies; CSRF double-submit; Origin allow-list | ✅ | `TestSessionSecurity` |
| Staff MFA (TOTP, RFC 6238) required for `/admin/*`; secrets AES-256-GCM encrypted at rest | ✅ | `TestAdminPermissions`, RFC vector test |
| RBAC with explicit permission per admin route; refunds/settings/roles gated | ✅ | `TestAdminPermissions` |
| Super-admin escalation guards (only super admins grant/remove super_admin; last one cannot be demoted) | ☑ | `admin.SetRoles` |
| IDOR: owner/party filters in SQL, 404 for foreign resources | ✅ | `TestBuyerJourneyAndContactProtection` |
| Seller contact never in listing/seller payloads; only via entitlement-checked unlock | ✅ | same test (payload scanned for phone) |
| Payment success only via provider verification or signed webhook; amount check; idempotent finalisation | ✅ | `TestWebhookIdempotency`, buyer journey |
| Webhook HMAC over raw body; event-id dedupe | ✅ | `TestWebhookIdempotency`, `TestRazorpayEndToEnd`, `payments_test.go` |
| Razorpay: checkout signature + server fetch/capture + amount & currency match; key secret never sent to clients; live keys + fixed API base enforced in production | ✅ | `TestRazorpayEndToEnd`, `config_test.go` |
| Uploads: size caps, magic-byte sniffing, dimension/pixel limits (decompression bombs), re-encode strips EXIF/GPS & polyglots, server-generated keys | ✅ | `media_test.go`, `TestSellerLifecycle` |
| Verification documents in private storage; not reachable via `/media`; staff downloads audited, served as attachment with sandbox CSP | ✅ | `TestSellerLifecycle` |
| Safe errors (no SQL/stack traces to clients), request IDs | ✅ | `TestFailHidesInternalErrors` |
| Security headers: CSP, HSTS, X-Frame-Options DENY, nosniff, Referrer-Policy, Permissions-Policy, COOP | ☑ | `middleware.SecurityHeaders` |
| Rate limits on auth, uploads, enquiries, messages, reports, checkout, support form + daily enquiry cap | ☑ | `router.go` |
| Audit log for logins, failures, locks, MFA, password changes, admin actions, refunds, settings, document views | ✅ (refund) / ☑ | `audit_logs` |
| One-time codes hashed; email outbox payloads redacted after delivery | ✅ | `TestJobRunnerDeliversRetriesAndDeadLetters` |
| No secrets in frontend bundle (only `/config` public values, Razorpay key id) | ☑ | `GET /config` |
| Header-injection-safe mailer | ☑ | `mail.smtpMailer` |
| Account deletion anonymises PII; financial records retained | ☑ | `auth.DeleteAccount` |

## Infrastructure
| Control | Status |
|---|---|
| Only Caddy publishes ports; backend Docker network is `internal` (no egress) | ☑ `docker-compose.yml` |
| TLS via Caddy/ACME, HSTS preload-ready | ☑ |
| Least-privilege DB roles: `petora_owner` (migrations) vs `petora_app` (DML only, 15 s statement timeout) | ✅ verified manually: app role cannot DROP/ALTER/CREATE |
| Distroless non-root runtime image | ☑ `Dockerfile` |
| Redis password-protected, memory-capped, not exposed | ☑ |
| Encrypted backups (age), retention, restore script with overwrite guard | ✅ verified manually |
| Test-mode payments refused in production by config validation | ☑ `config.validate` |

## Operator actions before launch (⚠)
1. Generate unique secrets; keep `.env` mode 600; never commit it (`.gitignore` covers it).
2. Store the `age` backup private key off-server; sync backups off-site; schedule a quarterly restore test.
3. Run `make vuln` (govulncheck) and `npm audit --omit=dev` in CI. **govulncheck could not run in the development sandbox** because `vuln.go.dev` was blocked.
4. Enable 2FA on the hosting, DNS, GitHub and Razorpay accounts; restrict SSH to keys.
5. Configure SMTP with SPF/DKIM/DMARC for the sending domain.
6. If using S3/R2: block public access on the private bucket; use separate, scoped access keys.
7. Penetration test / security review of the payment and contact flows before go-live.
8. Legal review (see `KNOWN_LIMITATIONS.md` → compliance).
