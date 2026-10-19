# PETORA design system (shared by web and Flutter)

Compact, premium, Android-first. Rounded cards, restrained shadows, high contrast, ≥44 px touch targets.

## Colour tokens
| Token | Light | Dark | Use |
|---|---|---|---|
| `primary-50…900` | 50 `#EDF7F0` 100 `#D3EBDA` 200 `#A9D6B8` 300 `#78BC93` 400 `#46A06F` 500 `#2A8656` **600 `#1E6B44`** 700 `#17563A` 800 `#124530` 900 `#0C3223` | primary = 400 `#46A06F`, on-primary `#0C3223` | forest green: brand, primary buttons, links |
| `secondary-50…700` | 50 `#E6F6F4` 100 `#C2E8E3` 500 `#0F766E` **600 `#0D5F59`** 700 `#0B4B47` | secondary = `#3DB6AB` | deep teal: info accents, verified badge ring, charts |
| `accent-400/500/600` | `#F08A6B` / **`#E8704F`** / `#D2593A` | `#F08A6B` | muted coral: CTAs that unlock, price highlight, favourite heart |
| `bg` | `#FFFFFF` (app), `bg-warm #FAF7F2` (page sections) | `#0F1714` | |
| `surface` | `#FFFFFF` | `#16211C` | cards |
| `border` | `#E8E2D8` | `#26342D` | hairlines (prefer border over shadow) |
| `text` / `text-muted` | `#1C2A24` / `#5E6B64` | `#E8F0EB` / `#9DB0A5` | |
| `success` `warning` `danger` `info` | `#1E8E5A` `#B97A00` `#C8402F` `#2B6CB0` | lightened equivalents | status badges |

## Typography
Inter (self-hosted/bundled — never fetched at runtime). Sizes (web px / Flutter sp): display 28/700, h1 22/700, h2 18/600, h3 16/600, body 14/400, small 12/400, label 12/600 uppercase tracking .04em. Line-height 1.35–1.5. Prices use tabular numerals.

## Shape, spacing, elevation
Radii: 8 chips/badges, 10 inputs/buttons, 14 cards, 20 bottom sheets/dialogs, full for avatars/pills.
Spacing scale: 4 · 8 · 12 · 16 · 24 · 32. Page gutter 16 (mobile) / 24 (desktop). Card padding 12. Shadow: `0 1px 2px rgba(16,24,20,.06)`, raised `0 4px 14px rgba(16,24,20,.10)`. Icon sizes 16/20/24.

## Components (both platforms)
Logo/wordmark · buttons (primary, secondary, outline, destructive, ghost) · text fields with inline validation · search bar · filter chips · listing card (4:3 cover, price, age/gender chips, verified badge, favourite heart) · category tile · seller verification badge ("Verified seller" only if `seller.verified`) · price label (`₹15,000`, "Free adoption") · plan card · enquiry card · status badge · image gallery with full-screen viewer · upload control with progress/retry · confirm dialog · bottom sheet · snackbar/toast · empty state · error state with retry · skeleton loaders · load-more/pagination · bottom navigation (Buyer: Home, Search, Favourites, Enquiries, Profile; Seller: Dashboard, Listings, Enquiries, Profile + Add-pet FAB).

## Content rules
Never say a seller is "licensed" or a pet is "health verified". The only trust label is **Verified seller** (admin-approved identity/business documents). Always show the health/welfare disclaimer from `ListingDetail.disclaimer`. Test-mode payments show a persistent **TEST MODE – no real charge** banner when `Checkout.test_mode` is true.

## Imagery
No stock photos are bundled. Listings without photos render a tinted category-icon placeholder. Demo seed data generates neutral placeholder images.
