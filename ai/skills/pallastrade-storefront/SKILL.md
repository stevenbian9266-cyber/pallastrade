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

The home page (`app/[country]/[locale]/(storefront)/page.tsx`) composes 7 sections in `components/home/`:

- `HeroSection` — brand tagline + value prop + primary/secondary CTAs (no demo links).
- `FeaturedProductsSection` — product grid + "view all".
- `PromoBanner` — wide gradient band, retargeted as a "limited-time offers" sale banner (distinct from featured products).
- `ValueProps` — 4 trust props (shipping / authenticity / returns / support).
- `BrandStory` — GEO-friendly "answer-ready" brand paragraph.
- `FaqSection` — visible Q&A + matching `FAQPage` JSON-LD (structured data always mirrors visible content).
- `NewsletterSignup` — client component, front-end validation + success state (no backend yet).

`CategoryNav` (`components/layout/CategoryNav.tsx`) is a **persistent desktop category bar** — a **client component** (receives categories as props from the server layout). **Hovering a root category opens its sub-category mega panel** (grid of all level-2 children, each column listing level-3 grandchildren inline, plus a "View all" footer link); **clicking locks the panel open** (click again / click outside closes). `hidden md:block`, `overflow-x-auto` for many categories. The mobile drawer `MobileMenu` (`md:hidden` trigger) remains the small-screen entry point. There is deliberately **no separate home "shop by category" section** and **no sr-only category nav** — the visible nav bar already covers category browsing.

### SEO / GEO (2026-08)

- JSON-LD helpers in `lib/seo.ts`: `buildOrganizationJsonLd`, `buildWebsiteJsonLd` (WebSite + SearchAction → `{basePath}/products?q={search_term_string}`), `buildProductJsonLd`, `buildBreadcrumbJsonLd`, `buildCategoryItemListJsonLd`. The storefront layout injects Organization + WebSite; pages inject Product / Breadcrumb / ItemList / FAQPage.
- `/llms.txt` (`app/llms.txt/route.ts`) — llmstxt.org site overview (title, about, categories, key pages, structured-data note). Route handlers are dynamic by default; do NOT add `export const dynamic` (incompatible with Cache Components mode).
- Semantic HTML rules: exactly one `h1` per page; sections use `section[aria-labelledby]`; images carry meaningful `alt`.

### SEO 301 redirects (2026-08, phase-1)

`src/middleware.ts` resolves every storefront pathname against the store's SEO redirects via
`GET /api/v3/store/redirects/resolve?path=...` (60s `revalidate` cache, 3s timeout). On a hit it
issues `NextResponse.redirect(target, status)` (guarded against A→A loops); on API failure it
**degrades open** (continues normal rendering — Turnstile-style). Redirects are managed in the
admin (Developers → Redirects) as `PallasTrade::Redirect` records. Static assets, `_next/*`
and `api/*` are excluded by the middleware matcher.

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

### Checkout

The Store API exposes payment sessions for the checkout flow — a single, provider-agnostic endpoint that works with any session-based gateway (Stripe, Adyen, PayPal); the provider is selected via `payment_method_id`. The pattern:

1. Customer hits checkout — `POST /api/v3/store/carts/:cart_id/payment_sessions` with a payment method choice (cart token in `X-PallasTrade-Token` header).
2. Backend returns a session with provider-specific data (Stripe Checkout URL, Adyen drop-in token, etc.).
3. Storefront redirects to the provider OR renders the provider's embedded form.
4. Customer completes — provider posts back to the PallasTrade backend, which fires `payment_session.completed` events.
5. Storefront calls `pallastrade.carts.paymentSessions.complete(cartId, sessionId, { session_result: 'success' }, options)` once the customer confirms, then `pallastrade.carts.complete(cartId, options)` to get the Order — or relies on the provider webhook, in which case the backend completes the cart → order transition automatically.

The `pallastrade_stripe` / `pallastrade_adyen` / `pallastrade_paypal_checkout` gems ship reference checkout flows. Don't roll your own unless you're integrating a new provider.

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
