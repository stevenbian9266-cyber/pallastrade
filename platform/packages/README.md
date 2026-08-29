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

Standard e-commerce flow (P1, PRD-20260829-checkout): `carts.submit(cartId, options?)` converts a standard-flow cart into an `or_`-prefixed `Order`; `orders.paymentSessions.create/get/complete(orderId, ...)` manage order-scoped payment sessions (Stripe Checkout `client_secret`); `shippingMethods.list()` returns the front-end delivery-method list (`DeliveryMethod` now carries `display_estimated_price`). The `Order` type exposes `state`/`status`/`submitted_at`/`cart_id`/`payment_methods`; cart line items accept `selected` for the selection step.

> **Build artifacts are committed.** `sdk/dist/` is gitignored, so run `pnpm build` (tsup) and commit the freshly built `dist/` outputs explicitly (`git add -f`), including the content-hashed type files (`index-<hash>.d.ts`/`.d.cts`) that `index.d.ts` references — committing `index.d.ts` without its hash sibling leaves the published types broken (downstream `next build` / `tsc` type resolution fails).
>
> **Verify before pushing.** After building, confirm the referenced hash chunk is present in the tree: `git ls-tree -r HEAD -- platform/packages/sdk/dist | grep 'index-'` must show the hash that `dist/index.d.ts` imports. A missing hash sibling surfaces as `Type error: Parameter 'x' implicitly has an 'any' type` in the CI `Deploy` workflow's "Build storefront image" step and silently stops the storefront image from being published.

Includes auto-generated TypeScript types and Zod schemas derived from the Rails Alba serializers — see the [type generation pipeline](../CLAUDE.md#type-generation-pipeline) in the root docs.

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
