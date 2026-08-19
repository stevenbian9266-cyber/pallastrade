# PallasTrade Agent Skills

Agent skills for [PallasTrade Commerce](https://pallastrade.cn) — works with Claude Code, Codex, Cursor, Copilot, Cline, Aider, Zed, Windsurf, OpenCode, and 60+ other agentic CLIs.

## Install

```bash
npx skills add stevenbian9266-cyber/pallastrade
```

That's it. The [`skills`](https://github.com/vercel-labs/skills) CLI auto-detects which agent(s) you have installed and copies the skill files into each agent's native location. Works in any project — new or existing.

Want to see what's available without installing?

```bash
npx skills add stevenbian9266-cyber/pallastrade --list
```

Want a specific subset?

```bash
npx skills add stevenbian9266-cyber/pallastrade --skill pallastrade-api-v3 --skill pallastrade-checkout
```

Update later:

```bash
npx skills update
```

## What ships

### 25 skills

| Skill | When it activates |
|---|---|
| `pallastrade-project` | General PallasTrade project context — conventions, customization patterns, common commands. |
| `pallastrade-customization` | Decision tree for "where does my customization belong" — routes to the right specific skill. Use FIRST when the pattern isn't obvious. |
| `pallastrade-resource` | Adding a new model + API endpoint via the `pallastrade:api_resource` generator, or a model-only resource via `pallastrade:model`. |
| `pallastrade-decorators` | Extending existing PallasTrade models/controllers via decorators (`Module#prepend`). |
| `pallastrade-dependencies` | Swapping core PallasTrade services via `PallasTrade.dependencies` — cart, checkout, ability, serializers. Includes the introspection rake tasks. |
| `pallastrade-api-v3` | PallasTrade REST API v3 conventions — Store vs Admin surfaces, auth (pk_/sk_/JWT), scopes, prefixed IDs, envelope, Ransack filters. |
| `pallastrade-typescript-sdk` | `@pallastrade/sdk` + `@pallastrade/admin-sdk` — auth modes, types, Zod, webhooks, retry config, MSW, extension patterns. |
| `pallastrade-cli` | `pallastrade api` — call/inspect the Admin API from the terminal (gh api-style verbs, offline endpoint/schema discovery, credential layers). Especially for debugging. |
| `pallastrade-data-model` | Domain model questions — Orders, LineItems, Variants, Stores, Channels, Markets. |
| `pallastrade-events-webhooks` | Subscribers + outbound webhooks (HMAC, retry, auto-disable). |
| `pallastrade-extensions` | Installing third-party gems (Stripe, Adyen, etc.) or building your own. |
| `pallastrade-catalog` | Products, Variants, Options, Categories, search, images. |
| `pallastrade-checkout` | Cart pipeline, order state machine, payment sessions, custom checkout flow. |
| `pallastrade-payments` | Payment methods, gateways, refunds, gift cards, store credits. |
| `pallastrade-promotions` | Promotion rules, actions, calculators, coupon codes. |
| `pallastrade-pricing` | Variant prices, multi-currency, price lists, EU Omnibus / PriceHistory. |
| `pallastrade-shipping-fulfillment` | Shipments, methods, rates, stock locations, returns. |
| `pallastrade-admin` | Customizing the PallasTrade admin (`pallastrade_admin` gem). |
| `pallastrade-storefront` | The Next.js storefront and `@pallastrade/sdk`. |
| `pallastrade-i18n` | UI translations (`PallasTrade.t` + YAML) and data translations (Mobility). |
| `pallastrade-testing` | RSpec + Factory Bot + Capybara, `pallastrade_dev_tools`, the `API v3 Store` shared context. |
| `pallastrade-security` | Rails security + PallasTrade-specific (CanCanCan scopes, encrypted preferences, webhook HMAC, PCI scope reduction). |
| `pallastrade-performance` | Cart pipeline, catalog N+1s, search latency, image processing, Sidekiq queue tuning. |
| `pallastrade-deployment` | Deploying to Heroku, Render, K8s, Docker — env vars, release commands, S3, Sidekiq. |

### `pallastrade-expert` subagent

Invoked by Claude (not the user) for multi-step PallasTrade work that benefits from a fresh context — audits, multi-resource API planning, checkout flow investigations.

### Two slash commands (Claude Code plugin only)

| Command | What it does |
|---|---|
| `/pallastrade:doctor` | Diagnose the local dev stack — Docker, containers, env, web, migrations, job queues — and prescribe the exact fix. |

### Two safety hooks (Claude Code only)

| Hook | What it does |
|---|---|
| `PreToolUse` on `Bash` | Blocks destructive database commands (`rake db:drop`, `PallasTrade::Model.delete_all`, raw `DROP TABLE pallastrade_*`, force-push to main/master). |
| `PostToolUse` on `Edit`/`Write`/`MultiEdit` | Warns when an edit adds a hardcoded secret (Stripe live keys, AWS access keys, GitHub PATs, OpenAI/Anthropic keys). |

Hooks honor `PALLASTRADE_HOOKS_DISABLE=1` as an escape hatch. Like the slash commands, they require the Claude Code plugin install path below — `npx skills add` installs skills, but not subagent, commands or hooks (the `${CLAUDE_PLUGIN_ROOT}` path resolution that hooks need only works under the plugin install).

## Claude Code: also get the safety hooks

If you're on Claude Code and want the safety hooks too, install as a plugin **from inside a Claude Code session**:

```text
/plugin marketplace add stevenbian9266-cyber/pallastrade
/plugin install pallastrade@pallastrade
```

Plugin install gives you everything `npx skills add` does **plus** subagent and the two slash commands and the two safety hooks. Use one path or the other — don't double-install (skills will collide).

## Cross-tool compatibility

`npx skills add` handles the per-tool delivery. Under the hood it places skill files where each tool expects:

| Tool | Where files land |
|---|---|
| Claude Code | `.claude/skills/`, `.claude/agents/` |
| Codex CLI | `AGENTS.md` walked from cwd to git root + per-skill files |
| Cursor | `.cursor/rules/*.mdc` |
| Copilot | `AGENTS.md` |
| Cline | `.clinerules/` |
| Aider, Zed, Windsurf, Amp | `AGENTS.md` |
| OpenCode | Native skill format |
| 60+ others | Each tool's native convention |

See [`vercel-labs/skills`](https://github.com/vercel-labs/skills) for the full agent matrix.

## Manual install (offline / air-gapped)

If you can't use `npx skills`:

```bash
git clone --branch main --single-branch https://github.com/stevenbian9266-cyber/pallastrade.git
mkdir -p .claude/skills .claude/agents
cp -R pallastrade/ai/skills/* .claude/skills/
cp -R pallastrade/ai/agents/* .claude/agents/
```

Or copy the [`AGENTS.md`](./AGENTS.md) to your project root for any AGENTS.md-aware agent.

## Maintenance

This plugin is maintained exclusively by Steven Bian. External code
contributions and pull requests are not accepted. Use the
[PallasTrade issue tracker](https://github.com/stevenbian9266-cyber/pallastrade/issues)
for bug reports and feature requests.
- `harness-standards-audit` — harness-standards-audit 领域（自动注册 2026-08-19）
- `harness-skill-author` — harness-skill-author 领域（自动注册 2026-08-19）
- `harness-prd` — harness-prd 领域（自动注册 2026-08-19）
- `harness-docs` — harness-docs 领域（自动注册 2026-08-19）
