# PETORA web (React + TypeScript + Vite + Tailwind)

Marketplace, buyer/seller portals and the admin control centre. Talks only to `/api/v1` (contract: `../docs/openapi.yaml`).

```bash
npm install
npm run dev        # http://localhost:5173, proxies /api and /media to http://localhost:8080
npm run typecheck && npm run lint && npm run test && npm run build   # build → dist/ (served by the Go server with SPA fallback)
```

* **Auth**: HttpOnly cookies + double-submit CSRF (`X-CSRF-Token` from the `petora_csrf` cookie). One single-flight `/auth/refresh` on 401. No tokens in JS/storage.
* **Roles**: UI route guards (`src/auth/guards.tsx`) and permission-based nav are conveniences only; the API enforces everything.
* **Payments**: the client never decides a payment succeeded — it polls `GET /payments/{id}` (see `src/components/Billing.tsx`). Test mode shows a persistent *TEST MODE – no real charge* banner.
* **Layout**: `src/pages/{public,auth,buyer,seller,admin,shared}`, shared UI in `src/components`, typed API layer in `src/api`.
* **Tests**: Vitest + Testing Library + vitest-axe (`src/**/*.test.tsx`). `screenshots/` holds a smoke-run capture of key pages.
