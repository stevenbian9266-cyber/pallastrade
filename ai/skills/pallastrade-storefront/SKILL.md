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
- `ProductReviews` (`components/products/ProductReviews.tsx`, P0-4) — PDP review section: rating summary (stars + count), approved review list (author, verified-purchase badge, date) and a submit form for signed-in customers. The server component page fetches reviews + auth state via `lib/data/reviews.ts` (`getProductReviews` public, `createProductReview` posts with the customer JWT) and passes them into the client `ProductDetails`; the form renders only when `isAuthenticated`. i18n labels live under a top-level `reviews` namespace in `messages/*.json`. Only admin-approved reviews are returned by the Store API, so a fresh submission won't appear until moderation. ⚠️ **`average_rating` is serialized as a string** (BigDecimal → string in the Store API) — always guard with `Number()` before calling `.toFixed()` (e.g. `{Number(averageRating).toFixed(1)}`). Calling `"4.5".toFixed(1)` directly crashes the PDP with `TypeError: b?.toFixed is not a function` (bugfix 2026-08-25).
- `BuyNowButton` (`components/products/BuyNowButton.tsx`, P5 2026-08-27) — PDP quick-purchase button. Creates a standalone cart with the current variant via `lib/data/buy-now.ts` `createBuyNowCart` and routes straight to `/checkout/{id}` (does not touch the cart). On the PDP it renders **in the same row as the Add to Cart button at equal width**: `ProductDetails` wraps both in `<div className="flex flex-1 gap-4">` with each action as `flex-1` (the `w-full` outline button fills its `flex-1` wrapper). The outer actions row is `flex flex-col gap-4 sm:flex-row sm:items-center`, so on mobile the quantity picker wraps to its own line while the two buttons share a row (bugfix 2026-08-29). i18n label: `products.buyNow`.
- `ProductDetails` availability states + variant deep link (PRD-20260915-catalog-pdp-state-correctness, 2026-09-15) — the PDP derives its presentation state from **existing Store API flags only**, via the pure helpers in `lib/utils/variant-selection.ts` (`deriveAvailabilityState` / `resolveInitialVariant` / `buildVariantHref` / `aggregateAvailability`): **in stock > pre-order (purchasable) > backorder (purchasable) > sold out**; pre-order shows `products.preorder` + a localized `products.preorderShipsBy` date (from `preorder_ships_at`), backorder shows `products.backorder` + `products.backorderNote`, and `BackInStockNotify` renders only in the sold-out state. `?variant=` is the shareable SKU deep link: `page.tsx` seeds `initialVariantId` from `searchParams`, `ProductDetails` falls back on unknown/stale ids (default_variant → first purchasable → first) and updates the URL through `router.replace(..., { scroll: false })` while preserving other query params (e.g. `category_id`). GA4 `view_item` reports the variant the page was opened with (`trackViewItem(product, currency, initialVariant)`); variant switches deliberately don't re-fire it. `buildProductJsonLd` (`lib/seo.ts`) emits a plain `Offer` for single SKUs and an `AggregateOffer` (lowPrice/highPrice/offerCount + most favourable availability) for multi-SKU products, with `brand` read from a custom field (`catalog.brand` / `brand` / `*.brand`, omitted when absent). New i18n keys (`products.preorder` / `preorderShipsBy` / `backorder` / `backorderNote`) are guarded for all five locales by `lib/__tests__/checkout-i18n-keys.test.ts`.

**Client-component import rule (build breaker):** a `"use client"` component MUST NOT import from the `@/lib/pallastrade` barrel (`index.ts`) — the barrel re-exports server-only cookie/`next/headers` helpers, and pulling them into the client bundle fails `next build` with "Ecmascript file had an error" on `import { cookies } from "next/headers"`. Import the specific client-safe module instead, e.g. `getClient` from `@/lib/pallastrade/config`. Server components / route handlers may keep using the barrel.

**Client-component SDK calls go through server actions.** `PALLASTRADE_API_URL` / `PALLASTRADE_PUBLISHABLE_KEY` are **server-only env** (no `NEXT_PUBLIC_` prefix), so `getClient()` throws in the browser. A client component that needs the Store API must call a `"use server"` action in `src/lib/data/` (e.g. `cart.ts`, `backInStock.ts`) that runs `getClient()` server-side; the action returns a `{ success, error }` result (via `actionResult`). Never build an SDK client directly in a client component.
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
2. **Unified checkout** `/{country}/{locale}/checkout/[id]`（`components/checkout/UnifiedCheckout.tsx`，购物车模式）：main column = email + `AddressFormFields` + itemized lines + delivery-method radio + payment-method radio；order summary 通过 `CheckoutContext#setSummaryContent` 发布到 desktop sticky sidebar。Stripe `CardPaymentForm` is rendered immediately but creates no provider object until Pay. One Pay calls same-origin `POST /api/checkout/start`（update Cart → idempotent submit → start/reuse Order session）, confirms the returned PaymentIntent in the same handler, best-effort PATCHes completion, then opens `/payment-result/[orderId]?session=...`. Never redirect to `checkout/or_` for a second Pay.
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

**禁止**（回归守护 `src/lib/data/__tests__/legacy-payment-sessions-guard.test.ts` 已机器化）：storefront 任何源码出现 `carts.paymentSessions.*`；恢复 `/confirm-payment` 页（已删，历史 3DS return_url 深链由 `/payment-result` 承接）、`lib/data/payment.ts`；钱包把用户送到 `order-placed` 或第二张支付页。`stripe.createPaymentMethod` 已从钱包移除（canonical 会话创建不接受网关侧 PM id）。组合/多单支付同样改走 Order 域 `orders.paymentSessions.complete`（`lib/data/payment-combination.ts#completeCombinationSession`）。

**零 legacy 调用（B5 扩展，2026-09-15）**：守护测试 `src/lib/data/__tests__/legacy-payment-sessions-guard.test.ts` 现在覆盖 §45 六行 —— ① 全仓源码（注释豁免）零 `carts.paymentSessions` / `carts.payments` / `carts.complete`；② `carts.{fulfillments,giftCards,storeCredits,discountCodes}` **只允许**出现在白名单四个文件（`lib/data/shopping-cart.ts`、`lib/data/checkout.ts`、`lib/data/express-checkout-flow.ts`、`app/api/checkout/coupon/route.ts`）——新增文件使用即失败。后端对 legacy 身份（非 `cart_`）回 `Deprecation`/`Warning`/`Link` 三头（B5），`cart_` 流量不受影响。

**Checkout 账单地址同配送建模（PRD-20260913-checkout-billing-mode，2026-09-13）**：`UnifiedCheckout` 发 `billing_mode: 'same_as_shipping' | 'custom'`，**不再发 `use_shipping`** —— 该字段不在 Store API 参数白名单（`carts_controller#permitted_params`）内，会被 ActionController 静默丢弃，正是「勾选同配送但 `Order.bill_address` 为空」的根因。约定：① 勾选初值 = `!cart.billing_address`（避免静默覆盖既有独立账单地址）；② 取消勾选时账单地址不完整 → 页内拦截并提示 `checkout.billingAddressIncomplete`（五语言，`checkout-i18n-keys` 守护）；③ 服务端账单快照 = 显式账单地址 → 否则配送地址副本（`Carts::Submit`），`billing_mode: 'custom'` 但地址不完整时返回校验失败且不落库。
**Storefront 验证清单（2026-09-14，CI 红线教训）**：`pnpm test`（vitest）**不够** —— 改动 storefront 后必须同时跑 ① `pnpm check`（biome）与 ② `pnpm typecheck`。`JSON.parse` 会静默保留重复键的最后一次定义，vitest 无法发现 i18n 重复键，而 biome `lint/suspicious/noDuplicateObjectKeys` 会让 Storefront CI 的 “Run pnpm check” 直接失败（实际发生过：5 语言 `checkout.returnToCart` 重复）；跨包引用 SDK 类型前先 `pnpm --filter @pallastrade/sdk build`（storefront 的 TS 解析走 `dist`）。**注意：任何后续编辑（哪怕只改测试文件）都要重跑 `pnpm check`** —— 第二次 CI 红线就是测试文件格式（`Formatter would have printed the following content`），发生在“只跑 vitest、没复验 biome”之后。
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
