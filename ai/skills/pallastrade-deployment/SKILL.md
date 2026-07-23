---
name: pallastrade-deployment
description: Use when the user is deploying a PallasTrade application to production — Heroku, Render, Fly, AWS, K8s, plain Docker. Covers required environment variables, Sidekiq setup, the release-phase command (`rake pallastrade:upgrade`), ActiveStorage backend config, asset precompile, the docker-entrypoint behavior. Common phrasings include "deploy PallasTrade", "Heroku deploy", "Render deploy", "PallasTrade on Kubernetes", "PallasTrade environment variables", "PallasTrade release command", "Procfile", "Sidekiq deployment", "S3 setup", "Cloudflare R2", "asset precompile failed". PallasTrade-specific bits only — generic Rails deployment is out of scope.
---

# Deploying PallasTrade

PallasTrade is a standard Rails 7+ application — most generic Rails deployment guides apply. This skill covers the PallasTrade-specific pieces: the env vars PallasTrade expects, the Sidekiq queue setup, the upgrade release command, and the ActiveStorage backends PallasTrade integrates with.

## Required environment variables

These must be set on every PallasTrade deployment:

| Variable | Required | Notes |
|---|---|---|
| `SECRET_KEY_BASE` | Yes | 128-char hex. Generate with `bin/rails secret`. Must be stable across restarts (cookies, sessions, encrypted preferences depend on it). |
| `DATABASE_URL` | Yes | PostgreSQL connection URL. `postgres://user:pass@host:5432/pallastrade_production`. |
| `REDIS_URL` | Yes | Used for caching, Sidekiq, ActionCable. `redis://host:6379/0`. |
| `RAILS_ENV` | Yes | `production` for production. Don't deploy `development`. |
| `RAILS_LOG_TO_STDOUT` | Not needed | pallastrade-starter logs to stdout unconditionally — this variable is never read. Use `RAILS_LOG_LEVEL` (default `info`) to tune verbosity. |
| `PORT` | Conditional | Web server port. Platform-dependent — Heroku/Render inject; K8s expects container's. |

### Optional but common

| Variable | Notes |
|---|---|
| `REDIS_CACHE_URL` | Separate Redis DB for `Rails.cache`. Falls back to `REDIS_URL`. Use a separate instance in production so cache evictions don't hit Sidekiq. |
| `RAILS_MAX_THREADS` | Puma threads per worker. Default 3; tune based on DB pool size. |
| `WEB_CONCURRENCY` | Puma worker count. Default 1; increase for multi-core. |
| `RAILS_FORCE_SSL` | Force HTTPS at the Rails layer (HTTP→HTTPS redirects, HSTS, secure cookies). **Default: on** — set `RAILS_FORCE_SSL=false` only when running without TLS (e.g. local Docker; pallastrade-starter's docker-compose.yml does this). Safe to leave on behind SSL-terminating load balancers because `RAILS_ASSUME_SSL` marks proxied requests as HTTPS. |
| `RAILS_ASSUME_SSL` | Tells Rails it runs behind an SSL-terminating reverse proxy, so requests are treated as HTTPS. **Default: on** — set `false` only when there's no SSL anywhere (local dev, non-SSL proxy). |
| `RAILS_HOST` | The public hostname. Used in email links and absolute URLs. |

### Email (SMTP)

| Variable | Notes |
|---|---|
| `SMTP_HOST` | When set, enables SMTP delivery. If unset, dev opens emails via `letter_opener`; production has no fallback — deliveries fail. |
| `SMTP_PORT` | Typically 587 (STARTTLS) or 465 (TLS). |
| `SMTP_USERNAME` / `SMTP_PASSWORD` | Provider credentials. |
| `SMTP_FROM_ADDRESS` | Default sender. |

Authentication is hardcoded to `plain` (with STARTTLS) in pallastrade-starter's production.rb — edit that file if your provider needs a different mechanism.

If `SMTP_HOST` is unset, dev uses the `letter_opener` gem (emails open in the browser instead of being sent). In production there is no fallback: no delivery method is configured, so ActionMailer stays on Rails' default `:smtp` pointing at localhost:25 and deliveries fail unless a local MTA is running — always set the SMTP vars in production. (The official env-var docs state this correctly; the *emails* doc claims unsent emails are "printed to the Rails log", which the pallastrade-starter code does not do.) Many merchants use Postmark / SendGrid / Resend — set the SMTP vars and you're done.

### File storage (ActiveStorage)

PallasTrade's product images, customer uploads, and admin assets go through ActiveStorage. Configure one of:

| Backend | Variables | Notes |
|---|---|---|
| Local disk | (none) | Default. Doesn't work on ephemeral filesystems (Heroku, K8s without persistent volumes) — files vanish on dyno restart. |
| AWS S3 | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `AWS_BUCKET` | Auto-detected: the `:amazon` service activates when the two access-key vars are set (region/bucket are read via storage.yml with defaults). |
| Cloudflare R2 | `CLOUDFLARE_ENDPOINT`, `CLOUDFLARE_ACCESS_KEY_ID`, `CLOUDFLARE_SECRET_ACCESS_KEY`, `CLOUDFLARE_BUCKET` | S3-compatible. Cheaper egress; same API. Auto-detected when the two access-key vars **and** `CLOUDFLARE_ENDPOINT` are set. |
| GCS / Azure | Standard ActiveStorage config | PallasTrade doesn't ship special integration; use ActiveStorage's standard configuration in `config/storage.yml`. |

For production, always use an object store — local disk on ephemeral platforms loses files on restart.

### Search

| Variable | Notes |
|---|---|
| `MEILISEARCH_URL` | When set, PallasTrade uses Meilisearch as the search provider. `http://meilisearch:7700` for a co-located instance; or a managed URL. |
| `MEILISEARCH_API_KEY` | The master or per-index key. Required for production Meilisearch. |

If `MEILISEARCH_URL` is unset, PallasTrade uses the Database search provider — fine for catalogs < 10K products.

### Error tracking

| Variable | Notes |
|---|---|
| `SENTRY_DSN` | pallastrade-starter ships Sentry integration (sentry-ruby/rails/sidekiq + an initializer gated on this var). When set, exceptions report to Sentry automatically. Non-starter apps must add the gems + initializer themselves. |

## The Sidekiq deployment

PallasTrade relies heavily on Sidekiq for background work. Required for production — without it, events don't fire, images don't process, search doesn't reindex.

### Process types (Procfile pattern)

```
# Procfile
web: bundle exec puma -C config/puma.rb
worker: bundle exec sidekiq -C config/sidekiq.yml
```

Run at least one worker process. For high-traffic stores, run multiple worker processes with explicit queue weights.

### Queue weights matter

See the `pallastrade-performance` skill for the full discussion. Queue names must match your app's `PallasTrade.queues.*` mapping — out of the box every PallasTrade queue maps to `:default`; pallastrade-starter overrides them to `pallastrade_`-prefixed names in `config/initializers/pallastrade.rb`. Any queue missing from the worker's list never gets processed. This is pallastrade-starter's shipped `config/sidekiq.yml` (the safe baseline — adjust weights, don't drop queues):

```yaml
# config/sidekiq.yml
:concurrency: <%= Integer(ENV.fetch('SIDEKIQ_CONCURRENCY', '25')) %>
:queues:
  - [default, 5]
  - [pallastrade_imports, 5]
  - [pallastrade_payment_webhooks, 5]
  - [mailers, 5]
  - [pallastrade_events, 3]
  - [pallastrade_exports, 3]
  - [pallastrade_images, 3]
  - [pallastrade_products, 3]
  - [pallastrade_reports, 3]
  - [pallastrade_variants, 3]
  - [pallastrade_taxons, 3]
  - [pallastrade_stock_location_stock_items, 3]
  - [pallastrade_coupon_codes, 3]
  - [pallastrade_addresses, 3]
  - [pallastrade_gift_cards, 3]
  - [pallastrade_webhooks, 3]
  - [pallastrade_api_keys, 3]
  - [pallastrade_search, 3]
  - [active_storage_analysis, 1]
  - [active_storage_purge, 1]
```

When tuning weights, keep payment webhooks near the top — they block the customer (who is waiting on the redirect-back) — while image processing is fine to lag behind.

### Sidekiq Pro / Enterprise

Not required. But every production store does need a job scheduler: `PallasTrade::StockReservations::ExpireJob` must run periodically (every minute recommended) — PallasTrade does not auto-schedule it, and without it expired checkout stock-reservation rows accumulate indefinitely (availability checks already ignore them; the job exists to clean up the table). Add `pallastrade:price_history:prune` as housekeeping. Use Sidekiq-Cron (free) or Sidekiq Enterprise's built-in scheduling. (`pallastrade:upgrade` is not a cron job — it belongs in the release phase, covered below.)

## The release-phase command

After every deploy, run database migrations AND the upgrade rake task. On Heroku:

```
# Procfile
release: bundle exec rake pallastrade:install:migrations db:migrate && bundle exec rake pallastrade:upgrade
```

On Render (recommended config — note pallastrade-starter's shipped `render.yaml` doesn't do this yet: it runs `db:prepare` inside `buildCommand` and never runs `pallastrade:upgrade`):

```yaml
# render.yaml
services:
  - type: web
    name: pallastrade-web
    autoDeploy: true
    preDeployCommand: bundle exec rake pallastrade:install:migrations db:migrate && bundle exec rake pallastrade:upgrade
```

On K8s, use an init container or a Helm post-install hook:

```yaml
initContainers:
  - name: migrate
    image: my-pallastrade-image:latest
    command: ["/bin/sh", "-c", "bundle exec rake pallastrade:install:migrations db:migrate && bundle exec rake pallastrade:upgrade"]
```

`pallastrade:upgrade` walks every eligible upgrade manifest for the installed PallasTrade version. It's **idempotent** — re-running on an already-upgraded app is a safe no-op. Use the `/pallastrade:audit-upgrade` command for an upgrade-readiness review.

**Why both `db:migrate` and `pallastrade:install:migrations`:** `pallastrade:install:migrations` copies new migrations from the gems into `db/migrate/`. Then `db:migrate` applies them. The order matters.

## Asset precompile

PallasTrade includes admin assets (Tailwind CSS, Stimulus controllers). They precompile via `bin/rails assets:precompile`. On most platforms this happens automatically at build time.

### Two common precompile failures

1. **`SECRET_KEY_BASE` not set at build time.** Even though precompile doesn't *need* the secret, the Rails app initializer reads it. Workaround: use `SECRET_KEY_BASE_DUMMY=1` at build time (Rails 7+ skips the secret check). The PallasTrade Dockerfile already does this.

2. **JS bundle fails on Tailwind.** The `pallastrade_admin` gem ships its own Tailwind config. If your app has its own Tailwind setup, the two can conflict. Run `bundle exec rake pallastrade:admin:tailwindcss:build` separately for the admin's CSS.

## The bin/docker-entrypoint convention

The pallastrade-starter Dockerfile uses a tiny entrypoint:

```bash
#!/bin/bash -e
# If running the rails server then create or migrate existing database
if [[ "$*" == *"./bin/rails server"* ]]; then
  ./bin/rails db:prepare
fi
exec "${@}"
```

`db:prepare` is `db:create` (idempotent) + `db:migrate` + `db:seed-if-empty`. For production, **this is wrong** — you want migrations to run before the server starts, but not from the entrypoint (which races multiple replicas). Override the entrypoint in production:

```dockerfile
ENTRYPOINT []
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
```

And run migrations via the release-phase command above.

## Platform-specific notes

### Heroku

- Use Heroku Postgres (the addon, not external) for `DATABASE_URL` — it injects automatically.
- Heroku Redis or Upstash Redis works for `REDIS_URL`.
- File storage **must** be S3 / R2 — Heroku's filesystem is ephemeral.
- One web dyno + one worker dyno is the minimum. Hobby tier works for staging.
- Set the release-phase command in the Procfile.

### Render

- Native PostgreSQL + Redis addons inject the URLs.
- Persistent disks are available for ActiveStorage local backend (cheaper than S3 for low-traffic stores) — but only on Render's paid tier.
- Set `preDeployCommand` in render.yaml (pallastrade-starter's shipped render.yaml instead runs `db:prepare` in `buildCommand` — migrating it to `preDeployCommand` is the safer pattern).

### Fly.io

- The Fly Postgres + Upstash Redis combo is common.
- ActiveStorage with Tigris (S3-compatible, edge-served) is the native choice.
- Use `release_command` in fly.toml.

### Kubernetes

- One Deployment per process type (web, worker, optionally separate workers per queue).
- Init container for migrations + upgrades.
- ConfigMap for non-secret env, Secret for `SECRET_KEY_BASE`, `DATABASE_URL`, `REDIS_URL`, S3 creds.
- HorizontalPodAutoscaler on the web Deployment based on CPU + request count.
- Liveness probe at `/up` (Rails built-in health endpoint, returns 200 when Rails booted).
- Readiness probe checks DB connectivity — point at a custom endpoint that does `ActiveRecord::Base.connection.active?`. Don't reuse `/up` here: Rails' built-in health check never touches the database (and PallasTrade does not extend it in any version).

### Plain Docker (single host)

- `docker-compose.yml` with web + worker + postgres + redis + meilisearch.
- PallasTrade-starter ships a working example — clone it as a starting point.
- Use a reverse proxy (Nginx, Caddy, Traefik) for SSL termination.

## Common deployment problems

### "Every page 404s (ActiveRecord::RecordNotFound) right after deploy"

You don't have a Store record — PallasTrade raises `ActiveRecord::RecordNotFound` from a before_action when no `PallasTrade::Store` exists (rendered as a 404 in production). Run `bin/rails db:seed` or create one manually:
```ruby
PallasTrade::Store.create!(name: 'My Store', url: ENV['RAILS_HOST'], code: 'my-store', mail_from_address: 'no-reply@example.com', default_currency: 'USD', default: true)
```

### "Sidekiq dashboard returns 401"

The dashboard at `/sidekiq` is auth-protected by default. pallastrade-starter already mounts it in `config/routes.rb` (the Rails root — that's the repo root in a standalone pallastrade-starter deploy; create-pallastrade-app projects nest it under `backend/`). Effectively:
```ruby
# shipped code derives the scope: PallasTrade.admin_user_class.model_name.singular_route_key.to_sym
authenticate :pallastrade_admin_user, ->(admin_user) { admin_user.pallastrade_admin? } do
  mount Sidekiq::Web => '/sidekiq'
end
```
A 401 (or redirect to sign-in) means the mount is working: sign in at `/admin` first, and note the user must also have the admin role (`pallastrade_admin?`) — a signed-in non-admin is rejected too. Only add this block yourself if your app wasn't generated from pallastrade-starter.

### "Image uploads work but images don't display"

S3 bucket policy isn't allowing public reads, OR the bucket is configured as `private` and ActiveStorage isn't signing URLs. Check:
```ruby
Rails.application.config.active_storage.service     # should be :amazon (or your service)
ActiveStorage::Blob.first.url                       # should return a signed URL or public URL
```

### "Webhooks aren't firing"

Sidekiq worker isn't running, OR the `pallastrade_events` / `pallastrade_webhooks` queues aren't in the worker's queue list. Confirm with `Sidekiq.redis { |r| [r.lrange('queue:pallastrade_events', 0, -1), r.lrange('queue:pallastrade_webhooks', 0, -1)] }` (queue names come from `PallasTrade.queues.*` in `config/initializers/pallastrade.rb`).

### "Search returns nothing after deploy"

Meilisearch index wasn't built. Run `bundle exec rake pallastrade:search:reindex`. On Heroku, run as a one-off: `heroku run bundle exec rake pallastrade:search:reindex`.

## Where to read further

- **PallasTrade-starter Dockerfile + docker-compose:** https://github.com/stevenbian9266-cyber/pallastrade — reference production-ready Docker setup.
- **Deployment docs:** `https://pallastrade.cn/docs/developer/deployment` — platform-specific guides.
- **Env vars:** `.env.example` at the app root, and the Environment Variables page at `https://pallastrade.cn/docs/developer/deployment/environment_variables`.
- **Sidekiq tuning:** the `pallastrade-performance` skill.
- **PallasTrade upgrades in production:** the `/pallastrade:audit-upgrade` command — release-phase readiness review.
