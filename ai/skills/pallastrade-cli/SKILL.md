---
name: pallastrade-cli
description: Use when calling the PallasTrade Admin API from the command line or driving it programmatically as an agent — exploring endpoints, reading or mutating store data, and especially DEBUGGING (inspecting an order/product/customer, checking why a request failed, reproducing a 403/422). The `pallastrade api` command group in `@pallastrade/cli` is a `gh api`-style generic HTTP client: `pallastrade api get|post|patch|delete <path>` plus offline discovery (`pallastrade api endpoints`, `pallastrade api schema`). Common phrasings include "pallastrade api", "pallastrade CLI", "call the admin API from the terminal", "pallastrade api get", "inspect this order", "why is this PallasTrade request failing", "list admin endpoints", "pallastrade auth". For SDK/TypeScript integration use pallastrade-typescript-sdk; for raw API protocol details use pallastrade-api-v3.
---

# PallasTrade CLI — Admin API from the terminal

`@pallastrade/cli` ships a `pallastrade api` command group: a generic Admin API v3 client modeled on `gh api`. It is the fastest way to inspect and manipulate store data from a terminal, and the most reliable way for an **agent to debug** — no SDK boilerplate, structured JSON in/out, and offline endpoint discovery.

It works against **any PallasTrade 5.5+ instance**. Inside a local project it self-provisions a read-only key; for any other server you supply a key.

## When to reach for the CLI

- **Debugging** — "what state is order `ord_x` in?", "why did this 403?", "does this product have the variant I expect?". One command, JSON back, pipe to `jq`.
- **Exploring the API** — list endpoints and their required scopes, dump an operation's schema, all offline.
- **Scripting / agents** — deterministic, pipeable, exit-coded. No client to instantiate.

For building an app, prefer `@pallastrade/admin-sdk` (see `pallastrade-typescript-sdk`). The CLI is for interactive work, scripts, and agents.

## Setup

The CLI is `@pallastrade/cli` (binary: `pallastrade`). Verify it's available:

```bash
pallastrade --version          # or: pnpm exec pallastrade --version
```

If not installed: `npm i -g @pallastrade/cli` (or run via `pnpm exec pallastrade` / `npx @pallastrade/cli` inside a project).

### Credentials — pick the layer that fits

Credentials resolve in this order (first match wins); host and key always resolve **together** per source:

1. **Explicit flags** — `--api-key sk_xxx`, or `--profile prod` to select a saved profile. Outrank everything below.
2. **Env** — set `PALLASTRADE_API_KEY`; the host defaults to `http://localhost:3000`, so local dev needs only the key. Set `PALLASTRADE_BASE_URL` for a remote store. Note an exported `PALLASTRADE_API_KEY` **outranks a local project's saved key**:
   ```bash
   PALLASTRADE_API_KEY=sk_xxx pallastrade api get /products            # → localhost:3000
   PALLASTRADE_BASE_URL=https://store.example.com PALLASTRADE_API_KEY=sk_xxx pallastrade api get /orders
   ```
3. **Inside a local PallasTrade project** (a dir with `docker-compose.yml`, dev stack running): zero config. The first `pallastrade api` call mints a **read-only** key via the dev stack and saves it to the gitignored local credentials file .pallastrade/credentials.json (created at runtime, never committed — this path is **not** a repo file). Just run commands.
4. **Default profile** (the first profile you `pallastrade auth login` becomes the default; key read from a prompt, never a flag):
   ```bash
   pallastrade auth login --profile prod --base-url https://store.example.com
   pallastrade api get /orders --profile prod    # or omit --profile once it's the default
   ```

Confirm what's resolved and that the server is reachable:

```bash
pallastrade api status
```

### Minting a key with the scopes you need

Auto-minted project keys are `read_all` only. For writes, create a scoped secret key (in a project):

```bash
pallastrade api-key create --type secret --scopes read_orders,write_products
```

Scopes follow `read_<resource>` / `write_<resource>` (`write_*` implies `read_*`); `read_all` / `write_all` are the catch-alls. `pallastrade api endpoints` shows the scope each endpoint needs.

## Core usage

```bash
# Read — Ransack filters as repeatable -q, plus sort/page/limit/expand/fields
pallastrade api get /products -q status_eq=active -q name_cont=shirt --sort -created_at --limit 10
pallastrade api get /orders/ord_x8k2J9aQ --expand items,payments,fulfillments
pallastrade api get /products --fields name,price          # id is always returned

# Write — JSON body inline, from @file, or '-' for stdin
pallastrade api post /products -d '{"name":"Classic Tee","price":29.99}'
pallastrade api patch /orders/ord_x8k2J9aQ/cancel
pallastrade api post /orders/ord_x8k2J9aQ/refunds -d @refund.json
cat prices.json | pallastrade api post /prices/bulk_upsert -d -
pallastrade api delete /products/prod_86Rf07xd
```

- **Paths** take the Admin API path; the `/api/v3/admin` prefix is optional (paste a full path and it still works).
- **Output** is JSON: indented + colored in a terminal, compact + uncolored when piped (clean for `jq`). `--format table` renders collections for humans.
- Mutations carry an automatic `Idempotency-Key`, so retries are safe.

## Discovery (offline — no server needed)

The CLI bundles a snapshot of the Admin API OpenAPI spec:

```bash
pallastrade api endpoints --resource orders        # every orders endpoint + required scope
pallastrade api endpoints --search "gift card"     # fuzzy search across method/path/summary
pallastrade api schema "POST /orders"              # full request/response schema for one op
```

Use `endpoints`/`schema` to find the right path and body shape **before** calling — this is how an agent should orient instead of guessing.

### Shell completion

```bash
eval "$(pallastrade completion zsh)"     # bash and fish also supported
```

Completes resource paths, Ransack predicate stems (`status_eq=`, `name_cont=`…), and scope names.

## Debugging workflow (the high-value path for agents)

When a request or app behavior is wrong, the CLI is the fastest probe. A typical loop:

```bash
# 1. Reproduce the read and see the actual state
pallastrade api get /orders/ord_x8k2J9aQ --expand payments,fulfillments | jq '.state, .payment_state'

# 2. If a write failed, find the endpoint's contract
pallastrade api schema "PATCH /orders/{id}/cancel"

# 3. Re-run the write and read the error envelope verbatim
pallastrade api patch /orders/ord_x8k2J9aQ/cancel
```

### Reading errors

Errors print the Stripe-style envelope to **stderr** and set the exit code:

- **`0`** success · **`1`** API error (4xx/5xx — the `{error: {code, message, details}}` envelope) · **`2`** usage/config error (bad flag, no credentials, unreachable host).

A **scope denial** (`403`, `code: access_denied`) prints `details.required_scope` and the exact remediation — mint a key with that scope and pass it via `--api-key` or `PALLASTRADE_API_KEY`:

```text
access_denied: API key lacks scope: write_products
{ "details": { "required_scope": "write_products" } }
Hint: this key lacks `write_products`. Create one that has it and use it:
  pallastrade api-key create --type secret --scopes write_products
  then pass it via --api-key <sk_...> or export PALLASTRADE_API_KEY=<sk_...>
```

A **validation error** (`422`, `code: validation_error`) puts per-attribute messages in `details` — read them to see which fields the body got wrong, then check `pallastrade api schema` for the correct shape.

`pallastrade api status` diagnoses the credential/reachability layer when calls fail before reaching the API at all (wrong host, expired/typo'd key).

## Gotchas

- The bundled spec for `endpoints`/`schema` reflects the **CLI's** PallasTrade version, not necessarily the live server's — `pallastrade api status` shows the bundled version. If an endpoint is missing from `endpoints` but exists on the server, the CLI may be older.
- `--api-key` on the command line leaks into shell history — prefer `PALLASTRADE_API_KEY` or a profile.
- Auto-minted project keys are read-only by design; a write returning 403 in a fresh project means you need an explicit scoped key, not a bug.
- The CLI talks to a **running** server; it can't bootstrap one. Inside a project, ensure the dev stack is up (`pallastrade dev`).
