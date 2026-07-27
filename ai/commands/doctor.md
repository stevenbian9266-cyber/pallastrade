---
description: Diagnose the local PallasTrade dev stack — Docker, containers, env, web, migrations, jobs — and prescribe the exact fix
allowed-tools: Bash, Read, Grep, Glob
---

# PallasTrade stack diagnosis

Run every check below in order against this project. Do not stop at the first failure — run all of them, then report. Judge each against its healthy state.

Pre-flight — detect the project flavor:
- `backend/docker-compose.dev.yml` exists (monorepo with Docker): run the Docker checks below as written, using `cd backend && docker compose -f docker-compose.dev.yml`.
- `backend/docker-compose.yml` exists: same as above.
- `docker-compose.yml` at the root (legacy create-pallastrade-app): run the Docker checks below as written.
- No Docker wiring but a Rails app with pallastrade gems at the root (classic pre-5.4 app): skip checks 1–2, run everything else **natively** — replace `pallastrade exec <cmd>` with plain `<cmd>` from the app root, check the web on the port `bin/dev`/`bin/rails s` uses (default 3000), and read `backend/Gemfile.lock` as `Gemfile.lock`.
- Neither: not a PallasTrade project — say so and stop.

Command routing (Docker flavors): prefer `cd backend && docker compose -f docker-compose.dev.yml exec web <cmd>`; if the `pallastrade` CLI isn't available, fall back to `docker compose exec -T web <cmd>`. On classic apps, remedies use native forms (`bin/dev`, `bin/rails db:migrate`, `bundle exec rake`).

## Checks

1. **Docker daemon** — `docker info --format '{{.ServerVersion}}'`
   Healthy: prints a version. Remedy: start Docker Desktop / OrbStack.

2. **Containers** — `docker compose ps -a --format '{{.Service}}: {{.State}} ({{.Status}})'`
   Healthy: `postgres`, `redis`, `web` running (plus `worker` and `meilisearch` when defined in the compose file). Exited app containers are normal if the user just hasn't booted; the remedy is `pallastrade dev` (foreground, Ctrl+C stops) — or `pnpm server:dev` in monorepo mode.

3. **Env file** — read `.env`: `SECRET_KEY_BASE` present and non-empty, `PALLASTRADE_PORT` (default 3000 when absent). Note `PALLASTRADE_VERSION_TAG` if pinned. Flag a missing `.env` as the likely root cause for boot loops.

4. **Web responding** — `curl -fsS -o /dev/null -w '%{http_code}' http://localhost:<PALLASTRADE_PORT>/` (substitute the detected port)
   Healthy: 2xx/3xx. `000` = nothing listening (stack down or still booting — check `pallastrade logs`); `5xx` = Rails boot/runtime error (read `pallastrade logs` and include the first error line in the report).

5. **Database connectivity** — `pallastrade exec bin/rails runner 'puts ActiveRecord::Base.connection.active?'`
   Healthy: `true`. Skip (and say so) if the web container isn't running.

6. **Pending migrations** — `pallastrade exec bin/rails db:migrate:status | grep -c '^\s*down'`
   Healthy: `0`. Remedy: `pallastrade migrate` (installs engine migrations from gems, then `db:migrate`).

7. **Background jobs** — `pallastrade exec bin/rails runner 'require "sidekiq/api"; puts({ queues: Sidekiq::Queue.all.map { |q| [q.name, q.size] }.to_h, retries: Sidekiq::RetrySet.new.size, dead: Sidekiq::DeadSet.new.size }.inspect)'`
   Healthy: no runaway queue (thousands) and a small dead set. Remedy for backlogs: confirm the `worker` container is running and check `pallastrade logs worker`.

8. **Installed PallasTrade version** — `grep -E '^    pallastrade(_core)? \(' backend/Gemfile.lock | head -3` (monorepo projects: gems resolve via path, note that instead). Report the version; if `@pallastrade/sdk` is declared in `apps/storefront/package.json`, report it next to the backend version so drift is visible.

## Report format

Produce a table — Check | Status (pass / warn / fail) | Detail | Remedy — followed by a short diagnosis paragraph: name the single most likely root cause if anything failed and give the exact first command to run. If everything passes, say the stack is healthy and print the URLs (`http://localhost:<port>`, `/admin`) and the installed versions. Do not fix anything yourself — this command diagnoses; the user decides.
