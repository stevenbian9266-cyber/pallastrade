---
name: pallastrade-api-v3
description: Use when the user is integrating with PallasTrade's v3 REST API — making requests as a customer, building an admin app, writing webhook consumers, debugging auth errors, parsing API responses. Distinguishes the Store API (customer-facing) from the Admin API (back-office). Common phrasings include "PallasTrade API", "Store API", "Admin API", "publishable key", "secret key", "X-PallasTrade-Api-Key", "API scopes", "prefixed IDs in API", "expand", "API pagination", "PallasTrade 401", "PallasTrade 403", "{data, meta} envelope", "v3 endpoint". For ADDING a new resource to the API, use the pallastrade-resource skill instead.
---

# PallasTrade API v3

PallasTrade exposes two distinct API surfaces under `/api/v3/`:

| Surface | Path | Audience | Auth |
|---|---|---|---|
| **Store API** | `/api/v3/store/*` | Storefronts, mobile apps, customers | Publishable key + optional JWT customer |
| **Admin API** | `/api/v3/admin/*` | Back-office apps, integrations, admin SPAs | Secret key + scopes OR JWT admin + CanCanCan |

They share conventions (envelope shape, prefixed IDs, pagination) but have **different auth, different default actions, and different exposed fields**. This is the most-confused-about distinction in the API; cover it carefully.

## Version lifecycle

API v3 is the only maintained PallasTrade public API protocol. New endpoints, SDK
features, examples, and OpenAPI changes must use `/api/v3/store/*` or
`/api/v3/admin/*`. First-party V1 and V2 routes and implementation sources are not
part of the release.

Canonical documentation is published at `https://pallastrade.cn/docs`. Canonical
source and issue tracking live at
`https://github.com/stevenbian9266-cyber/pallastrade`.

## Store API vs Admin API — the contract differences

### Store API

**Who calls it:** customer browsers and apps. Public, untrusted clients.

**Auth:** Always include `X-PallasTrade-Api-Key: pk_<token>` (a publishable key). Additional layers:
- **Anonymous browse:** publishable key alone is enough for reading products, categories.
- **Guest cart:** publishable key + `X-PallasTrade-Token: <cart_token>` for operations on a specific guest cart.
- **Logged-in customer:** publishable key + `Authorization: Bearer <jwt>` for account data, order history.

**What's exposed:** customer-visible fields only. Catalog and order Store serializers omit `created_at`/`updated_at`, exposing business dates instead (`available_on`, `completed_at`); a few resources (digitals, newsletter subscriptions) do include timestamps. No cost prices, no admin internal notes, no private metadata.

**What actions are enabled:** read-only by default. `index` and `show` for catalog endpoints. Cart/customer/address endpoints opt into `create`/`update`/`destroy`.

**Channel scope:** Store responses are scoped by `X-PallasTrade-Channel: <code>` (e.g. `online`, `pos`). When omitted, the store's default channel is used. Products not published on the requested channel don't appear.

```bash
curl -H "X-PallasTrade-Api-Key: pk_CzEKBTWFiuNLgz4wciLsS59n" \
     -H "X-PallasTrade-Channel: online" \
     -H "Accept-Language: en-US" \
     https://my-pallastrade.example.com/api/v3/store/products
```

### Standard e-commerce flow endpoints (P1 2026-08-30, PRD-20260829-checkout)

New `pallastrade_carts` entity + order-domain payments (all under Store API, publishable key; cart/order ops need the cart token header `X-PallasTrade-Token`):

- `GET /api/v3/store/carts` — authenticated current-cart discovery returns **active carts only**, scoped by `current_store` + the current JWT customer. Converted/abandoned carts remain readable by explicit ID/token for checkout recovery, but must never be returned as the customer's mutable current cart.
- `PATCH /api/v3/store/carts/:id` — cart mutation. `permitted_params` **is** the contract: any field missing from the allow-list (e.g. the legacy `use_shipping`) is silently dropped by ActionController — that is exactly how submitted orders ended up with an empty `bill_address`. Billing intent is modelled as `billing_mode: 'same_as_shipping' | 'custom'` (PRD-20260913-checkout-billing-mode): `same_as_shipping` clears the stored billing address and `Carts::Submit` snapshots the shipping address instead, while `custom` persists the explicit address and rejects an incomplete one (`Carts::Update::IncompleteBillingAddress` → validation failure, no half-empty address is written).
- `POST/DELETE /api/v3/store/carts/:cart_id/discount_codes[/:id]` — **dual resolution** (PRD-20260914-checkout-cart-discount-codes-canonical): a `cart_...` id resolves through `current_store.shopping_carts` (guest/user scoped) and persists the code on `cart.private_metadata['discount_code']`, while a legacy order-backed cart id still falls through to `CartResolvable#find_cart!` (logged as `[legacy-discount-codes]` for convergence tracking). Applying only validates (`coupon_code_not_found` / `coupon_code_expired`) and consumes nothing — reservation/commitment lives in `PromotionRedemption`; `Carts::Submit` re-applies the stored code through `PromotionHandler::Coupon` before the amount pipeline and **fails the submission (no Order)** when the code is no longer valid, instead of silently charging full price. Removal is idempotent.
- `POST/DELETE /api/v3/store/carts/:cart_id/gift_cards[/:id]` — **dual resolution** (PRD-20260914-checkout-cart-gift-cards-canonical): a `cart_...` id resolves through `current_store.shopping_carts` (guest/user scoped, `active` only) and persists `cart.private_metadata['gift_card_code']` via `PallasTrade::Carts::ApplyGiftCard`, while a legacy order-backed cart id still falls through to `CartResolvable#find_cart!` (logged as `[legacy-gift-cards]`). Error codes are shared by both kinds — `gift_card_not_found` → 404, `gift_card_expired` / `gift_card_already_redeemed` → 422 — so the storefront BFF maps one contract. Cart stage is **money-free**: no payment is created and no balance is reserved (an earlier 404 here was why `cart_` gift cards were unusable); redemption happens in `Carts::Submit` (`order.apply_gift_card`), and an unusable card **fails the submission (no Order)**. `ShoppingCart` serializes only `gift_card: { code, display_amount_remaining }`.
- `POST/DELETE /api/v3/store/carts/:cart_id/store_credits` — **dual resolution** (PRD-20260914-checkout-cart-store-credits-canonical): a `cart_...` id resolves through `current_store.shopping_carts` and persists `cart.private_metadata['store_credit_amount']` via `PallasTrade::Carts::ApplyStoreCredit`, while a legacy order-backed cart id still falls through to `CartResolvable#find_cart!` (logged as `cart.legacy_flow.used`, flow_type `legacy_cart_store_credits`). Authentication stays mandatory (store credit is account property): guests get 401. Omitting `amount` stores the customer's full available credit total in the cart currency; `Carts::Submit` redeems it through the authoritative `Checkout::AddStoreCredit` (creating the store-credit payment method on demand) and fails the submission — no Order — when the credit is gone. Store credit and gift cards are **mutually exclusive per cart** (`store_credit_gift_card_conflict` / `gift_card_store_credit_conflict`), mirroring `GiftCards::Apply`. Errors: `store_credit_requires_login` / `store_credit_not_available` / `store_credit_invalid_amount`.
- Legacy order-domain cart endpoints are **compatibility-only** and carry the P0-7 triad **serve + deprecated + usage metric** (research §9.3 P2, PRD-20260915-checkout B5): `carts/payments`, `carts/fulfillments`, `carts/gift_cards`, `carts/store_credits` and `carts/discount_codes` log `cart.legacy_flow.used` (one `flow_type` per endpoint; `discount_codes` / `gift_cards` keep their historical `[legacy-…]` markers via `message:`), while `carts/payment_sessions` keeps its historical `payment.legacy_flow.used` key. **Only non-`cart_` ids are counted** — a `cart_` canonical shopping cart is *not* legacy traffic even though it shares the same route shape. Counting that message (grouped by `flow_type`) is how we decide whether a legacy endpoint ever gets a canonical implementation.
- `POST /api/v3/store/carts/:id/submit` — converts an active cart into an `Order` (`or_`-prefixed). The Cart row lock makes converted-cart replays return the same Order. The response is `CartSubmitResult` (`Order` fields plus nullable `successor_cart`); partial checkout moves only unselected items to that active successor. `order.submitted` is emitted only after commit and cannot block the persisted checkout.
- `GET /api/v3/store/customers/me/orders` — submitted or completed order history is queried with both `current_store` and `user_id = current_user.id`, so a newly submitted pending-payment Order is immediately visible. Never broaden this to an email match, an unscoped `Order` query, or a frontend-only filter; member reads and payment endpoints must enforce the same ownership boundary.
- `POST /api/v3/store/orders/:order_id/payment_sessions` + `GET/PATCH .../:id` + `PATCH .../:id/complete` — order-scoped payment sessions (Stripe Checkout `client_secret`, etc.). Create delegates to `PallasTrade::PaymentSessions::Start`: reuse a matching active session, perform provider I/O outside the Order lock transaction, reconcile concurrent local sessions, and use a stable Stripe operation key. Completion drives `Carts::Complete` (`pay!` + `finalize!`). Resolution is current-store + current-customer/token scoped and uses the owned-order `:show` permission.
- `GET /api/v3/store/shipping_methods` — front-end display list (`display_on: both/front_end`); each item carries `display_estimated_price` (authoritative cost is computed at submit).
- `PATCH /api/v3/store/customers/me/orders/:order_id/shipping_address` — update an own unpaid order's shipping address (combined-payment shipping step). Only `!paid? && amount_due > 0` orders; `shipping_address_id` (user's saved address) or inline `shipping_address` (country_iso/state_abbr resolved by Address model); IDOR-safe, syncs shipment address_id, does not reset checkout state. `Store::Customer::Orders::ShippingAddressController` + `PallasTrade::Orders::UpdateShippingAddress`.
- `GET /api/v3/store/payment_combinations/:id?expand=orders` — expands member orders (items + shipping addresses) for the combined-flow shipping/itemized steps.
- `POST /api/v3/store/payment_combinations` — combines several unpaid customer orders into one payment. **`order_ids.first` is the primary order** (the payment session is created on it; the rest are members) and the server must preserve that request order: resolving them with a bare `where(id: ...)` leaves the primary up to the database row order, so the session can land on a different member order (a real defect that surfaced as an order-dependent flake — `resolve_orders` now re-indexes by the requested ids instead of trusting the query order).
- `Order` serializer adds `state`, `status`, `submitted_at`, `cart_id`, `payment_methods` (the active `PaymentMethod` list for the order's market/currency).
- Cart/CartItem serializers: new `ShoppingCart` shape with `status` and `items[].selected` (see `pallastrade-typescript-sdk`).
- `POST /api/v3/store/catalog_events` — **guest-accessible** batch ingest of storefront
  `impression` / `click` / `product_added` / `product_searched` events
  (PRD-20260917-catalog-product-events). Strictly a **side channel**: nothing in the
  pricing / stock / order / checkout paths reads it. Body is
  `{ visitor_id, events: [...] }`; the whole batch is rejected (422, nothing written)
  when any `event_name` is outside the whitelist or the batch exceeds 100 events.
  `event_id` is the **idempotency key** (a repeat is silently ignored) and the response
  reports `received` — the number of valid events, *not* rows inserted. Zero PII: no IP,
  user agent, email or customer identity is accepted, `visitor_id` is hashed server-side
  into a store-scoped HMAC digest and never stored, and free-form `metadata` is rejected
  by the attribute allow-list. Because its rate-limit bucket is the store-wide
  publishable key, clients must flush **at most once per page view**.

### Admin API

**Who calls it:** trusted backend apps (your ERP integration, marketplace fulfillment service) or trusted humans (admin SPA users). Never the browser of an anonymous visitor.

**Auth:** Two distinct paths, each with its own authorization model.

**Path 1: Secret key with scopes** — for server-to-server apps and integrations.

```bash
curl -H "X-PallasTrade-Api-Key: sk_…" \
     https://my-pallastrade.example.com/api/v3/admin/orders
```

Secret keys (`sk_*` prefix) carry **scopes** that gate which endpoints they can hit. Scopes are granted at key creation. Each request's scope is enforced by `ScopedAuthorization`; missing scope = 403.

The scope list (5.5, from `PallasTrade::ApiKey::SCOPES`):
```
read_orders               write_orders
read_products             write_products
read_promotions           write_promotions
read_customers            write_customers
read_payments             write_payments
read_fulfillments         write_fulfillments
read_refunds              write_refunds
read_gift_cards           write_gift_cards
read_store_credits        write_store_credits
read_stock                write_stock
read_categories           write_categories
read_settings             write_settings
read_webhooks             write_webhooks
read_api_keys             write_api_keys
read_dashboard
read_all                  write_all     # superset (full admin)
```

Some endpoints map onto these rather than having their own pair: custom-field-definition endpoints require `read_settings`/`write_settings`, and export endpoints resolve their required scope per request (there is no `read_exports`/`write_exports` scope).

This is the right path for **building an app or integration**. The app gets a minimum-privilege secret key from the merchant; no human user is involved. Audit-friendly (you know exactly which app made each request).

**Path 2: JWT with CanCanCan abilities** — for human admin users.

```bash
# Login first
curl -X POST https://my-pallastrade.example.com/api/v3/admin/auth/login \
     -H "Content-Type: application/json" \
     -d '{"email":"admin@example.com","password":"…"}'
# Returns: { token, user } — the JWT is in `token`; the refresh token is set as an
# httpOnly cookie (used by POST /api/v3/admin/auth/refresh), not returned in the body.

# Then use the JWT
curl -H "Authorization: Bearer <jwt>" \
     https://my-pallastrade.example.com/api/v3/admin/orders
```

JWT admin auth uses **`PallasTrade::Ability` (CanCanCan)** to determine what the human user can do. Roles + permission sets configure who can manage what.

(The store is resolved from the request host, not from an API key.)

**What's exposed:** everything visible to the Store API plus timestamps (`created_at`, `updated_at`, `deleted_at` if paranoid), cost prices, private metadata, internal notes, audit fields (`approved_by_id`, `cancelled_by_id`), back-office relations.

**What actions are enabled:** full CRUD by default. `index`, `show`, `create`, `update`, `destroy` for every resource unless explicitly restricted.

### Quick reference

| Question | Store API | Admin API |
|---|---|---|
| Default actions | index, show | full CRUD |
| API key prefix | `pk_*` | `sk_*` (or use JWT instead) |
| Timestamps in responses | No | Yes |
| Cost prices exposed | No | Yes |
| Channel scoping | Optional header (default channel when omitted) | N/A (header ignored; filter via Ransack) |
| Default for new endpoints | Read-only | Full CRUD |
| Authorization | Per-endpoint defaults | Scopes (sk_*) OR CanCanCan abilities (JWT) |

## The {data, meta} envelope

Every list endpoint returns:

```json
{
  "data": [
    { "id": "prod_86Rf07xd4z", "name": "...", ... },
    { "id": "prod_kvJ0pQrTb9", "name": "...", ... }
  ],
  "meta": {
    "page": 1,
    "limit": 25,
    "count": 152,
    "pages": 7,
    "from": 1,
    "to": 25,
    "in": 25,
    "previous": null,
    "next": 2
  }
}
```

Single-record endpoints return the record's attributes directly (no wrapping):

```json
{ "id": "prod_86Rf07xd4z", "name": "...", ... }
```

Conventions:
- **There is no `type` field.** The resource kind is implied by the prefixed-ID prefix (`prod_`, `or_`, `variant_`, …). A few resources do expose a `type` attribute (payment methods, promotion rules/actions, price rules), but it is an STI class discriminator specific to that resource, not an envelope convention.
- **`meta` is on lists only.** Single-record responses don't have it.
- **`next` / `previous`** are page numbers (or `null` at the ends). Pagination is offset-based via Pagy — pass `?page=N&limit=N` to navigate.

## Prefixed IDs

Every v3 API uses Stripe-style prefixed IDs:

```
prod_86Rf07xd4z       Product
variant_k5nR8xLq      Variant
or_m3Rp9wXz           Order
py_…                  Payment       (Stripe parity)
ful_…                 Shipment
adj_…                 Adjustment
li_…                  LineItem
ch_…                  Channel
key_…                 ApiKey        (record ID; the credential token values are prefixed pk_/sk_ — those are secrets, not IDs)
cf_…                  CustomField   (alias of Metafield)
```

The integer PK is **never** in API responses — only the prefixed form. Same on writes: send `"variant_id": "variant_k5nR8xLq"`, not `"variant_id": 42`. The server resolves prefixed IDs to integer PKs internally.

Computation: `Sqids.encode([integer_pk])` with `min_length: 10`. Deterministic — the same PK always gets the same prefixed ID. There's no database column for it; it's computed on read.

The prefix is a **type assertion, not decoration** (PRD-20260914-other-prefixedid-ownership-validation, research §9.1 P0-f): resolving an id whose prefix belongs to another resource is a contract violation. Server behaviour: resource lookups return **404** (`find_by_prefix_id!` → `RecordNotFound`) and filter/param lookups yield an **empty set / `nil`** — never a different resource that happens to share the integer PK. `Order.find_by_param` and `Orders::FindComplete` accept only `or_…` ids (legacy order number / numeric id fallbacks unchanged). Prefixes are globally unique and guarded by a spec: `PaymentSession` keeps `ps_` (storefront and SDK depend on it) while `PaymentSource` moved to `src_` on 2026-09-14 (PRD-20260914-other-paymentsource-prefix-disambiguation). A shared prefix would make the type assertion useless and let prefix-branching code (e.g. `PaymentSessionReservationSubscriber`, which treats `ps_` as a session) resolve the wrong resource.

## Expand

Resources support an `expand` query param for sideloading related data:

```bash
curl '/api/v3/store/products/cool-shirt?expand=media,default_variant,categories'
```

Returns the product with `media`, `default_variant`, and `categories` inlined as full objects. Without `expand`, related objects appear as ID references on the parent. Dot notation lets you expand nested associations:

```bash
curl '/api/v3/store/products/cool-shirt?expand=variants.media'
```

Allowed expand keys are per-resource and listed in the OpenAPI spec.

### Sparse fieldsets

The inverse of `expand`: pass `fields=name,slug` to trim the response to just those attributes (`id` and any expanded associations are always retained):

```bash
curl '/api/v3/store/products?fields=name,slug'
```

## Pagination

```bash
GET /api/v3/admin/orders?page=2&limit=50
```

Offset-based via Pagy. `limit` defaults to 25; max is generally 100. Use `meta.next` / `meta.previous` to navigate.

## Filtering with Ransack

List endpoints accept Ransack predicates as `q[<attribute>_<predicate>]`:

```bash
# Products with name containing "shirt"
GET /api/v3/store/products?q[name_cont]=shirt

# Orders completed in the last 30 days
GET /api/v3/admin/orders?q[completed_at_gteq]=2026-05-01

# Multiple filters — use `status` (draft/placed/canceled, new in 5.5), not the legacy `state` (removed in PallasTrade 6)
GET /api/v3/admin/orders?q[status_eq]=placed&q[total_gt]=100

# Sort by completed_at descending
GET /api/v3/admin/orders?q[s]=completed_at+desc
```

Common predicates: `_eq`, `_not_eq`, `_in`, `_not_in`, `_cont` (LIKE %x%), `_start` (LIKE x%), `_gteq`, `_lteq`, `_gt`, `_lt`, `_present`, `_blank`.

Only attributes in the model's `whitelisted_ransackable_attributes` and `whitelisted_ransackable_associations` are queryable. Predicates on attributes outside the whitelist are silently ignored — the request returns 200 with that condition dropped (any remaining whitelisted predicates still apply), not a 422.

## Error responses

All errors use a consistent envelope:

```json
// 401 Unauthorized
{ "error": { "code": "invalid_token", "message": "Valid API key required" } }

// 403 Forbidden (scope missing)
{ "error": { "code": "access_denied", "message": "API key lacks scope: write_orders", "details": { "required_scope": "write_orders" } } }

// 404 Not Found
{ "error": { "code": "record_not_found", "message": "Product not found" } }

// 422 Unprocessable Entity (validation)
{
  "error": {
    "code": "validation_error",
    "message": "Email can't be blank and Customer is required for checkout",
    "details": {
      "email": ["can't be blank"],
      "base": ["Customer is required for checkout"]
    }
  }
}

// 429 Too Many Requests (rate limited)
{ "error": { "code": "rate_limit_exceeded", "message": "..." } }
```

Note: some resources return a specific code instead of `record_not_found`: `order_not_found` (orders), `cart_not_found` (carts — order lookups on /carts paths), `line_item_not_found`, `variant_not_found`. The message is always "<Model> not found".

The `details` map on 422s uses **attribute names** as keys. Map field-level errors to inputs; `base` errors are non-field-specific (display as a form-level banner). The `@pallastrade/sdk` includes a `PallasTradeError` class that parses these automatically.

## Rate limiting

The API has per-key and per-endpoint rate limits configured via `PallasTrade::Api::Config`:

| Setting | Default | Scope |
|---|---|---|
| `rate_limit_per_key` | 300 / 60s | General requests, per API key |
| `rate_limit_window` | 60s | Window for the per-key counter |
| `rate_limit_login` | 5 / 60s | `POST /api/v3/{store,admin}/auth/login` + admin invitation acceptance, per IP |
| `rate_limit_register` | 3 / 60s | Customer register + newsletter subscribe endpoints, per IP |
| `rate_limit_refresh` | 10 / 60s | Token refresh (store + admin) and store logout, per IP |
| `rate_limit_password_reset` | 3 / 60s | Password reset, per IP |

Hit limits → `429 Too Many Requests` with `Retry-After` header. The `@pallastrade/sdk` retries with exponential backoff automatically.

Tune via `PallasTrade::Api::Config[:rate_limit_per_key]` etc. in `config/initializers/pallastrade.rb`. For tougher global throttling (per-IP at the proxy edge), layer Rack::Attack or your CDN's WAF on top.

### How the limit is actually implemented (read this before adding a high-volume endpoint)

The limits above are Rails 8.1's built-in `rate_limit`, declared **once** on
`PallasTrade::Api::V3::BaseController`:

```ruby
rate_limit to: PallasTrade::Api::Config[:rate_limit_per_key],
           within: PallasTrade::Api::Config[:rate_limit_window].seconds,
           store: Rails.cache,
           by: -> { request.headers['X-PallasTrade-Api-Key'] || request.remote_ip },
           with: RATE_LIMIT_RESPONSE
```

Four consequences that are easy to get wrong:

1. **The counter is keyed by API key, not by IP.** A storefront serves every visitor
   with a single publishable key, so `rate_limit_per_key` is a budget for the **whole
   store**, not per shopper.
2. **The bucket is scoped per controller** (`scope` defaults to `controller_path`, and
   `RateLimitHeaders` reads the same composed key). A new endpoint therefore gets its
   own budget and does **not** consume the products/cart/checkout budget.
3. **A subclass cannot opt out.** `rate_limit` registers an anonymous `before_action`
   lambda, so `skip_before_action` cannot target it — the inherited limit always
   applies. Adding a second `rate_limit` in a subclass only *adds* a limiter (the
   tighter one wins); it never relaxes the parent's.
4. **`config.cache_store = :null_store` in the test env makes every `rate_limit`
   inert**, and `store:` is captured when the class body is evaluated — so rate
   limiting cannot be exercised from specs. Assert the declaration/design invariant
   instead of expecting a 429.

High-volume endpoints (e.g. `catalog_events`) must therefore be designed so the
**request count scales with page views, not with events** — batch on the client, flush
at most once per page view, and add a stricter per-IP limiter so a single abusive client
cannot drain the store-wide budget.

---

## Store API — catalog events (side-channel product analytics)

`POST /api/v3/store/catalog_events` (guest-accessible, publishable key) ingests a batch
of storefront `impression` / `click` / `product_added` / `product_searched` events into
the store's **own** database so `Related Product CTR` can be computed from first-party
data. See `pallastrade-data-model` for the table and `pallastrade-storefront` for the
client-side batching contract.

## Turnstile human verification (customer registration)

`POST /api/v3/store/customers` (and newsletter subscribe) gates registration on a
Cloudflare Turnstile token **only when `TURNSTILE_SECRET_KEY` is configured**. The
client renders a Turnstile widget and submits the response as `turnstile_token`.

The verification outcome is tri-state:

| Verifier result | Meaning | API behavior |
|---|---|---|
| `true` | Cloudflare confirmed the token | Registration proceeds |
| `false` | Cloudflare explicitly rejected the token | `422 turnstile_verification_failed` |
| `nil` | Unable to verify (secret missing / network unreachable / upstream anomaly) | Degrade **open** with a `[Turnstile]` warning log; registration proceeds |

**Why degrade open on `nil`:** on CN-hosted servers `challenges.cloudflare.com` is
frequently unreachable (TCP/TLS connects but the HTTPS siteverify request times
out). Fail-closed there would make registration permanently impossible. An
explicit Cloudflare rejection (`false`) is still always respected.

Implementation: `PallasTrade::Api::Turnstile.verify(token, remote_ip:)` returns
`true` / `false` / `nil`; `PallasTrade::Api::V3::Store::CustomersController#turnstile_verified?`
maps `nil` → allow + `Rails.logger.warn`.

## SEO 301 redirects

Storefronts issue 301/302 redirects for retired/renamed URLs via `PallasTrade::Redirect`
(per-store `from_path` → `to_path`, paths are normalized: leading slash added, trailing
slash stripped, leading origin stripped from `from_path`; `to_path` must stay internal).

- **Store API** (used by the storefront middleware):
  `GET /api/v3/store/redirects/resolve?path=/old-product` → `{ data: { path, status_code } | null }`.
- **Admin API**: `/api/v3/admin/redirects` full CRUD (scoped to `read_settings` / `write_settings`,
  plus CanCanCan `manage`). Records carry optional business-facing `title`/`description`
  (serializer + `permitted_params` both expose them) so the admin list is readable.
  `active: false` entries are ignored by resolve.
- Storefront: `storefront/src/lib/pallastrade/middleware.ts` (wired via `src/proxy.ts`) resolves
  every storefront pathname with a 60s revalidate cache; on a hit it issues
  `NextResponse.redirect(target, status)`, guarded against A→A loops and degrading open when the
  API is unreachable (Turnstile-style).

### Back-in-stock subscriptions (Store API)

- **Store API**: `POST /api/v3/store/products/:product_id/back_in_stock_subscriptions`
  (guest-accessible, rate-limited). Body `{ email }`. Idempotent per (product, email); re-activates
  a previously-notified subscription. Serializer returns `{ id, email, status, product_id, created_at }`.
- Notifications are sent by `PallasTrade::BackInStockSubscriber` on the `product.back_in_stock`
  event; see the events skill.

### Review list ordering (Store API, F-4 2026-09-16)

`GET /api/v3/store/products/:product_id/reviews` takes an optional `?sort=`:
`newest` (default — the pre-F-4 order) / `highest_rating` / `lowest_rating`.

- **Unknown or blank values fall back to `newest`** instead of returning 4xx: the whitelist is an
  internal detail, not something a caller should be able to probe through error codes.
- **Every ordering ends with `id DESC`.** Rating (and `created_at`) repeat constantly, so without a
  final unique tie-break a paged walk would repeat or skip reviews.
- `meta.sort` echoes the value that was **actually applied** (including the fallback); every other
  `meta` key — the pagination set and F-1's `rating_distribution` — is unchanged.
- **Distribution is orthogonal to ordering**: `rating_distribution` always describes the whole
  approved population, never just the returned page, so it must be byte-identical across all three
  orderings (spec-asserted).

### Review helpful votes (Store API, F-5 2026-09-16)

`POST` / `DELETE /api/v3/store/reviews/:review_id/helpful_vote` — **customer JWT required**;
`:review_id` is the prefixed review id (`rev_…`). The path is top-level (not nested under
`products`) because the vote is about the review, not about browsing a product.

- **One vote per customer per review**, enforced by a unique index on
  `pallastrade_review_votes (review_id, user_id)`: repeating `POST` is idempotent and never double
  counts, and `DELETE` on a vote that was never cast is idempotent too.
- **Both calls answer the authoritative state**, not the review:
  `{ data: { id, type: "review_helpful_vote", attributes: { review_id, helpful_votes_count, helpful_voted } } }`.
  A storefront therefore never has to guess whether the click landed.
- **Guards**: your own review → 422 `own_review_vote_forbidden`; a review that is not `approved`
  (or belongs to another store) → 404 — the same “invisible means absent” rule the read endpoints
  follow; anonymous → 401.
- **Read model** (additive on `ReviewSerializer`): `helpful_votes_count` is public; `helpful_voted`
  is the caller's own state — `true`/`false` for a signed-in customer, `null` for anonymous callers
  (never a `false` that answers a question nobody asked). **Voter identity is never exposed**
  (no `user_id`, no voter list) — spec-asserted.
- `?sort=most_helpful` extends F-4's whitelist: `helpful_votes_count DESC, id DESC`. The tie-break
  matters here as much as it does for ratings — most reviews share a vote count (very often 0) —
  and the fallback / `meta.sort` contract is unchanged.
- The count is a **counter cache** on `pallastrade_reviews`, so a list page reads it per row without
  a `COUNT(*)` per review.

### Stock buckets & shipping estimate (Store API, F-2 2026-09-16)

- **`stock_status`** — added to `VariantSerializer` and `ProductSerializer` (additive; the 4.2
  booleans `purchasable/in_stock/backorderable/preorder` are untouched). Values:
  `in_stock | low_stock | preorder | backorder | out_of_stock`.
  - Single source of truth: `PallasTrade::Catalog::StockStatus` reads availability through
    `PallasTrade::Stock::Quantifier` — the same object `Variant#in_stock?` uses — so the bucket can
    never disagree with the booleans. `> threshold` → `in_stock`, `1..threshold` → `low_stock`,
    `0 + preorderable` → `preorder`, `0 + backorderable` → `backorder`, else `out_of_stock`.
  - Threshold: `Store#preferred_low_stock_threshold` (default 5); invalid (0/negative/blank)
    normalizes back to the default in `StockStatus.threshold_for`.
  - **Never publish a quantity**: exact `count_on_hand` / `total_on_hand` must not appear in any
    Store API response (spec-asserted). Variants that do not track inventory are always `in_stock` —
    never invent scarcity.
  - Product-level bucket = the best variant's bucket (in_stock > low_stock > preorder > backorder >
    out_of_stock). Lists preload `variants → stock_items → active_stock_reservations`
    (`collection_includes`), so serializing a page adds **no** per-product query.
- **`GET /api/v3/store/shipping_estimate`** (F-2) — the PDP shipping block's read model:
  `{ data: { available, digital, min_days, max_days, free_shipping, free_shipping_threshold,
  business_day_source: "weekdays", methods: [...] } }`. Optional `product_id` (prefixed) and
  `country`. Advice only — the authoritative cost is still computed at submit (`Carts::Submit`).
  Public, publishable key.
- **`GET /api/v3/store/shipping_methods`** (F-2) — now also returns
  `estimated_transit_business_days_min/max` and accepts an optional `country` that narrows the list
  by zone; when no zone matches it falls back to the full set rather than claiming there is no
  delivery.

### Product reviews (Store API, P0-4 / F-1)

- **Read (public, api_key)**: `GET /api/v3/store/products/:product_id/reviews` — approved reviews
  only, newest first, **paginated** (`?page&limit`, default 10 / max 100; deterministic
  `created_at DESC, id DESC` so consecutive pages neither repeat nor skip). The v3 envelope carries
  `meta` = standard pagination keys **+ `rating_distribution`** (`{"5": n, …, "1": n}`) computed
  server-side from the same scope as the page — never from the returned slice.
  Item: `{ id, product_id, user_name, rating, title, body, verified_purchase, created_at, image_urls,
  helpful_votes_count, helpful_voted }`; `image_urls` are absolute CDN URLs and only ever present
  for approved reviews, while the two vote fields are F-5 (see the helpful-votes section above).
- **Write (customer JWT required)**: `POST /api/v3/store/products/:product_id/reviews`
  with `{ rating (1–5, required), title?, body?, images? }`. Creates a `pending` review; one review
  per (product, user) — duplicates → 422. `verified_purchase` is computed from the customer's
  completed orders. Unauthenticated → 401.
  - `images` = up to 3 signed ids from `POST /api/v3/store/direct_uploads` (jpeg/png/webp, ≤ 5 MB).
    Failures are explicit 422s: `review_image_limit_exceeded`, `review_image_not_owned`,
    `review_image_invalid`. A rejected upload never mutates an existing review.
- **Direct uploads (customer JWT required)**: `POST /api/v3/store/direct_uploads` with
  `{ filename, content_type, byte_size, checksum }` → signed id + upload URL (same ActiveStorage
  shape as the admin side). The blob records the uploading user in its metadata, and review
  creation only accepts ids that user uploaded and has not attached already.
- Moderation: admin `PallasTrade::Admin::ReviewsController` approves/rejects/deletes; only
  `approved` reviews are public and counted in `Product#average_rating` / `#review_count`
  (exposed on `ProductSerializer`). The admin reviews table shows a **photos** column
  (`pallastrade/admin/tables/columns/_review_photos.html.erb`).
- Model: `PallasTrade::Review` (`SingleStoreResource`, `has_prefix_id :rev`, unique
  `[product_id, user_id]`, `has_many_attached :images` with `MAX_IMAGES = 3`,
  `ALLOWED_IMAGE_TYPES`, `MAX_IMAGE_BYTES = 5.megabytes`).

### Blog posts — CMS (Store + Admin API)

- **Store API (read-only, published only)**:
  - `GET /api/v3/store/posts` — paginated list of published posts, newest first (`{ data, meta }`).
  - `GET /api/v3/store/posts/:slug` (or `post_xxx` prefixed ID) — single post; drafts/scheduled → 404.
- **Admin API (full CRUD, scoped `read_settings`/`write_settings`)**:
  `GET/POST/PATCH/DELETE /api/v3/admin/posts`. Includes drafts and scheduled posts; the serializer
  exposes a `status` attribute (`draft` / `scheduled` / `published`). `published_at` blank = draft,
  future = scheduled.
- Model: `PallasTrade::Post` (store-scoped, `TranslatableResource` + ActionText body + FriendlyId slug).
- Serializer output: `id, title, slug, excerpt, author, published_at, cover_image_url, body, body_html,
  seo_title, seo_description` (Admin also `status`, timestamps).

### Payment methods — option projection (2026-09-15, D1 PRD-20260915-admin)

支付配置选项化（支付商 × 支付方式 → 前台入口）是**纯 additive** 契约增量，**无端点增删**：

- Store `PaymentMethodSerializer`（cart/order 的 `payment_methods[]`）新增：
  - `kind` — 前台入口身份；未选项化 provider 为默认入口（= `api_type`，如 `stripe`）
  - `frontend_kind` — 前端形态（`inline` / `manual`；选项化后取 provider 能力目录，如钱包 `express`）
- Store checkout serializer 的 `payment_method_payload` 同步这两个字段（两处契约必须一致）。
- Admin `PaymentMethodSerializer` 新增：
  - `optionized` — 是否已选项化（决定「0 入口」语义）
  - `options` — 生效入口目录：`kind` / `name` / `frontend_kind` / `active` / `position`
- `PallasTrade::PaymentSessions::Start`：provider 级新增 `frontend_visible?` 门控（选项化且 0 可用入口 →
  拒绝建会话）；新增**可选** `option_kind`（入口级同源校验，不传 = 行为完全不变）。
- 后台写入口不走 API：`/admin/payment_methods/:id` 表单（选项化页签 + Test connection，见 `pallastrade-admin`）；
  OpenAPI schemas 由 `scripts/ci/contracts.sh`（typelizer + `rake api:docs:schemas`）生成，勿手改。

### Payment credentials & environment (D9, 2026-09-15, PRD-20260915-payments-d9)

凭据与环境同样是 **additive** 契约增量，**无 store 侧变更**：

- Admin `PaymentMethodSerializer` 新增：
  - `environment` —— `test` / `live`（列默认 `live`，存量零回归）
  - `credential_status` —— `[{ key, level(secret|publishable|internal), rotated_at, expires_on, days_left, alert_level(none|30d|7d|1d|expired) }]`，**不含任何凭据值**
- Admin 新增动作 `POST /admin/payment_methods/:id/reveal_credential`（body `key`）：仅 owner 等价权限；返回 `{ key, value }`（JSON）或 turbo_stream；**必写审计**（记 key 不记值）；未知 key → 422。
- store 侧无字段变更：test provider 由服务端过滤，不在 `available_payment_methods[]`；测试会话仅在 `PaymentSession#external_data.test_mode` 里可观测。
- 契约经 `scripts/ci/contracts.sh` 再生成（typelizer → admin SDK + `api-docs/admin.yaml`）。

### Payment availability scope (D8, 2026-09-15, PRD-20260915-payments-d8)

支付适用范围（入口级 `rule_set`：market / country / zone / currency）同样是 **additive** 契约增量，**无端点增删**：

- Admin `PaymentMethodSerializer#options[]` 新增：
  - `rule_set` — 归一后的规则集（`{ match, include[], exclude[] }`；无规则 = `null`）
  - `scope_summary` — 后台可读摘要（i18n；如 `Markets: EU · Currencies: EUR`，排除项带 `Exclude` 前缀）
- Store 侧**请求/响应形状不变**：范围过滤在服务端（`Order#payment_methods`），被拒入口不出现在列表；
  唯一新增是失败码——`POST /orders/{order_id}/payment_sessions`（及 legacy cart 同形端点）422
  `payment_option_not_available`（入口在 Start 被范围/`frontend_visible?` 判不可用），store.yaml 两端点已补示例。
- 前台消费：收到该码 → 刷新支付方式列表 + 提示重选（**不得**拿旧列表重试）。

### Admin promotions — writable/readable fields (2026-09-11 batch6 cleanup)

`path` (and the never-exposed `advertise`) are gone from the Admin promotion contract: the v3 admin
`promotions_controller#permitted_attributes` no longer permits `:path`, and
`V3::Admin::PromotionSerializer` no longer declares/serializes `path`. Both columns were dropped
from `pallastrade_promotions` (PRD-20260911-promo-batch6). `promotion_category_id` is unchanged —
categories are admin-managed since batch6 (see the **Promotions → Categories** entry in
`pallastrade-admin`). **No endpoint was added or removed.**

### Promotion redemptions — read-only ops endpoints (Admin API, 2026-09-10 batch3c)

- `GET /api/v3/admin/promotion_redemptions` — `{ data, meta }` list of the redemption ledger,
  newest first. Convenience filters: `order_id` (`order_…`), `promotion_id` (`promo_…`),
  `state` (`reserved` / `committed` / `released`); Ransack `q[...]` and `page`/`limit` also work.
  Invalid prefixed filters return an empty set (never a 500).
- `GET /api/v3/admin/promotion_redemptions/:id` — single row (`redemption_…`); unknown id → 404.
- Read-only: no create/update/destroy. Scoped `read` capability (permission registry
  `:promotion_redemptions`); API-key principals are gated by `scoped_resource`, JWT admins by CanCan.
- Serializer fields: `state`, `promotion_id`, `order_id`, `user_id`, `coupon_code`, `amount`,
  `display_amount`, `currency`, `reserved_at`, `reserved_until`, `committed_at`, `released_at`,
  `release_reason`.

### Order refund calculation — read-only preview (Admin API, 2026-09-10 batch4b)

- `GET /api/v3/admin/orders/:order_id/refund_calculation` — read-only projection of
  **原金额 / 分摊优惠 / 可退金额** per line item (`data.line_items[]`: `line_item_id` (`li_…`),
  `original_amount`, `allocated_discount`, `allocated_discount_breakdown{line_item,order_prorata,shipment_prorata}`,
  `pre_tax_amount`, `refundable_amount`, `refundable_source`), plus `data.promotions[]`
  (per promotion `original_discount` / `allocated_discount` / `balanced`) and `data.totals`.
- Optional `quantities[<li_…>]=n` (default: full line quantity). Validation is strict:
  non-integer, unknown line item, or `n > line quantity` → **422** (`unknown line_item_id: …`).
- `refundable_amount` goes through the frozen refund authority (`ReturnItem` +
  `Calculator::Returns::DefaultRefundAmount`) — the endpoint never recomputes promotions and
  never writes (`Refund`/`ReturnItem` counts unchanged; repeated calls are identical).
- Authorization reuses `Orders::BaseController`: the parent order is resolved from
  `current_store.orders` (cross-store → 404) and authorized with the order's `:show` capability
  (read-only role OK; a role without `read Order` → 403). Serializer:
  `admin_refund_calculation_serializer` (registered in `pallastrade/api/dependencies.rb`).

## Read/write attribute symmetry (a v3 invariant)

For any resource: **whatever a serializer returns, the controller's `permitted_params` accepts on write under the same name.** No `label` exposed but `presentation` accepted. No `customer_note` exposed but `special_instructions` accepted. The client never has to translate.

When the underlying column has a legacy name, the model has an alias method (e.g. `PallasTrade::OptionType` exposes `label`/`label=` aliasing the underlying `presentation` column). The model owns the bridge.

## Common debugging recipes

### "I'm getting 401 on every call"

- Check `X-PallasTrade-Api-Key` header is set.
- Verify the key is valid: `GET /api/v3/admin/me` returns 200 if your JWT is valid; otherwise 401.
- Publishable key for Store API; secret OR JWT for Admin API. Mixing them = 401.

### "I'm getting 403 on Admin API"

- For secret keys: the key doesn't have the required scope. Check the key's scopes; either grant the scope or use a JWT admin user.
- For JWT admins: the user doesn't have the required ability. Check `PallasTrade::Ability` rules for the user's role.

### "My q[...] filter is silently ignored"

The attribute isn't in the model's Ransack allowlist. The API uses lenient `.ransack`, so conditions on non-whitelisted attributes are silently dropped — the list comes back unfiltered (200, no error). Add the attribute via `PallasTrade.ransack.add_attribute(PallasTrade::Product, :attr)` in an initializer, or append it to `whitelisted_ransackable_attributes` in a model decorator.

### "Empty data array but I know records exist"

- Wrong channel? Store API queries are channel-scoped. Try `X-PallasTrade-Channel: <code>` matching where the record was created.
- Wrong currency? Some resources (products) are filtered by `available(currency)` — record exists but doesn't have a price in the requested currency.
- Authorization scope? For Admin: maybe your role can see the index but the scope of accessible records is restricted.

### "Webhook payload uses raw IDs?"

It doesn't — Webhooks 2.0 uses the same prefixed IDs as the API. If you're seeing integer IDs, you're either on the legacy webhooks system OR the consumer is parsing wrong.

### 父订单聚合序列化（P3, 2026-08-27）

拆单后父订单（`is_parent: true`，有 children）的金额/状态字段在 Store + Admin `OrderSerializer` 中输出**聚合派生值**（模型方法见 `pallastrade-data-model` SKILL「Order 聚合派生」）：

| 字段 | 聚合语义 |
|---|---|
| `total` / `display_total` | own + Σ children（递归） |
| `amount_due` / `display_amount_due` | 聚合未结余额 - 已用 store credit，下限 0 |
| `payment_total` / `display_payment_total`（Admin） | own + Σ children 已付 |
| `payment_status`（= `fulfillment_status` 旧别名） | `combined_payment_state` |
| `fulfillment_status`（= `shipment_state` 旧别名） | `combined_shipment_state`（partial 等） |

单订单（无 children）时聚合值 == 原值，响应与拆单前完全一致（零行为变化）。字段类型不变（string money / string enum），OpenAPI schema 无需变更。

### 手动拆单端点（P6, 2026-08-28，flag 灰度）

`POST /api/v3/admin/orders/:id/split`（Admin API，scope `write_orders`）——把订单部分行项目拆成子订单：

- **参数**：`groups`（必需，`Hash<group_key → line_item_ids>`，支持 `li_` 前缀或整型）、`parent_order_id`（可选）、`store_id`（可选，P6 仅允许 == 源订单 store，跨店返回 `order_cannot_split`）。
- **flag**：`store.preferred_manual_split_enabled` / `Config[:admin_manual_split_enabled]`，默认关闭 → 404。
- **响应**：`{ data: { parent, children } }`（均走 Admin `OrderSerializer`，父订单输出 P3 聚合值）。
- **错误**：`order_cannot_split`（已取消/无行项目/重复拆单/跨店/已发货行项目），`code + message` 无裸 422。
- **编排**：`PallasTrade::Orders::ManualSplit`（复用 P2 `Splitter`，见 `pallastrade-checkout` SKILL「手动拆单」）。

### 组合级取消端点（REV-P6-8f, 2026-09-08）

`POST /api/v3/admin/payment_combinations/:id/cancel`（Admin API，scope `write_orders`）——succeeded 组合的
组合级取消编排（`PallasTrade::Orders::CombinationCancel`）：

- **前置**：组合必须 `status=succeeded`（pre-payment 取消仍是 `PaymentCombination#cancel`）；非 succeeded → 422。
- **参数**（均可选）：`member_ids`（`order_` prefixed id 数组，缺省=全部未取消成员）、`reason`/`note`/
  `refund_payments`（三态，缺省 auto）、`restock_items`/`notify_customer`。
- **资金语义**：每个 PAID 组合成员无本地 PSP payment —— `Orders::Cancel` split-aware 在组合 Payment +
  冻结 `PaymentSplit` 上建 durable `Refund(requested)`（`payment_split_id`/`target_order_id`），异步 ExecuteJob。
- **响应**：`{ data: { id: pcom_…, type: 'payment_combination', attributes: { status, members:
  {total,canceled,skipped,failed}, canceled[]/skipped[]/failed[] } } }`（只暴露 prefixed id + 单号，无整型 PK）。
- **错误**：404（跨店/不存在）、403（无 `:cancel` 权限）、422（非 succeeded / 无有效成员）。
- 幂等：重复调用只处理仍未取消成员（skip already_canceled），不重复建 Refund。

### 组合/支付/退款只读端点（REV-P6-8l, 2026-09-09）

Admin API **只读**端点（scope `read_orders`/ability read；**扁平 serializer 风格**——无 type/attributes
嵌套，同 8a refund create）：

- `GET /api/v3/admin/payment_combinations`（index：store 作用域 ransack `q` + `limit` 分页，`{data[],meta}`；
  轻量 status/amount/currency/member_count/refunded_total）；`GET /api/v3/admin/payment_combinations/:id`
  （`expand=members,payments,transaction`：split captured/refunded/credit_allowed + 组合 payment +
  txn 摘要）。新 `PallasTrade::Api::V3::Admin::PaymentCombinationSerializer`。
- `GET /api/v3/admin/orders/:order_id/refunds/:id`（refund 详情：8a 生命周期字段）。
- `GET /api/v3/admin/payments/:id`（**顶层** payment——组合 Payment `order_id=nil` 经嵌套不可达；store
  作用域=锚点派生 combo.store_id ∪ order.store_id）；`GET /api/v3/admin/payments/:id/orphan_pairing`
  （只读 `Refunds::OrphanPairing`：status 五态 + orphans 金额；零写/降级不 500）。

### 促销定义发现（`/promotion_*_types`, `/promotion_actions/calculators`）单源化（PRD-20260910-promo-batch5a）

三个只读发现端点的数据源统一为 `PallasTrade::Promotions::DefinitionRegistry`（只读投影）：

- `GET /api/v3/admin/promotion_rules/types`、`GET /api/v3/admin/promotion_actions/types`：
  `{ data: [{ type, label, description, preference_schema }] }`——`type` 是 **api_type 简写**
  （`category` / `customer` / `free_shipping`），`label`/`description` 来自 locale，
  `preference_schema` 来自 `serialized_preference_schema`；**响应结构未变**，仅来源换成 registry
  （`PreferenceSchema#registered_subclasses` 走 `DefinitionRegistry.rule_classes/.action_classes`）。
- `GET /api/v3/admin/promotion_actions/calculators?type=…`：`?type` 既接受简写（`create_adjustment`）
  也接受完整类名（`PallasTrade::Promotion::Actions::CreateAdjustment`，`SubclassedResource#resolve_subclass`
  兜底匹配——只匹配注册表内类，不做 `constantize`）。
- 写路径 `SubclassedResource#subclassed_via` 的 allowlist 同样是 registry
  （`DefinitionRegistry.rule_classes` / `.action_classes`），未注册类型一律 422
  （`unknown_promotion_rule_type` / `unknown_promotion_action_type`）。
- 新增规则/动作只需注册到 `PallasTrade.promotions.rules/.actions` 与 calculator 桶；
  可用 `bundle exec rake pallastrade:promotions:definitions` 校验四件套是否齐全。

## Where to read further

- **OpenAPI specs:** `node_modules/@pallastrade/docs/dist/api-reference/store.yaml` (Store API) and `admin.yaml` (Admin API) — every endpoint, parameter, response schema. Authoritative.
- **Adding a new endpoint:** see the `pallastrade-resource` skill — `pallastrade:api_resource` generator produces v3-conformant controllers + serializers automatically.
- **SDK:** `@pallastrade/sdk` (Store) and `@pallastrade/admin-sdk` (Admin) — typed clients. See the `pallastrade-typescript-sdk` skill.
- **Customization:** `node_modules/@pallastrade/docs/dist/developer/customization/api.md` and `authentication.md`
- **Webhooks vs subscribers:** see the `pallastrade-events-webhooks` skill.

## Legacy route deprecation & retirement（P0-7 三件套，2026-09-15 B5）

`/api/v3/store/carts/:cart_id/{discount_codes,gift_cards,fulfillments,payments,payment_sessions,store_credits}` 是方案 §45 的六行 legacy matrix。它们**继续服务存量调用**，但必须同时满足三件套：

1. **继续服务** —— 行为不变（状态码/响应体/副作用），不做“干净代码”式删除。
2. **deprecated 信号（机器可读）** —— 由 `PallasTrade::Api::V3::LegacyFlowObservable` 在 **legacy 身份**（请求 id 非 `cart_`）上注入：
   * 响应头 `Deprecation: true` / `Warning: 299 - "Legacy cart endpoint; migrate to …"` / `Link: <canonical>; rel="successor-version"`（不设 `Sunset`——删除须独立立项）；
   * `store.yaml`（+ `platform/docs/api-reference/store.yaml` 副本）`deprecated: true`（仅无 canonical 角色的 `payments` / `payment_sessions*` 四个操作）与 `x-cart-domain-legacy: true` + `x-canonical-successor: …`（全部 legacy 操作）；
   * SDK `carts.{discountCodes,giftCards,fulfillments,payments,paymentSessions,storeCredits}` 的 `@deprecated` JSDoc。
   **`cart_` canonical 流量不得被打标**（它与 legacy 共用同一路由形状，是当前新流程的正常路径）。
3. **usage metric** —— 统一字段契约：`message` / `flow_type` / `entry_point` / `requested_cart_id` / `legacy_identity`(`canonical_cart`｜`order_table_cart`｜`unknown`) / `action` / `deprecated: true` / `canonical_successor` / `user_agent`。历史 key 保留（`payment.legacy_flow.used` 与 `[legacy-…]` 标记），迁移/刷新都不得改 key。

**退役阀值（判决规则）**：某行连续 **30 天** `legacy_identity = order_table_cart` 的计数为 0 → 可**独立立项**删除该行（需新 PRD + 影响面公告）。阀值未达之前：**不得**删除控制器/路由，**不得**在 legacy 上新增能力（§45 禁令）。

**零新增调用**：`cart_` canonical 流程是唯一允许的前端路径（B4 已清掉最后一个 `carts.paymentSessions` 消费者）；`storefront` 的守护测试 `src/lib/data/__tests__/legacy-payment-sessions-guard.test.ts` 机器化该约束（零 `carts.{paymentSessions,payments,complete}`；其余四行只允许出现在白名单文件）。

## 支付入口展示元数据（D16 切片1, 2026-09-16；PRD-20260916-payments-d16-payment-method-presentation）

store 侧支付方式 payload 的 **additive** 字段（不新增端点、不改行基数）：

| 字段 | 来源 | 语义 |
|---|---|---|
| `option_id` | `PaymentMethod#option_identifier` | `"<prefixed_id>:<kind>"`，与后台 line item 的 `prefixed_id:kind` 同源 |
| `method_key` | 入口 `metadata['options'][i]['kind']` → `default_option_kind` | 前台按入口分流的键（不解析 `option_id` 字符串） |
| `display_name` | 入口 `display_name` → 回落 `name` | 入口级展示名（前台方法行优先渲染它） |

落地位置：`PallasTrade::Api::V3::Store::Checkout::CheckoutSerializer`（`payment.available_payment_methods[]`）
与 `PallasTrade::Api::V3::PaymentMethodSerializer`（cart / order / shopping_cart 同族）。
三字段都已进 typelize（`backend/app/javascript/types/serializers/*` + SDK generated types + `{store,admin}.yaml`），
契约漂移由 `harness generated:check` 守（漂移即失败）。**新增支付方式字段一律走这条链**，不要在控制器里手工拼 hash。

## checkout 认证需求标志（D15 切片3, 2026-09-17；PRD-20260917-checkout-d15-切片3）

`GET /api/v3/store/orders/:id/checkout` 的 `payment.available_payment_methods[]` **additive** 新增：

- `requires_authentication`（布尔）：本单是否要求 3DS/SCA 认证（源：门店策略 + 最近一次风险决策）。
- **列表仍只含可用入口**（隐藏 = 不出现）：认证需求 = 是时，未声明可认证能力的入口（如钱包 express）**不会出现在列表里**，客户端**不得**自己做筛选。
- 列表为空 + `requires_authentication: true` = 「本店没有可完成认证的支付方式」→ 前台展示提示（不得静默空白、不得降级到弱认证入口）。
- 入口不可用而客户端仍调 `POST .../payment_sessions` → 422 `payment_option_not_available`，`reason` 可能是 `authentication_required`（与 D8 其它不可用原因同码）；**不建会话**。
- 类型同步：Typelizer 生成的 `StoreCheckoutCheckout`（`platform/packages/sdk/src/types/generated/`）已含该字段；`harness generated:check` 零漂移。

## 入口级支付投影与 `option_kind`（D7, 2026-09-18；PRD-20260918-payments-d7-payment-section-express）

**响应（additive）**：

- `GET /api/v3/store/orders/:id/checkout` → `payment.available_payment_methods[]` 新增：
  - `entries[]`：`option_id`（`"pm_x:card"`）/ `method_key`（kind）/ `display_name` / `frontend_kind`（`inline`|`express`|`manual`）/
    `group`（`card`|`wallet`|`redirect`|`manual`）/ `position`；**有序**（= 后台排序），集合 = `Availability::Resolver.available_option_kinds`
    （无订单上下文时不过滤，安全降级）。
  - `group` / `position`（provider 级，取首个生效入口）。
- store `PaymentMethodSerializer`（cart / order / shopping_cart 同族）：新增 `group` / `position` **与 `entries[]`**。
  ⚠️ 该通道**没有订单上下文**，所以入口列表是「已配置且启用」的集合（**不过滤**）——
  前台因此能显示 Apple Pay / Google Pay；真正的可用性判定仍在 `PaymentSessions::Start`（带订单上下文，D8/D15c 同源），
  被拒 → `422 payment_option_not_available` → 前台刷新列表 + 提示重选。
  （checkout 通道的 `entries[]` 才是带订单上下文的**过滤后**集合；两者字段形状一致。）

**请求（additive）**：三处创建支付会话的端点接受 `option_kind`（缺省 = provider 默认入口，零回归）——

| 端点 | 行为 |
|---|---|
| `POST /api/v3/store/orders/:order_id/payment_sessions` | 透传 `PaymentSessions::Start` |
| `POST /api/v3/store/orders/:order_id/transactions` | 经 `Transactions::Start`（新 `option_kind:` 关键字参数）透传 |
| `POST /api/v3/store/carts/:cart_id/payment_sessions`（legacy） | 透传；拒绝时沿用通道通用错误码 `validation_error`（B5 治理：不新增 legacy 契约） |

不可用入口 → **建会话前** `422 payment_option_not_available`（orders/transactions；`details.reason` 说明原因），**零 session 行**。
`store.yaml` 三个端点均补了 `option_kind` 说明；SDK 手写类型 `CreateOrderTransactionParams` / `CreatePaymentSessionParams` 同步该字段。

## 结算页只读预览报价 `POST /api/v3/store/carts/:id/preview_quote`（2026-09-19；PRD-20260919-shipping-checkout-quote-preview）

结算页在**建单之前**就要显示运费/税费估算，且默认选中一个配送方式。为此新增一个**只读**端点
（cart token 授权，与其它 cart 端点一致）：

**请求**（全部可选，缺省 = 用车上的地址/方式）：

| 字段 | 说明 |
|---|---|
| `country` | header 国家（ISO）。无地址时用它构造**定价专用临时地址**；有地址时作为兜底 |
| `shipping_method_id` | 前台已选方式（未落库也可）；仍可用时预览按它计价并回传为 `selected_method_id` |
| `shipping_address` | 表单态地址（`country_iso` / `state_abbr` / `city` / `postal_code` / `address1`…），**不落库** |

**响应**：金额字段与 prepare 的订单报价同名同口径，但**全部可空**——

- `delivery_total` / `display_delivery_total`、`tax_total` / `display_tax_total`、
  `discount_total` / `display_discount_total`、`gift_card_total` / `display_gift_card_total`、
  `store_credit_total` / `display_store_credit_total`、`amount_due` / `display_amount_due`、
  `total` / `display_total`、`currency`
- `methods[]`：**展示集合**（= `Shipping::Estimate.scoped_methods(store, country)`，与前台列表同源）逐项给
  `id` / `raw_id` / `name` / `cost` / `display_cost` / `reason` / `selected`；不可计价者 `cost: null`
  且带 `reason`（`address_required` = 缺州/邮编；`currency_mismatch` = 该方式的计算器不收本币）
- `selected_method_id`：**服务端决定的默认**（管道口径 = 费率成本升序第一；显式传入且仍可用则用它）
- `estimated: true`、`provisional_country`、`address_complete`
- 降级：当**当前地址下没有任何可配送费率**（订单 warnings 含 `delivery_unavailable`）时返回 200 +
  金额全 `null` + `unavailable_reason`，**不是错误**——前台据此回落「提交时计算」并逐方式显示原因

**零副作用是契约**：内部走 `Carts::Submit` 的 dry-run（同一事务内建单 → 计价 → `ActiveRecord::Rollback`），
不建 Order、不发 `order.submitted`、不转换购物车、不建支付会话/交易、不写购物车地址、不动礼品卡余额。
**绝不**把 preview 当报价去向网关扣款——权威金额始终来自 prepare 之后的订单报价。

**错误**：`422 validation_error`（购物车不存在/无已选商品/礼品卡不可用等真正失败）。

SDK：`carts.previewQuote(cartId, params)` → `CartPreviewQuoteResult`；`shippingMethods.list(params, options)`
的第一个参数变成 `{ country }`（查询参数，zone 过滤，命中不了回退全集）。`store.yaml` 契约与
`platform/docs/api-reference/store.yaml` 同步，`harness generated:check` 守护。

## Changelog (P0 Payment, 2026-09-03)

- D8 适用范围 (2026-09-15, PRD-20260915-payments-d8): admin `options[]` 增 `rule_set`/`scope_summary`（typelizer → SDK 生成类型）；store 侧新增失败码 `payment_option_not_available`（两个 payment_sessions 创建端点 422 示例）；无端点增删。

- B5 legacy 治理 (2026-09-15, PRD-20260915-checkout-…-b5-…): 六行 legacy matrix 补齐三件套——`LegacyFlowObservable` 统一字段（`legacy_identity`/`action`/`deprecated`/`canonical_successor`）+ legacy 身份注入 `Deprecation`/`Warning`/`Link` 三头 + `carts/payment_sessions` 纳入 concern（**保留** `payment.legacy_flow.used`）+ `store.yaml`/SDK 弃用标注 + 退役阀值（连绞 30 天为 0 可立项删除）；storefront 守护测试扩到六行。

- P0 (2026-09-03): Cart 响应新增 express_payment 权威负载（amount/currency/display_total/line_items，hide_prices 时 null）；webhook 事件经 PaymentWebhookEvent 落库；详见 docs/payment/payment-identifiers.md。
- CHK-P1-1A (2026-09-03, PRD-20260903-checkout-chk-p1-1a): 新增只读 GET /api/v3/store/orders/:order_id/checkout → CheckoutView（OrderCheckout::View 投影 + CheckoutSerializer）；金额/地址/物流/优惠/税沿用 Order serializer 契约；OrderResolvable 授权；legacy checkout 态订单不暴露。
- CHK-P1-1B (2026-09-03): 同一 checkout 端点支持 PATCH /api/v3/store/orders/:order_id/checkout（mutation facade：contact.email / shipping_address / delivery_rate_id，返回最新 CheckoutView；!completed? 守卫；SelectShipping 复用 Shipments::Update 重算语义）。
- CHK-P1-2 (2026-09-03): CheckoutView 新增 version(=checkout_version)/price_version/expires_at 字段；PATCH 语义不变。
- CHK-P1-3 (2026-09-03): CheckoutSerializer 输出 ready/missing_requirements；orders/payment_sessions#create 传 ResultError 本体（结构化 checkout_not_ready + missing_requirements via details）；render_service_error 结构化分支 extra 键透传 details。
- CHK-P1-4 (2026-09-03): store.yaml（backend+platform docs 副本）手写补 `/orders/{order_id}/checkout` GET/PATCH + Checkout/CheckoutViewLine schema（rswag R1：typelizer/OpenAPI 全量生成仍不可执行）；修复 platform 副本既有 Psych 损坏。
- CHK-P1-5 (2026-09-04): orders/payment_sessions#create permit 增 expected_version/expected_price_version；error_handler `checkout_version_conflict` → HTTP 409 + code/message 之外键透传 details。
- R1 (2026-09-04): 契约生成基建可运行化（方案 A）——新增宿主 rake `api:docs:schemas`(generate)/`schemas:check`(漂移门)/`validate`(Psych + paths 全部 $ref 有目标)/`generate`/`check`；`components.schemas` 中 Typelizer 拥有项由 serializers 自动重写（新增自动补/删除自动清/`x-typelizer: true` 标记），paths/info 手维护权威字节保留；Typelizer 返回值 Symbol→String + `iso8601` 自定义标量→`type:string,format:date-time` 归一；`scripts/ci/contracts.sh` 编排（docker typelizer + rake + platform 副本同步）；`harness generated:check` 由空转改为真实 Contracts 检查（docker-gated）；store.yaml/admin.yaml 一次性 schema 归一化 + 修复手维护悬空 ref（Error→ErrorResponse、AdminPost→Post）。
- P2 收口 (2026-09-05, PRD-20260905-other-txn-p2-closure): 新增 Store `CommerceTransactionSerializer`（BaseSerializer typelize/attribute；id=prefixed、amount major string、时间戳 iso8601、recovery 元数据）——TXN-P2-6（SDK 类型生成 + controller 从手写 payload 切换）的生成 source；本包不切换 controller（输出与 P2-2 create 响应一致，零行为变化）。
- P2-6 契约快照 (2026-09-05, PRD-20260905-payments-txn-p2-6-contract-snapshot): R1 契约生成归一到含 CommerceTransaction——`ENABLE_TYPELIZER=1 rake api:docs:generate` 后 store.yaml schemas +80（CommerceTransaction typelizer-owned；paths 仍手维护）；SDK store TS 类型新增 `StoreCommerceTransaction`（backend/packages/sdk 暂存 + backend/app/javascript/types）；`schemas:check/validate/api:docs:check` 全绿、幂等。SDK client 方法消费与 storefront 迁移为 TXN-P2-6 下一阶段。
- TXN-P2-2 (2026-09-04, PRD-20260904-api-txn-p2-2): durable CommerceTransaction 启动/恢复端点——`POST /api/v3/store/orders/:order_id/transactions`（body：payment_method_id/purpose/external_data/expected_checkout_version/expected_price_version；成功 201 `{data:{id:txn_,type:'transaction',attributes:{state,purpose,currency,amount,checkout_version,price_version,snapshot_fingerprint,completed_at},payment_execution:{id:ps_,...}}}`；幂等复用返回同一 txn+session；409 code：`checkout_not_ready`/`quote_changed`/`transaction_not_payable`（error_handler conflict_codes→409））+ `GET /api/v3/store/transactions/:id`（owner 作用域 Resume 读模型：participants/payment_sessions/recovery/completion；404 隐藏他人交易）。store.yaml/SDK 同步随 R1/TXN-P2-6 收口。
- D10 (2026-09-15, PRD-20260915-payments-d10-client-config): 支付方式 payload **additive** 新增 `client_config: { provider: string, environment: string|null, publishable: Record<string,string>, session_token: string|null }` —— 两处落点：① store `CheckoutSerializer.payment.available_payment_methods[]`（同时补齐此前缺的 `kind`/`frontend_kind` typelize，类型与 payload 重新对齐）；② store `PaymentMethodSerializer`（cart / order / shopping_cart 的 `payment_methods[]`）。只含 publishable 级凭据（secret 永不出现，serializer spec 负向断言）；`env:` 引用在读取侧解析。admin `PaymentMethodSerializer` 继承同字段（publishable 非密）。契约经 `scripts/ci/contracts.sh` 再生成（store.yaml/admin.yaml + SDK/zod 类型），`harness generated:check` 零漂移。
