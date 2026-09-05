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
- `POST /api/v3/store/carts/:id/submit` — converts an active cart into an `Order` (`or_`-prefixed). The Cart row lock makes converted-cart replays return the same Order. The response is `CartSubmitResult` (`Order` fields plus nullable `successor_cart`); partial checkout moves only unselected items to that active successor. `order.submitted` is emitted only after commit and cannot block the persisted checkout.
- `GET /api/v3/store/customers/me/orders` — submitted or completed order history is queried with both `current_store` and `user_id = current_user.id`, so a newly submitted pending-payment Order is immediately visible. Never broaden this to an email match, an unscoped `Order` query, or a frontend-only filter; member reads and payment endpoints must enforce the same ownership boundary.
- `POST /api/v3/store/orders/:order_id/payment_sessions` + `GET/PATCH .../:id` + `PATCH .../:id/complete` — order-scoped payment sessions (Stripe Checkout `client_secret`, etc.). Create delegates to `PallasTrade::PaymentSessions::Start`: reuse a matching active session, perform provider I/O outside the Order lock transaction, reconcile concurrent local sessions, and use a stable Stripe operation key. Completion drives `Carts::Complete` (`pay!` + `finalize!`). Resolution is current-store + current-customer/token scoped and uses the owned-order `:show` permission.
- `GET /api/v3/store/shipping_methods` — front-end display list (`display_on: both/front_end`); each item carries `display_estimated_price` (authoritative cost is computed at submit).
- `PATCH /api/v3/store/customers/me/orders/:order_id/shipping_address` — update an own unpaid order's shipping address (combined-payment shipping step). Only `!paid? && amount_due > 0` orders; `shipping_address_id` (user's saved address) or inline `shipping_address` (country_iso/state_abbr resolved by Address model); IDOR-safe, syncs shipment address_id, does not reset checkout state. `Store::Customer::Orders::ShippingAddressController` + `PallasTrade::Orders::UpdateShippingAddress`.
- `GET /api/v3/store/payment_combinations/:id?expand=orders` — expands member orders (items + shipping addresses) for the combined-flow shipping/itemized steps.
- `Order` serializer adds `state`, `status`, `submitted_at`, `cart_id`, `payment_methods` (the active `PaymentMethod` list for the order's market/currency).
- Cart/CartItem serializers: new `ShoppingCart` shape with `status` and `items[].selected` (see `pallastrade-typescript-sdk`).

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

### Product reviews (Store API, P0-4)

- **Read (public, api_key)**: `GET /api/v3/store/products/:product_id/reviews` — approved reviews
  only, newest first. `{ id, product_id, user_name, rating, title, body, verified_purchase, created_at }`.
- **Write (customer JWT required)**: `POST /api/v3/store/products/:product_id/reviews`
  with `{ rating (1–5, required), title?, body? }`. Creates a `pending` review; one review per
  (product, user) — duplicates → 422. `verified_purchase` is computed from the customer's completed
  orders. Unauthenticated → 401.
- Moderation: admin `PallasTrade::Admin::ReviewsController` approves/rejects/deletes; only
  `approved` reviews are public and counted in `Product#average_rating` / `#review_count`
  (exposed on `ProductSerializer`). Product serializer also adds `average_rating`/`review_count`.
- Model: `PallasTrade::Review` (`SingleStoreResource`, `has_prefix_id :rev`, unique
  `[product_id, user_id]`).

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

## Where to read further

- **OpenAPI specs:** `node_modules/@pallastrade/docs/dist/api-reference/store.yaml` (Store API) and `admin.yaml` (Admin API) — every endpoint, parameter, response schema. Authoritative.
- **Adding a new endpoint:** see the `pallastrade-resource` skill — `pallastrade:api_resource` generator produces v3-conformant controllers + serializers automatically.
- **SDK:** `@pallastrade/sdk` (Store) and `@pallastrade/admin-sdk` (Admin) — typed clients. See the `pallastrade-typescript-sdk` skill.
- **Customization:** `node_modules/@pallastrade/docs/dist/developer/customization/api.md` and `authentication.md`
- **Webhooks vs subscribers:** see the `pallastrade-events-webhooks` skill.

## Changelog (P0 Payment, 2026-09-03)

- P0 (2026-09-03): Cart 响应新增 express_payment 权威负载（amount/currency/display_total/line_items，hide_prices 时 null）；webhook 事件经 PaymentWebhookEvent 落库；详见 docs/payment/payment-identifiers.md。
- CHK-P1-1A (2026-09-03, PRD-20260903-checkout-chk-p1-1a): 新增只读 GET /api/v3/store/orders/:order_id/checkout → CheckoutView（OrderCheckout::View 投影 + CheckoutSerializer）；金额/地址/物流/优惠/税沿用 Order serializer 契约；OrderResolvable 授权；legacy checkout 态订单不暴露。
- CHK-P1-1B (2026-09-03): 同一 checkout 端点支持 PATCH /api/v3/store/orders/:order_id/checkout（mutation facade：contact.email / shipping_address / delivery_rate_id，返回最新 CheckoutView；!completed? 守卫；SelectShipping 复用 Shipments::Update 重算语义）。
- CHK-P1-2 (2026-09-03): CheckoutView 新增 version(=checkout_version)/price_version/expires_at 字段；PATCH 语义不变。
- CHK-P1-3 (2026-09-03): CheckoutSerializer 输出 ready/missing_requirements；orders/payment_sessions#create 传 ResultError 本体（结构化 checkout_not_ready + missing_requirements via details）；render_service_error 结构化分支 extra 键透传 details。
- CHK-P1-4 (2026-09-03): store.yaml（backend+platform docs 副本）手写补 `/orders/{order_id}/checkout` GET/PATCH + Checkout/CheckoutViewLine schema（rswag R1：typelizer/OpenAPI 全量生成仍不可执行）；修复 platform 副本既有 Psych 损坏。
- CHK-P1-5 (2026-09-04): orders/payment_sessions#create permit 增 expected_version/expected_price_version；error_handler `checkout_version_conflict` → HTTP 409 + code/message 之外键透传 details。
- R1 (2026-09-04): 契约生成基建可运行化（方案 A）——新增宿主 rake `api:docs:schemas`(generate)/`schemas:check`(漂移门)/`validate`(Psych + paths 全部 $ref 有目标)/`generate`/`check`；`components.schemas` 中 Typelizer 拥有项由 serializers 自动重写（新增自动补/删除自动清/`x-typelizer: true` 标记），paths/info 手维护权威字节保留；Typelizer 返回值 Symbol→String + `iso8601` 自定义标量→`type:string,format:date-time` 归一；`scripts/ci/contracts.sh` 编排（docker typelizer + rake + platform 副本同步）；`harness generated:check` 由空转改为真实 Contracts 检查（docker-gated）；store.yaml/admin.yaml 一次性 schema 归一化 + 修复手维护悬空 ref（Error→ErrorResponse、AdminPost→Post）。
- P2 收口 (2026-09-05, PRD-20260905-other-txn-p2-closure): 新增 Store `CommerceTransactionSerializer`（BaseSerializer typelize/attribute；id=prefixed、amount major string、时间戳 iso8601、recovery 元数据）——TXN-P2-6（SDK 类型生成 + controller 从手写 payload 切换）的生成 source；本包不切换 controller（输出与 P2-2 create 响应一致，零行为变化）。
- TXN-P2-2 (2026-09-04, PRD-20260904-api-txn-p2-2): durable CommerceTransaction 启动/恢复端点——`POST /api/v3/store/orders/:order_id/transactions`（body：payment_method_id/purpose/external_data/expected_checkout_version/expected_price_version；成功 201 `{data:{id:txn_,type:'transaction',attributes:{state,purpose,currency,amount,checkout_version,price_version,snapshot_fingerprint,completed_at},payment_execution:{id:ps_,...}}}`；幂等复用返回同一 txn+session；409 code：`checkout_not_ready`/`quote_changed`/`transaction_not_payable`（error_handler conflict_codes→409））+ `GET /api/v3/store/transactions/:id`（owner 作用域 Resume 读模型：participants/payment_sessions/recovery/completion；404 隐藏他人交易）。store.yaml/SDK 同步随 R1/TXN-P2-6 收口。
