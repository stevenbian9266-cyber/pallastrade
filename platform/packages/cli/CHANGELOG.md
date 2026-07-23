# @pallastrade/cli

## 2.4.4

### Patch Changes

- Streamline the post-setup summary for projects with the React Dashboard.
The dashboard's dev server is presented as THE admin — the
`cd apps/dashboard && pnpm dev` command with the admin credentials and a
dim pointer to the classic admin — instead of listing two admins where only
the classic one carried credentials. The image-served `/dashboard` build
stays a deployment detail in the docs. `pallastrade dev` (and first-run setup)
now co-runs the dashboard's Vite dev server with the Docker stack — one
command brings up the whole dev environment, its output joins the stream
with a `dashboard |` prefix, Ctrl+C stops everything, a dashboard crash
warns without taking the API down, and `--open` waits for Vite and opens
the URL it actually reports (ports auto-bump when 5173 is taken). `pallastrade add dashboard` gains
`--quiet` to skip its summary note when a wrapping tool (create-pallastrade-app)
prints its own. Projects without the dashboard keep the classic summary
unchanged.

## 2.4.3

### Patch Changes

- Fix dashboard logins dying on CORS in scaffolded apps. `pallastrade add
dashboard` wrote `VITE_PALLASTRADE_API_URL=http://localhost:<port>` into
`apps/dashboard/.env.local` — but that variable is the SDK's switch to
absolute cross-origin URLs (meant for production deploys on a different
origin), so requests bypassed the Vite dev proxy and the browser blocked
them (`localhost:5173` → `localhost:3000` is cross-origin; the auth cookie
is `SameSite=Lax` on top). The scaffold now writes `VITE_API_PROXY_TARGET`
(the proxy target — the SPA stays same-origin, the SDK stays on relative
URLs), the dashboard template's Vite config reads it (via `loadEnv` — Vite
doesn't load `.env` files into `process.env` for configs), and the CLI
writes or repairs `.env.local` automatically: on scaffold, on every
`pallastrade dev` boot, and on a `pallastrade add dashboard` re-run — covering fresh
clones (the file is gitignored) and projects scaffolded by older CLI
versions. Repair rewrites only the broken line; everything else in the
file is preserved.

## 2.4.2

### Patch Changes

- `pallastrade dev` on a project that was never set up now runs the full first-run
flow automatically (pull fresh images, start services, seed the database,
configure API keys) instead of a bare `docker compose up`. A bare `up` never
pulls, so a mutable tag (`latest`) cached weeks ago by another project
silently booted an old PallasTrade whenever the first boot happened through
`pallastrade dev` — a `--no-start` scaffold, an interrupted create-pallastrade-app run,
or a fresh clone. A setup that was itself interrupted partway (e.g. Ctrl+C
during the first image pull) is also detected and completed on the next
`pallastrade dev`, for projects scaffolded by create-pallastrade-app 1.1.1+. The
sample-data choice create-pallastrade-app persists in `.env`
(`PALLASTRADE_SAMPLE_DATA`) is honored, so a deferred first run keeps the answer
given at scaffold time. Setup also installs `apps/storefront` and
`apps/dashboard` dependencies when they're missing (a fresh clone, or a
scaffold whose install step failed) — mirroring create-pallastrade-app's per-app
install steps — so every app is runnable with `pnpm dev` right after.
Already-initialized projects are untouched: later boots never pull, dev
stays offline-friendly, and upgrades stay explicit via `pallastrade update`.

## 2.4.1

### Patch Changes

- Re-embed the dashboard-starter template against `@pallastrade/dashboard` 0.10.1
and `@pallastrade/admin-sdk` ^0.6.0. 0.10.1 ships the Vite integration compiled to
JS — registry installs of 0.10.0 failed the host build with
`ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING` when `vite.config.ts` imported
`@pallastrade/dashboard/vite` — and admin-sdk 0.5.0 lacks the Admin API endpoints
and types the dashboard consumes (the 0.x caret in the previous template pin
never resolves to 0.6.0). The `pallastrade dashboard plugin` scaffold now pins
`@pallastrade/admin-sdk` ^0.6.0 as well.

## 2.4.0

### Minor Changes

- Add `pallastrade add dashboard` — scaffolds the React Dashboard starter (Developer
Preview), bundled inside the CLI with version pins matching the release, into
`apps/dashboard/` of an existing project and points it at the project's API
(`--template <path|git-url>` overrides the bundled copy). Also make
`pallastrade plugin new` fully non-interactive: every prompt has a flag
(`--ruby-name`, `--module-name`, `--npm-scope`, `--author`, `--author-email`,
`-y`), with author details defaulting from git config.

## 2.3.9

### Patch Changes

- Add `pallastrade shell` (alias: `pallastrade bash`) — open an interactive bash shell inside the web container, the system-shell sibling of `pallastrade console` (Rails) and `pallastrade db:console` (psql). When the web container is down — a crash-looping stack is exactly when a shell is most useful — it falls back to a one-off container against the same volumes, with postgres cold-started and health-waited first.

## 2.3.8

### Patch Changes

- Add `pallastrade rspec` — run the RSpec suite inside the web container without spelling out `pallastrade bundle exec rspec`. Everything after `rspec` is forwarded verbatim (`pallastrade rspec spec/models/pallastrade/brand_spec.rb:15`, `pallastrade rspec --format documentation`), `RAILS_ENV=test` is forced so tests always hit the test database, and when the stack is down the command falls back to a one-off container that cold-starts postgres first.

## 2.3.7

### Patch Changes

- Compile the admin dashboard stylesheet on ejected projects. Ejecting bind-mounts `./backend` over the image's precompiled `app/assets/builds`, and the dev stack never runs `assets:precompile`, so `pallastrade/admin/application.css` was missing and every admin page 500'd. `pallastrade eject` now compiles it, and `pallastrade dev` compiles it if missing and then runs the Tailwind watcher so admin edits recompile live.

## 2.3.6

### Patch Changes

- Fix `pallastrade --version` reporting a stale hardcoded `2.0.0` instead of the installed CLI version. The version is now read from the package's `package.json` at runtime, so `pallastrade -V` and `npx pallastrade -V` always match the release you have installed.

## 2.3.5

### Patch Changes

- Fix `pallastrade db:reset` and `pallastrade console` when the stack is down or already serving. `db:reset` now self-heals from any state: it stops the web + worker containers holding open Postgres connections (which a plain `DROP DATABASE` rejects), then runs the drop/create/migrate/seed chain in a one-off `docker compose run --rm web` container whose dependencies cold-start automatically — so a reset works whether the stack is up, partially up, or fully stopped, and a stale host DB client (TablePlus/psql on port 5433) blocking the drop now produces an actionable hint instead of a raw error. `pallastrade console` falls back to a one-off container when web is down (mirroring `pallastrade bundle`) instead of failing, and `pallastrade db:console` guides you to start the stack when Postgres isn't running. Both new fallbacks refuse cleanly in monorepo edge projects, consistent with the other commands.

## 2.3.4

### Patch Changes

- Fix `pallastrade upgrade` on create-pallastrade-app projects. Running it from the `backend/` directory no longer fails on a missing `.env` — the CLI now resolves to the project root automatically. When the bundle is out of sync (e.g. an un-checked-out git gem source), it surfaces the real bundler error and points you at `pallastrade bundle install` instead of a misleading "No PallasTrade gems detected". And it now refuses early with a clear message when the stack is down or in a monorepo edge project, rather than failing deep in a Docker command.

## 2.3.3

### Patch Changes

- Fix an intermittent `failed to mkdir … file exists` error on the first `pallastrade eject` / `pallastrade dev` / `pallastrade init` / `pallastrade update` of a fresh project. On a cold `bundle_cache` volume the `web` and `worker` containers raced to populate it; the CLI now brings `web` up alone first so it seeds the volume uncontended before the rest of the stack starts.

## 2.3.2

### Patch Changes

- `pallastrade api status` now shows the API key's live scopes fetched from the server instead of the stale snapshot saved at mint time. Falls back to the local snapshot (clearly labelled) when the server can't report scopes.

## 2.3.1

### Patch Changes

- Fix `pallastrade api` product-create examples in the CLI help text and docs. A product's price lives on its variants, so the example now ships a `prices` array (for a simple product) instead of an unsupported top-level `price` scalar, and monetary amounts are quoted strings (`"29.99"`) to match the API's read/write format and preserve localized input.

## 2.3.0

### Minor Changes

- `pallastrade init` now mints a read-only secret key and saves it to `.pallastrade/credentials.json`, so `pallastrade api` works immediately without a first-use minting round-trip. The setup summary shows both the Store API publishable key and the Admin API secret key.

## 2.2.1

### Patch Changes

- Fix `npm install` failing with `EUNSUPPORTEDPROTOCOL "workspace:"`. `@pallastrade/admin-sdk` is bundled into the CLI at build time, so it's now a dev dependency — the published `package.json` no longer carries an unresolvable `workspace:` runtime dependency.

## 2.2.0

### Minor Changes

- New `pallastrade api` and `pallastrade auth` command groups — a generic Admin API client (`get`/`post`/`patch`/`delete`) built into the CLI:

  - `pallastrade api get|post|patch|delete <path>` — generic verbs with Ransack `-q` filters, `--sort`/`--page`/`--limit`/`--expand`/`--fields`, and JSON bodies from inline/`@file`/stdin
  - `pallastrade api endpoints` / `pallastrade api schema` — offline schema introspection over a bundled OpenAPI snapshot, including each endpoint's required scope
  - `pallastrade api status` — resolved credentials + server reachability
  - `pallastrade auth login|status|logout|list` — named profiles in `~/.config/pallastrade/config.json`
  - `pallastrade completion bash|zsh|fish` — shell completion for resource paths, Ransack predicate stems, and scope names, resolved offline from the bundled spec
  - Zero-config credentials inside a project: a read-only key is minted via the dev stack on first use and stored in `.pallastrade/credentials.json`. For other servers, `PALLASTRADE_API_KEY` is enough — the host defaults to `http://localhost:3000`; set `PALLASTRADE_BASE_URL` or save a profile for a remote store.

  Output is JSON: indented and colored in a terminal, compact and uncolored when piped (clean for `jq`).

  Works against any PallasTrade 5.5+ instance.

- `pallastrade api-key create` now supports scopes for secret keys via `--scopes` (comma-separated, e.g. `--scopes read_orders,write_products`) or an interactive prompt defaulting to `read_all`. Required against PallasTrade 5.5+ servers, where secret keys must carry at least one scope.

## 2.1.2

### Patch Changes

- `pallastrade generate controller` now forwards to the Rails `controller` generator instead of the non-existent `pallastrade:controller`.

## 2.1.1

### Patch Changes

- `pallastrade eject` now repairs dev compose files scaffolded with the broken `.:/rails` bind-mount and runs `db:prepare` after switching to the dev stack. The dev image bypasses the entrypoint that creates the database in the prebuilt image, so without this the ejected stack booted against a missing `pallastrade_development` database.

## 2.1.0

### Minor Changes

- `pallastrade dev` now runs the app in the foreground like every other dev server (`vite dev`, `bin/dev`): it streams web + worker logs and `Ctrl+C` stops them, while the database containers keep running for a fast next boot — `pallastrade stop` remains the full shutdown. Previously `Ctrl+C` only detached from the logs and left everything running. Real compose failures (daemon down, port conflict, bad config) now exit with the underlying code instead of printing a clean shutdown message; a `Ctrl+C` stop still ends cleanly.

  Add `pallastrade restart` — restarts `web` + `worker` in place (same image, same volumes, fresh Rails process). For `config/initializers` changes and anything Zeitwerk doesn't reload; it does not pick up Gemfile or compose changes.

  `pallastrade bundle` now works when the stack is down: if the `web` container isn't running — for example after a `Gemfile.lock` change crash-loops the boot, which is exactly when bundler is needed — it runs bundler in a one-off container against the same `bundle_cache` volume instead of failing on `exec`.

  `pallastrade dev` and `pallastrade build` detect monorepo edge projects (`PALLASTRADE_PATH` in `.env`) and refuse with a pointer to the matching `pnpm server:*` script, instead of materializing the wrong compose config against the running edge stack.

  `pallastrade migrate` prints a header for each step and a completion note — previously a fully up-to-date run produced no output at all, leaving no signal that anything ran.

  `pallastrade upgrade`'s closing "Next steps" panel now includes the SDK side of the upgrade: when the project has the conventional `apps/storefront` consuming `@pallastrade/sdk`, it names the currently-declared version and reminds you to bump it to the release matching the new PallasTrade version.

- Add `pallastrade generate`, `pallastrade migrate` (+ `migrate:rollback`, `migrate:status`), `pallastrade build`, `pallastrade db:reset`, `pallastrade db:console`, and `pallastrade routes`. `pallastrade generate` auto-prefixes `pallastrade:` so `pallastrade generate model Brand name:string` invokes the PallasTrade generator. `pallastrade db:reset` and `pallastrade build --reset-bundle` are destructive and prompt by default; pass `--yes` to skip the prompt in CI. `pallastrade build` targets the active `docker-compose.yml` (the same file `pallastrade dev` runs) and refuses with a pointer to `pallastrade eject` when it has no `build:` section; in monorepo edge projects it points at `pnpm server:build`.

  `pallastrade eject` no longer runs a separate `docker compose build` step (the dev compose builds on first `up -d` automatically). Its description and post-eject hints now point at `pallastrade bundle add` for gems and `pallastrade build` for Dockerfile / `.ruby-version` changes.

- Add `pallastrade exec`, `pallastrade rails`, `pallastrade bundle`, `pallastrade rake`, and `pallastrade task` as generic passthrough commands so any Rails / bundler / rake invocation is reachable through `pallastrade` without `docker compose exec` incantations. `pallastrade task <name>` auto-prefixes `pallastrade:` to save the namespace prefix on the common path. `pallastrade console` is rewired onto the same helper.

- Add `pallastrade upgrade` — sequencer around the dev upgrade flow. Runs `bundle update`, applies pending migrations, then delegates to `bin/rake pallastrade:upgrade` (which executes the version-specific data backfills from a manifest shipped inside `pallastrade_core`). On production, only the rake task runs — your deploy pipeline handles `bundle install` and `db:migrate`. Flags `--plan`, `--step <id>`, `--to <version>`, `--yes` map to env vars (`DRY_RUN`, `STEP`, `TO`) on the rake task so the same arguments work on both surfaces.

### Patch Changes

- Run `pallastrade:search:reindex` during `pallastrade init` after sample data is loaded. This initializes the Meilisearch search index so product search works immediately after setup.

## 2.0.0

### Major Release

Stable release of `@pallastrade/cli` for PallasTrade Commerce 5.4.0. Docker-based project management CLI with `pallastrade init`, `pallastrade start`, `pallastrade stop`, `pallastrade eject`, and `pallastrade update` commands.

## 2.0.0-beta.7

### Patch Changes

- Run `pallastrade:search:reindex` during `pallastrade init` after sample data is loaded. This initializes the Meilisearch search index so product search works immediately after setup.

## 2.0.0-beta.6

### Minor Changes

- Add `pallastrade eject` command to switch from prebuilt Docker image to building from local `backend/` directory. Also update port detection to read `PALLASTRADE_PORT` from `.env`.

## 2.0.0-beta.5

### Patch Changes

- Automatically update storefront `.env.local` with the real API key during `pallastrade init`

## 2.0.0-beta.4

### Patch Changes

- Pull latest Docker image during `pallastrade init` to ensure fresh setups always use the newest version
- Show Docker pull progress output during `pallastrade init` and `pallastrade update` instead of a spinner
