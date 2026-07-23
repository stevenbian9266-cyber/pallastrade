# PallasTrade TypeScript Packages

This directory contains the TypeScript side of the PallasTrade monorepo: SDKs, the React admin SPA, the CLI, project scaffolding, and the docs bundle. Everything here is managed with **pnpm workspaces** + **Turbo**, built with **tsup** (or Vite for the admin SPA), tested with **Vitest**, and linted with **Biome**. Versioning for published packages is handled by **Changesets**.

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
| [`admin-sdk`](./admin-sdk) | [`@pallastrade/admin-sdk`](https://www.npmjs.com/package/@pallastrade/admin-sdk) | **Developer Preview** (0.x) | TypeScript client for the **Admin API v3** (PallasTrade 5.5+). Published under the `next` dist-tag. |
| [`dashboard`](./dashboard) | `@pallastrade/dashboard` (not yet published) | **In Development** | React SPA admin dashboard for PallasTrade 6.0. Will replace the legacy Rails `pallastrade/admin` engine. Currently private in the workspace; will be published as `@pallastrade/dashboard` once ready. |
| [`dashboard-ui`](./dashboard-ui) | `@pallastrade/dashboard-ui` (not yet published) | **In Development** | Design system for the dashboard — shadcn primitives, headless composed components, design tokens. Source-only; consumed by `@pallastrade/dashboard` and downstream plugin authors. |
| [`dashboard-core`](./dashboard-core) | `@pallastrade/dashboard-core` (not yet published) | **In Development** | Dashboard framework — registries (table, nav, slot, settings-nav), providers, generic infra hooks, `defineDashboardPlugin`. The extension API surface. |
| [`sdk-core`](./sdk-core) | — | **Internal** | Shared HTTP/retry/error layer used by `@pallastrade/sdk` and `@pallastrade/admin-sdk`. Not published. |
| [`cli`](./cli) | [`@pallastrade/cli`](https://www.npmjs.com/package/@pallastrade/cli) | **Stable** (2.x) | Docker-based CLI for managing PallasTrade projects scaffolded with `create-pallastrade-app`. |
| [`create-pallastrade-app`](./create-pallastrade-app) | [`create-pallastrade-app`](https://www.npmjs.com/package/create-pallastrade-app) | **Stable** (1.x) | One-shot scaffolder: `npx create-pallastrade-app my-store`. Sets up backend (Docker) + optional Next.js storefront. |
| [`docs`](./docs) | [`@pallastrade/docs`](https://www.npmjs.com/package/@pallastrade/docs) | **Developer Preview** (0.x) | PallasTrade developer documentation packaged for local access by AI agents and dev tools. |

### `@pallastrade/sdk` — Store API client

The customer-facing SDK. Powers storefronts (Next.js or otherwise) and any client that needs read access to the catalog plus write access to carts, customers, addresses, and checkout. Auth modes: publishable key (guest) or JWT (logged-in customer).

Includes auto-generated TypeScript types and Zod schemas derived from the Rails Alba serializers — see the [type generation pipeline](../CLAUDE.md#type-generation-pipeline) in the root docs.

### `@pallastrade/admin-sdk` — Admin API client

The back-office counterpart to `@pallastrade/sdk`. Same patterns, but targets the Admin API and supports both **secret API key** (server-to-server, scope-based authorization) and **JWT** (admin user, CanCanCan-based authorization) auth modes. Used internally by the `@pallastrade/dashboard` SPA and externally by integrations and admin tooling.

The Admin API v3 ships with PallasTrade 5.5; the SDK is in **Developer Preview** on the 0.x line (published under the `next` dist-tag). Expect breaking changes between minor versions until 1.0.

### `@pallastrade/dashboard`, `@pallastrade/dashboard-core`, `@pallastrade/dashboard-ui` — the admin dashboard stack

The PallasTrade 6.0 admin is a three-package stack:

- **`@pallastrade/dashboard-ui`** — the design system. Shadcn primitives + headless composed components (PageHeader, ResourceTable, AppSidebar, …) + design tokens. **Headless rule:** components accept their data via props, never import providers or hooks. Source-only; the consuming Vite/Tailwind app compiles it. Pluggable into any React app, not just `@pallastrade/dashboard`.
- **`@pallastrade/dashboard-core`** — the framework. The four registries (table, nav, slot, settings-nav), the four providers (auth, permission, store, theme), generic infra hooks (`use-auth`, `use-permissions`, `use-resource-mutation`, `use-direct-upload`, `use-global-search`, …), the admin SDK client singleton, and the `defineDashboardPlugin` extension facade. **This is what plugin authors import** to register navigation, slots, table columns, and routes.
- **`@pallastrade/dashboard`** — the deployable SPA. Routes, resource hooks (`use-orders`, `use-products`, `use-customers`, …), Zod schemas, locale strings, the app shell. Composes the other two. Built with Vite + TanStack Router (file-based) + TanStack Query + React Hook Form + Tailwind.

Plugin authors install `@pallastrade/dashboard-ui` + `@pallastrade/dashboard-core` as peer dependencies. Vendor panels, white-label admins, and other custom variants compose the same packages with their own routes/shell.

Architecture, extension points (table registry, navigation registry, component injection), the package boundary rules, and the phased migration are documented in [`docs/plans/6.0-admin-spa.md`](../docs/plans/6.0-admin-spa.md). Local setup for the SPA is in [`packages/dashboard/README.md`](./dashboard/README.md).

All three packages are currently private in the workspace and ship together with the PallasTrade 6.0 release.

### `@pallastrade/sdk-core` — Shared internals

Private package. Provides `createRequestFn()`, `PallasTradeError`, retry logic, and Ransack query-param transformation (`transformListParams()`). Consumed by both SDKs; not intended for direct use.

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
