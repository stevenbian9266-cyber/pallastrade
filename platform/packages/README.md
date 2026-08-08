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

The customer-facing SDK. Powers storefronts (Next.js or otherwise) and any client that needs read access to the catalog plus write access to carts, customers, addresses, and checkout. Auth modes: publishable key (guest) or JWT (logged-in customer).

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
