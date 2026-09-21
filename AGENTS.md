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
| `ai/skills/pallastrade-performance/SKILL.md` | Skill | 领域知识权威 | 涉及 performance 代码 | AI 维护 |
| `ai/skills/pallastrade-events-webhooks/SKILL.md` | Skill | 领域知识权威 | 涉及 events 代码 | AI 维护 |
| `ai/skills/pallastrade-i18n/SKILL.md` | Skill | 领域知识权威 | 涉及 i18n 代码 | AI 维护 |
| `ai/skills/pallastrade-testing/SKILL.md` | Skill | 领域知识权威 | 涉及 testing 代码 | AI 维护 |
| `ai/skills/pallastrade-deployment/SKILL.md` | Skill | 领域知识权威 | 涉及 deployment 代码 | AI 维护 |
| `ai/skills/pallastrade-payments/SKILL.md` | Skill | 领域知识权威 | 涉及 payment 代码 | AI 维护 |
| `ai/skills/pallastrade-data-model/SKILL.md` | Skill | 领域知识权威 | 涉及 data-model 代码 | AI 维护 |
| `ai/skills/pallastrade-api-v3/SKILL.md` | Skill | 领域知识权威 | 涉及 api 代码 | AI 维护 |
| `ai/skills/pallastrade-security/SKILL.md` | Skill | 领域知识权威 | 涉及 security 代码 | AI 维护 |
| `ai/skills/harness-docs/SKILL.md` | Skill | 领域知识权威 | 涉及 harness-docs 代码 | AI 维护 |
| `ai/skills/harness-prd/SKILL.md` | Skill | 领域知识权威 | 涉及 harness-prd 代码 | AI 维护 |
| `ai/skills/harness-skill-author/SKILL.md` | Skill | 领域知识权威 | 涉及 harness-skill-author 代码 | AI 维护 |
| `ai/skills/harness-standards-audit/SKILL.md` | Skill | 领域知识权威 | 涉及 harness-standards-audit 代码 | AI 维护 |
| `AGENTS.md`（本文件） | 自动注入 | **导航入口 + 全局规范权威** | 每会话 | 工程负责人 |
| `.github/copilot-instructions.md` | 自动注入 | 强制命令速查（R0-R8） | 每会话 | 工程负责人 |
| `backend/CLAUDE.md` | 后端规范 | 后端权威 | 涉及 backend 代码 | 后端维护者 |
| `platform/CLAUDE.md` | 平台规范 | 平台权威 | 涉及 platform 代码 | 平台维护者 |
| `storefront/CLAUDE.md` | 商城规范 | 商城权威（含 Code Style/样式规范） | 涉及 storefront 代码 | 商城维护者 |
| `ai/skills/*/SKILL.md`（29 个） | Skill | 领域知识权威 | gate 强制 + §0.2 路由 | 各领域维护者 |
| `harness/standards/*.json` | 规范注册表 | **机器可读开发规范索引**（不复制权威正文） | Change Plan / 开发监督 / 规范覆盖率检查 | 工程负责人 |
| `harness/policies/anti-patterns.json` | 反模式 | **反模式唯一权威**（机器执行） | CI 强制；违规检查 | 工程负责人 |
| `harness/policies/task-rules.json` | 任务规则 | 任务规则权威 | 新功能/优化 | 工程负责人 |
| `harness/policies/prd-categories.json` | PRD 分类 | 分类权威 | `prd new` | 工程负责人 |
| `harness.config.mjs` | Harness 项目配置 | **引擎配置权威**（Task/Brain/Risk/Evidence + layers/gates/standards/supervisor/docImpact/coverage/profiles/syncCheck） | 引擎配置相关任务；引擎默认值见独立包 `pallastrade-harness`（`bin/config-loader.mjs`） | 工程负责人 |
| `harness升级方案.md` | Harness 产品方案 | 下一代治理能力的已确认产品蓝图（具体规则仍以各权威文件为准） | Harness 能力规划/阶段升级 | 工程负责人 |
| `harness/scenarios/scenarios.json` | 场景库 | Eval 权威 | 能力变更 | 工程负责人 |
| `scripts/ci/prd-status-sync.mjs` | 工程脚本 | **PRD 状态一致性检查器**（README 索引 ↔ 文件头；`--check` / `--fix`） | PRD 状态变更 / 写 PRD 后 / pre-commit 失败时 | 工程负责人 |
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

### 0.4 分支策略（dev-only，2026-09-05）

- 远程仓库仅 `dev`（无 `main`、无 prod 服务器）；日常开发在 `dev`（本地 + 远程），提交/推送均在 `dev`；**发布 = 直接 push `dev`**（无 dev→main 合并）
- 发布流程：`dev` 推入 → CI 验证（所有组件 workflow 监听 `[dev]`）→ 服务器拉取式部署（pull-deploy.sh dev）
- **gate 绑定当前分支**：在哪个分支开 gate，就在哪个分支完成提交；切分支前先完成 gate
- 详见 `scripts/release/README.md` §分支策略（dev-only）与 `deploy/README.md`

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
| `node_modules/pallastrade-harness/` | Harness 引擎（独立 npm 包，`npx harness` 调用） | ✅ Yes |

---

## 2. Before Writing Any Code

### Step -2: MANDATORY Task Lifecycle (ALL mutation tasks)

Before opening a Gate, create or resume a persistent task and build its minimal context:

```bash
npx harness task start --title "<prefix：description>" --allow "<approved-glob>" --json
npx harness brain context --task <TASK-ID>
npx harness risk check --task <TASK-ID>
npx harness gate --task "<prefix：description>" --task-id <TASK-ID>
```

Task state is bound to repository/worktree/branch/HEAD. Use `task checkpoint`, `task resume`, and
`task handoff` for continuation; never recreate context from memory when a live task exists. Critical
tasks must also create and verify a manual-only recovery plan before completion. Legacy unbound Gates
may finish an already-running task, but every new Gate must use `--task-id`.

### � Step -1: MANDATORY Gate (ALL tasks — NO exceptions — enforced by process.exit(1))

**Before you invoke any file creation or edit tool, you MUST run**（命令与 copilot-instructions R1 相同）：

```bash
npx harness gate --task "<brief description>" --task-id <TASK-ID>
npx harness gate:clear --gate <GATE-ID> --clear <check-id>
```

- gate **非 0 退出** → **物理禁止** `create_file` / `replace_string_in_file` / `multi_replace_string_in_file`；清完 preparation 才实施
- task-bound `verify-test` 证据控制，不可手工 clear
- **Gate 期间仅允许**：编辑 `harness/requirements/`、`harness/gates/` + 读取任意文件；其他写操作必须先清 gate
- **新建 vs 修改**：能改已有→直接改；必须新增→REQ 说明原因；能改却新建→🚫 违规（先查跨层搜索）

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

新功能/优化：Steps 0-1 后用 `harness/requirements/_TEMPLATE.md` 创建 REQ（含 Step 0 跨层搜索结果）→ 呈现用户 **WAIT 确认** → 才写代码。Bug/样式：Steps 0-1 足够，但跨层搜索（Step 0）仍强制。

**违反 Step 0（跳过跨层搜索）或 Step 2（用户确认前写代码）= 流程错误。**（user-confirmed 细节见 copilot-instructions R3/R7）

### 📋 Step 3: PRD-Driven Workflow (一句话需求 → PRD → 实施)

一句话需求 MUST 遵循 **`ai/skills/pallastrade-prd/SKILL.md`**（命令与 7 步流程见 copilot-instructions R8，此处不重复）：

`harness prd new`（自动分类+查重 >0.3 阻止）→ 模板扩充到 `docs/prd/` → 用户确认（approved）→ gate + REQ → AC↔测试映射（`prd verify`）→ 接口文档同步（`generated:check`）→ 知识同步门（`sync-check --ack`）。

**违反 R8（跳过 PRD / 未确认 / 跳知识同步门）视为流程违规。**

### 🔎 Step 4: Development Supervisor（Harness 0.4+）

For feature / refactor / security tasks, use the machine-readable registry as a second control loop around implementation:

1. Before implementation, run `harness supervise plan --task "<task>" --allow <glob...>` to persist the allowed scope, risk, applicable standards, and required evidence.
2. During implementation and before commit, run `harness supervise diff --base <base> --plan <plan-path>`.
3. `assist` reports only; `guard` blocks error/critical findings; `strict` also blocks review-required findings. PallasTrade uses `guard`.
4. Every finding must include `standardId + file + line + risk + recommendation + confidence`; do not accept an untraceable prose-only judgment.
5. The supervisor complements `gate`, tests, anti-pattern scans, `sync-check`, and `doc-impact`; it does not replace them.

Gate phases are `preparation → implementation → verification → finished`: clearing preparation authorizes edits, while `verify-test` stays pending until objective evidence exists.

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
| AP-010 | `after_create :perform!` / 业务事务内同步 `Refunds::Execute`（资金副作用发生在 durable 行之前或长 DB 锁内） | 退款一律走 `Refunds::Request`（durable requested）→ `Refunds::ExecuteJob` 后台执行 | `anti-patterns.json` AP-010 |

---

## 6. Minimum Verification Per Change Type

| What you changed | Minimum check | Est. Time |
|---|---|---|
| Any Ruby file | `harness check --profile quick` | ≤5 min |
| 后台 i18n（`backend/config/locales/admin_*.zh-CN.yml`、`backend/spec/i18n/**`） | + `harness verify admin-i18n-rspec`（按功能域 en↔zh-CN **双向**键集相等 + 顶级键批次 + 已修缺陷回归；改 locale 键后**必须重启容器**才生效，Rails dev 不重载 locale 文件） | ≤2 min |
| Model / DB schema / migration | + `harness check --profile full` | ≤45 min |
| API endpoint (new/modified) | + `harness generated:check` (OpenAPI + SDK types) | ≤5 min |
| UI component / style | + `harness e2e dashboard` or `harness e2e storefront` | ≤15 min |
| Payment logic | + payment sandbox gate | ≤30 min |
| AI Skill file (`ai/skills/`) | + `harness eval ai --check-freshness` | ≤2 min |
| AI 供应商适配器 / 模型目录（`pallastrade_ai/**/providers/deep_seek.rb`、`catalogs/deep_seek.rb`、`config/initializers/provider_registry.rb`） | + `harness verify ai-provider-rspec`（结构化输出发 `json_object` 而非 DeepSeek 不支持的 `json_schema` + `system_instructions` 必须注入 system 消息 + `test_connection` 的 status 由响应派生、5xx/网络失败返回结构化失败 + 目录与 registry 两处模型 ID 同步） | ≤1 min |
| AI 输出校验 / 后台 AI 助手接线（`pallastrade_ai` 的 `gateway.rb`、`execute_run_job.rb`、`providers/*.rb`；`pallastrade_admin` 的 `ai_assist_controller.js` 与 5 个助手视图/`ai_assist_helper.rb`） | + `harness verify ai-output-validation-rspec`（声明 output schema 却无结构化输出 → 同步/异步都判失败且报 `ai_output_invalid`、Run 落 `failed` 且不写 artifact + 适配器错误码映射 + 助手容器的 `data-` 接线与文案 JSON 含兜底） | ≤1 min |
| `deploy/` scripts / repo-level guards (`tests/*.test.mjs`) | + `harness verify repo-guards-test` (前滚检测 + drill crontab 恢复 + PRD 状态同步 + AI 部署模板契约守卫 + AI 助手接线契约守卫 + **部署路径过滤守卫**（Dockerfile COPY 来源 ⊆ deploy.yml paths）) | ≤1 min |
| PRD 模板（`docs/prd/_TEMPLATE.md`） | + `harness verify repo-guards-test`（17 节结构守卫：章节序列 §0–§16 / UI·UX·数据与埋点子节 / 写作要求 / SKILL·场景库·promptfoo 跨文件一致） | ≤1 min |
| Admin store form / direct-upload attachments | + `harness verify admin-stores-rspec` (logo/mailer_logo 直传失败提示 + 多店 CRUD) | ≤1 min |
| Admin 样式 / 设计 token（`pallastrade_admin/app/assets/tailwind/**`、`pallastrade_admin.css`、后台 layout） | + `harness verify admin-theme-rspec`（品牌色阶/语义 token/密度双档 + 组件零直引 + WCAG AA 对比度契约） | ≤1 min |
| 支付商选项化（`pallastrade_admin` payment_methods 视图/控制器、core `payment_method(s)` 服务、`pallastrade_stripe` 能力目录） | + `harness verify admin-payment-methods-rspec`（选项化页签/保存归一 + Test connection + 凭证脱敏 + optionized 门控/Start 同源校验回归） | ≤1 min |
| 厂商层 / 账户配置 / 收窄校验（`payments/providers/**`、`PaymentMethod#provider_{capability,account_config,effective_scope,state,diagnostics}`、后台 `_provider_diagnostics` 卡与 `update_provider_account` 动作） | + `harness verify payment-providers-rspec`（能力声明（声明优先 / 目录推导 / traits 透传）+ 账户配置（缺失不猜、非法忽略、越界回显、空选=未声明、同值幂等、零资金副作用）+ 「能力 ∩ 账户」收窄与 basis + 三态（停用粘性、熔断自动恢复、部分熔断仍 enabled）+ 诊断 codes/severity + 后台只读诊断卡与账户表单渲染 + 写入口权限与审计） | ≤2 min |
| 支付适用范围引擎（`payments/availability/**`、`PaymentMethod#payment_option_rule_set`、`Order#payment_methods`、admin scope 编辑/序列化） | + `harness verify d8-availability-rspec`（规则集归一/求值 + 前台收集过滤 + Start 入口门禁 + 后台范围编辑与投影） | ≤3 min |
| 支付凭据与环境（`payment_methods.environment`、`Payments::Availability::Resolver` 前台过滤、`PaymentMethods::{Credentials,CredentialExpiryCheckJob}`、admin reveal/凭据卡/Webhook 卡） | + `harness verify d9-credentials-rspec`（环境隔离 + 凭据分级/env 引用 + 到期告警幂等 + reveal 权限与审计 + 后台卡片 + D1/D8 回归） | ≤4 min |
| 前台密钥下发（`PaymentMethods::ClientConfig`、`public_preference_keys`、`client_config` 下发面） | + `harness verify d10-client-config-rspec`（envelope + 仅 publishable 投影 + `env:` 解析 + Checkout payload + Stripe 声明） | ≤3 min |
| 账单详情透传 / 钱包采纳 / **PI 与 Checkout Session 参数合法性**（`pallastrade_stripe` presenters、`spec/models/gateway/{payment_intent,checkout_session}_payload_spec.rb`、`storefront/src/lib/utils/stripe-billing.ts`、`CardPaymentForm` / `ExpressCheckoutButton` / `WalletPaymentButtons`） | + `harness verify billing-details-rspec`（**PI 顶层与 CS `payment_intent_data` 都永不含 `billing_details`**（Stripe 只读，传了必 400 `parameter_unknown`——2026-09-19 两次真机事故）+ 两处 gateway 白名单/只读键断言在发请求前拒发 + 账单详情仅经客户端 PM 级透传 + 钱包地址不完整**降级 `same_as_shipping`**）；前端 `storefront-test` | ≤3 min |
| 结账失败体验 / 转换购物车恢复 / 未支付订单可见（`UnifiedCheckout#handlePayNow`、`checkout/[id]` 恢复路由、`account/orders/[id]`、`TopExpressPay`） | + `harness verify storefront-test`（确认失败 → 零 PATCH / 零跳转 + 未知 code 页内提示 + 资金事实 code 仍跳结果页 + 转换后 `cart_` → `checkout/or_...` + 未支付订单详情可渲染 + 顶部快捷支付常显） | ≤15 min |
| 补付重验（`order_checkout/revalidate.rb`、`promotions/remove_application.rb`、`catalog/line_item_availability.rb`、`transactions/start.rb`、`carts/submit.rb` 签窗与状态投影、`payment_preflight` 端点） | + `harness verify order-repay-rspec`（**dry-run 零副作用**（不落库/不发事件）+ 失效行剔除（写路径）+ 行级预留释放 + 窗口内锁价 / 过期重定价与续窗 + 全面失效 → `no_payable_items` + 优惠复核与抵扣再平衡 + `Transactions::Start` 同源接线与 409 `quote_changed.changes[]` + **orders 通道请求契约**（`transactions` 201/409 与 `d7` 入口门禁 422，夹具签发有效报价窗口））；前台 + `storefront-test`（补付重验提示 4 态 + 跳转入口）；接口 + `generated:check` | ≤5 min |
| 结算页只读预览报价（`carts/submit.rb` 的 `dry_run:`、`carts/preview_quote.rb`、`Address#pricing_only`、store API `carts#preview_quote`、SDK `carts.previewQuote` / `shippingMethods.list`、BFF `/api/checkout/preview`、`UnifiedCheckout` 预览读模型） | + `harness verify checkout-preview-quote-rspec`（预览 = 同参数 prepare 金额**逐字段一致** + dry-run **零副作用**（零 Order/Event/PaymentSession、车仍 active、礼品卡余额不变）+ `pricing_only` 临时地址（不伪造州/城市）+ 州级 zone 缺州 → `address_required` 且金额 nil（**绝不编 0**）+ 默认选中 = 成本最低/显式传入 + 端点 200/422 契约）；前端 `storefront-test` | ≤3 min |
| Webhook 治理（`PaymentWebhookEvent` quarantine、`Payments::{QuarantineWebhookEvent,MarkWebhookEventProcessed,WebhookHealth,WebhookSubscriptionChecklist}`、`/admin/webhook_events`） | + `harness verify d12-webhook-governance-rspec`（隔离状态机 + 筛选 + 处置审计 + 健康聚合 + 订阅清单 + 导航一致性） | ≤3 min |
| 支付入口展示元数据（`PaymentMethod#effective_payment_option/option_display_name/option_identifier` + checkout/支付方式序列化三字段 + 前台方法行 `display_name ?? name`） | + `harness verify d16-payment-presentation-rspec`（读模型口径 + option_id/method_key/display_name 契约 + 选项化回归）+ 前端 `storefront-test` | ≤3 min |
| 支付熔断与健康（`payment_method` breaker 状态机、`payments/health/metrics.rb`、`payments/circuit_breaker/**`、Resolver 门禁、admin `soft_disable`/`soft_enable` + 熔断卡） | + `harness verify d11-circuit-breaker-rspec`（软置灰状态机 + 窗口指标 + 自动判定/到期恢复 + 巡检作业 + 前台可用性 + 后台动作/卡面 + D8 回归） | ≤3 min |
| 对账差异队列（`reconciliation_cases` / `reconciliation_case_notes` 两表、`reconciliations/sync_cases.rb`、sweeper 案例同步、admin 工作台与 CSV 导出） | + `harness verify d13-reconciliation-cases-rspec`（映射口径 + 幂等/自动销案/签名取代 + 零资金副作用 + sweeper 接入 + 工作台筛选/动作/CSV/权限）+ P4 回归 `finance-reconciliation-rspec` | ≤3 min |
| 结算台账（`payouts` / `payout_lines` 两表、`reconciliations/payouts/**`、后台 `/admin/payouts` 导入与重匹配） | + `harness verify d13b-payouts-rspec`（状态合成/汇总/唯一键 + CSV 导入幂等与错误收集 + 匹配锚点/容差 + 差异入队与自动销案 + 台账页筛选/详情/导入/重匹配/权限）+ D13 切片1 回归 `d13-reconciliation-cases-rspec` | ≤3 min |
| 退款审批（`refund_approvals` 表 + `refunds.request_key` 列、`refunds/{policy,submit}.rb`、`refunds/approvals/**`、后台 `/admin/refund_approvals`、Admin API 策略门 + `approval_status`） | + `harness verify d14-refund-approval-rspec`（策略归一化矩阵 + 自动/待批分支 + 请求键幂等 + 双人批准/拒绝 SoD + 工作台/策略卡/权限 + API 契约字段）+ 回归 `orders cancel` / refunds 既有 spec + `harness generated:check` | ≤3 min |
| 争议期限分档（`dispute_deadline_alerts` 表、`disputes/deadline_policy.rb`、`disputes/alert_deadlines.rb`、`dispute.evidence_deadline_tier` 事件 + 超期自动 lost 策略、后台期限看板/列/提醒历史） | + `harness verify d14b-dispute-deadlines-rspec`（策略归一化 + 台账幂等/跳档补齐 + 分档事件 + 策略门控自动 lost（默认关闭/单轮上限）+ sweeper 指标 + 订阅者分档 + 看板计数与筛选同源/历史/权限 + DSP-P7-5 回归） | ≤3 min |
| 风控名单与评估（`payment_risk_lists` / `payment_risk_assessments` 两表、`risk/lists/**`、`risk/assess.rb`、`order.submitted` 订阅者、后台 `/admin/risk_lists`、订单页风控卡） | + `harness verify d15-risk-lists-rspec`（归一化/唯一键/生效率 + CSV 导入导出往返 + 维护撤销审计 + 决策矩阵（白名单短路/黑名单默认 review）+ 留痕幂等 + 跨店隔离 + 零资金副作用 + 订阅者接线 + 工作台/订单卡 + 导航回归） | ≤3 min |
| 费率模型与支付成本报表（`payment_fee_policies` 表、`payments/fees/{resolver,calculate}.rb`、`payments/costs/report.rb`、后台 `/admin/payment_costs` + `/admin/payment_fee_policies`） | + `harness verify d13c-cost-report-rspec`（费率策略归一化/优先级/条件 + 单笔计算（分量/保底封顶/跨境与转换「不猜」）+ 只读报表自洽/按入口排名与下钻/实际 vs 模型偏差/跨店隔离/零资金副作用/查询数不随行数增长 + 后台维护页与报表页（计数同源/审计/权限/CSV 无卡号）+ 导航回归） | ≤5 min |
| 汇率快照与结算汇率对比（`currency_rates` / `fx_snapshots` 两表、`currencies/rates/**`、`currencies/fx/**`、`order.submitted` 订阅者、`CompareSweeperJob`、后台 `/admin/currency_rates` + `/admin/fx_snapshots`） | + `harness verify d13d-fx-snapshot-rspec`（汇率归一化/身份键/优先级与本店优先 + 锁汇（加点后有效汇率/同币种跳过/无汇率不写行/幂等）+ 结算汇率来源（报文/推导/不可判定）+ bips 容差与差异入队 kind=fx/自动销案/人工判定保护 + 跨店隔离与期间 + 零资金副作用 + 读路径查询不随行数增长 + 订阅者不阻断 + 巡检指标/调度 + 后台两页（计数同源/权限/CSV 无凭证）+ 结算导入 fx_rate 列回归 + 导航回归） | ≤5 min |
| 拒付率看板与卡组织阈值预警（`dispute_rate_alerts` 表、`disputes/rate_{policy,report,alert}.rb`、`RateAlertSweeperJob`、后台 `/admin/dispute_rates`） | + `harness verify d14c-dispute-rates-rspec`（策略归一化 + 双阈值判定（ok/approaching/breached/unconfigured，未配置不判定）+ 比率口径（分子=窗口内争议、分母=同组织已完成卡支付、卡品牌别名归一、不可判定归 unknown 且不判定）+ 跨币种不入金额比且计数明示 + 分母 0 → nil + 台账幂等（店/组织/评估日唯一）+ 档位升级发事件一次/同日不降档 + 巡检多店与失败隔离/指标日志/零 provider + 下钻四维度（桶合计==汇总）+ 卡指纹脱敏（页面/CSV，且页面只提交掩码、服务端唯一反解）+ 一键加黑写 D15 名单 + 零资金副作用 + 查询数不随行数增长 + 导航回归） | ≤4 min |
| 风控规则引擎版本化/灰度/回滚（`risk_rule_sets` / `risk_rule_versions` 两表、`risk/rules/{condition,schema,evaluate,versioning}.rb`、`Risk::Assess` 决策合并、后台 `/admin/risk_rules`） | + `harness verify d15b-risk-rules-rspec`（作用域 code 唯一 + 版本不可变 + 条件词汇逐键（含边界与不猜跳过）+ 发布校验拒绝未知键/类型错/重复码且不落库 + priority 首个命中与店铺优先于全局 + 灰度确定性分桶（0/100 边界、桶==percent 归稳定、跨 now 恒定）+ 版本流转与归档 + **回滚生成新版本且源版本不改写、原因必填** + 两事件无 PII + 与名单取最严者/白名单短路 + 留痕 signals/metadata + 零资金副作用 + 后台动作/计数同源/试算零写入 + preflight 与 D15 切片1 回归 + 导航回归） | ≤3 min |
| 3DS/SCA 认证策略与下发（`payments/three_d_secure/{policy,required,provider_hint}.rb`、`PaymentRiskAssessment` 动作 `force_3ds`、`Payments::Availability::Resolver` 闸门、`PaymentSessions::Start`、Stripe `request_three_d_secure`、门店策略区块 + 入口能力列） | + `harness verify d15c-three-d-secure-rspec`（策略归一化 fail-safe 读/拒绝式写与审计 + 未配置回落默认 + 认证需求三模式与**风险严格性优先**（`off` 不压显式 `force_3ds`）+ 豁免只放宽挑战不放宽阻断 + 阈值仅同币种比较 + `force_3ds` 入发布门与严重度 `allow<review<force_3ds<block` 且最严者胜/白名单短路 + 能力目录声明 `three_d_secure`（未声明按 unsupported）+ 闸门只留可认证入口 + `Start` 建会话前 422 `authentication_required` 且零 session 行 + 契约新增 `requires_authentication`（隐藏=不出现）+ 仅已声明能力才下发 + 查询数不随入口数增长 + D8/D11/D16/契约/切片1·2 回归 + 导航回归） | ≤4 min |
| 交易排障台人工裁决（`transactions/review.rb`、`CommerceTransaction#approve_after_review/release_after_review`、admin `transactions#approve_and_capture|release_and_cancel` + 复核卡/历史） | + `harness verify d2-manual-review-rspec`（capture 分支＝捕获→finalizing→既有 Finalize→completed；release 分支＝void 授权+`Orders::Cancel`+canceled 且**零退款**；`reason_required`/`invalid_decision`/`transaction_not_reviewable`/`no_pending_authorization`/`paid_payment_present` 全部**不改状态**；`(transaction, decision)` 审计键幂等返回 `already_applied` 且仅一条审计；before/after+决策+原因+操作人留痕；**人工专用**调用点唯一断言 + 后台 302/flash 与两种状态渲染 + 状态机·Recover·Finalize 回归） | ≤4 min |
| 风控看板与阈值告警（`risk/dashboard_{policy,report,threshold,alert}.rb`、`DashboardAlertSweeperJob`、后台 `/admin/payment_risk`） | + `harness verify d3-risk-dashboard-rspec`（5 水位口径逐项可复算（risky 单 / 3DS 挑战率 / **拒付率委派 D14c 不重算** / 退款率 / 审核队列时长含已处理 P90）+ **不可判定不猜**（分母 0 或报表降级 → `nil` + 结构化 `reason`，绝不回落 0）+ 阈值策略归一化（`warning < critical` 强制、越界/类型错/未知指标拒收码、坏载荷 fail-safe 读、`configured?` 双档齐备）+ 五态判定（`unconfigured` 不判定）+ **同日留痕幂等且不降档** + 事件无 PII + 跨店隔离 + 零资金副作用 + 查询数不随行数增长 + 巡检逐店隔离/坏配置不炸 + 后台 5 卡/策略保存与拒绝/立即评估/权限拒绝零写入 + D14c·D8·D2 回归 + 导航回归） | ≤3 min |
| 入口级支付区（`payment_method.rb#payment_option_entries`、checkout 投影 `entries[]`/`group`/`position`、三通道 `option_kind`、`Transactions::Start`） | + `harness verify d7-payment-section-rspec`（一入口一行且顺序 = `position` + 停用入口不出现 + 非选项化 provider 仍 1 条（零回归）+ 入口集合来自 `Availability::Resolver`（与 Start 同源）+ **不可用入口建会话前被拒且零 session 行**（orders/transactions 为 `payment_option_not_available`，cart legacy 为 `validation_error`）+ 旧响应无 `entries` 时前台回落单行）+ 前端 `storefront-test` | ≤3 min |
| Admin Catalog Health（7 类商品健康 issue + 一键过滤列表 + 覆盖率 + 可解释健康分） | + `harness verify admin-catalog-health-rspec`（**服务层覆盖面清单**：metrics 恰为 `Issues::KEYS` 且顺序一致 + 每类必有分母（无声明会静默落到 zero_denominator）；口径逐项 + 计数==列表条数 + 筛选横幅 + 覆盖率分母各自自洽 + 健康分可手工复算/不可计算维度排除 + 导航子项一致性） | ≤3 min |
| 商品事件回流（`catalog_events` 表 + `store/catalog_events` 批量端点 + 前台 `lib/analytics/catalog-events.ts`） | + `harness verify catalog-events-rspec`（幂等 `event_id` + 事件名白名单 + 批量上限整批拒收 + 跨店隔离 + 零 PII 摘要（不落原值）+ CTR 分母为 0 返回 `nil` + 保留作业幂等） | ≤2 min |
| 商品批量移除媒体（`products/bulk_media_removal.rb` + products 列表 `remove_media` 动作，预览→确认） | + `harness verify bulk-media-rspec`（预览零写入且与执行同源计数 + 商品级与变体级媒体均清空 + `primary_media_id` 两侧置空 + 不留悬空 `VariantMedia` + 权限不足零写入 + 按 `current_store` 收窄 + bulk 审计） | ≤2 min |
| Admin 商品批量运营（批量价格/库存/渠道 + 预览确认） | + `harness verify admin-products-bulk-rspec`（预览零写入 + 预览/执行计数一致 + 逐条权限跳过 + 模态接线） | ≤2 min |
| 到货订阅（SKU 级，`back_in_stock_subscriptions` / 事件层 / store API / 后台 SKU 列） | + `harness verify back-in-stock-rspec`（SKU 唯一约束 + 双通道分流不重复 + API variant_id + 后台 SKU 列） | ≤2 min |
| 商品级 Product History 时间线（`product_history/**` + 后台 `_history` 侧栏注入） | + `harness verify product-history-rspec`（只记变化字段/无变化跳过 + 批量每商品一条含计数 + 审计与改价合并倒序 + 编辑页渲染与空态） | ≤2 min |
| 重复商品检测（`products/duplicate_candidates.rb` + 后台 Duplicate Products 工作台/对比视图） | + `harness verify duplicate-products-rspec`（三类信号口径 + 计数==组数 + 店铺/软删除作用域 + 对比渲染 + 导航子项） | ≤2 min |
| AI Product Copilot（`ai/catalog/product_copy.rb` + 商品编辑页 Generate/Preview/Accept + 两个 admin 端点） | + `harness verify ai-copilot-rspec`（能力注册/schema + Gateway 调用与 Run 审计 + **接受前不落库** + 降级/权限） | ≤2 min |
| AI Translate Missing（`ai/catalog/product_translation.rb` + 翻译抽屉 `[AI Translate Missing]` + `POST /admin/ai/product_translation`） | + `harness verify ai-translate-rspec`（能力注册/schema + 缺失口径 `fallback:false` 排除 slug + 无缺失零 Run + 接受前不落库 + 降级/权限/抽屉渲染） | ≤2 min |
| Catalog Health AI 修复建议（`ai/catalog/health_fix_suggestion.rb` + 工作台行内面板 + 商品侧栏卡片 + `POST /admin/ai/catalog_health_suggestion`） | + `harness verify ai-health-suggestion-rspec`（能力注册 read 授权/schema + 采样范围与字段最小化 + 计数 0/未知 issue 零 Run + 入口白名单 + 零写库 + 两种粒度渲染） | ≤2 min |
| 评论系统升级一期（`review.rb` images + store reviews 分页/评分分布 + store `direct_uploads` + 后台图片列） | + `harness verify reviews-f1-rspec`（图片归属/上限/类型错误码 + 分页不重复 + rating_distribution 与列表同源 + 未审核图片不外泄 + 后台图片列） | ≤2 min |
| 评论列表排序（`reviews_controller` 的 `sort` 白名单 + 稳定 tie-break + `meta.sort` + 前台下拉） | + `harness verify f4-review-sorting-rspec`（白名单与回退 + 同分翻页不重不漏 + `meta` 超集 + 分布与排序正交） | ≤1 min |
| 评论「有用」投票（`pallastrade_review_votes` 表 + `reviews.helpful_votes_count`、`review_helpful_votes_controller`、`most_helpful` 排序、后台 Helpful 列） | + `harness verify f5-helpful-vote-rspec`（一人一票唯一索引 + 幂等投票/撤销 + 自投 422/pending 404/未登录 401/跨店 404 + 计数公开而本人状态仅登录（无投票者身份）+ most_helpful 稳定 tie-break + 后台列）+ 前端 `pnpm check`（biome：格式与 import 顺序，CI 强制执行） | ≤3 min |
| 商品合并（`pallastrade_product_merges` 台账 + `products/{merge_preview,merge,undo_merge}.rb`、Duplicate Products 工作台入口） | + `harness verify d3-product-merge-rspec`（预检零写入 + 迁移守恒 + SKU/评论冲突跳过且留在原处 + **历史交易零改写** + 归档/软删/`merged_into` 留痕 + 台账与审计 + 撤销逐项还原/阻塞即拒 + 后台预览/执行/撤销） | ≤3 min |
| 评论审核工作台批量通过/拒绝（`admin/reviews#bulk` + `admin_tables` 注册两个 bulk action） | + `harness verify f3-review-bulk-rspec`（逐条状态机与审计口径 + 逐条鉴权跳过 + 空选/超 50 条守卫 + 四计数报告 + 只增不改的公开口径） | ≤1 min |
| 库存阈值化与配送信息（`catalog/stock_status.rb` + `shipping/estimate.rb` + Store 两个偏好 + PDP/卡片徽章 + `/shipping_estimate`） | + `harness verify f2-stock-shipping-rspec`（分桶口径与 `Variant#in_stock?` 同源 + 任何响应不含精确库存 + 阈值归一 + 时效/免运费矩阵 + 列表查询数不随条数增长） | ≤2 min |
| Financial ledger / reconciliation (`reconciliations/`, `financial_ledger/`) | + `harness verify finance-reconciliation-rspec` (source/transaction/payment/refund/dispute 对账 + sweeper) | ≤2 min |
| Any change | `harness doc-impact --base origin/dev` — checks knowledge docs are synced | ≤1 min |

### Verification Evidence Required

Use `npx harness evidence run|record` to capture typed evidence. Before closing the task, run
`npx harness knowledge verify --task <TASK-ID>` and `npx harness evidence verify --task <TASK-ID> --gate <GATE-ID>`;
only fresh evidence bound to the current HEAD/worktree/file hashes may finish the Gate.

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
| `docs/prd/_TEMPLATE.md` (modified) | `ai/skills/pallastrade-prd/SKILL.md` |
| `docs/prd/**` (new PRD) | `docs/prd/README.md` index |
| `harness/policies/prd-categories.json` (modified) | `ai/skills/pallastrade-prd/SKILL.md` |
| `harness/policies/{anti-patterns,task-rules}.json` (modified) | This `AGENTS.md` §5 + `.github/copilot-instructions.md` |
| `ai/commands/**` / `ai/agents/**` (modified) | `ai/README.md` |
| `platform/packages/{cli,sdk,create-pallastrade-app}/**` (modified) | `platform/README.md` or `platform/packages/README.md` |
| `harness.config.mjs` / `package.json` / `lefthook.yml` (harness 配置/依赖变更) | `AGENTS.md` + `ai/skills/pallastrade-prd/SKILL.md` + `harness/scenarios/scenarios.json` |
| `ai/skills/**/SKILL.md` (modified) | `harness/scenarios/scenarios.json` — add/update an Eval Scenario |
| `AGENTS.md` / `CLAUDE.md` (modified) | Run `harness docs:check` to verify no broken references |
| Any file (framework version upgrade) | ALL Skill files — `harness eval ai --check-freshness` |

**CI command**: `harness doc-impact --base origin/dev` checks your PR against this table. If any required doc update is missing, the PR is blocked with status `docs-required`.

**Knowledge sync gate**: for PRD-driven tasks, before closing `verify-test`, run `harness sync-check --id PRD-xxx` — it lists every knowledge asset (Skill / README / Agent files / style & technical standards / anti-patterns / scenarios) the change may require updating. Resolve each (update, or record "已评估，无需更新" in PRD §12（文档同步清单）/ §16（变更记录）), then confirm with `harness sync-check --ack`.

---

## 8. Dangerous Operations (PHYSICALLY BLOCKED)

These commands are intercepted by safety hooks at the tool-call level, not the prompt level. The AI literally cannot execute them.

- `rake db:drop` / `rails db:drop` / `rake db:reset` / `rails db:reset`
- `DROP TABLE pallastrade_*` / `DROP DATABASE`
- `DELETE FROM pallastrade_orders` (and similar mass deletes on core tables)
- `PallasTrade::Order.delete_all` / `PallasTrade::Order.destroy_all`
- `git push --force origin dev`
- Writing secrets (`sk_live_...`, `AKIA...`, `ghp_...`) into source files

**Bypass**: Set `PALLASTRADE_HOOKS_DISABLE=1` and run the command manually in a terminal (not through the AI tool invocation). This is for emergencies only.

### Physical Enforcement (agent-agnostic)

Beyond prompt-level rules, the repo has **git-level gates** that fire regardless
of which agent (Copilot / Codex / Claude Code) or human drives it:

- Root `lefthook.yml` — pre-commit runs the anti-pattern + AP-009 degraded-loop
  scans on **staged files only** (error severity blocks); pre-push runs
  `harness doc-impact`. Install once: `npm i && npx lefthook install`.
- `harness task` persists repository/worktree-bound state, checkpoints and handoffs; `.harness-state/`
  is local runtime state and must not be committed.
- `harness gate` supports task types: feature / bugfix / style / audit /
  research / docs / refactor / security / test. Gates bind branch + HEAD commit
  and record `--note` on each cleared check; task-bound verification is completed only by typed evidence.
- Harness self-checks: `npm run test:harness` (node:test contract tests) and
  `harness eval-ai --scenarios` (GS scenario library validation).
