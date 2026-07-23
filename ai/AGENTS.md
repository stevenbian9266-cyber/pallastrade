# PallasTrade Commerce — Agent Guidance

This file follows the [agents.md](https://agents.md) cross-tool standard. It's a portable summary of how to be effective on a PallasTrade Commerce codebase, written for any agentic CLI (Codex, Cursor, Copilot, Aider, Windsurf, Zed, Amp, etc.) that reads `AGENTS.md`.

If you're running in **Claude Code**, install this package as a plugin and you'll get the 26 SKILL.md files under `skills/` as on-demand context, the `pallastrade-expert` subagent, and two safety hooks. See [README.md](./README.md) for install instructions.

If you're running in **any other tool**: read this file, then dive into the relevant `skills/<name>/SKILL.md` when the task matches its domain.

---

## What PallasTrade is

PallasTrade Commerce is an open-source, self-hosted commerce platform built on Ruby on Rails. The thing people choose it for is the ability to customize and extend it without forking. Architecture in three layers:

1. **Backend (Ruby gems)** — `pallastrade_core` (models, services, business logic), `pallastrade_api` (Store + Admin REST APIs under `/api/v3/`), `pallastrade_admin` (Rails admin UI), optional payment/integration gems (`pallastrade_stripe`, `pallastrade_adyen`, `pallastrade_paypal_checkout`, `pallastrade_i18n`).
2. **Frontend SDKs (TypeScript)** — `@pallastrade/sdk` (Store API client), `@pallastrade/admin-sdk` (Admin API client).
3. **Admin UI** — `pallastrade_admin` (the Rails/Turbo admin).

Users run PallasTrade in their own infrastructure — there's no PallasTrade cloud. Everything is opt-in customization.

## Core conventions (don't violate these without a reason)

### Ruby / Rails

- All PallasTrade code is namespaced under `PallasTrade::`.
- All models inherit from `PallasTrade.base_class` — not `ApplicationRecord` directly.
- Use `PallasTrade.user_class` and `PallasTrade.admin_user_class` instead of `PallasTrade::User` so apps can swap the user model.
- Always scope queries through `current_store` (e.g. `current_store.orders`, not `PallasTrade::Order.all`). Multi-store apps share a database; un-scoped queries leak data across stores.
- State/status fields on state-machine models (Order, Payment, Shipment) are string columns — don't convert them to Rails enums. (Core does use integer enums for a few non-workflow fields like `Promotion#kind`; string + state machine is still the default for anything with transitions.)
- IDs are treated as strings (Stripe-style prefixed IDs at the API surface; integer PKs internally — never `.to_i` an ID).
- State machines use the `state_machines-activerecord` gem.
- Uniqueness validations use `scope: pallastrade_base_uniqueness_scope` plus a DB index.
- Always pass `class_name` and `dependent` on associations.
- Use the events system (`publish_event` + subscribers) for side effects — not `after_*` callbacks.

### API v3 (REST)

Two surfaces under `/api/v3/`:

- **Store API** (`/api/v3/store/*`) — customer-facing. Auth: publishable key (`pk_*`) + optional JWT customer. Read-only by default.
- **Admin API** (`/api/v3/admin/*`) — back-office. Auth: secret key (`sk_*` with scoped permissions) OR JWT admin (with CanCanCan abilities). Full CRUD by default.

Both share: prefixed IDs (`prod_…`, `or_…`, `variant_…`), `{ data, meta }` envelope on lists, Ransack filters (`q[name_cont]=...`), `expand=...` for sideloading (and `fields=...` for sparse responses). See `skills/pallastrade-api-v3/SKILL.md`.

### TypeScript

- The `@pallastrade/sdk` (Store) and `@pallastrade/admin-sdk` (Admin) packages are the canonical way to call the API from TypeScript.
- For custom endpoints, use the SDK's `client.request<T>(method, path, options)` escape hatch or extend the client with a wrapped resource class — don't fork the SDK and don't bypass with raw `fetch`.

## Development commands

Projects scaffolded with `create-pallastrade-app` use the `@pallastrade/cli` to drive the Docker-based dev environment. **Flavor check first:** classic Rails apps with PallasTrade gems (no Docker/CLI — typical pre-5.4, Rails app at the repo root) take the native equivalents instead — `bin/rails console`, `bin/rake pallastrade:install:migrations && bin/rails db:migrate`, `bin/rake pallastrade:upgrade`, `bin/rails g pallastrade:api_resource …` — and paths lose the `backend/` prefix. The rake tasks and generators ship in the gems (pallastrade_core 5.5+ for `pallastrade:upgrade` and the generators — older apps gain them after the gem bump) and work identically in both flavors; only the wrapper differs.

```bash
pallastrade init                  # one-time setup: starts services, seeds DB, generates API key
pallastrade dev                   # run the stack in the foreground (Ctrl+C stops web + worker; DBs stay up)
pallastrade stop
pallastrade restart               # in-place restart for initializer changes
pallastrade logs                  # web (default) or `pallastrade logs worker`
pallastrade console               # Rails console
pallastrade migrate               # install + run pending migrations
pallastrade db:reset               # drop, recreate, seed
pallastrade routes                # bin/rails routes passthrough
pallastrade generate <args>       # run a generator — bare names auto-prefix to `pallastrade:` (`model` → `pallastrade:model`, `api_resource` → `pallastrade:api_resource`); Rails built-ins (`migration`, `scaffold`, `job`, …) forwarded as-is
pallastrade exec <command>        # arbitrary command inside the web container
pallastrade rails <args>          # bin/rails passthrough
pallastrade bundle <args>         # bundle passthrough (lands in bundle_cache volume)
pallastrade rake <task>
pallastrade upgrade               # walk version upgrade (bundle + migrate + pallastrade:upgrade)
pallastrade eject                 # switch from prebuilt image to building from ./backend/
pallastrade build                 # rebuild dev image (after eject + Dockerfile/.ruby-version changes)
pallastrade update                # pull latest image + recreate containers
pallastrade migrate:status        # show migration status
pallastrade migrate:rollback      # roll back last migration (STEP=n for more)
pallastrade db:console            # psql session against the dev database
pallastrade task <name>           # rake task with auto `pallastrade:` prefix (e.g. pallastrade task search:reindex)
pallastrade seed                  # seed the database
pallastrade sample-data           # load sample data (products, categories, images)
pallastrade user create           # create an admin user (interactive, or --email/--password)
pallastrade api-key create|list|revoke   # manage publishable/secret API keys (--type publishable|secret)
pallastrade open                  # open the admin dashboard in the browser
pallastrade api <verb> <path>     # generic Admin API client (see skills/pallastrade-cli/SKILL.md)
pallastrade auth login            # save a credentials profile for a remote store
pallastrade completion <shell>    # bash/zsh/fish shell completions
```

For the full command reference see `dist/developer/cli/quickstart.md` in the installed `@pallastrade/docs` package (source: `docs/developer/cli/quickstart.mdx` in the pallastrade monorepo).

### Testing

```bash
# Inside the project's backend directory or via `pallastrade exec`:
bundle exec rspec                       # full suite
bundle exec rspec spec/models/...       # one file
bundle exec rspec spec/models/...:42    # one test (by line number)

# Only when developing a PallasTrade engine or extension (these tasks don't exist in a scaffolded app backend):
bundle exec rake test_app               # regenerate the dummy test app (after schema changes)
bundle exec rake parallel_setup         # create per-worker test DBs
bundle exec parallel_rspec spec         # parallel run
```

## Testing conventions

- RSpec + Factory Bot + Capybara — **not** Minitest, **not** fixtures.
- Install `pallastrade_dev_tools` for PallasTrade-specific helpers (`stub_authorization!`, `'API v3 Store'` shared context, PallasTrade factories).
- Always use factories (`create(:order_with_line_items)`), never `Model.create` directly.
- Prefer `build` over `create` when persistence isn't needed.
- Don't test Rails framework guarantees (strong params, presence validations). Test your custom logic.

## Security non-negotiables

- Secrets live in Rails encrypted credentials or env vars — never in the repo.
- Configure Rails Active Record encryption keys in production (`active_record.encryption.primary_key`, `deterministic_key`, `key_derivation_salt` — generate with `bin/rails db:encryption:init`, store in encrypted credentials). PallasTrade uses `encrypts` for secrets like webhook signing keys and gateway customer profile IDs; these columns only encrypt at rest when AR encryption is configured. Keep `secret_key_base` stable within each environment.
- Webhook receivers MUST verify HMAC-SHA256 signatures + timing-safe compare + replay window (default 5 min).
- Publishable keys (`pk_*`) are safe in client code. Secret keys (`sk_*`) are server-to-server only — never ship in mobile apps or browser JS.
- Grant secret keys minimum scopes (`read_orders`, `write_products`, etc.) — not `write_all`.
- All queries scoped through `current_store` to prevent cross-store data leaks.
- See `skills/pallastrade-security/SKILL.md` for the full list.

## The skills index — where to look

When the task domain matches one of these, read the corresponding `skills/<name>/SKILL.md`:

| Domain | Skill |
|---|---|
| General project conventions, customization patterns | `pallastrade-project` |
| Routing question: "where does my customization belong" / "decorator vs subscriber vs ..." | `pallastrade-customization` |
| Adding a new model + API endpoint (uses the `pallastrade:api_resource` generator) | `pallastrade-resource` |
| Extending an existing PallasTrade model/controller via decorators (`prepend`) | `pallastrade-decorators` |
| Swapping a core PallasTrade service via `PallasTrade.dependencies` (cart, checkout, serializers, ability) | `pallastrade-dependencies` |
| REST API v3 protocol — auth, envelopes, prefixed IDs, scopes | `pallastrade-api-v3` |
| Maintaining or migrating legacy v2 (JSON:API) integrations | `pallastrade-legacy-api-v2` |
| `@pallastrade/sdk` + `@pallastrade/admin-sdk` usage, extension patterns | `pallastrade-typescript-sdk` |
| Calling/inspecting the Admin API from the terminal, debugging requests (`pallastrade api`) | `pallastrade-cli` |
| Auditing an upgrade across minor/major versions | `/pallastrade:audit-upgrade` command |
| Domain model — Orders, LineItems, Variants, Stores, Channels, Markets | `pallastrade-data-model` |
| Events + subscribers (in-process) + outbound webhooks (HMAC, retry) | `pallastrade-events-webhooks` |
| Installing third-party gems or writing your own extension | `pallastrade-extensions` |
| Products, Variants, Options, Categories, search, images | `pallastrade-catalog` |
| Cart pipeline, order state machine, payment sessions, checkout customization | `pallastrade-checkout` |
| Payment methods, gateways, refunds, gift cards, store credits | `pallastrade-payments` |
| Promotion rules, actions, calculators, coupon codes | `pallastrade-promotions` |
| Variant prices, multi-currency, price lists, EU Omnibus | `pallastrade-pricing` |
| Shipments, shipping methods, rates, stock locations, returns | `pallastrade-shipping-fulfillment` |
| Legacy Rails/Turbo admin customization (`pallastrade_admin` gem) | `pallastrade-admin` |
| Next.js storefront + `@pallastrade/sdk` integration | `pallastrade-storefront` |
| UI translations (`PallasTrade.t`) + data translations (Mobility) | `pallastrade-i18n` |
| RSpec / Factory Bot / `pallastrade_dev_tools` testing patterns | `pallastrade-testing` |
| Rails security + PallasTrade-specific (scopes, encrypted prefs, webhook HMAC, PCI) | `pallastrade-security` |
| Perf hotspots — cart pipeline, catalog N+1s, search, image processing, Sidekiq | `pallastrade-performance` |
| Deploying to Heroku/Render/K8s/Docker — env vars, release commands, S3, Sidekiq | `pallastrade-deployment` |

## What NOT to do

- Don't write `PallasTrade::User.find(...)` — use `PallasTrade.user_class.find(...)`.
- Don't add foreign key constraints in migrations on business tables — PallasTrade's generators emit `foreign_key: false` (the only FKs in the schema come from ActiveStorage and the Mobility translation tables).
- Don't model state/status fields as Rails enums — use string columns (+ a state machine where transitions matter).
- Don't drop or truncate `pallastrade_*` tables in development without backup. The PallasTrade Agent Skills plugin's safety hook blocks the most dangerous of these automatically when installed via `/plugin install pallastrade@pallastrade` in Claude Code (DROP TABLE on any `pallastrade_*` table, `db:drop`/`db:reset`, and TRUNCATE or mass-deletes of orders, payments, users); other tables and other tools aren't covered.
- Don't bypass `current_store` scoping in custom controllers.
- Don't expose raw integer IDs in API responses — always prefixed IDs (`prod_…`, `or_…`).
- Don't fork `@pallastrade/sdk` to add custom endpoints — extend it via `client.request` or a wrapped resource class.

## Where to read further

- **PallasTrade developer docs:** https://pallastrade.cn/docs/developer
- **Installed locally:** `node_modules/@pallastrade/docs/dist/developer/` after scaffolding with `create-pallastrade-app`
- **Source code:** https://github.com/stevenbian9266-cyber/pallastrade
- **Each `skills/<name>/SKILL.md` is self-contained** — read it when its domain is in scope.
