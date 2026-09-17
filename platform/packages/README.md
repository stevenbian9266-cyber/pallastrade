# PallasTrade TypeScript Packages

This directory contains the TypeScript side of the PallasTrade monorepo: the store SDK, the CLI, project scaffolding, and the docs bundle. Everything here is managed with **pnpm workspaces** + **Turbo**, built with **tsup**, tested with **Vitest**, and linted with **Biome**. Versioning for published packages is handled by **Changesets**.

For monorepo-wide conventions (type generation pipeline, code style, testing) see the root [`CLAUDE.md`](../CLAUDE.md). For backend conventions see [`pallastrade/`](../pallastrade/).

## Status legend

| Badge | Meaning |
|---|---|
| **Stable** | Published to npm, follows semver, safe for production. |
| **Developer Preview** | Published to npm but API may change between minor versions. Pin exact versions. |
| **In Development** | Active work for an upcoming PallasTrade release. Not yet published or only published behind a `next` dist-tag. |
| **Internal** | Private to the workspace (`"private": true`), not published. |

## Packages

| Package | npm | Status | Description |
|---|---|---|---|
| [`sdk`](./sdk) | [`@pallastrade/sdk`](https://www.npmjs.com/package/@pallastrade/sdk) | **Stable** (1.x) | TypeScript client for the customer-facing **Store API v3**. |
| [`sdk-core`](./sdk-core) | — | **Internal** | Shared HTTP/retry/error layer used by `@pallastrade/sdk`. Not published. |
| [`cli`](./cli) | [`@pallastrade/cli`](https://www.npmjs.com/package/@pallastrade/cli) | **Stable** (2.x) | Docker-based CLI for managing PallasTrade projects scaffolded with `create-pallastrade-app`. |
| [`create-pallastrade-app`](./create-pallastrade-app) | [`create-pallastrade-app`](https://www.npmjs.com/package/create-pallastrade-app) | **Stable** (1.x) | One-shot scaffolder: `npx create-pallastrade-app my-store`. Sets up backend (Docker) + optional Next.js storefront. |
| [`docs`](./docs) | [`@pallastrade/docs`](https://www.npmjs.com/package/@pallastrade/docs) | **Developer Preview** (0.x) | PallasTrade developer documentation packaged for local access by AI agents and dev tools. |

### `@pallastrade/sdk` — Store API client

The customer-facing SDK. Powers storefronts (Next.js or otherwise) and any client that needs read access to the catalog plus write access to carts, customers, addresses, checkout, back-in-stock subscriptions (`backInStockSubscriptions.create(productId, { email })` — guest-accessible), product reviews (`products.reviews.list(productId)` — approved, public; `products.reviews.create(productId, { rating, title?, body? }, { token })` — signed-in customers), contact messages (`contactMessages.create(...)` — complaint/feedback/inquiry submission that lands in the admin Email → Inbox & Feedback page), and combined payments (`paymentCombinations.create({ orderIds, paymentMethodId })` / `paymentCombinations.get(id)` — create/load a multi-order combined-payment session; see the combined-payment checkout flow). Read-only catalog/content resources include `products`, `categories`, `policies`, `posts` (CMS blog — `posts.list(params?, options?)` / `posts.get(id, options?)`, published only), `markets`, `currencies`, `locales`. Auth modes: publishable key (guest) or JWT (logged-in customer).

Standard e-commerce flow (P1, PRD-20260829-checkout): `carts.submit(cartId, options?)` converts a standard-flow cart into an `or_`-prefixed `Order`; `orders.paymentSessions.create/get/complete(orderId, ...)` manage order-scoped payment sessions (Stripe Checkout `client_secret`); `shippingMethods.list()` returns the front-end delivery-method list (`DeliveryMethod` now carries `display_estimated_price`). The `Order` type exposes `state`/`status`/`submitted_at`/`cart_id`/`payment_methods`; cart line items accept `selected` for the selection step. `carts.complete` is **deprecated** (its backend route `POST /carts/:id/complete` was removed in CORE-P5-5) — final order completion is server-driven (webhook / `Transactions::OnPaymentSuccess`); new code must use `orders.paymentSessions.complete`.

**3DS/SCA（D15 切片3, 2026-09-17）**：checkout 投影 `payment.available_payment_methods[]` 新增 `requires_authentication: boolean`（服务端权威；列表**只含可用入口**，隐藏 = 不出现）。该字段随 Typelizer 生成：`platform/packages/sdk/src/types/generated/StoreCheckoutCheckout.ts` 由 `scripts/ci/contracts.sh` 从 `backend/packages/sdk/...` 同步而来 —— **不要手改生成的类型文件**，改序列化器后跑一次 `bash scripts/ci/contracts.sh`（`harness generated:check` 验证零漂移）。

Order-module combined payment (PRD-20260829-checkout 订单模块): `paymentCombinations.get(id, { expand: ['orders'] }, options?)` expands member orders (items + shipping addresses) for the combined-flow shipping/itemized steps; `orders.updateShippingAddress(orderId, { shipping_address | shipping_address_id }, options?)` (`PATCH /customers/me/orders/:id/shipping_address`) updates an own unpaid order's shipping address.

Order durable transactions (P2, 2026-09-05): `orders.transactions.create(orderId, { payment_method_id, purpose?, external_data?, expected_checkout_version?, expected_price_version? }, options?)` (`POST /orders/:order_id/transactions`) starts/reuses a durable `CommerceTransaction` with a frozen quote snapshot and returns the transaction plus its `payment_execution` (ps_ session for the provider UI); `transactions.get(id, options?)` (`GET /transactions/:id`) returns the resume read model (state, participants, payment sessions, recovery, completion). Business conflicts surface as 409 `checkout_not_ready` / `quote_changed` / `transaction_not_payable`. **Storefront TXN-P2-6 轮3 (2026-09-05)** consumes this as transaction-first: `/api/checkout/start` and the order-payment server action start the session via `orders.transactions.create` (session = `payment_execution`), while `PATCH` completion keeps using `orders.paymentSessions.complete`. Because the SDK's published types come from `dist`, rebuild it (`pnpm --filter @pallastrade/sdk build`) after adding client methods and commit the rebuilt `dist/` (hash chunks via `git add -f`).

> **Build artifacts are committed.** `sdk/dist/` is gitignored, so run `pnpm build` (tsup) and commit the freshly built `dist/` outputs explicitly (`git add -f`), including the content-hashed type files (`index-<hash>.d.ts`/`.d.cts`) that `index.d.ts` references — committing `index.d.ts` without its hash sibling leaves the published types broken (downstream `next build` / `tsc` type resolution fails).
>
> **Verify before pushing.** After building, confirm the referenced hash chunk is present in the tree: `git ls-tree -r HEAD -- platform/packages/sdk/dist | grep 'index-'` must show the hash that `dist/index.d.ts` imports. A missing hash sibling surfaces as `Type error: Parameter 'x' implicitly has an 'any' type` in the CI `Deploy` workflow's "Build storefront image" step and silently stops the storefront image from being published.

Includes auto-generated TypeScript types and Zod schemas derived from the Rails Alba serializers — see the [type generation pipeline](../CLAUDE.md#type-generation-pipeline) in the root docs.

Cart-domain legacy methods are `@deprecated` (PRD-20260915-checkout B5, 2026-09-15): `carts.{discountCodes,giftCards,fulfillments,payments,paymentSessions,storeCredits}` are the six routes of the §45 legacy migration matrix. They stay callable — `cart_` canonical carts legitimately use the same route shapes (cart-stage intent, redeemed at `carts.submit`) — but legacy-identity (`or_…`) callers now receive `Deprecation: true` + `Warning: 299` + `Link: rel="successor-version"` headers and are counted under `cart.legacy_flow.used` (or the historical `payment.legacy_flow.used` for payment sessions). Canonical successors: `orders.paymentSessions`, `orders.transactions`, `PATCH /orders/:order_id/checkout`. Never add new consumers; removal requires the documented retirement threshold (30 consecutive days of zero legacy traffic) and its own PRD.

Cart billing address (PRD-20260913-checkout-billing-mode, 2026-09-13): `carts.update(id, { billing_mode: 'same_as_shipping' | 'custom', billing_address? }, options?)` models the billing address explicitly instead of relying on a flag the server silently drops. `same_as_shipping` clears the stored billing address so the submitted order snapshots the shipping address; `custom` stores the explicit address and rejects an incomplete one. The legacy `use_shipping` boolean still works but is now `@deprecated` — it was never in the server's parameter allow-list (`carts_controller#permitted_params`), which is how orders ended up with an empty billing address. Rebuild the SDK (`pnpm --filter @pallastrade/sdk build`) and commit the refreshed `dist/` (including the new content-hashed `index-<hash>.d.ts`/`.d.cts` via `git add -f`) whenever these types change.

Applied-discount lines (2026-09-10, PRD-20260909-promotions-promo-batch2): `Cart`, `Order` and the
Checkout types all expose `discounts: Array<{ id, promotion_id, name, description, code, kind,
amount, display_amount, breakdown, removable }>` — the canonical projection shared by Cart / Order /
Admin Order / Checkout serializers. Regenerate whenever a serializer's `typelize` changes:
`bundle exec rake typelizer:generate` (backend) + `bundle exec rake api:docs:schemas` (OpenAPI), then
copy the generated files into `platform/packages/sdk/src/types/generated/` and
`platform/docs/api-reference/` (both steps are automated by `scripts/ci/contracts.sh`).

Server CheckoutView credits / capabilities / payment methods (PRD-20260914-checkout B1, 2026-09-14):
`client.orders.checkout.get(orderId)` now also returns `credits` (`gift_cards[]` + `store_credit`,
positive amounts — the UI renders the minus), `capabilities` (`can_edit_address` /
`can_change_shipping` / `can_apply_promotion` / `can_pay`), `billing_mode` (derived display value;
writes still use the `billing_mode` request param) and `payment.available_payment_methods` — the same
`PaymentMethod#available_for_order?` scope `PaymentSessions::Start` enforces, so the storefront's
payment-method list can never offer an option the server rejects. All four blocks are additive, so an
older payload keeps rendering (the `CheckoutView` type is hand-written in `sdk/src/types/index.ts`
and must be extended alongside the generated types).

D10 (PRD-20260915-payments-d10-client-config) adds `client_config` to every payment-method payload —
`{ provider, environment, publishable, session_token }` on `payment.available_payment_methods[]` (checkout)
and on `cart/order.payment_methods[]` (the store `PaymentMethodSerializer`). Only **publishable-level**
credentials ever appear (secrets are never projected), and `env:` references are resolved server-side, so the
storefront reads its Stripe publishable key from the API (`resolveStripePublishableKey`) with a temporary
fallback to `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` during the migration window.

Canonical cart gift card intent (2026-09-14, PRD-20260914-checkout-cart-gift-cards-canonical):
`ShoppingCart` gains `gift_card: { code, display_amount_remaining } | null` (typed as of B2) — the
cart-stage projection of `client.carts.giftCards.apply('cart_…', code)`. The card is validated at
cart stage but **no money
moves** (`pallastrade_carts` has no payments); redemption happens on `carts.submit`, so a card that
became unusable fails the submission instead of silently charging full price. Legacy `or_` carts keep
their immediate-apply behaviour and share the same error codes.

Canonical cart store credit intent (2026-09-14, PRD-20260914-checkout-cart-store-credits-canonical):
`ShoppingCart` gains `store_credit: { amount, display_amount } | null` (typed as of B2) for
`client.carts.storeCredits.apply('cart_…', amount?)`.
The endpoint keeps requiring a bearer JWT (store credit is account property) and stores intent only —
`carts.submit` redeems it through `Checkout::AddStoreCredit` (clamped to the final outstanding balance).
Store credit and gift cards are mutually exclusive per cart, mirroring the order-level rule.

Cart credit intents are now typed (PRD-20260914-checkout B2, 2026-09-14): `ShoppingCartSerializer`
declares `discount_code` (the customer's own, already-validated coupon code) plus object-literal
typelize types for `gift_card` / `store_credit`, so `@pallastrade/sdk` no longer exposes them as
`unknown`. All three stay **cart-stage intent** — the cart page renders them as summary rows and lets
the shopper apply/remove them via server actions, but nothing is redeemed until `carts.submit`
(`@pallastrade/sdk` carries the hand-written `ShoppingCart` fields in `src/types/index.ts`).

Payment-method option projection (PRD-20260915-admin 支付配置选项化, D1 slices 1–3, 2026-09-15): the
generated `PaymentMethod` type gains `kind` (the storefront entry identity — `api_type` such as
`stripe` while a provider is not optionized yet) and `frontend_kind` (`inline` / `manual`, or a
capability value such as `express` once the provider is optionized). The admin SDK type additionally
gains `optionized` (whether the provider has switched to per-method entries — zero enabled entries
then means zero storefront entries) and `options` (the effective entry list: `kind` / `name` /
`frontend_kind` / `active` / `position`). Entries are configured in the Rails admin (provider edit
page → 「支付方式」tab with Test connection), not through this SDK; both fields are additive, so older
consumers keep working. Regenerate with `scripts/ci/contracts.sh` whenever a payment serializer's
`typelize` changes.

Back-in-stock subscriptions are SKU-aware (PRD-20260915-catalog-batch-c2-sku-back-in-stock, 2026-09-15):
`backInStockSubscriptions.create(productId, { email, variant_id? })` now takes an optional prefixed
`variant_id` (`variant_…`) so a customer watches one SKU; the response gains `variant_id` (null for the
legacy product-level subscription). The generated `BackInStockSubscription` type carries the new field —
regenerate it with `scripts/ci/contracts.sh` when the serializer's `typelize` changes (the SDK method
itself is hand-written in `sdk/src/store-client.ts`).

Review helpful votes (PRD-20260916-catalog-batch-f5-helpful-vote, 2026-09-16): a new top-level
resource — `reviewHelpfulVotes.create(reviewId, { token })` /
`reviewHelpfulVotes.destroy(reviewId, { token })` — records and withdraws a customer's "helpful" vote
on an approved review (one per customer per review; the API is idempotent). Both calls return
`ReviewHelpfulVoteResponse` (`{ data: { attributes: { review_id, helpful_votes_count, helpful_voted } } }`),
i.e. the **authoritative state** rather than the review, so a UI never has to guess whether the click
landed. The hand-written methods live in `sdk/src/store-client.ts` / `sdk/src/types/index.ts`; the
`Review` type additionally gains `helpful_votes_count` / `helpful_voted` (regenerate with
`scripts/ci/contracts.sh` when the serializer changes — note `helpful_voted` is `null` for anonymous
callers). Review lists now accept `sort=most_helpful` on top of the F-4 orderings. Touching `store-client.ts` (as this change did) renames the
content-hashed type chunk (`index-<hash>.d.ts`/`.d.cts`), so rebuild and commit the whole `dist/` with `git add -A -f` — otherwise
`index.d.ts` ends up referencing a sibling that was never committed.

### `@pallastrade/sdk-core` — Shared internals

Private package. Provides `createRequestFn()`, `PallasTradeError`, retry logic, and Ransack query-param transformation (`transformListParams()`). Consumed by the SDK; not intended for direct use.

### `@pallastrade/cli` — Project management CLI

Docker-based commands for projects scaffolded via `create-pallastrade-app`: starting/stopping services, running migrations, opening Rails consoles, loading sample data, etc. Bundled automatically into new projects.

### `create-pallastrade-app` — Project scaffolder

The recommended entry point for new PallasTrade projects. Clones [`stevenbian9266-cyber/pallastrade`](https://github.com/stevenbian9266-cyber/pallastrade) once from `main`, reads `backend/` and `storefront/` from their fixed paths, wires up Docker Compose, and runs first-time setup. Replaces the legacy in-repo `server/` directory.

### `@pallastrade/docs` — Documentation bundle

PallasTrade developer documentation (core concepts, customization, API reference, integration guides) packaged as plain Markdown so AI agents and offline tooling can read it from `node_modules/@pallastrade/docs/dist/`. Built from the fixed `platform/docs/` tree.

## Working in the monorepo

From the repo root:

```bash
pnpm install      # install workspace deps
pnpm build        # turbo-cached build for all packages
pnpm test         # run all package tests
pnpm typecheck    # TypeScript across all packages
pnpm lint         # Biome lint
pnpm lint:fix     # Biome lint + auto-fix
pnpm format       # Biome format-write
```

Per-package commands are documented in each package's `README.md`. Changesets for versioning go in the package's `.changeset/` directory.
