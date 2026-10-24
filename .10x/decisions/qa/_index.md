# QA Decisions Index

## Core Principles
1. **Behavior Over Implementation:** Tests verify contracts, authorization bounds, idempotency, and user expectations, not internal private functions.
2. **Structural Security (IDOR Defense):** Queries must enforce tenancy and ownership in SQL `WHERE` clauses, returning 404 to avoid resource enumeration.
3. **Graceful Failure & Fast Feedback:** Rate limits, auth errors, and business constraints must return structured machine-readable error codes with human-friendly messages.
4. **User-Centric Performance & A11y:** Every page must meet WCAG 2.1 AA standards (zero axe violations) and maintain responsiveness across small mobile displays (320px).

## Active Features & Areas
| Slug | Area | Status | Last Audit |
|---|---|---|---|
| `full-marketplace-cycle` | Full Project Cycle (Buyer, Seller, Moderation, Payment, Mobile) | Audited (Passed with Recommendations) | 2026-10-24 |
