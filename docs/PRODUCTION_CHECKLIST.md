# Production launch checklist

## Accounts & credentials
- [ ] Razorpay account activated (KYC); live key id/secret and webhook secret in `.env`
- [ ] Staging cycle passed with `rzp_test_` keys: checkout → verify → webhook → invoice → refund → refund webhook
- [ ] SMTP provider configured, SPF/DKIM/DMARC passing; test emails received (verification, reset, enquiry, payment)
- [ ] Domain DNS (A/AAAA for apex + www) pointing at the server
- [ ] Object storage decided (local volume or S3/R2); private bucket blocks public access
- [ ] `age` key pair created; private key stored offline; off-site backup sync configured

## Configuration
- [ ] `APP_ENV=production`, `APP_BASE_URL=https://…`, unique secrets (`JWT_SECRET`, `DATA_ENCRYPTION_KEY`, DB/Redis passwords)
- [ ] First super admin created; MFA enrolled; additional staff created with minimum roles
- [ ] Plans, prices, tax rates, grace/refund windows reviewed in Admin → Plans
- [ ] Settings reviewed: auto-approve (off), verified-seller requirement, listing expiry, subscription-expiry policy, contact retention, prohibited keywords, support email, invoice seller details/GSTIN
- [ ] Category list and jurisdiction rules reviewed (Reptiles disabled by default)
- [ ] Legal pages (Terms, Privacy, Refund, Seller policy, Safety) approved by counsel and republished from Admin → Content → Legal
- [ ] Grievance officer / contact details published (DPDP Act, Consumer Protection (E-Commerce) Rules)

## Verification
- [ ] `docker compose --profile prod up -d` healthy; `/readyz` → database ok, redis ok
- [ ] `make test` green in CI against Postgres + Redis; frontend `npm run lint typecheck test build` green; `flutter analyze` + `flutter test` green
- [ ] Manual smoke: register buyer → verify email → browse → locked contact → membership → unlock → enquiry → seller reply
- [ ] Manual smoke: seller register → documents → verification approval → subscription → listing → moderation → live
- [ ] Backup ran and a restore test succeeded on a separate host
- [ ] Uptime monitor + alerting for `/readyz`, 5xx rate, dead jobs, stuck pending payments, stale backups
- [ ] Android release build signed with the upload key, `API_BASE_URL=https://petora.in/api/v1`, tested on a physical device

## Compliance (India) — confirm with counsel
- [ ] Prevention of Cruelty to Animals Act 1960; Dog Breeding and Marketing Rules 2017; Pet Shop Rules 2018 (State Animal Welfare Board registration of breeders/pet shops) — seller verification requirements per state
- [ ] Wild Life (Protection) Act 1972 / CITES: prohibited species list and keyword rules
- [ ] Transport of Animals Rules (if sellers arrange delivery)
- [ ] Consumer Protection Act 2019 and E-Commerce Rules 2020 (seller disclosures, grievance redressal)
- [ ] Digital Personal Data Protection Act 2023 (notice, consent, retention, data principal rights)
- [ ] GST registration and invoice format; RBI/payment aggregator terms
- [ ] Advertising Standards (ASCI) for marketing claims
