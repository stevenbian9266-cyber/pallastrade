# PallasTrade — Agent Instructions (Root)

You are working on **PallasTrade Commerce**, a self-hosted e-commerce platform built on Ruby on Rails. This is a monorepo. This file is the single source of truth for all AI agents. Component-level files (`CLAUDE.md` / `AGENTS.md`) supplement it.

---

## 0. AI Coding 文件导航地图（每会话必读）

> 本表是 AI 执行 coding 任务的**唯一文件路由表**。任务开始先查 §0.2 任务路由表，
> 按需读取对应文件。冲突时以 §0.3 冲突裁决规则为准。
> ⚠️ 新增规范文件必须登记到 §0.1，否则视为未正式纳入。

### 0.1 规范文件总表

| 文件 | 类别 | 权威角色 | 何时读取 | 更新责任人 |
|---|---|---|---|---|
| `AGENTS.md`（本文件） | 自动注入 | **导航入口 + 全局规范权威** | 每会话 | 工程负责人 |
| `.github/copilot-instructions.md` | 自动注入 | 强制命令速查（R0-R8） | 每会话 | 工程负责人 |
| `backend/CLAUDE.md` | 后端规范 | 后端权威 | 涉及 backend 代码 | 后端维护者 |
| `platform/CLAUDE.md` | 平台规范 | 平台权威 | 涉及 platform 代码 | 平台维护者 |
| `storefront/CLAUDE.md` | 商城规范 | 商城权威（含 Code Style/样式规范） | 涉及 storefront 代码 | 商城维护者 |
| `ai/skills/*/SKILL.md`（25 个） | Skill | 领域知识权威 | gate 强制 + §0.2 路由 | 各领域维护者 |
| `harness/policies/anti-patterns.json` | 反模式 | **反模式唯一权威**（机器执行） | CI 强制；违规检查 | 工程负责人 |
| `harness/policies/task-rules.json` | 任务规则 | 任务规则权威 | 新功能/优化 | 工程负责人 |
| `harness/policies/prd-categories.json` | PRD 分类 | 分类权威 | `prd new` | 工程负责人 |
| `harness/scenarios/scenarios.json` | 场景库 | Eval 权威 | 能力变更 | 工程负责人 |
| `docs/standards/README.md` | 规范索引 | **规范文件指针权威** | 不确定规范位置时 | 工程负责人 |
| `docs/prd/_TEMPLATE.md` | PRD 模板 | PRD 权威模板 | 一句话需求 | AI |
| `ai/commands/doctor.md` | AI 命令 | 命令定义 | 运维诊断 | AI 维护者 |
| `ai/agents/pallastrade-expert.md` | AI 代理 | 专家代理定义 | 多步调研 | AI 维护者 |
| `ai/memories/*.md` | 记忆 | 决策记录 | 重要决策/续接任务 | AI |

### 0.2 任务 → 必读文件路由表

| 任务类型 | 必读文件（按顺序） |
|---|---|
| 新功能/一句话需求 | §0.1 → copilot-instructions → **pallastrade-prd** → **pallastrade-customization** → 领域 skill → 对应层 CLAUDE.md → task-rules.json |
| Bug 修复 | §0.1 → copilot-instructions → 领域 skill → 对应层 CLAUDE.md → anti-patterns.json |
| 接口增删改查 | §0.1 → **pallastrade-api-v3** → 对应层 CLAUDE.md → `backend/public/api-docs/*.yaml` → generated-check |
| UI/组件/样式 | §0.1 → **pallastrade-storefront** → storefront/CLAUDE.md → docs/standards → anti-patterns.json（AP-001/006） |
| 模型/DB 变更 | §0.1 → **pallastrade-data-model** → 领域 skill → 对应层 CLAUDE.md |
| 支付相关 | §0.1 → **pallastrade-payments** → **pallastrade-security** → 对应层 CLAUDE.md |
| 安全/权限 | §0.1 → **pallastrade-security** → anti-patterns.json → §8 危险操作 |
| 事件/订阅者 | §0.1 → **pallastrade-events-webhooks** → 对应层 CLAUDE.md |
| SDK/CLI/平台 | §0.1 → **pallastrade-typescript-sdk** / **pallastrade-cli** → platform/CLAUDE.md |
| 部署/配置 | §0.1 → **pallastrade-deployment** → `.env.example` → 部署 README |
| i18n | §0.1 → **pallastrade-i18n** → 对应层 CLAUDE.md |
| 测试补充 | §0.1 → **pallastrade-testing** → 对应层测试约定 |

### 0.3 权威与冲突裁决

- 每个概念只有一个**唯一权威**（§0.1 权威角色列），其他文件为指针/摘要
- 冲突裁决顺序：`harness/policies/anti-patterns.json` > 本文件 §5/§6 > 各层 CLAUDE.md > skill 细节
- 新增规范文件 → 必须登记到 §0.1；修改权威文件 → 按 §7 知识同步矩阵更新指针文件

### 0.4 分支策略

- 日常开发在 `dev`（本地 + 远程），提交/推送均在 `dev`；`main` 为生产部署分支，**仅接受 `dev` 合并**，禁止直接向 `main` 推送开发提交
- 发布流程：`dev` 推入 → CI 验证（所有组件 workflow 监听 `[main, dev]`）→ `dev` 合并 `main` → 推送 `main`（部署/打 Tag）
- **gate 绑定当前分支**：在哪个分支开 gate，就在哪个分支完成提交；切分支前先完成 gate
- 详见 `scripts/release/README.md` §分支策略

---

## 1. Repository Layout

| Directory | Purpose | Can Modify? |
|---|---|---|
| `backend/` | Rails application root | — |
| `backend/app/` | Customer application code (models, controllers, decorators, subscribers) | ✅ Yes, freely |
| `backend/pallastrade_gems/` | Framework source — local gems. **This is a PallasTrade team product.** Modify gem files directly. Git tracks all changes; upgrades are merges, not replacements. Only Host App override for net-new modules (e.g., `ai/`). Mark modified gem files with `# PALLAS-CUSTOM:` comment | ✅ Yes, freely |
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

### � Step -1: MANDATORY Gate (ALL tasks — NO exceptions — enforced by process.exit(1))

**Before you invoke any file creation or edit tool, you MUST run:**

```bash
node scripts/harness/cli.mjs gate --task "<brief description>" [--type feature|bugfix|style]
```

This creates a gate file at `harness/gates/GATE-*.json` and outputs a checklist.
The command **always exits with code 1** until every check is cleared via `gate:clear`.

**The AI is physically forbidden from calling `create_file`, `replace_string_in_file`, or `multi_replace_string_in_file` while the active gate's exit code is non-zero.** Check status with:

```bash
node scripts/harness/cli.mjs gate:clear --gate <GATE-ID> --clear <check-id>
```

Only when all checks are cleared and `gate:clear` exits 0 may the AI proceed to implementation.

**Gate 期间的例外（仅允许以下文件操作）：**

| 允许 | 目录/场景 | 原因 |
|---|---|---|
| ✅ `create_file` / 编辑 | `harness/requirements/` | 需求文档，必须创建才能清 `create-req-doc` |
| ✅ `create_file` / 编辑 | `harness/gates/` | Gate 状态文件 |
| ✅ 读取任意文件 | 所有目录 | 跨层搜索、读 Skill 文件 |
| 🚫 其他所有文件操作 | — | 必须先清 gate |

**新建 vs 修改的判断规则：**

```
Gate cleared 开始编码后：
  改已有文件 → ✅ 直接改
  必须新建文件才能实现需求 → ✅ 允许（在 REQ doc 中说明原因）
  改已有文件就能实现却新建了文件 → 🚫 违规。先检查跨层搜索是否遗漏
```

### �🔍 Step 0: Mandatory Cross-Layer Search (ALL tasks — NO exceptions)

**Every task, regardless of type, starts here.** PallasTrade is a layered framework.
Finding a capability in one layer does NOT mean it exists in another.
Skipping this step is the #1 cause of duplicated/conflicting code.

| Layer | Search Path | What to Search For |
|---|---|---|
| **App** (your code) | `backend/app/` | models, controllers, views, decorators, subscribers, services |
| **Core** (framework models) | `backend/pallastrade_gems/pallastrade_core/app/` | models, services, state machines, associations |
| **API** (framework endpoints) | `backend/pallastrade_gems/pallastrade_api/app/` | controllers, serializers, routes |
| **Admin** (framework admin UI) | `backend/pallastrade_gems/pallastrade_admin/app/` | controllers, views, helpers, navigation |
| **Storefront** | `storefront/src/` | components, pages, layouts |
| **Platform** | `platform/packages/` | SDK, Admin SDK, Dashboard, CLI |

**Search protocol:**

1. Identify 2-3 domain keywords (and their synonyms) from the task description
2. Search EVERY layer above independently using those keywords
3. For each found file, answer: "Does this already satisfy the requirement?"
4. If controller not found by model name, try admin resource name (e.g., `Category` → search `taxon`)
5. Document findings in the response — even if "nothing found"

**Three anti-patterns that cause missed capabilities:**

| # | Anti-Pattern | What Happens | Rule |
|---|---|---|---|
| AP-SEARCH-1 | **STOP_EARLY** | Find model in core → stop searching → miss admin controller in admin gem | Never stop at first match. Always search all 6 layers. |
| AP-SEARCH-2 | **NAME_MISMATCH** | Search "categories_controller" → not found → assume absent. Real name: "taxons_controller". | Search by domain concept, not exact class name. |
| AP-SEARCH-3 | **LAYER_ASSUME** | Model exists in core → assume Admin UI also exists → skip admin gem search. Reality: each layer is independent. | Never assume. Always verify each layer. |

### 📋 Step 1: Task-Specific Understanding

1. **Read the relevant Skill file.** Map task domain → `ai/skills/<domain>/SKILL.md`. Use `pallastrade-customization` FIRST when the right approach isn't obvious.
2. **Run `harness affected`** to see what your change will impact.
3. **Check the anti-patterns list (§5).** Know what NOT to do before you start.

### ⏸️ Step 2: Confirmation Gate (新功能 / 功能优化 ONLY)

For **新功能** and **功能优化**, after completing Steps 0-1, AI MUST:

1. **Create a requirements document** using `harness/requirements/_TEMPLATE.md`
   - Include the cross-layer search results from Step 0
2. **Save it** as `harness/requirements/REQ-{YYYYMMDD}-{slug}.md`
3. **Present to user and WAIT for confirmation** before writing ANY code
4. After user confirms, output design document → Go/No-Go → implementation

For **Bug修复 / 样式调整**, Steps 0-1 are sufficient to proceed — but cross-layer search (Step 0) is still mandatory.

**Violating Step 0 (skipping cross-layer search) or Step 2 (writing code before user confirmation for new features) is a process error.**

### 📋 Step 3: PRD-Driven Workflow (一句话需求 → PRD → 实施)

For tasks originating from a **one-line requirement**（一句话需求）, the AI MUST follow the PRD workflow defined in **`ai/skills/pallastrade-prd/SKILL.md`**:

1. **PRD generation** — expand the one-liner into a detailed PRD at `docs/prd/{category}/PRD-{YYYYMMDD}-{category}-{slug}.md` (template: `docs/prd/_TEMPLATE.md`; category auto-detected via `harness/policies/prd-categories.json`). Update `docs/prd/README.md` index.
2. **Dedupe first** — search existing PRDs + all 6 layers before creating (AP-SEARCH).
3. **User confirmation** — PRD → `approved` only after explicit user confirmation.
4. **Gate + REQ** — `harness gate` (feature checks now include `create-prd-doc` + `read-skill-prd`), then generate REQ at `harness/requirements/REQ-*.md`.
5. **Tests & acceptance** — every AC in the PRD must map to a test tagged `# PRD-xxx AC-x`; verify with `harness prd verify --id PRD-xxx`.
6. **API docs** — interface changes MUST sync `backend/public/api-docs/{store,admin}.yaml` + `platform/docs/api-reference/` (verify with `generated:check`).
7. **Knowledge sync gate** — before closing `verify-test`, run `harness sync-check --id PRD-xxx` and resolve every asset in the §7 knowledge matrix (Skill / README / Agent files / style & technical standards / anti-patterns / scenarios). Record conclusions in PRD §9/§10.

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
| 8 | **Direct Gem Modification** | Modify, add, or replace existing Gem views, controllers, or models. This project uses Git to track changes — upgrades are merges. | `pallastrade-admin` |

**For Admin views specifically**: Modify files directly in `backend/pallastrade_gems/pallastrade_admin/app/views/`. Add `# PALLAS-CUSTOM: <reason>` as the first line. Net-new modules (no Gem counterpart) go in `backend/app/views/`.

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
| AP-008 | Copying Gem view files to Host App for modification | Modify the Gem source file directly in `pallastrade_gems/pallastrade_admin/app/views/`. Add `# PALLAS-CUSTOM:` comment. Host App `backend/app/views/` is for new modules only. | `anti-patterns.json` AP-008 |
| AP-009a | `redirect('/hardcoded-path')` (hardcoded string) without a self-redirect guard → infinite loop. **Guard-aware**: dynamic targets (template literals / variables) and redirects guarded by a condition (`if (target !== currentPath)`, pathname rewrite) are exempt | Add guard: `if (target !== currentPath) { redirect(target); }`, or use a dynamic/template-literal target | `anti-patterns.json` AP-009a (guard-aware) |
| AP-009b | `.catch(() => [])` collapses unknown→empty → triggers loop | Return `null` on API failure; handle unknown state explicitly with degraded UI | `anti-patterns.json` AP-009b |

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
| Any change | `harness doc-impact --base origin/main` — checks knowledge docs are synced | ≤1 min |

### Verification Evidence Required

Before clearing `verify-test`, provide objective evidence:

| What you changed | Required evidence |
|---|---|
| UI (view/component/style) | Screenshot or DOM snapshot showing corrected state |
| Backend logic | Rails log line showing `Completed 200 OK` or `302 Found` |
| Data fix | DB query result before/after |
| Config-only change | Server restart log confirming new config loaded |

**"no test needed" is not valid for UI or backend logic changes.**

---

## 7. Knowledge Sync Rules — Code Changed = Docs MUST Sync

**When your PR changes files matching the left column, it MUST also update the corresponding docs in the right column. CI enforces this.**

| Code Change (Glob) | Knowledge Docs That MUST Be Updated |
|---|---|
| `backend/app/models/**/*.rb` (new/modified) | `ai/skills/pallastrade-catalog/SKILL.md` or `pallastrade-data-model/SKILL.md` |
| `backend/app/controllers/**/api/v3/**/*.rb` (new/modified) | `ai/skills/pallastrade-api-v3/SKILL.md` + `backend/public/api-docs/{store,admin}.yaml` + `platform/docs/api-reference/` |
| `backend/app/decorators/**/*.rb` (new/modified) | `ai/skills/pallastrade-decorators/SKILL.md` + relevant domain skill |
| `backend/app/subscribers/**/*.rb` (new/modified) | `ai/skills/pallastrade-events-webhooks/SKILL.md` |
| `storefront/src/components/**/*.tsx` (new/modified) | `ai/skills/pallastrade-storefront/SKILL.md` §Components |
| `storefront/src/app/**/*.tsx` (new page/route) | `ai/skills/pallastrade-storefront/SKILL.md` + E2E test |
| `*.css` / `tailwind.config.*` (modified) | `ai/skills/pallastrade-storefront/SKILL.md` §Style Guide or `pallastrade-admin/SKILL.md` §Styling |
| `docs/prd/**` (new/modified PRD) | `ai/skills/pallastrade-prd/SKILL.md` + `docs/prd/README.md` index |
| `harness/policies/prd-categories.json` (modified) | `ai/skills/pallastrade-prd/SKILL.md` |
| `harness/policies/{anti-patterns,task-rules}.json` (modified) | This `AGENTS.md` §5 + `.github/copilot-instructions.md` |
| `ai/commands/**` / `ai/agents/**` (modified) | `ai/README.md` |
| `platform/packages/{cli,sdk,create-pallastrade-app}/**` (modified) | `platform/README.md` or `platform/packages/README.md` |
| `scripts/harness/**` (modified) | `AGENTS.md` + `ai/skills/pallastrade-prd/SKILL.md` + `harness/scenarios/scenarios.json` |
| `ai/skills/**/SKILL.md` (modified) | `harness/scenarios/scenarios.json` — add/update an Eval Scenario |
| `AGENTS.md` / `CLAUDE.md` (modified) | Run `harness docs:check` to verify no broken references |
| Any file (framework version upgrade) | ALL Skill files — `harness eval ai --check-freshness` |

**CI command**: `harness doc-impact --base origin/main` checks your PR against this table. If any required doc update is missing, the PR is blocked with status `docs-required`.

**Knowledge sync gate**: for PRD-driven tasks, before closing `verify-test`, run `harness sync-check --id PRD-xxx` — it lists every knowledge asset (Skill / README / Agent files / style & technical standards / anti-patterns / scenarios) the change may require updating. Resolve each (update, or record "已评估，无需更新" in PRD §9/§10), then confirm with `harness sync-check --ack`.

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

### Physical Enforcement (agent-agnostic)

Beyond prompt-level rules, the repo has **git-level gates** that fire regardless
of which agent (Copilot / Codex / Claude Code) or human drives it:

- Root `lefthook.yml` — pre-commit runs the anti-pattern + AP-009 degraded-loop
  scans on **staged files only** (error severity blocks); pre-push runs
  `harness doc-impact`. Install once: `npm i && npx lefthook install`.
- `harness gate` supports task types: feature / bugfix / style / audit /
  research / docs / refactor / security / test. Gates bind branch + HEAD commit
  and record `--note` on each cleared check.
- Harness self-checks: `npm run test:harness` (node:test contract tests) and
  `harness eval-ai --scenarios` (GS scenario library validation).
