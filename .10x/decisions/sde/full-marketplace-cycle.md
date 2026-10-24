# SDE Decision: Marketplace Lifecycle Bug Fixes & UX Implementation

## Feature / Area: Full Marketplace Lifecycle (`full-marketplace-cycle`)
- **Status:** Implemented & Verified
- **Date:** 2026-10-24
- **Lead:** SDE
- **Reviewer:** Senior Engineer

---

## 1. Summary of Changes

### Backend (Go)
1. **`internal/httpserver/handlers.go`:**
   - Modified `createEnquiry` input struct to accept both `Body` and `Message`.
   - Modified `replyEnquiry` input struct to accept both `Body` and `Message`.
   - Normalised the resulting string to ensure message storage is seamless regardless of client field conventions.
2. **`internal/httpserver/router.go`:**
   - Introduced environment-aware registration rate limits (`regLimit := 30` in production, `regLimit := 200` in non-production environments).
   - Passed dynamic dev origin flag to `mw.CORS` and `mw.OriginCheck`.
3. **`internal/auth/service.go`:**
   - Replaced generic conflict error on duplicate email/phone with:
     `"An account with this email or mobile number already exists. Try logging in or use 'Forgot password'."`
4. **`internal/listings/types.go` & `internal/sellers/sellers.go`:**
   - Added `Currency string json:"currency,omitempty"` to `listings.Input`.
   - Added `Address *string json:"address,omitempty"` to `sellers.ProfileInput`.
5. **`internal/media/media.go` & `internal/media/media_test.go`:**
   - Lowered minimum image dimension requirement from 200x200 to 100x100 pixels.
   - Added unit test `TestProcessImage` checking a 160x140 image successfully processes.
6. **`internal/listings/owner.go` & `internal/sellers/sellers.go`:**
   - Sanitized upload error strings to strip `image could not be read: ` prefix for clean user presentation.
7. **`internal/middleware/middleware.go` & `internal/storage/storage.go`:**
   - Added `isAllowedOrigin` helper to allow `localhost` and `127.0.0.1` origins on any port in development mode.
   - Added `Access-Control-Allow-Origin: *` header in `Local.PublicHandler()` so client SPAs can fetch media assets without CORS restrictions.
8. **`tools/decrypt_mfa/main.go`:**
   - Added Go tool to securely decrypt staff demo TOTP secrets via `security.NewBox` and output live 6-digit TOTP codes for automated E2E testing.

### Frontend (React + TypeScript)
1. **`frontend/src/components/Billing.tsx`:**
   - Created reusable `BuyerTrustNote` component highlighting scam prevention, serious adopter verification, and zero brokerage.
   - Rendered note in `PlanPicker` modal when `audience === 'buyer'`.
2. **`frontend/src/pages/public/Pricing.tsx` & `frontend/src/pages/shared/Billing.tsx`:**
   - Integrated `BuyerTrustNote` beneath the plan selection cards for buyer viewports.
3. **`frontend/src/components/Upload.tsx`:**
   - Extracted `details` array from API error payloads so field validation messages appear directly on failed upload items.
4. **`frontend/src/pages/seller/Wizard.tsx`:**
   - Updated dropzone hint to: `JPEG, PNG or WebP · min 100x100 px · up to ${maxMb} MB each · ${images.length}/${maxImages} used`.

### Mobile (Flutter)
1. **`mobile/lib/features/billing/plans_screen.dart`:**
   - Added `_BuyerTrustCard` widget with custom security icon, bulleted trust factors (Protects pets & prevents scams, Serious adopters only, Direct zero brokerage).
2. **`mobile/lib/core/config.dart` & `mobile/test/core_test.dart`:**
   - Updated `defaultDevUrl` to detect Web platform (`http://localhost:8080/api/v1`) vs Android emulator (`http://10.0.2.2:8080/api/v1`).
   - Added test coverage in `core_test.dart`.

---

## 2. Test Execution & Verification Results

| Suite | Component | Command | Result |
|-------|-----------|---------|--------|
| Master E2E | All 7 Cycles | `node test_full_marketplace_cycle.js` | **40 / 40 Passed** (100%) |
| Web Tests | Vitest + Axe A11y | `npm test -- --run` | **74 / 74 Passed**, 0 A11y violations |
| Web Typecheck | TypeScript | `npm run typecheck` | **0 Errors** |
| Web Lint | ESLint | `npm run lint` | **0 Warnings / 0 Errors** |
| Mobile Tests | Flutter Engine | `flutter test` | **87 / 87 Passed** across 4 screen sizes |
| Backend Tests | Go Packages | `go test ./internal/...` | **100% Passed** |
| API Build | Go Binary | `go build ./cmd/api` | **Compiled cleanly** |
| Worker Build | Go Binary | `go build ./cmd/worker` | **Compiled cleanly** |
