# Senior Engineer Decision: Marketplace Hardening & Resilience

## Feature / Area: Full Marketplace Lifecycle (`full-marketplace-cycle`)
- **Status:** Approved & Implemented
- **Date:** 2026-10-24
- **Lead:** Senior Engineer
- **Collaborators:** SDE, QA Engineer

---

## 1. Problem Statement & Architecture Context
Following the comprehensive QA lifecycle audit of the PETORA pet marketplace, several friction points and failure modes were identified that would compromise high-scale public adoption in India:
1. **Indian CGNAT Network Lockout:** Strict IP rate limiting (10 registrations/hour) causes false-positive lockouts for users sharing cellular gateways on Jio, Airtel, and college/office Wi-Fi networks.
2. **DTO Rigidity vs Client Diversity:** Strict JSON decoding (`httpx.Decode` enforcing `DisallowUnknownFields`) caused `400 Bad Request` errors due to minor naming variances between web and mobile clients (e.g. `message` vs `body`, `currency` in listings, `address` in seller profiles).
3. **Cryptic Conflict Handling:** Duplicate phone/email registration returned generic conflict errors without actionable recovery pathways.
4. **Photo Upload Friction:** 200x200 px minimum resolution rejected real-world pet photos shared via messaging apps (e.g. WhatsApp, which aggressively compresses photos).
5. **Buyer Trust & Paid Unlock Friction:** Users encountering locked contact details felt surprise or suspicion when asked for a fee, requiring upfront trust-building communication.

---

## 2. Technical Decisions & Architectural Rationale

### Decision 1: Scaled Registration Rate Limiting for Indian Network Topology
- **Production Limit:** Scaled from 10 to 30 registrations per hour per IP.
- **Development/Staging Limit:** Configured to 200 per hour per IP to prevent developer and automated test lockouts.
- **Rationale:** Indian mobile users heavily traverse Carrier-Grade NAT (CGNAT) where thousands of subscribers share public IP pools. Raising the threshold prevents widespread collateral lockouts while still blocking brute-force automation. Future milestone: implement device fingerprinting and Turnstile captcha.

### Decision 2: Harmonized API DTOs & Dual-Field Decoding
- **Enquiries & Replies:** Updated `createEnquiry` and `replyEnquiry` to accept either `body` or `message` transparently:
  ```go
  body := strings.TrimSpace(in.Body)
  if body == "" {
    body = strings.TrimSpace(in.Message)
  }
  ```
- **Listings & Seller Profiles:** Added `Currency string json:"currency,omitempty"` to `listings.Input` and `Address *string json:"address,omitempty"` to `sellers.ProfileInput`.
- **Rationale:** Preserves strict backend typing while preventing client-breaking regressions across web and mobile release cycles.

### Decision 3: Image Processing Thresholds for Real-World Mobile Users
- **Resolution Floor:** Lowered from 200x200 px to 100x100 px in `internal/media/media.go`.
- **Clean Error Messaging:** Stripped internal diagnostic prefixes (e.g. `"image could not be read: "`) so end-users see actionable feedback like `"image must be at least 100x100 pixels"`.
- **Rationale:** Indian pet parents frequently photograph pets on budget smartphones and exchange photos over WhatsApp. A 100x100 px floor prevents rejection while ensuring sufficient clarity for the 80x80 thumbnail and 600x600 preview variants.

### Decision 4: Local Development & Cross-Origin Developer Experience
- **CORS & Origin Checks:** Permitted `localhost` and `127.0.0.1` origins on any port in non-production mode (`internal/middleware/middleware.go`).
- **Public Storage CORS:** Added `Access-Control-Allow-Origin: *` to static media file serving in `internal/storage/storage.go`.
- **Rationale:** Ensures seamless multi-port development (Vite on 5173, API on 8080, Flutter Web on ephemeral ports) without CORS preflight blockages.

### Decision 5: Trust Architecture & Fee Transparency
- **Web (`BuyerTrustNote`) & Mobile (`_BuyerTrustCard`):** Explicitly explains *why* a nominal contact unlock fee (from ₹50) exists:
  1. Protects pets and prevents scams (stops puppy mills, commercial flippers, and automated number scrapers).
  2. Serious adopters only (eliminates spam calls and time-wasters for pet parents).
  3. Direct, zero-brokerage contact (direct phone & WhatsApp without middlemen).
- **Rationale:** Transforms a perceived paywall into a positive trust and pet safety feature.

---

## 3. Verification & Compliance
- **Go Unit Tests:** All internal packages pass (`go test ./internal/...`).
- **Web Frontend Vitest:** 74/74 unit tests passed, 0 Axe accessibility violations.
- **Web TypeScript Check:** 0 errors (`tsc --noEmit`).
- **Mobile Flutter Suite:** 87/87 tests passed across all screen viewports (320px to 800px).
- **Master E2E Lifecycle Suite:** 40/40 checks passed with zero errors across all 7 cycles.
