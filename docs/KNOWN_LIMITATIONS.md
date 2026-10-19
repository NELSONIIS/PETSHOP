# Known limitations and outstanding production prerequisites

This is an honest list of what is **not** done or **not** verified.

## Not verified in the development environment
| Item | Why | What to do |
|---|---|---|
| Docker image build and `docker compose up` | There was no Docker daemon in the sandbox. Only `docker compose config` was validated. | Build and run on staging (`docs/DEPLOYMENT.md` §3, §5). |
| Caddy HTTPS/ACME | Needs a real domain. | Staging deploy with the staging domain. |
| Razorpay against Razorpay's real servers | No merchant keys, and the sandbox's egress proxy blocks `api.razorpay.com` / `checkout.razorpay.com`. The full server flow (order → signed callback → fetch/capture → webhooks → reconciliation → refund → outage) passes end to end against a fake Razorpay API (`tests/integration/razorpay_test.go`). | With `rzp_test_` keys on staging, follow `docs/DEPLOYMENT.md` §4. |
| Android APK build | Android SDK downloads (`dl.google.com`) were blocked. `flutter analyze` (clean) and `flutter test` (87 pass, 1 opt-in live test skipped) did run. | `flutter build apk` / `appbundle` on a machine with the Android SDK (`mobile/README.md`), then test on devices. |
| Native plugins (Razorpay SDK, geolocator, secure storage, image picker) on device | No emulator. | Device QA. |
| govulncheck | `vuln.go.dev` was blocked. | Runs in CI (`.github/workflows/ci.yml`). |
| SMTP delivery | No SMTP credentials. Emails are logged in development. | Configure SMTP and verify SPF/DKIM. |
| S3/R2 storage driver | Implemented via minio-go but only the local driver was exercised. | Test against your bucket on staging. |

## Not implemented (by design or scope)
- **Phone/SMS OTP:** only email verification is implemented, and phone numbers are stored unverified. Integrating an SMS provider (MSG91, Twilio) needs credentials plus DLT registration in India.
- **Push notifications (FCM):** notifications are in-app and email only. The app saves the push preference, but there is no FCM integration and no `POST_NOTIFICATIONS` permission declared.
- **Automatic recurring billing:** plans are prepaid terms with renewal reminders. `auto_renew` is stored but no mandate or subscription charging exists (Razorpay Subscriptions or UPI Autopay could be added later).
- **Proration:** upgrades and downgrades take effect immediately and supersede the current term without proration.
- **Real-time chat:** enquiry threads refresh by polling (about 15 seconds on mobile). A websocket or SSE channel would need sticky connections and fan-out (Redis pub/sub).
- **Background image processing:** variants are generated synchronously during upload (images are at most 8 MB and 40 MP, which takes well under a second). Move this to a job if the upload limit is raised.
- **Social login, an admin mobile app and multi-language UI** are not built.
- **Duplicate detection:** heuristics only (same-title, copied description, contact details in text, prohibited keywords). There is no image-hash or ML-based detection.
- **Search:** Postgres full-text plus trigram. Revisit with a search engine when the catalogue grows past the low hundreds of thousands.
- **Reverse geocoding:** location is city/state text plus optional coordinates. There is no maps/places provider.
- **Point-in-time database recovery:** nightly logical dumps only (recovery point up to 24 hours). Add WAL archiving (pgBackRest) if you need better.
- **Tax invoices:** invoices carry PETORA's lines, subtotal, GST and total. A GST-compliant tax invoice also needs your GSTIN, legal entity, HSN/SAC code and place of supply. Configure `invoice.seller_details` and extend the invoice view with your accountant.

## Compliance — requires legal review before launch
The legal pages are **templates**. Pet sales in India are regulated:
- the PCA Act 1960, the Dog Breeding and Marketing Rules 2017 and the Pet Shop Rules 2018, including breeder and pet-shop registration with State Animal Welfare Boards;
- the Wild Life (Protection) Act 1972 and CITES;
- the Consumer Protection (E-Commerce) Rules 2020;
- the DPDP Act 2023;
- GST.

Category rules, seller-verification requirements per state, the prohibited-keyword list and the policies must be confirmed by counsel. "Verified seller" means only that staff reviewed the identity or business documents. The product never claims licensing or health verification.

## Demo data
`api seed --demo` creates sample accounts, listings with generated placeholder images, and **test-mode** subscriptions. It is refused in production and in any non-testmode payment configuration. There are no bundled real pet photos.
