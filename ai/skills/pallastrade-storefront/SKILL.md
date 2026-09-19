---
name: pallastrade-storefront
description: Use when the user is working on the optional Next.js storefront (the customer-facing online store) — adding a page, customizing checkout, fetching products, integrating with PallasTrade's Store API. Common phrasings include "customize storefront", "Next.js storefront", "frontend changes", "PDP", "product page", "cart", "checkout flow", "@pallastrade/sdk", "publishable key". Provides the storefront architecture, the @pallastrade/sdk integration model, and the storefront-vs-backend decision tree.
---

# PallasTrade Storefront (Next.js)

The PallasTrade Next.js storefront talks to the PallasTrade backend over the v3 Store API. Its canonical source is the fixed `storefront/` directory in `https://github.com/stevenbian9266-cyber/pallastrade`; `create-pallastrade-app` clones the canonical repository once and copies that directory into `apps/storefront/`.

The storefront is **optional**. Headless deployments may use a custom frontend — React Native, Astro, Remix, or hand-rolled. PallasTrade's job is to expose a clean API; what consumes it is your choice. This skill assumes the official Next.js storefront, but the API contract is identical for any frontend.

## How it connects to PallasTrade

```
Browser ──HTTPS──> Next.js storefront ──API──> PallasTrade backend (Rails)
                          │
                          └── @pallastrade/sdk for typed API calls
```

The storefront authenticates against the PallasTrade backend via a **publishable API key** (`pk_…` prefix). Customer-bound operations (their cart, their account) use additional auth — JWT for logged-in customers, cart tokens for guest carts.

```bash
# .env.local — server-side only (the storefront makes all API calls via Server Actions)
PALLASTRADE_API_URL=http://localhost:3000
PALLASTRADE_PUBLISHABLE_KEY=pk_…
```

## @pallastrade/sdk — the canonical client

Don't hand-write fetch calls. Use `@pallastrade/sdk` for typed access to the Store API:

```ts
import { createClient } from '@pallastrade/sdk'

const pallastrade = createClient({
  baseUrl: process.env.PALLASTRADE_API_URL!,
  publishableKey: process.env.PALLASTRADE_PUBLISHABLE_KEY!,
})

// List products
const { data, meta } = await pallastrade.products.list({
  expand: ['media', 'default_variant'],
})

// Get a single product by slug or prefixed ID
const product = await pallastrade.products.get('cool-shirt')

// Create a cart
const cart = await pallastrade.carts.create()

// Add item to cart — cart ID positional, token via options.guestToken
await pallastrade.carts.items.create(cart.id, {
  variant_id: 'variant_k5nR8xLq',
  quantity: 1,
}, { guestToken: cart.token })
```

The SDK includes:
- Full TypeScript types generated from the PallasTrade serializers (`Product`, `Order`, `Cart`, etc.)
- Runtime Zod schemas in `@pallastrade/sdk/zod` if you want validation
- Automatic retry with exponential backoff
- Ransack query param transformation
- Webhook signature verification in `@pallastrade/sdk/webhooks`

> **Request timeout（修复：storefront API 请求缺超时导致预渲染挂起/构建失败）**：
> The SDK's fetch has **no built-in timeout** and retries GET network errors (maxRetries=2,
> exponential backoff). When the API is unreachable (deployment/rebuild window, DNS/network
> fault), a single request can hang for minutes — Next.js prerender "use cache" cache-fill
> then times out (`USE_CACHE_TIMEOUT`) and the **build fails**. `lib/pallastrade/config.ts`
> therefore wraps the SDK client's `fetch` with `createFetchWithTimeout()` (8s
> `AbortSignal.timeout`), so every API call fails fast and bubbles to the existing
> `.catch(() => …)` degradation instead of hanging. Keep this timeout when touching
> `getClient()`/`initPallasTradeNext()`.

## Authentication modes

| Who | How | Use for |
|---|---|---|
| Anonymous browser | Publishable key | Browsing products, viewing categories |
| Guest cart | Publishable key + cart token | Cart operations for not-yet-signed-up customers |
| Logged-in customer | Publishable key + JWT (customer login) | Order history, saved addresses, account pages |

The customer login flow:

```ts
const { token, refresh_token, user } = await pallastrade.auth.login({
  email: 'jane@example.com',
  password: 'secret',
})

// Pass the JWT per request via options.token
const orders = await pallastrade.customer.orders.list({}, { token })
const me = await pallastrade.customer.get({ token })

// Refresh later
const { token: newToken } = await pallastrade.auth.refresh({ refresh_token })
```

## Channels — which sales surface

If the merchant has multiple channels (website, mobile app, in-store POS), the storefront should identify which one it represents. Set the channel via the SDK config:

```ts
const pallastrade = createClient({
  baseUrl: process.env.PALLASTRADE_API_URL!,
  publishableKey: process.env.PALLASTRADE_PUBLISHABLE_KEY!,
  channel: 'online',         // channel code; or prefixed ID like 'ch_…'
})
```

The PallasTrade backend uses `PallasTrade::Current.channel` to scope queries — only products published on that channel surface in API responses. If `channel` is omitted, the store's default channel is used.

## Common storefront patterns

### Server-rendered PDP

```tsx
// app/products/[slug]/page.tsx
import { pallastrade } from '@/lib/pallastrade'

export default async function ProductPage({ params }: { params: { slug: string } }) {
  const product = await pallastrade.products.get(params.slug, {
    expand: ['default_variant', 'variants', 'media', 'categories'],
  })

  return (
    <main>
      <h1>{product.name}</h1>
      <img src={product.media?.[0]?.large_url ?? undefined} alt={product.media?.[0]?.alt ?? ''} />
      <AddToCartButton variantId={product.default_variant_id} />
    </main>
  )
}
```

The v3 Store API uses **flat responses** — `product.name`, not `product.data.attributes.name`. Related records appear as either ID fields (e.g. `default_variant_id`) or, when expanded, as nested objects (e.g. `product.default_variant`, `product.media[]`).

### SEO / metadata

The storefront ships a shared SEO layer under `storefront/src/lib/`:

- `seo.ts` — shared helpers (canonical URLs, Open Graph tags, structured data).
- `metadata/` — per-route metadata builders, one per content type:
  - `home.ts`, `category.ts`, `product.ts`, `store.ts` — `generateMetadata` data for each route.
  - `alternates.ts` — hreflang/locale alternates (per-country/per-locale URL variants).

Page routes under `[country]/[locale]/...` use these builders so every page emits
canonical + localized `<head>` metadata. When adding a new page route, extend the
matching builder in `metadata/` rather than inlining metadata in the page.

Key components:

- `ProductCard` (`components/products/ProductCard.tsx`) — product grid card; consumes the product + media via the SDK and links to the PDP.
- `product-image` (`components/ui/product-image.tsx`) — shared image renderer with srcset/fallback handling. When `src` is missing or fails to load it renders an **accessible placeholder**: a `<div role="img">` with an icon + `aria-label` (NOT a `<img>` element) — tests must assert on that placeholder (e.g. `getAllByRole("img")` → `tagName === "DIV"`), not on the absence of an image role. Pass a multi-size webp `srcSet` (built with `lib/image-srcset.ts` `buildImageSrcSet(media)` from the media record's `small/medium/large/xlarge_url` CDN variants) to get a responsive plain `<img>` — the backend already produced optimized webp variants, so they must NOT be run through the Next.js optimizer again. `ProductCard` and `MediaGallery` feed `srcSet`; leave `srcSet` unset to keep the existing `next/image` path. CI enforces `pnpm check` (Biome lint + format) on every push — new files must pass locally (`pnpm check` / `pnpm check --write`) before committing.
- `CategoryBanner` (`app/[country]/[locale]/(storefront)/c/[...permalink]/CategoryBanner.tsx`) — category hero banner in the category listing route.
- `BackInStockNotify` (`components/products/BackInStockNotify.tsx`) — client-side "notify me when back in stock" form. Shown on the PDP (`ProductDetails`) only when the availability state is **sold out** (pre-order / backorder SKUs stay purchasable and must not trade a sale for an email — see the PDP state entry below); calls `sdk.backInStockSubscriptions.create(productId, { email })` (Store API, guest-accessible) and shows success/error states with i18n labels (`backInStock*` keys).
- `AvailabilityStatus` (`components/products/AvailabilityStatus.tsx`, 4.2 / F-2) — the PDP stock line. Takes `availability` (from `deriveAvailabilityState`) plus the API's `stockStatus` bucket: `low_stock` renders the amber **Only a few left** badge instead of the plain in-stock line, and the bucket is the *only* scarcity signal the browser ever sees (exact quantities are not published by the API). `ProductCard` shows the same phrasing as a compact pill, and only for `low_stock` — plain in-stock stays quiet to avoid noise. Tests: `__tests__/AvailabilityStatus.test.tsx` (PDP stock line, incl. the backorder + low-stock combination) and `__tests__/ProductCardStockBadge.test.tsx` (grid-card badge, incl. payloads that predate `stock_status` — a missing field must stay silent, not render a badge).

- `ProductReviews` sorting (F-4 2026-09-16) — the PDP review list carries a `<select id="review-sort">` paired with a `<label htmlFor>` (so tests and screen readers can find it by label). It defaults to `newest` from `meta.sort`. **Switching it refetches page 1 with the new ordering and replaces the appended pages** — the new order is never merged with the old one — and a failed refetch keeps the reviews already on screen (`getMoreProductReviews` returns `null` rather than an empty list; AP-009b). `lib/data/reviews.ts` passes `sort` through both `getProductReviews` and `getMoreProductReviews(productId, page, limit, sort)`.

- `ProductReviews` helpful vote (F-5 2026-09-16) — each review row carries a `Helpful` button (`data-testid="review-helpful-<id>"`, `aria-pressed` when the caller already voted, and a `review-helpful-count-<id>` span whose `data-count` is the number the API returned). The click goes through the `voteReviewHelpful(reviewId, voted)` server action in `lib/data/reviews.ts` — **the reply is the only state that gets stored** (count + `helpful_voted`), so the UI can never drift from the API; a failed call keeps what the row already showed and prints `helpfulFailed` (or `helpfulOwnReview` for the API's `own_review_vote_forbidden`) instead of flipping the button (AP-009b). Guests get a sign-in link (`review-helpful-signin-<id>`, derived from `usePathname` — **not** `useParams`, so a page-level test with its own `next/navigation` mock can still render this component) rather than a button that would always answer 401. `sort=most_helpful` is offered in the same `<select>` as the F-4 orderings. Tests: `__tests__/ProductReviewsHelpfulVote.test.tsx` (count from the payload, vote + own-state flip, take-back, failed vote keeps the previous state, own-review refusal message, guest sign-in link).

- `ShippingEstimate` (`components/products/ShippingEstimate.tsx`, F-2 2026-09-16) — the PDP shipping line, rendered straight under the price/stock row. Data comes from the server action `lib/data/shipping.ts` (`getShippingEstimate(productId, country)`, country from the `[country]` route), which returns `null` on failure so the block is **omitted** rather than claiming shipping is unavailable. Wording branches: digital → `instantDownload`; no front-end method → `shippingAtCheckout`; otherwise `transitDaysRange`/`transitDaysSingle` + an arrival date from `lib/utils/arrival.ts` (`estimatedArrivalRange` / `formatArrivalRange`) + `freeShipping` / `freeShippingOver`. Transit days are **weekdays** (Mon–Fri, no holiday calendar — the API publishes the same assumption), and dates are formatted with `Intl.DateTimeFormat` per locale. The arrival label is a `sr-only` span, not `aria-label` on a plain `<span>` (Biome `useAriaPropsSupportedByRole`).

- `ProductReviews` (`components/products/ProductReviews.tsx`, P0-4 / F-1 2026-09-16) — PDP review section: rating summary (stars + count + five-bar **rating distribution**), approved review list (author, verified-purchase badge, date, **photo thumbnails**), a **Load more** button and a submit form for signed-in customers. The server component page fetches reviews + auth state via `lib/data/reviews.ts` (`getProductReviews` public → `{ reviews, meta }`, `getMoreProductReviews` for later pages, `createProductReview` posts with the customer JWT, `uploadReviewImage` presigns + PUTs a photo) and passes them into the client `ProductDetails`; the form renders only when `isAuthenticated`. i18n labels live under a top-level `reviews` namespace in `messages/*.json`. Only admin-approved reviews are returned by the Store API, so a fresh submission won't appear until moderation — and **pending photos are never exposed at all**. The list is paged by the API (10 per page); the component appends through `getMoreProductReviews`, keeps the fetched list when a page fails, and renders the server's `rating_distribution` instead of recomputing it from the loaded slice. Photo picking is prefixed by a client-side pre-flight (≤ 3 images, jpeg/png/webp, 5 MB) whose constants **stay in this file** — see the `"use server"` rule below for why they must not live in `lib/data/reviews.ts`. ⚠️ **`average_rating` is serialized as a string** (BigDecimal → string in the Store API) — always guard with `Number()` before calling `.toFixed()` (e.g. `{Number(averageRating).toFixed(1)}`). Calling `"4.5".toFixed(1)` directly crashes the PDP with `TypeError: b?.toFixed is not a function` (bugfix 2026-08-25).
- `BuyNowButton` (`components/products/BuyNowButton.tsx`, P5 2026-08-27) — PDP quick-purchase button. Creates a standalone cart with the current variant via `lib/data/buy-now.ts` `createBuyNowCart` and routes straight to `/checkout/{id}` (does not touch the cart). On the PDP it renders **in the same row as the Add to Cart button at equal width**: `ProductDetails` wraps both in `<div className="flex flex-1 gap-4">` with each action as `flex-1` (the `w-full` outline button fills its `flex-1` wrapper). The outer actions row is `flex flex-col gap-4 sm:flex-row sm:items-center`, so on mobile the quantity picker wraps to its own line while the two buttons share a row (bugfix 2026-08-29). i18n label: `products.buyNow`.
- `ProductDetails` availability states + variant deep link (PRD-20260915-catalog-pdp-state-correctness, 2026-09-15) — the PDP derives its presentation state from **existing Store API flags only**, via the pure helpers in `lib/utils/variant-selection.ts` (`deriveAvailabilityState` / `resolveInitialVariant` / `buildVariantHref` / `aggregateAvailability`): **in stock > pre-order (purchasable) > backorder (purchasable) > sold out**; pre-order shows `products.preorder` + a localized `products.preorderShipsBy` date (from `preorder_ships_at`), backorder shows `products.backorder` + `products.backorderNote`, and `BackInStockNotify` renders only in the sold-out state. `?variant=` is the shareable SKU deep link: `page.tsx` seeds `initialVariantId` from `searchParams`, `ProductDetails` falls back on unknown/stale ids (default_variant → first purchasable → first) and updates the URL through `router.replace(..., { scroll: false })` while preserving other query params (e.g. `category_id`). GA4 `view_item` reports the variant the page was opened with (`trackViewItem(product, currency, initialVariant)`); variant switches deliberately don't re-fire it. `buildProductJsonLd` (`lib/seo.ts`) emits a plain `Offer` for single SKUs and an `AggregateOffer` (lowPrice/highPrice/offerCount + most favourable availability) for multi-SKU products, with `brand` read from a custom field (`catalog.brand` / `brand` / `*.brand`, omitted when absent). New i18n keys (`products.preorder` / `preorderShipsBy` / `backorder` / `backorderNote`) are guarded for all five locales by `lib/__tests__/checkout-i18n-keys.test.ts`.

**JSON-LD phase 2** (PRD-20260917-catalog-json-ld-phase2, business plan 4.3) adds four
fields to the same `Product` schema. `buildProductJsonLd(product, canonicalUrl, context?)`
takes an optional third argument carrying what the page has **already** fetched — no new
request, no new endpoint:

| Field | Source | Omitted when |
|---|---|---|
| `seller` | `getStoreName()` + `getStoreUrl()` | the storefront URL is unconfigured (prod) |
| `priceValidUntil` | `product.price.price_list_ends_at` (the price list that was **actually applied**) | no price list, no window, or the window already closed |
| `shippingDetails` | the `getShippingEstimate` result the PDP already awaited | digital goods, or an unavailable/failed estimate |
| `hasMerchantReturnPolicy` | `getReturnPolicy()` → the return policy's structured terms | nothing configured, unknown enum, or a finite window with no day count |

**The rule is omit, never invent.** A missing field costs nothing; a wrong one is a
structured-data error (and `aggregateRating` follows the same rule already). Two
consequences worth naming: `shippingRate` is only ever written when shipping is
**known to be free** — the API hands back a *localised display string* and parsing it
would be a guess; and a `finite_window` return policy without `merchantReturnDays` is
dropped rather than published half-formed.

The return terms live on the store's return policy record (edited in **Settings →
Policies**) and reach the PDP through the existing `client.policies.get("returns-policy")`
call — the slug comes from `POLICY_LINKS`, not a second hardcoded string. The API
carries domain values (`finite_window`, `by_mail`, `free`), and `lib/seo.ts` is the only
place that maps them to schema.org vocabulary, so a schema.org revision touches one file.
Tests: `lib/__tests__/seo.test.ts` (AC-001~AC-012, including the "key absent, not null"
assertions).

### Catalog events — first-party analytics (PRD-20260917-catalog-product-events, 2026-09-17)

`lib/analytics/catalog-events.ts` mirrors the GA4 calls in `lib/analytics/gtm.ts` into the
store's **own** database so `Related Product CTR` can be computed from first-party data.
The GA4/GTM path is untouched — the sink calls are added **inside** the existing
`gtm.ts` functions (`trackViewItemList` → impressions, `trackSelectItem` → click,
`trackAddToCart` → `product_added`, `trackQuickSearch` → `product_searched`), so every
existing call site is covered without touching a component.

**Batching is mandatory, not an optimisation.** The backend's `rate_limit` bucket is keyed
by the publishable key that the whole store shares, and a subclass cannot opt out of it, so
the request count must scale with **page navigations** rather than with events:

- events accumulate in a queue for the life of a page view;
- the queue is flushed **once** on `visibilitychange` → `hidden` and on `pagehide`;
- an overflow flush fires only if one page view exceeds `CATALOG_EVENT_MAX_BATCH` (100);
- a failed flush is **dropped, never retried**, so analytics can never compete with real
  user traffic for the budget. `sendCatalogEvents` returns `null` on failure (AP-009b).

The Store API call goes through the `"use server"` action in `lib/data/catalog-events.ts`
because `PALLASTRADE_API_URL` / `PALLASTRADE_PUBLISHABLE_KEY` are server-only env vars — a
client component must never build an SDK client itself. The visitor id is a **random** value
kept in `localStorage` (`pallastrade_visitor_id`) and is hashed server-side; no IP, user
agent, email, customer id, or search term is ever sent. Tests:
`lib/analytics/__tests__/catalog-events.test.ts`.

**Client-component import rule (build breaker):** a `"use client"` component MUST NOT import from the `@/lib/pallastrade` barrel (`index.ts`) — the barrel re-exports server-only cookie/`next/headers` helpers, and pulling them into the client bundle fails `next build` with "Ecmascript file had an error" on `import { cookies } from "next/headers"`. Import the specific client-safe module instead, e.g. `getClient` from `@/lib/pallastrade/config`. Server components / route handlers may keep using the barrel.

**Client-component SDK calls go through server actions.** `PALLASTRADE_API_URL` / `PALLASTRADE_PUBLISHABLE_KEY` are **server-only env** (no `NEXT_PUBLIC_` prefix), so `getClient()` throws in the browser. A client component that needs the Store API must call a `"use server"` action in `src/lib/data/` (e.g. `cart.ts`, `backInStock.ts`) that runs `getClient()` server-side; the action returns a `{ success, error }` result (via `actionResult`). Never build an SDK client directly in a client component.

**A `"use server"` module may only export async functions (build breaker).** Exporting a plain `const`, `let` or non-async helper from a `"use server"` file (e.g. a limit like `REVIEW_IMAGE_LIMIT = 3`) fails `next build` with `Error: Turbopack build failed … Only async functions are allowed to be exported in a "use server" file` — often reported against **every** importer (10+ errors) instead of the offending file. Types/interfaces are fine (they erase); values are not. Keep such constants in the client component that needs them (or another plain module) and leave a private copy for the server action when it has to validate too. `pnpm typecheck` and `vitest` do **not** catch this — run `pnpm build` before pushing storefront changes (2026-09-16, F-1).
- `TawkToWidget` (`components/layout/TawkToWidget.tsx`) — optional Tawk.to live-chat widget, mounted in the root layout `<body>`. Enabled only when BOTH `NEXT_PUBLIC_TAWK_TO_PROPERTY_ID` and `NEXT_PUBLIC_TAWK_TO_WIDGET_ID` are set (public IDs, like publishable keys — safe for `NEXT_PUBLIC_`); loads via `next/script` `afterInteractive` so it never blocks first paint. Renders `null` (no third-party script) when either var is missing.
- `TurnstileWidget` (`components/auth/TurnstileWidget.tsx`) — optional Cloudflare Turnstile human-verification widget, used on the registration form (`account/register/page.tsx`). Enabled only when `NEXT_PUBLIC_TURNSTILE_SITE_KEY` is set (the site key is PUBLIC — it is not a secret); loads the script from the **exact official URL** `https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit` (explicit rendering — the path MUST include `/v0/`, omitting it returns 404 + `Cross-Origin-Resource-Policy: same-origin` which blocks loading) and reports the `cf-turnstile-response` token through `onTokenChange`. **The component ALWAYS renders a visible wrapper** (border + status area) with loading → ready/error states; if the script fails to load (network/region blocking) it shows an error message + retry button (retry reloads the script with a native `<script>` tag so next/script dedup can't swallow it). Labels are passed via the `labels` prop (i18n lives in the parent). The page must gate submission on the token when the widget is enabled; the backend validates the token server-side via `PallasTrade::Api::Turnstile` (secret key only from `ENV['TURNSTILE_SECRET_KEY']`, never committed).

### Cookie consent (2026-08, PRD-20260812)

> 组件与测试文件统一遵循 Biome 格式（`pnpm format` / `pnpm check`），CI 的 `pnpm check` 强制校验格式与 lint。

The storefront has a GDPR/CCPA-style cookie consent system. Consent is stored in a
plain-JS-readable cookie `pallastrade_cookie_consent` (JSON: `necessary` + `functional`
/ `analytics` / `marketing` booleans + `version` + `updatedAt`). Categories and the
cookie name are defined in `lib/constants/cookies.ts`; pure parse/serialize helpers
and the `document.cookie` read/write layer live in `lib/cookie-consent.ts`
(unit-testable without a DOM). Key pieces:

- `CookieConsentProvider` (`contexts/CookieConsentContext.tsx`) — client provider in the
  **root layout**; reads the consent cookie in an effect. It exposes `acceptAll` /
  `rejectAll` / `savePreferences`. **Do NOT put "client mounted" state in the provider** —
  it crosses streaming boundaries and causes React hydration mismatches. Each consumer
  keeps its own local `useState`+`useEffect` `mounted` flag in the same component that
  conditionally renders.
- `CookieBanner` (`components/cookie/CookieBanner.tsx`) — first-visit banner (Accept all /
  Necessary only / Customize). Renders `null` until mounted AND undecided, so returning
  visitors never see a flash. Mounted in `app/[country]/[locale]/layout.tsx`.
- `CookieSettings` (`components/cookie/CookieSettings.tsx`) — the shared category toggle
  panel (used by the banner's "Customize" and the standalone settings page). Necessary is
  always enabled and disabled.
- `Cookie settings page` (`app/[country]/[locale]/(storefront)/cookies/page.tsx`) — server
  component route with `cookie` i18n metadata; footer links to it (`footer.cookieSettings`).
- `GatedScripts` (`components/cookie/GatedScripts.tsx`) — client gate in the **root layout**
  that mounts third-party scripts only after consent: GTM (`NEXT_PUBLIC_GTM_ID`,
  analytics), Vercel Analytics / Speed Insights (`NEXT_PUBLIC_VERCEL_ANALYTICS` +
  `NODE_ENV=production`, analytics), Tawk.to (marketing). Loads nothing before consent.
- Sentry client reporting (`instrumentation-client.ts`) is gated per-event via
  `beforeSend` / `beforeSendTransaction` checking `readConsentFromDocument()?.analytics`.

Necessary cookies (cart token, auth JWT, locale/country, the consent cookie itself) are
never gated. All banner/settings copy lives in the `cookie` i18n namespace across all
5 locale files.

### Home page sections (2026-08 redesign, PRD-20260810)

The home page (`app/[country]/(storefront)/page.tsx`) composes 8 sections in `components/home/`:

- `HeroSection` — brand tagline + value prop + primary/secondary CTAs (no demo links).
- `FeaturedProductsSection` — product grid + "view all".
- `PromoBanner` — wide gradient band, retargeted as a "limited-time offers" sale banner (distinct from featured products).
- `ValueProps` — 4 trust props (shipping / authenticity / returns / support).
- `BrandStory` — GEO-friendly "answer-ready" brand paragraph.
- `FaqSection` — visible Q&A + matching `FAQPage` JSON-LD (structured data always mirrors visible content).
- `ContactForm` (`components/home/ContactForm.tsx`, **client component**) — complaint / feedback / inquiry form behind the footer `#contact` anchor. Classifies by `kind` (complaint / feedback / inquiry), validates email + body, and submits via `createContactMessage` server action (Store API `POST /api/v3/store/contact_messages`, guest-accessible). Messages surface in the admin **Email → Inbox & Feedback** page. Client-safe import: the action lives in `lib/data/contact.ts` (`"use server"`), so the component never imports the server-only barrel. i18n under the `contact` namespace in all 5 locale files.
- `NewsletterSignup` — client component, front-end validation + success state (no backend yet).

`CategoryNav` (`components/layout/CategoryNav.tsx`) is a **persistent desktop category bar** — a **client component** (receives categories as props from the server layout). **Hovering a root category opens its sub-category mega panel** (grid of all level-2 children, each column listing level-3 grandchildren inline, plus a "View all" footer link); **clicking locks the panel open** (click again / click outside closes). `hidden md:block`, `overflow-x-auto` for many categories. The mobile drawer `MobileMenu` (`md:hidden` trigger) remains the small-screen entry point. There is deliberately **no separate home "shop by category" section** and **no sr-only category nav** — the visible nav bar already covers category browsing.

### Header: account entry + single search overlay + mobile menu search (2026-09-08, PRD-20260908-storefront-小屏下个人中心入口可见与移动菜单search弹出搜索框)

- `SearchToggle` (`components/layout/SearchToggle.tsx`, **client**) owns the **only** search-overlay state (`searchOpen`) and exports `SearchOverlayContext` + `useSearchOverlay()` (`{ open, openSearch, closeSearch }`) so **any sibling slot** (e.g. the mobile menu's Search row) can open the same `#search-overlay` (auto-focused `SearchBar`; Esc / click-outside / ✕ close). **Never build a second search UI** — reuse this overlay.
- `Header`'s account (User icon → `{basePath}/account`) renders on **all breakpoints** (the old `hidden md:block` wrapper is gone). Do not re-add a desktop-only gate — the mobile personal-center entry lives in the top bar too.
- `MobileMenu` main-panel **"Search" row is a `<button>`**: it closes the drawer and calls `openSearch()` (fallback: navigate `/products` only when rendered outside `SearchToggle`). The drawer footer **"My Account"** link stays as the in-menu account entry (PRD-20260810 AC-103).

### SEO / GEO (2026-08)

- JSON-LD helpers in `lib/seo.ts`: `buildOrganizationJsonLd`, `buildWebsiteJsonLd` (WebSite + SearchAction → `{basePath}/products?q={search_term_string}`), `buildProductJsonLd`, `buildBreadcrumbJsonLd`, `buildCategoryItemListJsonLd`. The storefront layout injects Organization + WebSite; pages inject Product / Breadcrumb / ItemList / FAQPage. `buildProductJsonLd` adds an `AggregateRating` (`ratingValue` = `product.average_rating`, `reviewCount` = `product.review_count`, `bestRating: 5`) whenever the product has at least one approved review (P0-4) — the fields come from the Store API Product serializer.
- `/llms.txt` (`app/llms.txt/route.ts`) — llmstxt.org site overview (title, about, categories, key pages, structured-data note). Route handlers are dynamic by default; do NOT add `export const dynamic` (incompatible with Cache Components mode).
- Semantic HTML rules: exactly one `h1` per page; sections use `section[aria-labelledby]`; images carry meaningful `alt`.

### SEO 301 redirects (2026-08, phase-1)

`src/lib/pallastrade/middleware.ts` (`createPallasTradeMiddleware`, wired via Next.js 16
`src/proxy.ts`) resolves every storefront pathname against the store's SEO redirects via
`GET /api/v3/store/redirects/resolve?path=...` (60s `revalidate` cache, 3s timeout). On a hit it
issues `NextResponse.redirect(target, status)` (guarded against A→A loops); on API failure it
**degrades open** (continues normal rendering — Turnstile-style). Redirects are managed in the
admin (Developers → Redirects) as `PallasTrade::Redirect` records. Static assets, `_next/*`
and `api/*` are excluded by the proxy matcher. Do NOT add a separate `src/middleware.ts` —
Next.js 16 errors when both a middleware and a proxy file are present.
### Blog posts — CMS (2026-08, PRD-20260816-other-新增cms博客)

Blog is rendered from the PallasTrade CMS `Post` model (published only):

- Routes: `/blog` (list) and `/blog/[slug]` (detail) under
  `app/[country]/[locale]/(storefront)/blog/`.
- Data layer: `src/lib/data/posts.ts` (`listPosts` / `getPost`) uses `client.posts.list`
  / `client.posts.get` from `@pallastrade/sdk`.
- Components: `src/components/blog/PostCard.tsx` (server component; cover image, title,
  excerpt, author, publish date).
- SEO: detail page `generateMetadata` uses `seo_title`/`seo_description` (fall back to
  title/excerpt) + JSON-LD `Article`; published posts are added to `src/app/sitemap.ts`
  via `client.posts.list` (`Post` type from SDK).
- Locale messages: `blog` namespace in all 5 `messages/*.json` files.
- Do NOT use inline `style={{}}` — Tailwind classes only (AP-001).
### Client-side cart

Carts are server-state, so use SWR or React Query. The cart ID + token persist in a cookie:

```tsx
'use client'
import useSWR from 'swr'

export function MiniCart({ cartId, token }: { cartId: string; token: string }) {
  const { data: cart } = useSWR(
    ['cart', cartId],
    () => pallastrade.carts.get(cartId, { guestToken: token })
  )
  if (!cart) return null
  return <span>{cart.items.length} items</span>
}
```

#### Applied discounts — one canonical shape everywhere (2026-09-10, PRD-20260909-promotions-promo-batch2)

`cart.discounts`, `order.discounts` and the Checkout API's `discounts` now render the **same** rows
(`DiscountLine` in the OpenAPI/SDK types): one row per promotion, aggregating its eligible
order / line-item / shipment adjustments. Fields the storefront may rely on:

| Field | Use |
|---|---|
| `code` | Coupon code to display and to send back when removing (`CouponCode` filters on it; `gtm.ts` reads it for the purchase payload) |
| `display_amount` | Pre-formatted negative amount for display |
| `name` / `description` | Fallback label when the promo has no code |
| `removable` | Show the remove button (coupon-code promos only) |
| `promotion_id`, `kind`, `amount`, `breakdown` | Analytics / detail UIs |

Invariant: `SUM(discounts[].amount) == discount_total`; when `hide_prices` is set the whole field is
`null` (gate UI accordingly). `discounts[].id` is an order-promotion id (`discount_…`), not an
adjustment id — never treat it as an Adjustment reference.

### Checkout

**结算页占位控件治理（PRD-20260914-checkout-placeholder-controls-governance，2026-09-14）**：`UnifiedCheckout` 的 `SHOW_PLACEHOLDER_SECTIONS = false` 控制三个**无后端能力**的占位区块（Add-ons 无定价管线 / SMS opt-in 无发送通道 / Save Info 无持久化语义）—— 组件与文案保留，改成 `true` 即恢复；**无后端能力时不要渲染**（对顾客是无效承诺）。Marketing opt-in 已**真正接线**：订单创建成功后经 BFF `POST /api/checkout/newsletter`（服务端 SDK `newsletterSubscribers.create`）best-effort 订阅，**订阅失败绝不阻断下单**（NFR-1）；该 BFF 对跨域 403、空邮箱 422、provider 失败 `202 { ok: false }`（不向买家暴露错误）。

The Store API exposes payment sessions for the checkout flow — a single, provider-agnostic endpoint that works with any session-based gateway (Stripe, Adyen, PayPal); the provider is selected via `payment_method_id`. The pattern:

1. Customer hits checkout — `POST /api/v3/store/carts/:cart_id/payment_sessions` with a payment method choice (cart token in `X-PallasTrade-Token` header).
2. Backend returns a session with provider-specific data (Stripe Checkout URL, Adyen drop-in token, etc.).
3. Storefront redirects to the provider OR renders the provider's embedded form.
4. Customer completes — provider posts back to the PallasTrade backend, which fires `payment_session.completed` events.
5. Storefront calls `pallastrade.carts.paymentSessions.complete(cartId, sessionId, { session_result: 'success' }, options)` once the customer confirms, then `pallastrade.carts.complete(cartId, options)` to get the Order — or relies on the provider webhook, in which case the backend completes the cart → order transition automatically.

The `pallastrade_stripe` / `pallastrade_adyen` / `pallastrade_paypal_checkout` gems ship reference checkout flows. Don't roll your own unless you're integrating a new provider.

#### Standard e-commerce flow (P1 2026-08-30, PRD-20260829-checkout + PRD-20260830-checkout 下单链路统一化)

New Cart entity (`pallastrade_carts`, independent table — see `pallastrade-data-model`) with a standard flow. Since 2026-08-30 the flow is unified (阿里国际站风格：一页确认+支付 / 收银台弹窗):

1. **Cart page** `/{country}/{locale}/cart` (`lib/data/shopping-cart.ts`): line-item `selected` checkboxes, select-all, quantity, remove. Only selected items flow into the order. Client component — all SDK calls go through `"use server"` actions (`updateCartItemSelection`, `setAllCartItemsSelected`, `updateCartItemQuantity`, `removeCartItem`); never import `getClient()` in a client component. Current-cart resolution (`getCart()` / `getShoppingCart()` without an explicit ID) must accept `status === "active"` only: after submit changes the cart to `converted`, the cart page renders empty and the next Add to Cart creates a new active cart instead of surfacing the expected converted-cart authorization rejection. Explicit-ID reads remain available to the checkout recovery path. **车阶段抵扣（PRD-20260914-checkout B2，2026-09-14）**：Order Summary 的「优惠与抵扣」模块 + 三行摘要（折扣码 / 礼品卡 / 店铺余额）全部由服务端 `ShoppingCart` 意图快照驱动（`discount_code` / `gift_card` / `store_credit`，车阶段零资金副作用，提交时由 `Carts::Submit` 兑现）——动作走 `lib/data/shopping-cart.ts` 的 `applyDiscountCode|removeDiscountCode|applyGiftCard|removeGiftCard|applyStoreCredit|removeStoreCredit`（`"use server"`，服务端错误码经 `actionResult` 的 `code` 透传给 UI 映射 i18n）；**未登录时余额按钮禁用 + 登录引导（不发请求）**，礼品卡已应用时余额按钮禁用（服务端互斥 `store_credit_gift_card_conflict`）；折扣金额在提交时才计算 → 折扣行必须带「结算时计算」提示；合计仍是 `display_item_total`。 **去结算** → `/checkout/[cartId]`（统一下单页，不再有独立的 `/checkout-info` 确认页——该目录已删除）。
2. **Unified checkout** `/{country}/{locale}/checkout/[id]`（`components/checkout/UnifiedCheckout.tsx`，购物车模式）：main column = email + `AddressFormFields` + delivery-method radio + payment-method radio（**商品明细自 2026-09-19 起只保留在右栏订单摘要**，左栏重复的 Items 区块已删除，见下条）；order summary 通过 `CheckoutContext#setSummaryContent` 发布到 desktop sticky sidebar。Stripe `CardPaymentForm` is rendered immediately but creates no provider object until Pay. One Pay calls same-origin `POST /api/checkout/start`（update Cart → idempotent submit → start/reuse Order session）, confirms the returned PaymentIntent in the same handler, best-effort PATCHes completion, then opens `/payment-result/[orderId]?session=...`. Never redirect to `checkout/or_` for a second Pay.
   **移动端摘要折叠按钮（PRD-20260919-checkout-remove-items-block-mobile-summary-meta，2026-09-19）**：`CheckoutContext` 除 `summaryContent` 外还发布 `summaryMeta`（`{ itemCount, displayTotal }`，取服务端 `ShoppingCart.item_count` / `display_item_total`）；`(checkout)/layout.tsx` 的 `MobileSummaryToggle` 收起时渲染 `checkoutLayout.showOrderSummaryWithMeta`（`Show order summary · N items · $X`，ICU 复数五语言），展开态仍是纯 `Hide order summary`。回退：`summaryMeta` 缺失或 `displayTotal` 为空 → 纯 `showOrderSummary`；`summaryContent === null`（`order-placed` / `payment-result`）→ 按钮整体不渲染；`or_` 订单页（`OrderPaymentContent`）只发布内容、不发布元数据 → 自动走纯文案，无需改动。
   **物流变化提示只有一个面（PRD-20260919-checkout-remove-shipping-change-placeholder-banner，2026-09-19）**：第 3 节（Shipping method）内那个恒显的黄框「The shipping options have changed…」是 PRD 3.4 的**占位遗留**（后端从未提供 `shipping_options_changed` 信号）——已删除，文案键 `checkout.shippingOptionsChanged` 五语言一并清理。运费/物流变化的**唯一**呈现面是页面顶部 `data-testid="checkout-quote-diff"`（服务端 `quote_changed` / `checkout_version_conflict` 时出现，`quote-diff-shipping` 行展示运费 before → after）。新增任何「已变化」类提示前，先确认服务端是否真有对应信号（否则就是下一个常显占位）。
3. **Order payment** `/{country}/{locale}/checkout/[id]`（`components/checkout/OrderPaymentContent.tsx`，`or_` 订单模式）：read-only shipping and direct card form. It creates/reuses the existing Order session and ends at the unified payment result. Non-session methods remain pending and also use the result page. B1（PRD-20260914-checkout B1）：抵扣行（gift card / store credit）、支付方式列表与「编辑/支付」门控全部取自服务端 CheckoutView（`credits` / `payment.available_payment_methods` / `capabilities`），order 快照仅作兼容回退；展示遵循 money 契约（raw 判逻辑、display 仅渲染、抵扣正值 + UI 负号）。
4. **Buy Now** creates an isolated Cart tagged with `checkout_source=buy_now` + `previous_cart_id`; after submit the BFF restores the previous regular Cart cookie from `successor_cart`.
5. **Cashier modal（个人中心场景 D）** `components/checkout/PaymentCheckoutModal.tsx`：only payment UI, never Cart submit/Order create. Single Order uses Order sessions; multi-order uses PaymentCombination. Every provider success/failure/cancel/pending outcome navigates to the same server-authoritative result page instead of closing and guessing via `router.refresh()`.
6. **库存错误与履约结果页（PRD-20260915-checkout B3，2026-09-15）**：结账页按服务端 code 分流三态库存错误——`INSUFFICIENT_STOCK` → 专属标题 + [返回购物车]；`INVENTORY_CHANGED` → 专属标题 + 「检查购物车」；`RESERVATION_EXPIRED` → **自动重试一次**（仅该码），失败回落为手动 [重新确认库存]。**约束**：`INSUFFICIENT_STOCK`/`INVENTORY_CHANGED` **不得自动重试**（§26/§27：不得继续创建新 PaymentSession），自动重试不得新建订单、且一次为限（`stockRetryRef` 守卫 + 等 `payProcessing` 复位后的 effect 触发）。支付结果页（`payment-result/[id]`）对已找到的订单**所有状态**渲染履约摘要（`order` 命名空间的 Ship to / Delivery / Items / Paid / Promotion savings + 「查看订单」；非成功态用 `orderContents` 副标题，**绝不出现 “Order confirmed”**）；多履约经 `components/order/ShippingGroups.tsx` 按 Shipment 分组（单履约不渲染分组标题；`fulfillment.items[].item_id` 找不到 line item 时静默降级）；`?session=` 只用于服务端状态判定，transaction / reservation / payment session 标识一律不进 DOM（§37）。

Keys: cart items use `selected`; submitted Orders get short-lived HttpOnly checkout-token cookies because the current-cart cookie may switch to a successor. Totals always come from the API. **Money 契约（PRD-20260913-checkout-money-contract，2026-09-13）：raw 金额字段（`delivery_total` / `tax_total` / `discount_total` …）只用于条件判断；`display_*` 只用于渲染** —— 禁止 `parseFloat/Number(display_*)`（display 含货币符号 → `NaN`；`OrderPaymentContent` 运费/税行曾因此不渲染；邮件 `order-confirmation` 同理需传 raw 入参）。"TOTAL SAVINGS" 只统计促销折扣（`|discount_total|`），礼品卡 / 店铺余额是支付手段，单列不计入节省。Result text lives under `paymentResult.*` in all five locales.

**两段语义（PRD-20260915-checkout-单页两段语义，2026-09-15）**：`UnifiedCheckout` 点 Pay Now **先 Prepare、再 Pay** —— `POST /api/checkout/prepare`（BFF：`carts.update` + `carts.submit`，返回 `{ order_id, order, quote }`，**不建** PaymentSession/Transaction）→ 拿到 Order 权威报价（含运费/税费）后**页内确认区**（`data-testid="order-quote-confirm"`，金额全部用 `display_*` 只读渲染）→ 用户点「确认并支付」才 `POST /api/checkout/start`（**只做 Pay**：`order_id` + `payment_method_id` + `session_required` + `expected_checkout_version`/`expected_price_version`）。已建订单会被记住（`preparedOrder`），所以**重试（如预留过期自动重试）不会重复 submit 购物车**。降级：Prepare 未返回权威报价时不渲染空确认区，保持一次点击直付（金额由支付控件自身展示）。钱包（Express）仍走合并语义（面板即金额确认界面）。
**CI 提示（2026-09-15 实测踩坑）**：`pnpm check`（= `biome check .`）是**全量**检查——改完组件/测试后必须跑全量，而不是只跑改动文件；测试断言里禁止 `(call?.[1] as RequestInit).body` 这种「可选链 + 断言后立即取成员」写法（`lint/correctness/noUnsafeOptionalChaining`），先赋值再取 `.body`；`messages/*.json` 新增长文案后需 biome 格式化，否则 CI 红灯。

**Express 钱包 canonicalize（PRD-20260915-checkout B4，2026-09-15）**：Apple/Google Pay 钱包**不再**走 cart 域 legacy 会话，与结账页共用同一条链。`components/checkout/ExpressCheckoutButton.tsx` 的 `onConfirm` 顺序固定为：
1. `elements.submit()` → 取 `cart.payment_methods` 中 `session_required` 的支付方式；
2. `lib/checkout/express-canonical.ts#startExpressCheckout({ cart_id, payment_method_id, payment_mode: "payment_intent", checkout: { email, shipping_address, billing_address, billing_mode } })` → `POST /api/checkout/start`（BFF 内 `carts.update → 幂等 submit → orders.transactions.create`；**不传 `shipping_method_id`**——配送费率已在车阶段 `expressCheckoutSelectRates` 服务端入账，`Cart` 类型也没有该字段）；
3. `startResult.ok === false` 时按 `expressErrorRoute(code)` 分流：`recovery`（`INVENTORY_RECOVERY_REQUIRED` / `transaction_not_payable`）→ `expressResultUrl(...)?notice=…` 且**绝不** `event.paymentFailed`（资金事实已发生）；其余 → 抽屉内提示（服务端 `message`，经 `normalizeErrorMessage`）+ `event.paymentFailed`；
4. `expressClientSecret(session)` 为空 → 不调 `stripe.confirmPayment`；有值 → `confirmPayment({ elements, clientSecret, confirmParams: { return_url: expressResultUrl(origin, basePath, orderId, sessionId) }, redirect: "if_required" })`；
5. `await completeExpressCheckout(orderId, sessionId)`（`PATCH /api/checkout/start`，**best-effort**：失败仅 `console.warn`，webhook / `Transactions::OnPaymentSuccess` 兜底）→ `router.push(returnUrl)` → `onComplete()`。

**禁止**（回归守护 `src/lib/data/__tests__/legacy-payment-sessions-guard.test.ts` 已机器化）：storefront 任何源码出现 `carts.paymentSessions.*`；恢复 `/confirm-payment` 页（已删，历史 3DS return_url 深链由 `/payment-result` 承接）、lib/data/payment.ts（已删除，勿恢复）；钱包把用户送到 `order-placed` 或第二张支付页。`stripe.createPaymentMethod` 已从钱包移除（canonical 会话创建不接受网关侧 PM id）。组合/多单支付同样改走 Order 域 `orders.paymentSessions.complete`（`lib/data/payment-combination.ts#completeCombinationSession`）。

**零 legacy 调用（B5 扩展，2026-09-15）**：守护测试 `src/lib/data/__tests__/legacy-payment-sessions-guard.test.ts` 现在覆盖 §45 六行 —— ① 全仓源码（注释豁免）零 `carts.paymentSessions` / `carts.payments` / `carts.complete`；② `carts.{fulfillments,giftCards,storeCredits,discountCodes}` **只允许**出现在白名单四个文件（`lib/data/shopping-cart.ts`、`lib/data/checkout.ts`、`lib/data/express-checkout-flow.ts`、`app/api/checkout/coupon/route.ts`）——新增文件使用即失败。后端对 legacy 身份（非 `cart_`）回 `Deprecation`/`Warning`/`Link` 三头（B5），`cart_` 流量不受影响。

**Checkout 账单地址同配送建模（PRD-20260913-checkout-billing-mode，2026-09-13）**：`UnifiedCheckout` 发 `billing_mode: 'same_as_shipping' | 'custom'`，**不再发 `use_shipping`** —— 该字段不在 Store API 参数白名单（`carts_controller#permitted_params`）内，会被 ActionController 静默丢弃，正是「勾选同配送但 `Order.bill_address` 为空」的根因。约定：① 勾选初值 = `!cart.billing_address`（避免静默覆盖既有独立账单地址）；② 取消勾选时账单地址不完整 → 页内拦截并提示 `checkout.billingAddressIncomplete`（五语言，`checkout-i18n-keys` 守护）；③ 服务端账单快照 = 显式账单地址 → 否则配送地址副本（`Carts::Submit`），`billing_mode: 'custom'` 但地址不完整时返回校验失败且不落库。
**Storefront 验证清单（2026-09-14，CI 红线教训）**：`pnpm test`（vitest）**不够** —— 改动 storefront 后必须同时跑 ① `pnpm check`（biome）与 ② `pnpm typecheck`。`JSON.parse` 会静默保留重复键的最后一次定义，vitest 无法发现 i18n 重复键，而 biome `lint/suspicious/noDuplicateObjectKeys` 会让 Storefront CI 的 “Run pnpm check” 直接失败（实际发生过：5 语言 `checkout.returnToCart` 重复）；跨包引用 SDK 类型前先 `pnpm --filter @pallastrade/sdk build`（storefront 的 TS 解析走 `dist`）。**注意：任何后续编辑（哪怕只改测试文件）都要重跑 `pnpm check`** —— 第二次 CI 红线就是测试文件格式（`Formatter would have printed the following content`），发生在“只跑 vitest、没复验 biome”之后。
**Formatter 与 printWidth（2026-09-15 第三次 CI 红线）**：biome 的 `lineWidth` 是 **80**，`const result = await createBackInStockSubscription(productId, value, variantId);` 这类 84 字符单行会被判 **error**（`Formatter would have printed the following content`），Storefront CI 直接红。**本地复现只需 `pnpm check`（在 `storefront/` 目录里跑）**；修法 `node node_modules/@biomejs/biome/bin/biome check --write <该文件>`。⚠️ **不要用 `git checkout -- <file>` 回退 biome 的格式化结果**——那正是把 CI 红线重新引入（本次踩过）；只把**与本批无关**的文件回退（`biome check --write src` 会顺手改历史文件）。
**BFF 错误契约 + `/api` 路由所有权（bugfix 2026-09-06）**：storefront BFF（`app/api/checkout/start`、`app/api/checkout/coupon`、`app/api/webhooks/pallastrade`）错误统一为后端 v3 envelope `{ error: { code, message } }`（顶层 `order_id` 保留供失败恢复）。**UI 展示前一律经 `lib/errors.ts#normalizeErrorMessage` 归一化为字符串**，禁止把 unknown/object 直传 sonner `toast.error` 或 JSX——否则 sonner 渲染对象触发 React error #31 → global-error 整页崩溃（本 bug 现场根因）。nginx 反代所有权：`/api/v3/* → Rails`，其余 `/api/* → Next`（storefront BFF 默认即达）；权威配置版本化于 `deploy/nginx/dev.pallastrade.cn.conf`，由 pull-deploy 在每次部署后经 `deploy/nginx/sync-and-smoke.sh` 原子同步并做路由归属 smoke。**不要在 BFF 手工加 `location /api/xxx` 例外——默认已进 Next。**

**Checkout 交易错误落点分流（PRD-20260913-checkout-txn-error-routing，2026-09-13）**：`UnifiedCheckout#handlePayNow` 对“提交后”错误必须**按 `code` 分流**（用 `lib/errors.ts#extractErrorCode`；**不得**以“是否带 `order_id`”为准）：
- `quote_changed` / `checkout_version_conflict` → **留在 `cart_` 页内**（PRD-20260914-checkout-quote-confirmation-loop，2026-09-14）：Pay Now 携带客户端报价快照（`lib/checkout-quote.ts`：`readQuoteSnapshot`/`expectedVersions`，存于 sessionStorage）；409 时渲染 `checkout-quote-diff`（Shipping / Promotion / Amount due 旧→新）并用服务端最新报价覆盖快照，要求**重新点击**；**绝不跳转、绝不自动扣款**。（取代 PRD-20260913 的 `router.replace('/checkout/or_…?notice=quote_changed')` 分支；`or_` 页的 `quoteUpdatedBanner` 保留为其他入口的兜底。）
- `INSUFFICIENT_STOCK` / `INVENTORY_CHANGED` / `RESERVATION_EXPIRED` → **页内** `checkout-error-notice`（`role="alert"`；标题 `checkout.stockUnavailableTitle` + 服务端 message + `checkout.returnToCart` CTA）——**不进结果页**、不出现“支付失败”字样（此时无任何 PSP 扣款）；
- `INVENTORY_RECOVERY_REQUIRED` → `/payment-result/{or_ id}?notice=recovery`；`transaction_not_payable` → 同页 `?notice=processing`；结果页两种 notice 均**隐藏** `retryPayment` / `refreshStatus`（防重复支付）；
- `checkout_not_ready` → 页内提示（无 CTA）；其他 code 且带 `order_id` → 保留跳结果页（回归兜底）。展示文案一律经 `normalizeErrorMessage`。

#### Account orders: single vs combined payment (2026-08-29, PRD-20260829-checkout 订单模块；2026-08-30 改收银台弹窗)

- **`OrderCombinedPay`** (`components/account/OrderCombinedPay.tsx`) opens **`PaymentCheckoutModal`** on Pay selected: **1** unpaid order → 单笔弹窗（`Orders::PaymentSessions`）；**2+** → 组合弹窗（弹窗内 `POST /payment_combinations` + 各单分摊 + `PaymentCombinations::Complete`）。弹窗打开/切换支付方式即创建 session 并直接显示 `StripePaymentForm`，不需要先点 Pay 揭示表单。个人中心订单列表只消费 ownership-scoped `GET /customers/me/orders` 的结果，不按 email 做前端补偿过滤，也不读取当前 cart 来决定订单支付方式；弹窗从订单自己的 `payment_methods` 选择，服务端仍按当前 store + JWT customer 验证每一笔订单。个人中心订单可能是 `completed_at` 已有但仍 `balance_due`；order payment-session API 必须按 ownership-scoped show 权限解析，不能复用排除 completed order 的普通 `:update` 权限。不再跳 `/combined-payment/[pcom_id]` 两步页。
- **`OrderDetail`** (`components/account/OrderDetail.tsx`) 补 **Pay Now**（`components/account/OrderPayButton.tsx`，`balance_due` 且非子订单）→ 打开单笔收银台弹窗（AC-007）。
- **账户区会话门控（bugfix 2026-09-07）**：账户区鉴权由 `storefront/src/app/[country]/[locale]/(storefront)/account/layout.tsx`（client）统一负责——`!loading && !isAuthenticated` 且非 auth 页/非 `/account` 时 `router.replace(/account?redirect=<回跳>)`（登录成功后回跳原页）。订单历史数据来自 ownership-scoped `GET /customers/me/orders`（必须 JWT，后端已含全部所属订单）；因此“未登录查单看不到订单”= 会话/账户语义，登录所属账户即正常展示。注意：不要在 Server Component 页面里做 `next/navigation#redirect()` 服务端门控——本部署（Next 16）服务端 redirect 对匿名直连不产生 307（curl/无 JS 可见空态），一律走 client 布局门控。
- **`CombinedPaymentCheckout`**（CHK-P1-4C 2026-09-04 已移除：组件与 `/combined-payment/[pcom_id]` 路由均已删除，现行入口 = `PaymentCheckoutModal`）——以下为移除前的两步页行为，供追溯：step 1 **收货** (per-member-order `AddressFormFields` + save via `lib/data/payment-combination.ts` `updateOrderShippingAddress` → `PATCH /customers/me/orders/:id/shipping_address`; saved-address dropdown; no-address orders forced before continuing) → step 2 **商品 + 支付** (per-order itemized lines + combined total + `StripePaymentForm`; no address inputs in the payment card). Uses `paymentCombinations.get(id, { expand: ['orders'] })` for member order items/addresses.

#### Recovering a guest cart from an emailed checkout link (abandoned-cart recovery)

Recovery emails (e.g. `abandoned_cart_mailer.recovery_email`) link back to `/{country}/{locale}/checkout/{cart_id}?token=…`. The checkout page must restore the cart token cookie **before** fetching the cart, otherwise the guest cart is treated as anonymous:

```tsx
// page.tsx — Server Component
export default async function CheckoutPage({ params, searchParams }) {
  const cartId = (await params).id
  const token = searchParams?.token
  if (token) await setCartCookies(cartId, token) // writes cart token cookie for this guest cart
  const cart = await pallastrade.carts.get(cartId, { guestToken: token })
  // …
}
```

Use `setCartCookies(cartId, token)` (shared cookie helper) so subsequent client-side fetches and the payment session calls carry the token.

#### ⚠️ NEXT_PUBLIC_* build/runtime divergence → React #418 hydration mismatch (PALLAS-CUSTOM bugfix 2026-08-25)

Symptom: checkout page blank / stuck on the loading skeleton; console shows `Minified React error #418` (hydration text mismatch) on production builds; the page occasionally recovers after 30–60s or never does. Product/PDP pages (server-component layout) are unaffected — only pages whose **layout or header/footer are client components** (e.g. the `(checkout)/layout.tsx`, `Header.tsx`, `Footer.tsx`, `StoreContext.tsx`) throw it.

Root cause: client components read `NEXT_PUBLIC_*` (e.g. `getStoreName()` in `lib/store.ts`) — those are **inlined into the client bundle at build time**. Server components read the **runtime** `process.env`. If the build-time value differs from the runtime env file value (`.env.storefront.dev` → `NEXT_PUBLIC_STORE_NAME=PallasTrade-Dev`), the server SSR-renders one string while the client hydrates another → #418 → React aborts hydration → the mounted-gate `useEffect` never runs → permanent skeleton / blank page.

Correct fix (not just a mounted gate): **bake every `NEXT_PUBLIC_*` that client components read as a Docker build arg, and make it exactly match the runtime env file**:
- `storefront/Dockerfile` — declare `ARG` + `ENV` for `NEXT_PUBLIC_STORE_NAME`, `NEXT_PUBLIC_SITE_URL`, `NEXT_PUBLIC_DEFAULT_LOCALE`, `NEXT_PUBLIC_DEFAULT_COUNTRY` (in addition to the existing Tawk/Turnstile/Stripe args).
- `.github/workflows/deploy.yml` + `deploy/docker-compose.dev.yml` — pass the same values as build args.
- Runtime `.env.storefront.*` must keep the identical values.

A mounted gate (render the checkout body only after client mount, SSR outputs the skeleton) is a **fallback** that stops the checkout body from participating in hydration, but it does NOT fix the underlying mismatch — always fix the env consistency first. Verify: after deploy, the SSR HTML and the client bundle must contain the same store name; console must be free of #418.

#### ⚠️ Stripe PaymentElement silently empty when `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` is not baked (PALLAS-CUSTOM bugfix 2026-08-26)

Symptom: checkout renders fully (Pay Now visible, "Test card: 4242…" note shown) but the Stripe payment form area is **empty** — no card-number input, no Stripe iframe. Console has no obvious error; backend logs show `POST /carts/:id/payment_sessions 201` with a valid `client_secret`. The `StripePaymentForm` mounts (`<div class="p-4"><div><div></div></div></div>`) but `PaymentElement` renders nothing.

Root cause: `@stripe/stripe-js`'s `loadStripe(publishableKey)` runs on the client and reads `process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` — a `NEXT_PUBLIC_*` var that must be **inlined at build time**. If the Dockerfile does not declare `ARG NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` (e.g. after a rollback that dropped the original `b68095f` fix), Docker silently ignores the `--build-arg`, the bundle ships with an empty key, `isStripeConfigured` is false, `stripePromise` resolves to `null`, and `Elements` renders an empty container. The backend still creates PaymentIntents (201) — the failure is purely the client key.

Correct fix: `storefront/Dockerfile` must declare `ARG NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` + `ENV`, and the build (`deploy.yml` via `vars.STRIPE_PUBLISHABLE_KEY`, `docker-compose.dev.yml`, or the manual `docker build`) must pass the key. Verify after deploy: `grep -rl pk_ /app/.next/static/chunks/` inside the image must match the key; in the browser the Stripe iframe (`iframe[src*="stripe"]`) must appear under Payment Method.

### Webhook handling

For Next.js storefronts, `@pallastrade/sdk/webhooks` provides HMAC signature verification with typed event payloads:

```ts
// app/api/webhooks/pallastrade/route.ts
import { verifyWebhookSignature, type WebhookEvent } from '@pallastrade/sdk/webhooks'

export async function POST(req: Request) {
  const body = await req.text()
  const signature = req.headers.get('x-pallastrade-webhook-signature') ?? ''
  const timestamp = req.headers.get('x-pallastrade-webhook-timestamp') ?? ''

  if (!verifyWebhookSignature(body, signature, timestamp, process.env.PALLASTRADE_WEBHOOK_SECRET!)) {
    return new Response('Invalid signature', { status: 401 })
  }

  const event: WebhookEvent = JSON.parse(body)
  switch (event.name) {
    case 'order.completed':
      await sendCustomThankYouEmail(event.data)
      break
    case 'order.shipped':
      await pushShippingNotification(event.data)
      break
  }

  return Response.json({ received: true })
}
```

The PallasTrade backend ships outbound webhooks as `PallasTrade::WebhookEndpoint` records. Configure URL + events under Settings → Webhooks in the admin.

## PDP discovery rails — Related / Recently viewed / Wishlist (2026-09-15)

PRD-20260915-catalog-batch-c1-discovery：PDP 从「交易终点」变成「发现节点」，三块能力分工明确：

| 能力 | 位置 | 数据来源 | 规则 |
|---|---|---|---|
| Related | `components/products/RelatedProducts.tsx`（服务端） | Store API 列表（`in_categories` + `in_stock`） | 同分类（含子分类）→ 在售 → 排除当前商品 → ≤8；空则不渲染整块（含标题）；数据在 `lib/data/products.ts#getRelatedProducts`，复用 `cachedListProducts`（10 分钟缓存 + `products` tag） |
| Recently viewed | `RecentlyViewed.tsx` + `RecentlyViewedTracker.tsx`（客户端） | `localStorage['pt.recently_viewed']` | 倒序、按 id 去重（重访移到最前）、上限 12；展示时排除当前商品 |
| Wishlist | `WishlistButton.tsx` / `WishlistHeaderButton.tsx` / `/wishlist` 页 | `localStorage['pt.wishlist']` | 切换加入/移除、上限 100、头部数量徽章、空态引导。PDP 上的开关是**轻量次级动作**（`variant="outline"` + `size="sm"`），挂在**库存状态行**（`data-testid="availability-row"`）右侧，**不得**放进 数量行 / Add to Cart / Buy Now 的 flex 行（否则桌面端成为第三个 flex 子项，把主 CTA 挤扁 —— 2026-09-15 修复） |

新增同类能力时照做的约定：

1. **纯函数下沉**：状态计算进 `lib/utils/{related-products,recently-viewed,wishlist}.ts`（解析/去重/截断/切换 + 事件名常量），组件只做读写与渲染 → 纯函数 100% 可测。
2. **浏览器存储统一走 `lib/utils/local-store.ts`**（`readLocalValue` / `writeLocalValue` / `dispatchLocalEvent`）——全部 try/catch：隐私模式与配额满必须静默降级，绝不炸页面。
3. **hydration 安全**：首帧不读 localStorage（组件返回 `null` / 徽章为 0），挂载后 effect 再同步；同页同步用自定义事件（`pt:recently-viewed` / `pt:wishlist`），跨标签用 `storage` 事件。
4. **i18n 5 语言 + 守护**：新键必须进 `messages/{de,en,es,fr,pl}.json`，并在 `lib/__tests__/checkout-i18n-keys.test.ts` 的 `REQUIRED` 登记（缺键 = 用户可见缺陷）。
5. **埋点复用**：新 rail 直接用 `ProductCard` 的 `select_item`（传 `listId` / `listName` 区分区块），不新增埋点代码。
   ⚠️ **必须真的传**：`ProductCarousel` 曾把 `listId` **硬编码**成 `featured-products`，于是 Related /
   Recently Viewed 的点击全被记到 Featured（比"没有归因"更糟）。现在它接受 `listId` / `listName`
   （默认仍是 featured，首页 rail 行为不变），**每个 rail 必须显式传自己的标识**
   （`related-products` / `recently-viewed`）；机制回归见 `storefront/src/components/products/__tests__/ProductCarousel.test.tsx`。
   ⚠️ **转化类动作也要发事件**：缺货订阅成功后发 `back_in_stock_subscribe`
   （`lib/analytics/gtm.ts#trackBackInStockSubscribe`，带 `product_id` / `variant_id` / `success`）；
   该 helper **自己吞异常** —— 埋点失败绝不能让订阅显示为失败（AP-009b 精神，回归见 `BackInStockNotify.test.tsx`）。
6. 服务端 rail 的 `locale` 用全局 `Locale` 类型（`src/types/next-intl.d.ts`），页面传参需要 `locale as Locale`；`currency` 这种可空字段要 `?? undefined`。
7. **PDP 按钮层级**（2026-09-15 修复）：主 CTA 行只放 数量选择 + Add to Cart + Buy Now；收藏/分享这类弱动作一律 `outline` + `sm` 且贴到信息行（库存状态行），**禁用 `size="lg"` + `w-full`**：那是主 CTA 的形制，放进行级 flex 会直接挤压主按钮。

回归验证：`harness verify storefront-test`（vitest 全量，自动含本批新增用例）。

## Storefront vs backend — where does the change belong

| Want to... | Belongs in |
|---|---|
| Change how a product is displayed (layout, colors, copy) | Storefront |
| Add a new field to product responses | Backend (model + serializer) |
| Add a custom page like /about, /shipping | Storefront |
| Change pricing logic | Backend (service swap or extension) |
| Add a country to checkout | Backend (Markets / Country config) |
| Customize the checkout UI flow | Storefront |
| Add an A/B test to the PDP | Storefront |
| Sync orders to a CRM | Backend (subscriber) |
| Custom analytics events | Storefront (client-side tracking) OR backend (subscriber) — depends on what triggers them |
| Customize the cart total calculation | Backend (service swap on `PallasTrade.cart_recalculate_service`) |
| Send a custom transactional email | Backend (subscriber + ActionMailer) |

The rule: **anything customer-visible is the storefront. Anything that touches data, money, or business logic is the backend.** When in doubt, backend — keeping logic centralized makes it consistent across all frontends if you ever ship a second one.

## Common gotchas

- **Dynamic inline styles are valid AP-001/AP-006 exceptions.** Data-driven styles (backgroundImage from `image_url`, backgroundColor from `option.color_code`, percentage widths, animation delays), SDK config objects (PayPalButtons `style`, Stripe Elements `variables`), and CSS-variable injection (sonner `--normal-bg`) are acceptable — do NOT rewrite them into Tailwind classes. Only genuinely static styles (fixed width/height/color) should become Tailwind classes. Email templates (`lib/emails/`) must keep inline styles (email clients don't support external CSS).
- **Don't ship secret keys to the browser.** Secret API keys (`sk_…`) never belong in `NEXT_PUBLIC_*` env vars. In the official storefront even the PallasTrade publishable key stays server-side (`PALLASTRADE_PUBLISHABLE_KEY`, no `NEXT_PUBLIC_` prefix) since all API calls run in Server Actions — `NEXT_PUBLIC_*` is only for third-party client SDK keys (Stripe/PayPal publishable keys).
- **Cart tokens are not credentials** — they identify a cart, not a user. But they grant cart access, so treat them like a session token: HTTPS only, set as an httpOnly cookie when possible.
- **Cache aggressively but invalidate on cart/auth changes.** Product catalog can sit in CDN; cart calls must always hit fresh.
- **Pricing displayed must match what the API will charge.** Don't compute totals client-side. Always pull the cart's `total` from the API after add/remove operations — the backend applies promotions, taxes, shipping rules.
- **i18n is the storefront's job.** The Store API returns translated strings based on the `x-pallastrade-locale` header (or a `locale` query param) — not `Accept-Language`. Set it via the SDK: `createClient({ ..., locale })` for a default, or pass `{ locale }` in per-request options; the SDK sends it as `x-pallastrade-locale`.

## Where to read further

- **SDK docs:** `node_modules/@pallastrade/docs/dist/developer/sdk/quickstart.md` (also at https://pallastrade.cn/docs/developer/sdk/quickstart)
- **Storefront docs:** `node_modules/@pallastrade/docs/dist/developer/storefront/nextjs/architecture.md`, `customization.md`, `deployment.md`
- **Storefront tutorial:** `node_modules/@pallastrade/docs/dist/developer/tutorial/api.md`, `sdk.md`
- **Storefront source:** https://github.com/stevenbian9266-cyber/pallastrade — reference implementations for product listing, cart, checkout, account pages

## 支付方法行展示（D16 切片1, 2026-09-16；PRD-20260916-payments-d16-payment-method-presentation）

支付方法列表（结账页方法行 / 统一结账、支付弹窗）**必须**渲染服务端下发的入口级展示名：

```tsx
{method.display_name ?? method.name}   // display_name 缺失 → 回落 provider 名（老数据零回归）
```

- `display_name` / `method_key` / `option_id` 由 store API 下发（见 `pallastrade-api-v3` Skill 的 D16 小节）；前台**不要**自己
  从 `option_id` 拆字符串拼展示名，也不要按 provider 名做分支——入口语义一律以 `method_key` 为准。
- 三处渲染点：`components/checkout/OrderPaymentContent.tsx`、`components/checkout/PaymentCheckoutModal.tsx`、
  `components/checkout/UnifiedCheckout.tsx`（注意同文件里还有运输方式行，改动要落在 `name="payment-method"` 块）。
- 覆盖测试：`components/checkout/__tests__/OrderPaymentContent.test.tsx`（有 `display_name` 渲染展示名 + 无 `display_name` 回落
  provider 名）；改动后跑 `storefront-test`。

## 认证需求提示（D15 切片3, 2026-09-17；PRD-20260917-checkout-d15-切片3）

结账页**不做支付入口筛选**（服务端权威）：认证需求 = 是时后端只会投影「能完成 3DS/SCA」的入口；前端只负责**解释**两种显式状态：

```tsx
// 投影里的每项带 requires_authentication（布尔）；订单快照回退可能没有该字段 → 组件内本地类型标为可选
{paymentMethods.some((m) => m.requires_authentication) && <div data-testid="authentication-required-notice">…</div>}
{paymentMethods.length === 0 && <div data-testid="no-payment-method">…</div>}
```

- ⚠️ **不得**在客户端根据 `kind`/`frontend_kind` 自己隐藏钱包入口 —— 隐藏 = 不出现由 `Payments::Availability::Resolver` 决定（D8 §66.5 同源硬约束），客户端筛选会造成「看得到、付不了」。
- 「一个入口都没有」= **显式状态**（提示用户而非静默空白），且**不得**自动降级到弱认证入口。
- 文案 5 语言（`messages/{en,de,es,fr,pl}.json`）**键集必须一致**（`pnpm check:locales`）；改完必跑 `npx tsc --noEmit`（一行两个值这类 JSON 手误只在 tsc 暴露）。
- 覆盖测试：`components/checkout/__tests__/OrderPaymentContent.test.tsx`（新增 2 例：认证提示 / 无可用入口提示）。

## 入口级支付区（D7, 2026-09-18；PRD-20260918-payments-d7-payment-section-express）

前台支付区从「一 provider 一行」升级为 **一入口一行**（信用卡 / Apple Pay / Google Pay 同时可见）。

- **共用外壳**：`components/checkout/PaymentSection.tsx`
  - `paymentEntriesFor(method)` —— 读服务端 `entries[]`（**两条通道都下发**：cart/order 的
    `payment_methods[].entries` 为「已配置且启用」集合，checkout 投影的为带订单上下文过滤后的集合）；
    **旧响应无 `entries` → 合成单入口**（`option_id = `${method.id}:default``、
    `display_name = display_name ?? name`、`frontend_kind` 缺失时按 `session_required` 推导
    `inline`/`manual`）→ 零回归（AC-010）。
  - `PaymentSection` 渲染 radio 行（`data-testid="payment-entry-row"` + `data-option-id` + `data-frontend-kind`），
    顺序即服务端 `position`；`manual` 入口出说明行；认证提示与空态仍由这里渲染。
- **形态槽（父级决定）**：`frontend_kind === "express"` → 钱包按钮；`"inline"` → `CardPaymentForm`；`"manual"` → 无额外控件。
  ⚠️ **仍然零筛选**：只按形态选渲染槽，**不按 kind 隐藏入口**（隐藏与否由服务端 `Availability::Resolver` 决定，见上节 D15）。
- **钱包快付（or_ 订单页）**：`components/checkout/WalletPaymentButtons.tsx`
  - 点钱包入口 → `createOrderPaymentSession(orderId, methodId, undefined, "payment_intent", { optionKind: method_key })`
    → 挂 `ExpressCheckoutElement`（clientSecret）→ `stripe.confirmPayment` → `completeOrderPaymentSessionAndRedirectToResult`。
  - 错误落点复用 `lib/checkout/express-canonical.ts`（`expressErrorRoute` / `expressNoticeFor`）：入口不可用 → 提示 + 刷新列表。
  - **cart 页不新建流程**：选中 `express` 入口时复用既有 cart 绑定 `ExpressCheckoutButton`（`next/dynamic`，`ssr: false`）。
- **移动吸底 Pay 条**：`OrderPaymentContent` 的 `data-testid="mobile-pay-bar"`（`lg:hidden fixed bottom-0`）——
  与页内按钮**同一 handler**（钱包入口则复用同一钱包组件，不复制支付逻辑）；两个 Pay 按钮各有 testid
  （`pay-now-button` / `mobile-pay-button`）避免同名查询歧义。
- **`option_kind` 透传**：`lib/data/order-payment.ts`（第 5 个参数 `startOptions.optionKind`）与
  BFF `/api/checkout/start`（`body.option_kind`）两处；cart Pay 请求也会带 `option_kind`。
- 覆盖测试：`__tests__/WalletPaymentButtons.test.tsx`（AC-007/008：option_kind 下发、client_secret 确认、拒绝后刷新）、
  `__tests__/OrderPaymentContent.test.tsx`（AC-006/007/008/009/010）；改动后跑 `storefront-test`。

### 设备钱包能力与降级（D7 补口 2/3, 2026-09-18；AC-011~AC-015）

钱包入口的**服务端可用性**（D8/D11/D15c）与**设备能力**是两件事，后者只有客户端知道。
读数模型集中在 `lib/checkout/wallet-availability.ts`（**改钱包行为先看它**）：

- **点谁显示谁（AC-013）**：`expressPaymentMethodsFor(method_key)` 把选中钱包设 `always`、其余设 `never`。
  **为什么是 `always` 而不是 `auto`**（Stripe 官方文档 *Express Checkout Element* → 支持的浏览器）：
  **脚注 3** 非 Safari 桌面端浏览器（Chrome/Edge）**仅当 `paymentMethods.applePay = 'always'` 才支持 Apple Pay**；
  **脚注 4** Firefox / Safari / iOS 浏览器**仅当 `googlePay = 'always'` 才支持 Google Pay**；
  且 `always` 只解除「未设置/浏览器未命中就不显示」，**平台或币种不支持时仍不会强行渲染**（文档同名章节）。
  坑（实测）：用 `auto` 时 PC 端 Apple Pay 永远不初始化（表现为一直加载），移动端 Safari 的 Google Pay 同理。
  `link` 只接受 `auto` | `never`（`@stripe/stripe-js` 的 `express-checkout.d.ts` 类型即如此，写 `always` 会编译失败）。
  `method_key` 为 undefined/空 → **无入口上下文**（购物车抽屉）→ 两个钱包 `always`、Link `auto`；
  非前台支持的 kind（`paypal` / `shop_pay` / `amazon_pay`）→ 返回 null → 不渲染钱包元素（只给说明行）。
- **三态而非布尔（AC-015）**：`unknown`（**仅** `onReady` 未触发的初始态，由看门狗兜底）/ `available` / `unavailable` + **原因**
  （`device` 本环境无此钱包 / `timeout` 看门狗超时 / `unsupported` 前台不支持 / `unconfigured` 无密钥）。
  入口行的 `data-unavailable` 值就是原因，行内文案与区块说明按原因分档。
  ⚠️ **`onReady` 一旦触发，`availablePaymentMethods === undefined` 是确定性结论而非「未知」**
  （官方类型原文：*"or undefined if **no payment methods can show**"*）→ 必须立即判 `unavailable(device)`；
  当成「还在加载」会让界面停住转圈、10s 后还把确定性结论误报成「加载失败」（实测：VS Code 内嵌 Electron /
  无 `ApplePaySession` 的 Windows 浏览器上两个钱包都必然 `undefined`）。
- **看门狗**：`WALLET_READY_TIMEOUT_MS`（10s，移动网络较慢）内未收到任何上报 → `unavailable(timeout)`，
  文案是「加载失败，可重试」而**不是**「本设备不支持」——两者不得混同（旧文案把网络/初始化失败
  误报成设备不支持，移动端因此被错误置灰）。
- **可恢复 + 重试（AC-014）**：探测为不可用 → 标注 + 自动回落卡支付；
  **重新点该入口 = 重试**（父级清除标注 + `walletProbeTokens` 递增 → 槽位 `key` 变化 → 重新挂载元素重新探测）；
  后续上报 `available` → 父级自动**解除**标注（单向置灰是旧缺陷）。
  ⚠️ 入口行**不 disabled**（否则无法重试）；入口集合仍不删除（服务端决定，D15c 红线）。
- **不可用时的显式态**：`wallet-unavailable-notice`（带 `data-reason`，超时/不可用时附 `wallet-retry`），
  不允许 `return null`；加载态显示 `walletLoading` 提示。
- **两页同口径**：cart 页（`UnifiedCheckout`）与 `or_` 页（`OrderPaymentContent` 页内槽位 + 移动吸底条）接线一致；
  cart 页选中钱包入口时**隐藏 Pay Now**、且不再渲染无意义的 `Processing...`；cart 页钱包槽位 **`showDivider={false}`**
  （只有抽屉下面真的有「去结账」按钮，分隔线才成立）。
- 覆盖测试：`__tests__/ExpressCheckoutButton.test.tsx` / `WalletPaymentButtons.test.tsx`（三态 + 按入口过滤 + 看门狗 + 未配置）、
  `__tests__/UnifiedCheckout.test.tsx` / `OrderPaymentContent.test.tsx`（回落 + 原因标注 + 重试 + 无 `Processing...`）；改动后跑 `storefront-test`。

### 顶部快捷支付区 + Stripe 语种跟随（2026-09-19；PRD-20260919-payments-checkout-top-express-pay-locale）

- **顶部快捷支付区**（cart_ 统一下单页，`components/checkout/TopExpressPay.tsx`）：位于 `<h1>` 之下、
  第 1 节之前；把服务端 `payment_methods[].entries` 中 `frontend_kind === "express"` 且**元素可承载**的
  kind（`apple_pay` / `google_pay` / `link`）一次性以钱包按钮呈现（`entryKinds` → `expressPaymentMethodsForKinds`：
  集合内 `always`、集合外 `never`，`link` 用 `auto`），`maxColumns=2` 横向自适应（**不自动堆叠**）。
  不可承载 kind（paypal / shop_pay / …）不进顶部区，**仍保留在第 5 节入口列表**（零筛选红线）。
- **双触点（用户决策）**：第 5 节入口行与「选中 express 入口 → 钱包槽位」保持既有行为，**不删除**。
- **顶部区降级**（`degradedDisplay="toast"`）：加载失败/超时 → `sonner` toast 3 秒（每次挂载一次）+ 整区隐藏；
  `device` / `unsupported` / `unconfigured` → **静默隐藏**（桌面零噪音）；`unknown` 期间保留加载态。
- **`option_kind` 透传**：钱包 confirm 时把用户**实际点击**的 kind（`expressPaymentType`，或单入口上下文）
  作为 `option_kind` 随 `/api/checkout/start` 下发 → 服务端 `PaymentSessions::Start` 入口级同源复算。
- **Stripe 语种跟随**：`lib/utils/stripe.ts#stripeLocaleFor`（`en/de/es/fr/pl` → 同码；未知 → `auto`），
  三处 `Elements`（`ExpressCheckoutButton` / `WalletPaymentButtons` / `CardPaymentForm`）均传 `locale` ——
  此前未传 → Stripe 按**浏览器语言**渲染（中文浏览器上显示中文按钮，与站点语种不符）。
  ⚠️ **平台限制**：Apple Pay 按钮/弹层语言由 **Apple 设备系统**决定，站点 `locale` 不保证改变之
  （Google Pay 同理有 Google 侧规则）；实测口径见 PRD §NFR-007。
- 覆盖测试：`__tests__/TopExpressPay.test.tsx`（渲染条件/入口集合/整区隐藏/凭据）、
  `ExpressCheckoutButton.test.tsx` 的 `(top express area)` 段（多入口配置/2 列/locale/option_kind/toast 降级）、
  `lib/__tests__/stripe-locale.test.ts`；改动后跑 `storefront-test`。

## Changelog (P0 Payment, 2026-09-03)

- P0 (2026-09-03): Express(Apple/Google Pay) 金额/行项目改由服务端 Cart#express_payment 权威提供（expressAmount/expressLineItems；legacy buildLineItems 仅 fallback）；Legacy cart 支付=Compatibility Only。
- CHK-P1-4 (2026-09-03): SDK `orders.checkout.get`（手写 CheckoutView 类型）→ `lib/data/order-checkout.ts`（server，null 安全）；`OrderPaymentContent`（or_ 纯支付页）改为服务端 CheckoutView 投影驱动金额/商品/地址（view 缺失回退 order 快照）+ `ready=false` 禁用 Pay（i18n checkoutNotReady）；死代码清理 `submitCartOrder`/`submitCartAndGoToCheckout`；legacy 边界注释（CheckoutPageContent/PaymentSection/CombinedPaymentCheckout）。mutation PATCH 消费（4B）、legacy 退役（4C）留后续。
- CHK-P1-4B (2026-09-04): SDK `orders.checkout.update` + `lib/data/order-checkout.ts#updateOrderCheckout`（409/业务错误 code 透传）；`OrderPaymentContent`（or_ 页）物流 rate/收货地址可内联编辑（PATCH → 服务端最新 view；复用 AddressFormFields + useCountryStates）；会话创建遇 `checkout_version_conflict` → 提示 + 重取 view（不自动支付）；createOrderPaymentSession 失败透传 code。
- CHK-P1-4C (2026-09-04): 移除孤儿两步合并支付页 `combined-payment/[id]` + `CombinedPaymentCheckout.tsx`（账户弹窗 PaymentCheckoutModal 为现行入口）；删除死代码 `lib/data/payment-combination.ts#updateOrderShippingAddress`；legacy 一页式（CheckoutPageContent/PaymentSection/Express/confirm-payment）保留（4C-4 后续）。
- CHK-P1-4C4 (2026-09-04): legacy 一页式支付页退役——删除 `checkout/[id]/CheckoutPageContent` + `CheckoutSidebar` + `components/checkout` 下 `AddressSection/DeliveryMethodSection/PaymentSection/AddressSelector/Summary/AdyenPaymentForm/PayPalPaymentForm`（9 文件，Adyen/PayPal 内嵌表单仅 legacy 用，新流程走网关跳转 + confirm-payment）；`checkout/[id]/page.tsx` 兜底改为 redirect 首页 `/{country}/{locale}`（cart_→UnifiedCheckout、or_→OrderPaymentContent 覆盖全部有效 id，后端整数 id 序列化恒 or_ 前缀）；data 孤儿清理 `checkout.ts#applyCode/removeDiscountCode/removeGiftCard` + `payment.ts#createDirectPayment`（UnifiedCheckout 折扣码走 BFF /api/checkout/coupon）；barrel 保留 CouponCode/ExpressCheckoutButton/StripePaymentForm。共享组件 AddOnsSection/SaveInfoSection/AddressEditModal/AddressFormFields/CouponCode/CardPaymentForm/StripePaymentForm/ExpressCheckoutButton/PolicyConsent/CheckoutSectionTitle 全部保留。
- TXN-P2-6 轮3 (2026-09-05, PRD-20260905-checkout-txn-p2-6-轮3-storefront-transaction-first): 订单域支付入口 **payment-session-first → transaction-first**（P2 §42/§57）。`/api/checkout/start#POST` 的 `session_required` 分支改用 `orders.transactions.create`（后端 Transactions::Start：quote 同意/幂等/快照冻结 + PaymentSessions::Start 绑定 transaction_id），返回 `payment_execution` 作为会话 + 响应新增 `transaction:{id,state}`；PATCH complete 仍走 `orders.paymentSessions.complete`（session=transaction 的支付 attempt，AC-2006）。`lib/data/order-payment.ts#createOrderPaymentSession`（OrderPaymentContent server action）内部同样改走 transactions.create，返回 `payment_execution` 作为 session + `transaction` meta；`completeOrderPaymentSession*` 不变。`OrderPaymentContent` 409 映射：`quote_changed` 与既有 `checkout_version_conflict` 同处理（toast「报价已更新」+ refreshView，不自动支付，INV-07）。Provider UI（Stripe 自绘卡字段/会话跳转）独立不变。SDK 依赖 dist 需重建（`pnpm --filter @pallastrade/sdk build`）后 storefront 才解析到新方法。
- PRD-20260913-checkout-txn-error-routing + PRD-20260913-checkout-money-contract (2026-09-13, RESEARCH-20260913 §9.2/§9.1)：错误落点按 `code` 分流（见上方新增段落；`lib/errors.ts#extractErrorCode`；`payment-result` 支持 `?notice=recovery|processing` 覆盖文案并抑制重试入口）+ Money 契约（`OrderPaymentContent` 运费/税行与 `order-confirmation` 邮件改用 raw 判逻辑；TOTAL SAVINGS 仅促销折扣）+ i18n 5 语言新增 8 键；测试：`chk-p1-4b-storefront` / `chk-p1-4c-storefront` / 全量 storefront 套件绿。
- PRD-20260915-checkout B4 (2026-09-15)：Express 钱包 canonicalize——`ExpressCheckoutButton` 改走同源 BFF（新的 `lib/checkout/express-canonical.ts`：start/complete/错误路由/结果页 URL），删除 `lib/data/express-checkout-flow.ts` 的 legacy 会话包装与 `lib/data/payment.ts`、删除 `/confirm-payment/[id]` 页；组合完成改 Order 域 `orders.paymentSessions.complete`；后端仅补规格（Order 域 complete 已内置组合分支，`payment_combinations_controller_spec.rb` 7 examples 绿）；新增守护测试 `legacy-payment-sessions-guard.test.ts`（零 `carts.paymentSessions`）+ 组件测试 `ExpressCheckoutButton.test.tsx`；i18n 无新增键（错误文案用服务端 `message`）；GS-123。
- 踩坑（2026-09-15）：删除含 `[country]` / `(checkout)` 的路径时，PowerShell 默认把 `[ ] ( )` 当通配符 —— `Remove-Item` / `Test-Path` 会静默失配（表现为“删除成功但文件还在”、`Test-Path` 返回 `False`）；一律用 `-LiteralPath`，并且 `biome.cmd` 也无法接受这类路径（改用 `node node_modules/@biomejs/biome/bin/biome check --write src`）。`pnpm typecheck` 若报 `.next/dev/types/validator.ts` 找不到已删路由，删掉 `.next/{dev/,}types` 后重跑即可（生成物）。
- PRD-20260915-catalog-batch-c1-discovery (2026-09-15)：PDP 发现三件套——Related（服务端规则：同分类 + 在售 + 排除自身，`lib/data/products.ts#getRelatedProducts` 复用缓存列表并 over-fetch 1 条）、Recently viewed（本地 12 条，Tracker + rail）、Wishlist V1（本地切换 + `/wishlist` 页 + 头部徒章）；新增纯函数 3 个 + 浏览器存储封装 `lib/utils/local-store.ts` + 组件 5 个 + 页 1 个；i18n 5 语言新增 8 键（`products.relatedTitle` / `products.recentlyViewedTitle` / `wishlist.*`）；测试 12 文件 85 例绿；GS-132。
- PRD-20260915-catalog-batch-c2-sku-back-in-stock (2026-09-15)：PDP 到货通知**按所选 SKU 订阅**——`BackInStockNotify` 新增 `variantId` 属性（`ProductDetails` 传 `selectedVariant?.id ?? default_variant?.id`），`lib/data/backInStock.ts#createBackInStockSubscription(productId, email, variantId?)` 只在有 SKU 时带 `variant_id`；后端双通道通知（variant 级 / 商品级）见 catalog Skill；无新增文案（GS-133）。
- PRD-20260915-payments-d10-client-config (2026-09-15)：**支付密钥从构建期内联改为服务端下发**——`lib/utils/stripe.ts` 导出 `resolveStripePublishableKey(clientConfig)`（API 值 → 回落 `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` → null）、`isStripeConfigured(clientConfig)`（**由 boolean 常改为函数**）、`getStripePromise(clientConfig)`（按 publishable key 缓存 `loadStripe`，换环境自动重载）；移除模块级 `stripePromise` 常量。三个消费组件（`CardPaymentForm` / `StripePaymentForm` / `ExpressCheckoutButton`）新增可选 `clientConfig` 属性；装配点从所选支付方式透传：`OrderPaymentContent` / `UnifiedCheckout`（`cart.payment_methods[].client_config`）/ `PaymentCheckoutModal`。`client_config.publishable.publishable_key` 为服务端权威；缺省时回落环境变量，两者皆无 → 组件渲染“未配置”态（不抛错）。测试：`src/lib/utils/__tests__/stripe-client-config.test.ts`（5 例双读）+ 4 个既有 mock 更新（GS-136）。
- PRD-20260918-payments-隐藏-stripe-elements-开发者工具入口 (2026-09-18)：**测试模式下 Stripe 会在结账页右下角注入 Developer Tools 浮层**（Easel UI，iframe 标题 `Stripe developer tools frame`）；`lib/utils/stripe.ts` 新增导出常量 `STRIPE_DEVELOPER_TOOLS_DISABLED`（`{ developerTools: { assistant: { enabled: false } } }`，官方公开选项）并在 `getStripePromise()` 的 `loadStripe(pk, options)` 传入 —— **禁止用 CSS/DOM 屏蔽**（Easel 类名 hash 随版本漂移 + 同体系承载真实支付 UI）。platform 侧第二处实例化点同步（见 payments Skill）。测试：`stripe-client-config.test.ts` 新增 3 例（选项形状 / 密钥双路径 / 缓存语义），既有 2 例断言补第二参。
