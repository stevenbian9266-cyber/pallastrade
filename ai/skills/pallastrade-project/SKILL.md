---
name: pallastrade-project
description: Use when the user is working on a PallasTrade Commerce project — anything involving PallasTrade models, controllers, customization patterns (decorators, subscribers, services), PallasTrade conventions like prefixed IDs / PallasTrade::Model namespacing / PallasTrade.user_class / PallasTrade::Current, or asking how PallasTrade works. Activates broadly for any task in a PallasTrade backend.
---

# PallasTrade Commerce Project

A Rails application powered by [PallasTrade Commerce](https://pallastrade.cn).

## Project flavors — detect FIRST, it changes every command

Not every PallasTrade app is a `create-pallastrade-app` project. Check these signals in order before running anything:

| Signal | Flavor | How commands run |
|---|---|---|
| `backend/Gemfile` mentions pallastrade + `docker-compose.yml` at root | **create-pallastrade-app project** (5.4+) | `pallastrade <cmd>` — the `@pallastrade/cli` routes into the Docker `web` container |
| Rails app at root (`config/application.rb`, Gemfile with pallastrade) + `docker-compose.yml` with a PallasTrade image/build | **pallastrade-starter-style Docker app** | `pallastrade <cmd>` if the CLI resolves (`npx pallastrade --version`); else `docker compose exec web <cmd>` |
| Rails app at root with pallastrade gems, no Docker wiring | **classic Rails app** (typical pre-5.4) | Native, from the app root: `bin/rails …`, `bundle exec rake …` |

Command mapping — PallasTrade CLI form → classic-app native form:

| Task | PallasTrade CLI (Docker) | Classic Rails app |
|---|---|---|
| Boot for development | `pallastrade dev` | `bin/dev` (or `bin/rails server`) |
| Rails console | `pallastrade console` | `bin/rails console` |
| Install + run migrations | `pallastrade migrate` | `bin/rake pallastrade:install:migrations && bin/rails db:migrate` |
| Version upgrade | `pallastrade upgrade` | `bundle update <pallastrade gems>`, migrations, then `bin/rake pallastrade:upgrade` |
| Run a generator | `pallastrade generate api_resource …` | `bin/rails g pallastrade:api_resource …` (spell the `pallastrade:` prefix yourself — auto-prefixing is a CLI feature) |
| Any rake task | `pallastrade rake <task>` | `bundle exec rake <task>` |
| Seeds / sample data | `pallastrade seed` / `pallastrade sample-data` | `bin/rails db:seed` / `bin/rails pallastrade:load_sample_data` |
| Arbitrary command | `pallastrade exec <cmd>` | just run `<cmd>` |

Other flavor differences:
- **Rails root**: `backend/` in create-pallastrade-app projects, `.` in classic apps. Paths written as `backend/app/…` in these skills mean `app/…` on a classic app.
- **Local docs** (`node_modules/@pallastrade/docs/dist/`) exist only when the project installs `@pallastrade/docs`. On classic apps, use https://pallastrade.cn/docs/llms.txt instead.
- The rake tasks themselves (`pallastrade:install:migrations`, `pallastrade:upgrade`, the `pallastrade:model`/`pallastrade:api_resource` generators) ship inside the pallastrade gems and work identically in both flavors — only the invocation wrapper differs. Note `pallastrade:upgrade` and the generators ship in pallastrade_core **5.5+**: a pre-5.5 app gains them after the `bundle update` step of the upgrade, so on old apps run the gem bump first.

## create-pallastrade-app project layout

| Directory | Description |
|---|---|
| `backend/` | The Rails app — PallasTrade mounted as an engine |
| `apps/storefront/` | Optional Next.js storefront |
| `node_modules/@pallastrade/docs/dist/` | Local copy of PallasTrade developer docs |

All PallasTrade-specific code (models, decorators, subscribers) lives under `backend/app/`.

## Where to find PallasTrade documentation

When you need PallasTrade-specific guidance — how a model works, what events are available, how the cart pipeline runs — read the local docs first:

```
node_modules/@pallastrade/docs/dist/
├── developer/
│   ├── core-concepts/       Products, orders, payments, inventory
│   ├── customization/       Decorators, extensions, dependencies, events
│   ├── admin/               Admin panel customization
│   ├── storefront/          Storefront building guides
│   ├── sdk/                 TypeScript SDK documentation
│   └── tutorial/            Step-by-step guides
├── api-reference/
│   ├── store-api/           Store API v3 guides
│   └── store.yaml           OpenAPI spec — every Store API endpoint
└── integrations/            Stripe, Meilisearch, etc.
```

Reach for these before guessing from training data. The local docs are the authoritative source for the installed PallasTrade version.

## Customization patterns

90% of work on a PallasTrade project is customization: wiring in external services, adding custom models, tweaking behavior. PallasTrade exposes a layered set of extension points for this — settings, configuration, events, dependency injection, admin extension APIs, the resource generator, decorators, gems. Picking the right one matters because each layer has different upgrade-safety characteristics.

**For routing a specific customization to the right pattern, use the `pallastrade-customization` skill.** It has the full decision table (subscribers vs decorators vs `PallasTrade.dependencies` vs admin APIs vs `PallasTrade.ransack`) with worked examples. Reach for it whenever the right approach isn't obvious.

Quick summary of the priority order:

1. **Settings / `PallasTrade::Config`** — for runtime behavior toggles.
2. **Events + subscribers** — for side effects ("sync to ERP when order completes").
3. **Dependency injection** (`PallasTrade.dependencies`) — for swapping how a core service computes. See `pallastrade-dependencies` skill.
4. **Admin extension APIs** (`PallasTrade.admin.navigation`, `PallasTrade.admin.partials`, `PallasTrade.admin.tables`, `PallasTrade.ransack`) — for admin UI and search.
5. **Generators** (`pallastrade:api_resource`, `pallastrade:model`) — for brand-new models / resources.
6. **Decorators** (`pallastrade:model_decorator`, `pallastrade:controller_decorator`) — for structural changes to existing PallasTrade classes.
7. **Extensions** (gems) — only when sharing customization across multiple apps.

## Conventions you should always follow

- **Namespace under `PallasTrade::`** — all PallasTrade-related Ruby classes live in `app/models/pallastrade/`, `app/controllers/pallastrade/`, etc.
- **`PallasTrade.user_class` / `PallasTrade.admin_user_class`** — never reference `PallasTrade::User` directly. The user class is configurable.
- **`PallasTrade::Current.store` / `.currency` / `.locale`** — per-request context, available in models, controllers, services.
- **Prefixed IDs in the API** — every v3 API response returns Stripe-style prefixed IDs (`prod_86Rf07xd4z`, `or_m3Rp9wXz`). Never expose raw integer IDs. Same on writes — the API accepts prefixed IDs.
- **`PallasTrade.base_class`** — inherit from this, not `ActiveRecord::Base`. It applies PallasTrade's base configuration.

## Common commands

`@pallastrade/cli` (installed by `create-pallastrade-app`) wraps the Docker-based dev workflow:

```bash
pallastrade dev                          # run the stack in the foreground (streams logs; Ctrl+C stops web + worker, DBs stay up)
pallastrade stop                         # tear down
pallastrade console                      # Rails console
pallastrade logs                         # follow web container logs
pallastrade restart                      # restart the Rails process

pallastrade migrate                      # install engine migrations from gems + db:migrate
pallastrade generate <name> [args]       # any PallasTrade generator
pallastrade bundle add <gem>             # add a gem (persists in bundle_cache volume)
pallastrade rake <task>                  # any rake task
pallastrade exec <cmd>                   # universal escape hatch
pallastrade rails <cmd>                  # any bin/rails command
pallastrade routes                       # show Rails routes
pallastrade seed                         # seed the database
pallastrade sample-data                  # load sample products/categories/images
pallastrade user create                  # create an admin user
pallastrade api-key create               # create an API key (also: list, revoke)
pallastrade db:reset                     # drop + recreate + migrate + seed (destructive)

pallastrade upgrade                      # version upgrade
```

If you don't have `pallastrade` on your PATH, prefix with the package runner: `npx pallastrade …`, `pnpm exec pallastrade …`, or `bunx pallastrade …`.

## When in doubt

- Not sure which customization pattern fits? See the `pallastrade-customization` skill — it routes the decision.
- Need to add a new model + API endpoint? See the `pallastrade-resource` skill.
- Need to extend an existing PallasTrade model/controller? See the `pallastrade-decorators` skill.
- Need to upgrade PallasTrade? Run the `/pallastrade:audit-upgrade` command.
- Need details on a specific PallasTrade concept? Read `node_modules/@pallastrade/docs/dist/developer/` first.
