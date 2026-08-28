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
