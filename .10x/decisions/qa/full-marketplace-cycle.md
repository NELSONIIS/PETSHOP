# QA Decision: Full Marketplace Cycle & Quality Audit

## Feature / Area: Full Marketplace Lifecycle (`full-marketplace-cycle`)
- **Status:** Verified & Audited
- **Date:** 2026-10-24
- **Evaluator:** QA Engineer

---

## 1. Scope & Cycles Tested
A complete end-to-end audit of all core project cycles was executed:
1. **Public Visitor / Catalog & Search Cycle:**
   - Multi-attribute search (category, city, price range, age, breed)
   - Detail view with seller masking
   - SEO metadata and legal/safety content fallback
2. **Buyer Journey Cycle:**
   - Registration with terms acceptance
   - Email verification via OTP (Mailpit)
   - Gated contact unlock rules (unverified -> 403, no plan -> 402)
   - Checkout & payment activation (testmode & Razorpay model)
   - Contact unlock allowance deduction & idempotency (free re-unlock)
   - Two-way enquiry messaging & favourites persistence
3. **Seller Journey Cycle:**
   - Onboarding & profile customization
   - Plan subscription with listing allowance enforcement
   - Listing creation wizard (draft -> photo upload -> cover image -> submit)
   - Enforcing minimum 1 photo before moderation submission
4. **Staff Moderation & Admin Cycle:**
   - MFA login with TOTP verification
   - Pending moderation queue inspection (`/admin/listings?status=pending`)
   - Atomic listing approval (triggers notifications & immediate catalog cache invalidation)
5. **Cross-Platform Verification:**
   - Go backend unit tests (`100% pass`)
   - Web frontend Vitest + Axe Accessibility tests (`73/73 pass, 0 axe violations`)
   - Web TypeScript & ESLint validation (`0 errors, 0 warnings`)
   - Web production build compilation (`Vite, 615 kB vendor bundle with route-splitting`)
   - Flutter mobile tests (`87/87 pass across 320px, 360px, 411px, 800px screen sizes`)

---

## 2. Issues & High-Risk Areas Found

### P1: High-Priority Quality & Scale Risks
1. **CGNAT & Shared IP Registration Rate-Limit Lockout:**
   - Current rule: `RateLimit("register", 10, time.Hour)` per client IP.
   - In India, massive mobile networks (Jio, Airtel) operate on Carrier Grade NAT where thousands of cell towers and users share single egress IPs.
   - Result: If 10 people register from the same college campus, office Wi-Fi, or carrier gateway within an hour, all subsequent legitimate registrations from that IP are blocked with `429 rate_limited`.
   - **Recommendation:** Replace strict IP counting on registration with Cloudflare Turnstile / hCaptcha or progressive exponential delays.

2. **Unverified Phone Number Collision:**
   - `users.phone` has a UNIQUE database constraint, but phone numbers are not verified during sign-up (only email is verified via OTP).
   - If an account is abandoned or a phone number is mistyped, the real owner cannot register and receives a generic `409 Conflict` without clarification.
   - **Recommendation:** Implement SMS OTP verification before locking phone numbers to user accounts.

3. **Inconsistent API Message Contracts:**
   - Initial enquiry (`POST /pets/{id}/enquiries`) expects `{ "message": "..." }`.
   - Thread reply (`POST /seller/enquiries/{id}/messages` and `/buyer/enquiries/{id}/messages`) expects `{ "body": "..." }`.
   - Because `httpx.Decode` disallows unknown fields, sending `message` in a reply causes an immediate `400 Bad Request`.
   - **Recommendation:** Standardize field names across enquiry endpoints (accept `message` or `body` aliases).

### P2: User Experience (UX) & Delight Improvements (for High Volume Public Use)
1. **Real-Time Instant Messaging:**
   - Enquiries currently rely on 15s client-side polling. This drains battery on mobile and causes noticeable latency.
   - **Recommendation:** Implement WebSockets or Server-Sent Events (SSE) with Redis pub/sub.
2. **Push Notifications (FCM):**
   - Critical for buyers and sellers to respond quickly to pet inquiries.
3. **Background Image Transcoding:**
   - Currently, generating thumb/medium/large image variants is performed synchronously inside the HTTP request. Under heavy seller traffic, move this to the transactional `jobs` queue.
4. **Optimistic UI & Feedback:**
   - Add micro-animations and optimistic updates for "Save to Favourites", "Unlock Contact", and "Send Enquiry".

---

## 3. Quality Gate Assessment
- **Unit Test Coverage:** PASS
- **Accessibility (WCAG 2.1 AA):** PASS (0 axe violations on login, search, listing detail, and home)
- **Responsive Layout:** PASS (Tested from 320x568 to 800x1280)
- **Data Integrity & Concurrency:** PASS (Idempotent locks, single finalization path, minor units integer arithmetic)
- **Release Readiness:** READY FOR STAGING (address CGNAT rate limit and SMS OTP before full public rollout)
