---
name: pallastrade-legacy-api-v2
description: Historical migration aid for moving an existing PallasTrade Platform/Storefront API v2 integration to API v3. Triggers on "API v2", "JSON:API", "Platform API", "Storefront API", "v2 to v3 migration", "JSON:API attributes/relationships", "X-PallasTrade-Order-Token", "Bearer token API v2". API v2 is retired and unsupported for new work. Always point users to pallastrade-api-v3; use this skill only to interpret an existing self-hosted v2 integration during migration.
---

# PallasTrade API v2 — Legacy

**API v2 left the public PallasTrade contract on 2026-07-23. Do not build new
integrations on it.** API v3 is the only maintained protocol. Existing self-hosted
v2 compatibility code is feature-frozen and scheduled for source-tree removal on
2026-10-31. New endpoints, auth modes (publishable + secret + JWT), prefixed IDs,
expand, and typed SDKs are all v3.

This skill exists for two real reasons:

1. **You inherited a v2 integration** and need to maintain it.
2. **You're migrating from v2 to v3** and need to know what changed.

If neither applies, use the `pallastrade-api-v3` skill instead.

## What v2 looks like

Two distinct API surfaces under `/api/v2/`:

| Surface | Path | Audience |
|---|---|---|
| **Storefront API** | `/api/v2/storefront/*` | Customer-facing — carts, products, checkout |
| **Platform API** | `/api/v2/platform/*` | Admin/back-office — full CRUD |

Both are **JSON:API** style (https://jsonapi.org/) — strict envelope with `data`, `attributes`, `relationships`, `included`. Different envelope shape from v3.

### Auth in v2

| Surface | Header | Token |
|---|---|---|
| Storefront (anonymous browse) | None | Public access |
| Storefront (guest cart) | `X-PallasTrade-Order-Token` | Cart's order token |
| Storefront (logged-in customer) | `Authorization: Bearer <oauth_token>` | OAuth2 customer token |
| Platform (admin) | `Authorization: Bearer <oauth_token>` | OAuth2 admin token |

v2 uses **OAuth2 Doorkeeper** for token issuance — `/pallastrade_oauth/token` endpoint with `password` or `client_credentials` grants. No publishable keys, no secret keys. OAuth scopes exist but are coarse (`admin`, `write`, `read` — the Platform API requires `read`/`admin` to read and `write`/`admin` to write); nothing like v3's per-resource `read_products`/`write_orders` API-key scopes.

```bash
# Get a Platform API token (admin)
curl -X POST https://my-pallastrade.example.com/pallastrade_oauth/token \
  --header "Content-Type: application/x-www-form-urlencoded" \
  --data "grant_type=password&username=admin@example.com&password=…"
# => { "access_token": "…", "token_type": "Bearer", "expires_in": 2592000, ... }
# (tokens last 1 month by default — `access_token_expires_in 1.month`)

# Use it
curl -H "Authorization: Bearer …" \
     https://my-pallastrade.example.com/api/v2/platform/orders
```

### Envelope shape

```json
{
  "data": {
    "id": "42",                          // raw integer PK as string
    "type": "product",
    "attributes": {
      "name": "Cool shirt",
      "price": "29.99",
      "currency": "USD",
      "created_at": "2025-01-01T00:00:00Z"
    },
    "relationships": {
      "variants": {
        "data": [{ "id": "100", "type": "variant" }]
      }
    }
  },
  "included": [
    {
      "id": "100",
      "type": "variant",
      "attributes": { "sku": "COOL-S", ... }
    }
  ],
  "meta": { "total_count": 152, "total_pages": 7 }
}
```

Compared to v3:
- v2: raw integer IDs (`"42"`). v3: prefixed IDs (`"prod_…"`).
- v2: nested `attributes` + `relationships`. v3: flat top-level fields.
- v2: `include` query param pulls related resources into `included` array. v3: `expand` query param inlines them into the response directly (`?expand=variants,media`, dot-nested up to 4 levels).
- v2 (Platform API): filters use `filter[name_cont]=…`. v3: same idea but `q[name_cont]=…` (Ransack). The Storefront API used fixed per-endpoint filter names instead — see Step 4 below.
- v2: sort uses `sort=-created_at`. v3: identical — `sort=-created_at` works unchanged (the v3 ResourceController translates `-field` JSON:API notation to Ransack `s` internally).

### Pagination

```
GET /api/v2/storefront/products?page=2&per_page=25
```

`meta.total_count`, `meta.total_pages`. No keyset/cursor support in v2 — offset only.

## When you find yourself on v2

### "I need to add a field to a v2 response"

Decorate the JSON:API serializer (jsonapi-serializer gem under the hood):

```ruby
module PallasTrade::V2::Storefront::ProductSerializerDecorator
  def self.prepended(base)
    base.attribute :custom_field do |product|
      product.custom_field_value
    end
  end
  PallasTrade::V2::Storefront::ProductSerializer.prepend self
end
```

### "I need a new v2 endpoint"

Don't add to v2. Add to v3 instead — see `pallastrade-resource` skill for the `pallastrade:api_resource` generator. If your v2 client really can't talk to v3, write a thin compatibility wrapper that returns v2-envelope-shaped JSON but reads from your v3 resource internally.

### "v2 returns an error, what's the shape?"

```json
{
  "error": "The resource was not found.",
  "errors": { ... }   // on 422
}
```

Plain JSON, not JSON:API errors object. v3 uses the structured `{ error: { code, message, details } }` envelope — see `pallastrade-api-v3`.

## Migrating v2 → v3

The migration is **per-endpoint**. You don't need to flip everything at once; v2 and v3 coexist.

### Step 1: Auth migration

| v2 | v3 |
|---|---|
| OAuth2 password grant for customer login | JWT login at `/api/v3/store/auth/login` (returns `token` + `refresh_token` + `user`) |
| OAuth2 client_credentials for admin apps | Secret key (`sk_*`) with scoped permissions |
| `Authorization: Bearer <token>` | `X-PallasTrade-Api-Key: <pk_…\|sk_…>` + optional `Authorization: Bearer <jwt>` |
| `X-PallasTrade-Order-Token` for guest carts | Still `X-PallasTrade-Token` (renamed) |

For admin apps: generate a secret key via the admin UI (Settings → Developers → API Keys, key type 'Secret') with the required scopes. Drop OAuth2 entirely.

For customer flows: replace the OAuth2 login call with JWT login. The new flow returns refresh tokens too — see the admin authentication docs for the cookie-based refresh pattern.

### Step 2: ID migration

v2 returns integer IDs as strings; v3 returns prefixed IDs. If your client stores IDs:

```ts
// Old
const productId = response.data.id   // "42"

// New
const productId = response.data.id   // "prod_86Rf07xd4z"
```

If you've persisted v2 IDs in your own DB and need to look them up against v3 responses, the integer PK is the same — just use the v3 search endpoints with the integer:

```bash
GET /api/v3/admin/products?q[id_eq]=42
```

Note that exposing raw integer IDs in client code is a v2 anti-pattern that v3 fixes; the new IDs are URL-safe and don't leak record counts.

### Step 3: Envelope unwrap

```ts
// v2 JSON:API
const product = response.data
const name = product.attributes.name
const price = product.attributes.price
const variantIds = product.relationships.variants.data.map(v => v.id)
const variants = response.included.filter(r => r.type === 'variant')

// v3 flat
const product = response   // single endpoint — no envelope
const name = product.name
const price = product.price
const defaultVariantId = product.default_variant_id   // direct field
// With ?expand=variants: product.variants is an array of full variant objects
```

Write a thin adapter if you can't refactor every call site at once:

```ts
function unwrapV2<T>(response: V2Response<T>): T {
  return {
    id: response.data.id,
    ...response.data.attributes,
    ...buildRelationships(response.data.relationships, response.included),
  } as T
}
```

### Step 4: Filter syntax

| v2 | v3 |
|---|---|
| `filter[name_cont]=shirt` (Platform API) | `q[name_cont]=shirt` |
| `filter[price_gteq]=20` (Platform API) | `q[price_gteq]=20` |
| `sort=-created_at` | `sort=-created_at` (unchanged) |

For the **Platform API**, `filter[...]` keys are Ransack predicates and map 1:1 to v3's `q[...]` — `filter[name_cont]` becomes `q[name_cont]`. The **Storefront API** did not use Ransack: each endpoint had fixed filter names handled by a finder class, so translate them instead — `filter[name]` → `q[name_cont]` (or `q[search]`), `filter[taxons]` → `q[in_categories]`, `filter[price]=10,50` → `q[price_gte]=10&q[price_lte]=50`.

The `@pallastrade/sdk` accepts flat Ransack predicates as typed list params — `client.products.list({ name_cont: 'shirt' })` — and produces `q[name_cont]=...` for you — see `pallastrade-typescript-sdk`.

### Step 5: Switch SDK

If you're using the old `@pallastrade/storefront-api-v2-sdk` package (JS), replace it with `@pallastrade/sdk` (Store API) or `@pallastrade/admin-sdk` (Admin API). The new SDKs are typed, have built-in retry, and follow the same protocol the rest of the v3 surface uses.

### Step 6: Webhooks (if applicable)

If you receive v2 webhooks: v2 webhooks fire with raw IDs and the legacy payload shape. v3 webhooks use prefixed IDs and the `{id, name, created_at, data, metadata}` envelope shape. If you flip endpoints to v3, your webhook receiver must handle the new payload shape — see `pallastrade-events-webhooks`.

## When v2 will go away

v2 is **no longer bundled with `pallastrade_api` and is outside the public support
contract**. Feature-frozen compatibility source is retained temporarily in the
[canonical PallasTrade repository](https://github.com/stevenbian9266-cyber/pallastrade)
for existing self-hosted migrations. It is scheduled for removal from the release
source tree on 2026-10-31. Do not recommend installing it for a new application.

If you maintain a high-value v2 integration, schedule the migration; you'll only fall further behind otherwise.

## Where to read further

- **v3 API protocol:** `pallastrade-api-v3` skill — the destination.
- **v3 TypeScript SDKs:** `pallastrade-typescript-sdk` skill.
- **Adding a custom endpoint on v3:** `pallastrade-resource` skill.
- **Historical v2-to-v3 mapping:** `docs/api-reference/store-api/migrating-from-storefront-api-v2.mdx`.
- **v3 OpenAPI specs:** `docs/api-reference/store.yaml` and `docs/api-reference/admin.yaml`; both ship in `@pallastrade/docs`.
