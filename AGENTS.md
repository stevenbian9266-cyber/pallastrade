# PallasTrade — Agent Instructions (Root)

You are working on **PallasTrade Commerce**, a self-hosted e-commerce platform built on Ruby on Rails. This is a monorepo. This file is the single source of truth for all AI agents. Component-level files (`CLAUDE.md` / `AGENTS.md`) supplement it.

---

## 1. Repository Layout

| Directory | Purpose | Can Modify? |
|---|---|---|
| `backend/` | Rails application root | — |
| `backend/app/` | Customer application code (models, controllers, decorators, subscribers) | ✅ Yes, freely |
| `backend/pallastrade_gems/` | Owned framework source — 13 local gems | ⚠️ Prefer Decorator/DI first. Direct changes OK with `# PALLAS-CUSTOM:` comment |
| `backend/db/migrate/` | Past database migrations | 🚫 Never modify. Create a NEW migration instead |
| `backend/db/schema.rb` | Auto-generated schema snapshot | 🚫 Never hand-edit |
| `backend/Gemfile.lock` | Auto-generated dependency lock | 🚫 Never hand-edit |
| `storefront/` | Next.js customer-facing storefront | — |
| `storefront/src/` | Storefront source code | ✅ Yes, freely |
| `platform/` | TypeScript monorepo (packages) | — |
| `platform/packages/sdk/` | `@pallastrade/sdk` — Store API client | ✅ Yes |
| `platform/packages/admin-sdk/` | `@pallastrade/admin-sdk` — Admin API client | ✅ Yes |
| `platform/packages/cli/` | `@pallastrade/cli` — Project management CLI | ✅ Yes |
| `platform/packages/dashboard/` | `@pallastrade/dashboard` — React SPA admin | ✅ Yes |
| `platform/packages/dashboard-ui/` | `@pallastrade/dashboard-ui` — Design system (Shadcn + Tailwind) | ✅ Yes |
| `platform/packages/dashboard-core/` | `@pallastrade/dashboard-core` — Plugin framework | ✅ Yes |
| `ai/` | Agent skills and safety hooks | — |
| `ai/skills/` | 24 domain-specific SKILL.md files | ✅ Yes, update as code evolves |
| `ai/hooks/` | Safety hooks (bash scripts) | ⚠️ Understand full impact before modifying |
| `.github/workflows/` | GitHub Actions CI definitions | ⚠️ Understand full impact before modifying |
| `harness/` | Engineering policies and configs | ✅ Yes (active construction zone) |
| `scripts/harness/` | Harness CLI Node.js source | ✅ Yes (active construction zone) |

---

## 2. Before Writing Any Code

1. **Read this AGENTS.md first.** You are doing that now.
2. **Read the relevant Skill file.** Map task domain → `ai/skills/<domain>/SKILL.md`. Use `pallastrade-customization` FIRST when the right customization approach isn't obvious.
3. **Run `harness affected`** to see what your change will impact.
4. **Check the anti-patterns list (§5).** Know what NOT to do before you start.

---

## 3. Customization Decision Tree (MUST follow this order)

Lower number = safer upgrade, cleaner code, easier to test.

| Priority | Approach | When to Use | Deep-Dive Skill |
|---|---|---|---|
| 1 | **Settings / `PallasTrade::Config`** | Toggle behavior at runtime | (straightforward) |
| 2 | **Events + Subscribers** | Side effects: sync to ERP, send notifications, update caches | `pallastrade-events-webhooks` |
| 3 | **Dependency Injection** (`PallasTrade.dependencies`) | Swap how a core service computes (cart, tax, search, checkout) | `pallastrade-dependencies` |
| 4 | **Admin Extensions / Ransack** | Customize admin UI, sidebar, tables, search | `pallastrade-admin` / `pallastrade-api-v3` |
| 5 | **Generators** (`pallastrade:api_resource` / `pallastrade:model`) | Brand-new model + API endpoint | `pallastrade-resource` |
| 6 | **Decorators** (`Module#prepend`) | Structural changes to existing PallasTrade classes | `pallastrade-decorators` |
| 7 | **Extensions (gems)** | Share customization across multiple PallasTrade apps | `pallastrade-extensions` |

**If you skip to a lower number without trying higher ones first, your PR will be flagged by CI.**

---

## 4. API v3 Rules (NEVER violate)

- All API routes under `/api/v3/store/` (customer) or `/api/v3/admin/` (admin)
- All IDs in API responses are **prefixed**: `prod_xxx`, `order_xxx`, `variant_xxx`, `brand_xxx`, etc.
- Never expose raw integer primary keys in any API response body
- Always scope queries through `current_store`:
  ```ruby
  current_store.products.where(active: true)  # ✅ Correct
  PallasTrade::Product.where(active: true)     # 🚫 Cross-store data leak
  ```
- List endpoints return `{ data: [...], meta: { count, current_page, total_pages } }`
- Single-resource endpoints return `{ data: { id, type, attributes } }`
- Use `expand=...` for sideloading, `fields=...` for sparse fieldsets
- Auth: Store API = publishable key (`pk_...`), Admin API = secret key (`sk_...`) or JWT

---

## 5. Anti-Patterns (BLOCKED by CI — not just "suggested")

| # | NEVER do this | Do this instead | CI Rule |
|---|---|---|---|
| AP-001 | `style={{ }}` inline styles in JSX/TSX | Use Tailwind classes (`className="..."`) or design-system component props | `anti-patterns.json` AP-001 |
| AP-002 | `fetch('/api/v3/...')` raw HTTP calls | Use `@pallastrade/sdk` (Store) or `@pallastrade/admin-sdk` (Admin) typed client | AP-002 |
| AP-003 | `Model.create(...)` outside `spec/` files | Use Factory Bot in tests, Service objects in application code | AP-003 |
| AP-004 | `after_save :do_something` callbacks | Create a `PallasTrade::Subscriber` subclass and register it | AP-004 |
| AP-005 | `PallasTrade::Order.all` without store scope | Always chain from `current_store`: `current_store.orders` | AP-005 |
| AP-006 | Hardcoded hex colors (`#ff0000`) in components | Use CSS custom properties from design tokens (`var(--color-brand-primary)`) | AP-006 |
| AP-007 | Hand-editing auto-generated files | Run the generation command, then commit the result | `generated:check` |

---

## 6. Minimum Verification Per Change Type

| What you changed | Minimum check | Est. Time |
|---|---|---|
| Any Ruby file | `harness check --profile quick` | ≤5 min |
| Model / DB schema / migration | + `harness check --profile full` | ≤45 min |
| API endpoint (new/modified) | + `harness generated:check` (OpenAPI + SDK types) | ≤5 min |
| UI component / style | + `harness e2e dashboard` or `harness e2e storefront` | ≤15 min |
| Payment logic | + payment sandbox gate | ≤30 min |
| AI Skill file (`ai/skills/`) | + `harness eval ai --check-freshness` | ≤2 min |
| Framework version upgrade | + `harness upgrade:audit` + `harness upgrade:verify` | ≤20 min |
| Any change | `harness doc-impact --base origin/main` — checks knowledge docs are synced | ≤1 min |

---

## 7. Knowledge Sync Rules — Code Changed = Docs MUST Sync

**When your PR changes files matching the left column, it MUST also update the corresponding docs in the right column. CI enforces this.**

| Code Change (Glob) | Knowledge Docs That MUST Be Updated |
|---|---|
| `backend/app/models/**/*.rb` (new/modified) | `ai/skills/pallastrade-catalog/SKILL.md` or `pallastrade-data-model/SKILL.md` |
| `backend/app/controllers/**/api/v3/**/*.rb` (new/modified) | `ai/skills/pallastrade-api-v3/SKILL.md` + `platform/docs/store.yaml` or `admin.yaml` |
| `backend/app/decorators/**/*.rb` (new/modified) | `ai/skills/pallastrade-decorators/SKILL.md` + relevant domain skill |
| `backend/app/subscribers/**/*.rb` (new/modified) | `ai/skills/pallastrade-events-webhooks/SKILL.md` |
| `storefront/src/components/**/*.tsx` (new/modified) | `ai/skills/pallastrade-storefront/SKILL.md` §Components |
| `storefront/src/app/**/*.tsx` (new page/route) | `ai/skills/pallastrade-storefront/SKILL.md` + E2E test |
| `*.css` / `tailwind.config.*` (modified) | `ai/skills/pallastrade-storefront/SKILL.md` §Style Guide or `pallastrade-admin/SKILL.md` §Styling |
| `platform/packages/dashboard-ui/**/*.tsx` (modified) | Component documentation + Storybook story (if applicable) |
| `ai/skills/**/SKILL.md` (modified) | `harness/scenarios/scenarios.json` — add/update an Eval Scenario |
| `harness/policies/anti-patterns.json` (modified) | This `AGENTS.md` §5 — ensure the anti-pattern table matches |
| `AGENTS.md` / `CLAUDE.md` (modified) | Run `harness docs:check` to verify no broken references |
| Any file (framework version upgrade) | ALL Skill files — `harness eval ai --check-freshness` |

**CI command**: `harness doc-impact --base origin/main` checks your PR against this table. If any required doc update is missing, the PR is blocked with status `docs-required`.

---

## 8. Dangerous Operations (PHYSICALLY BLOCKED)

These commands are intercepted by safety hooks at the tool-call level, not the prompt level. The AI literally cannot execute them.

- `rake db:drop` / `rails db:drop` / `rake db:reset` / `rails db:reset`
- `DROP TABLE pallastrade_*` / `DROP DATABASE`
- `DELETE FROM pallastrade_orders` (and similar mass deletes on core tables)
- `PallasTrade::Order.delete_all` / `PallasTrade::Order.destroy_all`
- `git push --force origin main` / `git push --force origin master`
- Writing secrets (`sk_live_...`, `AKIA...`, `ghp_...`) into source files

**Bypass**: Set `PALLASTRADE_HOOKS_DISABLE=1` and run the command manually in a terminal (not through the AI tool invocation). This is for emergencies only.
