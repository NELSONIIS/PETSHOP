# Deploying PETORA

The target is a single Linux VM (4 vCPU, 8 GB RAM, 80 GB SSD is plenty for launch) running Docker Engine 24+ with the Compose plugin. PostgreSQL, Redis and the worker never publish ports; only Caddy listens on 80/443.

> **Not yet verified here:** the Docker images and the full compose stack have not been built or run in the development environment, which had no Docker daemon. `docker compose config` validates. Perform the staging run below before production.

## 1. Server preparation
```bash
# Ubuntu 24.04
sudo apt-get update && sudo apt-get install -y docker.io docker-compose-v2 ufw
sudo ufw allow OpenSSH && sudo ufw allow 80,443/tcp && sudo ufw allow 443/udp && sudo ufw enable
# Make client IPs reach Caddy unmodified (needed for rate limiting & audit IPs):
echo '{ "userland-proxy": false, "log-driver": "json-file", "log-opts": {"max-size":"10m","max-file":"5"} }' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker
```
Point the DNS `A`/`AAAA` records for `petora.in` and `www.petora.in` at the server before first start, so Caddy can obtain certificates.

## 2. Configure
```bash
git clone <repo> /opt/petora && cd /opt/petora
cp .env.example .env && chmod 600 .env
# fill in every secret:
openssl rand -base64 48   # JWT_SECRET
openssl rand -base64 32   # DATA_ENCRYPTION_KEY (must decode to 32 bytes)
openssl rand -hex 24      # POSTGRES_*_PASSWORD, REDIS_PASSWORD (hex avoids URL-escaping issues)
age-keygen -o backup.key  # put the public key in BACKUP_AGE_RECIPIENT; move backup.key OFF the server
```
The application refuses to start in production in these cases:
* `PAYMENT_PROVIDER=testmode`;
* `APP_BASE_URL` is not `https`;
* `REDIS_URL` or any required secret is missing.

## 3. First start
```bash
docker compose --profile prod build
docker compose --profile prod up -d          # migrate job runs first: migrations + reference data
docker compose ps                            # web-api healthy, migrate exited 0
docker compose logs -f web-api worker
# Bootstrap the first super administrator (MFA is enrolled at first login in /admin):
docker compose run --rm -e ADMIN_EMAIL=you@petora.in -e ADMIN_NAME="Your Name" -e ADMIN_PASSWORD='<long passphrase>' web-api create-admin
```
Then, in the admin portal:
1. Enable MFA.
2. Review the legal pages under Content → Legal. They are templates and must be approved by counsel.
3. Review the plans and prices.
4. Review the settings.
5. Create the remaining staff with least-privilege roles.

## 4. Payments (Razorpay)
1. Complete Razorpay KYC and activate the account.
2. In the Razorpay dashboard, create a webhook to `https://petora.in/api/v1/webhooks/razorpay` with these events: `payment.captured`, `payment.failed`, `order.paid`, `refund.processed`, `refund.failed`. Put its secret in `RAZORPAY_WEBHOOK_SECRET`.
3. On **staging**, use `rzp_test_…` keys and run the full checkout → verify → webhook → refund cycle before switching production to live keys.
4. Enable auto-capture in Razorpay settings (the adapter captures authorised payments as a fallback).

**Razorpay is the production payment gateway.** `config` refuses to start production with `testmode`, with `rzp_test_` keys, or with a `RAZORPAY_API_BASE` override.

How it works:
1. The server creates the order with the plan price it computes itself. The client receives only the order id and the public key id.
2. Checkout.js (web) or the `razorpay_flutter` SDK (Android) collects the payment.
3. The client posts `razorpay_payment_id`, `razorpay_order_id` and `razorpay_signature` to `POST /payments/{id}/verify`.
4. The server checks the HMAC, then fetches the payment from Razorpay (capturing it if only authorised), then checks the amount and currency, then activates.
5. The `payment.captured` / `order.paid` webhook and the 10-minute reconciliation cover closed tabs and lost callbacks. Refunds go through `POST /payments/{id}/refund`.

This flow passes end to end against a fake Razorpay API in CI (`tests/integration/razorpay_test.go`). **It has not yet run against Razorpay's real servers**, because no keys were available and the dev sandbox blocks razorpay.com.

Staging acceptance run, with `rzp_test_` keys:

| # | Action | Expected |
|---|---|---|
| 1 | Buy *Buyer Basic* with test card `4111 1111 1111 1111`, any future expiry and CVV, OTP from the test page | Status succeeded; invoice `TEST-PET/…` appears; contact unlock works |
| 2 | Repeat with UPI `success@razorpay` | Succeeded |
| 3 | Repeat with UPI `failure@razorpay` | Failed; "not charged" message; no subscription |
| 4 | Pay, then close the tab before the success screen | Webhook settles it within seconds; otherwise reconciliation does within 10 minutes |
| 5 | In the Razorpay dashboard → Webhooks, resend the same event | Acknowledged, no second subscription |
| 6 | As finance, refund the payment in the admin portal | Razorpay dashboard shows the refund; membership ends |
| 7 | On an Android device build, buy a seller plan | The same as #1 via the SDK |

Then switch production to `rzp_live_` keys and do one real low-value purchase and refund.

## 5. Staging
Staging uses a separate host, or a separate project name with its own `.env.staging`:
```bash
docker compose --env-file .env.staging -p petora-staging --profile staging up -d
```
Use `APP_ENV=staging`, a staging domain, Razorpay test keys, a separate database volume and separate buckets. Never point staging at production data.

## 6. Upgrades and rollback
* **Migrations are forward-only and additive** (expand → migrate → contract across releases), so the previous image keeps working against the new schema.
* Deploy:
```bash
git pull && docker compose --profile prod build
docker compose run --rm migrate               # applies new migrations under an advisory lock
docker compose --profile prod up -d web-api worker
curl -fsS https://petora.in/readyz
```
* Roll back the application: check out the previous tag, `docker compose build web-api worker && docker compose up -d web-api worker`.
* Roll back data: only for a destructive incident. Restore the latest backup into a new database, verify it, then switch over (see §8). Take a fresh backup (`docker compose exec backup sh /scripts/backup.sh`) before any risky change.

## 7. Backups
* The `backup` service writes a `pg_dump` (custom format) and a media archive every day at `BACKUP_HOUR_UTC`, plus one at start-up. Both are encrypted with `age` and kept for `BACKUP_RETENTION_DAYS`.
* **Copy `./backups` off-site** (e.g. `rclone sync ./backups r2:petora-backups` from cron, or restic). An on-server backup alone doesn't protect against losing the server.
* With `STORAGE_DRIVER=s3`, enable bucket versioning and lifecycle rules. The private bucket must have public access blocked.
* Optionally add WAL archiving / point-in-time recovery (e.g. pgBackRest) when your recovery point objective needs to be tighter than 24 hours.

## 8. Restore (and quarterly restore test)
```bash
# on a recovery/test host with the age private key:
export PGHOST=... PGUSER=postgres PGPASSWORD=... BACKUP_AGE_IDENTITY=./backup.key
sh deployments/scripts/restore.sh backups/petora-db-<stamp>.dump.age petora_restore_test   # verification restore
# disaster recovery into the live DB name (stop web-api/worker first):
docker compose stop web-api worker
sh deployments/scripts/restore.sh backups/petora-db-<stamp>.dump.age petora --i-understand-this-overwrites
tar -C <media volume path> -xzf <(age -d -i backup.key backups/petora-media-<stamp>.tar.gz.age)
docker compose up -d
```
The restore script prints table, migration, user and payment counts for comparison. A restore of a development database dump was verified with these scripts: plain and age-encrypted, row counts matched, and the script refused to overwrite the live database without the flag.

## 9. Monitoring and logs
* `GET /healthz` is a liveness check. `GET /readyz` reports database status, which fails readiness when unavailable, and Redis status (`ok`, `degraded` or `disabled`).
* Logs are structured JSON on stdout (`request_id`, `user_id`, `status`, `ms`) and rotated by the Docker json-file driver. Ship them to your log platform (Loki, Better Stack, CloudWatch) with a Docker logging driver or Promtail.
* Alert on:
  * `/readyz` non-200;
  * 5xx rate;
  * `jobs` rows with `status='dead'`, also shown as `dead_jobs` on the admin dashboard;
  * payments stuck in `pending` for more than 1 hour;
  * backup files older than 26 hours;
  * certificate expiry, which Caddy renews automatically.
* An uptime probe on `https://petora.in/healthz` from outside the server is recommended.

## 10. Android release
See `mobile/README.md` for build flavours and signing. The release build must use `API_BASE_URL=https://petora.in/api/v1`.
