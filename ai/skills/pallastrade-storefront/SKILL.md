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
- `product-image` (`components/ui/product-image.tsx`) — shared image renderer with srcset/fallback handling. When `src` is missing or fails to load it renders an **accessible placeholder**: a `<div role="img">` with an icon + `aria-label` (NOT a `<img>` element) — tests must assert on that placeholder (e.g. `getAllByRole("img")` → `tagName === "DIV"`), not on the absence of an image role.
- `CategoryBanner` (`app/[country]/[locale]/(storefront)/c/[...permalink]/CategoryBanner.tsx`) — category hero banner in the category listing route.

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
