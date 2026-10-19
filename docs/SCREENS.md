# Screen inventory

This maps the brief's screen list to real routes. A ✓ means the screen is implemented against the live API. Several brief items share one screen; for example, the add-pet wizard steps are steps of `/sell/listing/new`.

## Android app (`mobile/`, GoRouter)

| Brief § | Screens | Route(s) |
|---|---|---|
| A 1–10 Auth | splash, onboarding, login, register (buyer/seller), email verification code, forgot, reset, profile setup, location, notification explainer | `/splash` `/onboarding` `/login` `/register` `/verify-email` `/forgot` `/reset` `/profile/edit` `/setup/location` `/setup/notifications` ✓ |
| A 11–22 Discovery | home (featured, recent, nearby, verified sellers), search + results + filters sheet, category and breed, nearby/featured/recent lists, verified sellers, favourites, recently viewed | `/` `/search` `/category/:slug` `/pets/:kind` `/sellers` `/favourites` ✓ |
| A 23–34 Pet detail | detail, full-screen gallery, seller profile, health disclosures, similar, report, share, locked contact → membership required → contact unlocked → enquiry form → sent | `/pet/:id` (+ `contact`, `enquire`, `enquiry-sent`), `/s/:slug` ✓ |
| A 35–52 Account | enquiries list and thread, notifications, plans + comparison, checkout, payment processing/success/failure, billing, invoice, profile, security, privacy, help, delete account | `/enquiries` `/enquiry/:id` `/notifications` `/plans` `/membership` `/checkout/:planId` `/payment/:id` `/billing` `/invoice/:id` `/profile/*` `/help` `/legal/:slug` ✓ |
| Buyer bottom nav | Home · Search · Favourites · Enquiries · Profile | buyer shell ✓ |
| B 1–10 Seller onboarding | registration, individual/business, business profile, documents, verification status, plans, checkout, confirmation, profile | `/sell/onboarding` `/sell/profile/edit` `/sell/verification` `/plans` `/checkout/:planId` ✓ |
| B 11–20 Dashboard | dashboard, listings by status (active/draft/pending/rejected/sold), listing detail, analytics, subscription summary | `/sell` `/sell/listings` `/sell/listing/:id` `/sell/listing/:id/analytics` ✓ |
| B 21–35 Add pet wizard | 10 steps: basics, species/breed, age/gender, price/type, description, health, photos (progress/retry/cancel, cover, reorder), location, availability, preview → submit → confirmation; edit | `/sell/listing/new` `/sell/listing/:id/edit` `/sell/listing/:id/submitted` ✓ |
| B 36–47 Operations | inbox, thread, reply, notifications, subscription/upgrade/renewal, payment history, invoice, profile, settings, support/disputes | `/sell/enquiries` `/sell/enquiry/:id` `/membership` `/billing` `/sell/profile` `/help` ✓ |
| Seller bottom nav | Dashboard · Listings · Enquiries · Profile + Add-pet FAB | seller shell ✓ |
| Staff | "Use the web admin portal" | `/staff` ✓ |

## Web (`frontend/`, React Router)

| Area | Routes |
|---|---|
| Public | `/` `/pets` `/pets/:slug` `/categories/:slug` `/sellers/:slug` `/pricing` `/safety` `/faq` `/support` `/terms` `/privacy` `/refund-policy` `/seller-policy` `/login` `/register` `/register/seller` `/verify-email` `/forgot-password` `/reset-password` ✓ |
| Buyer portal `/buyer/*` | dashboard, favourites, enquiries (+ thread), membership, billing (+ invoice), notifications, profile & security ✓ |
| Seller portal `/seller/*` | dashboard, listings (status tabs), listing wizard new/edit, enquiries (+ thread), analytics, membership & billing, verification, profile ✓ |
| Admin `/admin/*` | overview, users, verifications, moderation, categories, plans, subscriptions, payments & refunds, reports & disputes, enquiry abuse, templates, content & legal, settings, security (roles/staff/MFA), audit logs, jobs; plus `/admin/mfa` ✓ |
