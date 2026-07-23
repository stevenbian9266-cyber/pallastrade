# @pallastrade/cli

CLI for managing [PallasTrade Commerce](https://pallastrade.cn) projects.

Automatically included in projects created with [`create-pallastrade-app`](https://www.npmjs.com/package/create-pallastrade-app). Can also be installed standalone.

## Installation

Already included when you scaffold a project with `create-pallastrade-app`. To install separately:

```bash
npm install @pallastrade/cli
```

Or run directly with npx:

```bash
npx @pallastrade/cli <command>
```

Or install globally:

```bash
npm install -g @pallastrade/cli
pallastrade <command>
```

## Commands

Run these from your PallasTrade project directory.

### `pallastrade dev`

Run the app in the foreground — prints connection info, then streams web + worker logs (like `vite dev`).

```bash
pallastrade dev
```

Press `Ctrl+C` to stop web + worker. The databases (postgres, redis, meilisearch) keep running for a fast next boot — `pallastrade stop` shuts everything down.

### `pallastrade stop`

Stop all running services.

```bash
pallastrade stop
```

### `pallastrade update`

Pull the latest PallasTrade Docker image and recreate containers. Database migrations run automatically on startup via `db:prepare`.

```bash
pallastrade update
```

To pin a specific version, edit `PALLASTRADE_VERSION_TAG` in your `.env` file:

```
PALLASTRADE_VERSION_TAG=5.4
```

### `pallastrade eject`

Switch from the prebuilt Docker image to building from your local `backend/` directory. This lets you customize the Rails app — add gems, override models, add migrations, etc.

```bash
pallastrade eject
```

After ejecting, edit files in `backend/` and run `pallastrade dev` to rebuild and restart.

### `pallastrade logs [service]`

Stream logs from a service. Defaults to `web`.

```bash
pallastrade logs          # web server logs
pallastrade logs worker   # background job logs
```

### `pallastrade console`

Open an interactive Rails console inside the running container.

```bash
pallastrade console
```

### `pallastrade shell`

Open an interactive bash shell inside the web container. If the container is down, a one-off container is started against the same volumes instead.

```bash
pallastrade shell
pallastrade bash    # alias
```

### `pallastrade rspec`

Run the RSpec test suite inside the web container with `RAILS_ENV=test`. Everything after `rspec` is passed through to RSpec.

```bash
pallastrade rspec                                      # full suite
pallastrade rspec spec/models/product_spec.rb          # one file
pallastrade rspec spec/models/product_spec.rb:15       # one example
pallastrade rspec --format documentation
```

Before the first run, create the test database with `pallastrade rails db:test:prepare`.

### `pallastrade user create`

Create an admin user. Prompts interactively for email and password, or accepts flags for scripting.

```bash
# Interactive
pallastrade user create

# Non-interactive
pallastrade user create --email admin@example.com --password secret123
```

The user is automatically assigned the `admin` role on the default store.

### `pallastrade api-key create`

Create a Store API (publishable) or Admin API (secret) key. Prompts interactively for name and type, or accepts flags.

```bash
# Interactive
pallastrade api-key create

# Non-interactive
pallastrade api-key create --name "My Storefront" --type publishable
pallastrade api-key create --name "Admin Integration" --type secret --scopes read_orders,write_products
```

Secret keys require at least one scope (`read_all` for a read-only key, `write_all` for full access, or granular `read_*`/`write_*` pairs).

**Important:** Secret key tokens are displayed only once at creation time and cannot be retrieved later. Save them immediately.

### `pallastrade api-key list`

List all API keys for the default store with their name, type, token/prefix, creation date, and status.

```bash
pallastrade api-key list
```

### `pallastrade api-key revoke`

Revoke an API key by its token (publishable) or token prefix (secret).

```bash
pallastrade api-key revoke pk_abc123def456...
```

### `pallastrade api`

Call the Admin API directly with generic `get`/`post`/`patch`/`delete` commands. Works against any PallasTrade 5.5+ instance — inside a project it self-provisions a **read-only** key via the dev stack on first use (saved to `.pallastrade/credentials.json`, gitignored). For other servers set `PALLASTRADE_API_KEY` (the host defaults to `http://localhost:3000`; add `PALLASTRADE_BASE_URL` for a remote store) or save a profile with `pallastrade auth login`.

```bash
pallastrade api get /products -q status_eq=active --sort -created_at --limit 10
pallastrade api get /orders/ord_x8k2J9aQ --expand items,payments
pallastrade api post /products -d '{"name":"Classic Tee","prices":[{"currency":"USD","amount":"29.99"}]}'
pallastrade api patch /orders/ord_x8k2J9aQ/cancel
pallastrade api delete /products/prod_86Rf07xd

pallastrade api endpoints --resource orders     # endpoints + required scopes (offline)
pallastrade api schema "POST /orders"           # request/response schema (offline)
pallastrade api status                          # resolved credentials + server check
```

Output is JSON on stdout — indented and colored in a terminal, compact and uncolored when piped (so it feeds cleanly into `jq`). `--format table` renders collections for humans. `--fields name,price` trims the response (the `id` is always included). API errors exit `1` with the error envelope on stderr — scope denials include the exact `--scopes` remediation.

### `pallastrade completion`

Output a shell completion script (`bash`, `zsh`, or `fish`). Tab-completion suggests resource paths, Ransack predicate stems, and scope names — offline from the bundled spec.

```bash
eval "$(pallastrade completion zsh)"     # add to ~/.zshrc (bash/fish also supported)
```

### `pallastrade auth`

Manage saved Admin API credentials for remote stores (profiles in `~/.config/pallastrade/config.json`).

```bash
pallastrade auth login --profile prod --base-url https://store.example.com   # key read from a prompt
pallastrade api get /orders --profile prod
pallastrade auth status
pallastrade auth list
pallastrade auth logout --profile prod
```

### `pallastrade seed`

Run database seeds.

```bash
pallastrade seed
```

### `pallastrade sample-data`

Load sample products, categories, customers, and images.

```bash
pallastrade sample-data
```

## How It Works

The CLI detects your project by looking for `docker-compose.yml` in the current directory. All commands execute via `docker compose` against the running PallasTrade containers.

- **Port** is read from `PALLASTRADE_PORT` in your `.env` file (default: `3000`)
- **User and API key commands** run Ruby scripts via `docker compose exec web bin/rails runner`
- **Service commands** (`dev`, `stop`, `update`) are thin wrappers around `docker compose`

## Using with npm scripts

Projects created with `create-pallastrade-app` include convenience scripts in `package.json`:

```bash
npm run dev             # pallastrade dev
npm run stop            # pallastrade stop
npm run update          # pallastrade update
npm run eject           # pallastrade eject
npm run logs            # pallastrade logs
npm run logs:worker     # pallastrade logs worker
npm run console         # pallastrade console
npm run seed            # pallastrade seed
npm run load-sample-data # pallastrade sample-data
```

## Learn More

- [PallasTrade Documentation](https://pallastrade.cn/docs)
- [Store API Reference](https://pallastrade.cn/docs/api-reference/introduction)
- [create-pallastrade-app](https://www.npmjs.com/package/create-pallastrade-app)
- [PallasTrade GitHub](https://github.com/stevenbian9266-cyber/pallastrade)
