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
| Model / DB schema / migration | + `harness check --profile full` | ≤45 min |
| API endpoint (new/modified) | + `harness generated:check` (OpenAPI + SDK types) | ≤5 min |
| UI component / style | + `harness e2e dashboard` or `harness e2e storefront` | ≤15 min |
| Payment logic | + payment sandbox gate | ≤30 min |
| AI Skill file (`ai/skills/`) | + `harness eval ai --check-freshness` | ≤2 min |
| `deploy/` scripts / repo-level guards (`tests/*.test.mjs`) | + `harness verify repo-guards-test` (前滚检测 + drill crontab 恢复 + PRD 状态同步契约守卫) | ≤1 min |
| Admin store form / direct-upload attachments | + `harness verify admin-stores-rspec` (logo/mailer_logo 直传失败提示 + 多店 CRUD) | ≤1 min |
| Admin 样式 / 设计 token（`pallastrade_admin/app/assets/tailwind/**`、`pallastrade_admin.css`、后台 layout） | + `harness verify admin-theme-rspec`（品牌色阶/语义 token/密度双档 + 组件零直引 + WCAG AA 对比度契约） | ≤1 min |
| 支付商选项化（`pallastrade_admin` payment_methods 视图/控制器、core `payment_method(s)` 服务、`pallastrade_stripe` 能力目录） | + `harness verify admin-payment-methods-rspec`（选项化页签/保存归一 + Test connection + 凭证脱敏 + optionized 门控/Start 同源校验回归） | ≤1 min |
| 支付适用范围引擎（`payments/availability/**`、`PaymentMethod#payment_option_rule_set`、`Order#payment_methods`、admin scope 编辑/序列化） | + `harness verify d8-availability-rspec`（规则集归一/求值 + 前台收集过滤 + Start 入口门禁 + 后台范围编辑与投影） | ≤3 min |
| 支付凭据与环境（`payment_methods.environment`、`Payments::Availability::Resolver` 前台过滤、`PaymentMethods::{Credentials,CredentialExpiryCheckJob}`、admin reveal/凭据卡/Webhook 卡） | + `harness verify d9-credentials-rspec`（环境隔离 + 凭据分级/env 引用 + 到期告警幂等 + reveal 权限与审计 + 后台卡片 + D1/D8 回归） | ≤4 min |
| 前台密钥下发（`PaymentMethods::ClientConfig`、`public_preference_keys`、`client_config` 下发面） | + `harness verify d10-client-config-rspec`（envelope + 仅 publishable 投影 + `env:` 解析 + Checkout payload + Stripe 声明） | ≤3 min |
| Webhook 治理（`PaymentWebhookEvent` quarantine、`Payments::{QuarantineWebhookEvent,MarkWebhookEventProcessed,WebhookHealth,WebhookSubscriptionChecklist}`、`/admin/webhook_events`） | + `harness verify d12-webhook-governance-rspec`（隔离状态机 + 筛选 + 处置审计 + 健康聚合 + 订阅清单 + 导航一致性） | ≤3 min |
| 支付入口展示元数据（`PaymentMethod#effective_payment_option/option_display_name/option_identifier` + checkout/支付方式序列化三字段 + 前台方法行 `display_name ?? name`） | + `harness verify d16-payment-presentation-rspec`（读模型口径 + option_id/method_key/display_name 契约 + 选项化回归）+ 前端 `storefront-test` | ≤3 min |
| 支付熔断与健康（`payment_method` breaker 状态机、`payments/health/metrics.rb`、`payments/circuit_breaker/**`、Resolver 门禁、admin `soft_disable`/`soft_enable` + 熔断卡） | + `harness verify d11-circuit-breaker-rspec`（软置灰状态机 + 窗口指标 + 自动判定/到期恢复 + 巡检作业 + 前台可用性 + 后台动作/卡面 + D8 回归） | ≤3 min |
| 对账差异队列（`reconciliation_cases` / `reconciliation_case_notes` 两表、`reconciliations/sync_cases.rb`、sweeper 案例同步、admin 工作台与 CSV 导出） | + `harness verify d13-reconciliation-cases-rspec`（映射口径 + 幂等/自动销案/签名取代 + 零资金副作用 + sweeper 接入 + 工作台筛选/动作/CSV/权限）+ P4 回归 `finance-reconciliation-rspec` | ≤3 min |
| 结算台账（`payouts` / `payout_lines` 两表、`reconciliations/payouts/**`、后台 `/admin/payouts` 导入与重匹配） | + `harness verify d13b-payouts-rspec`（状态合成/汇总/唯一键 + CSV 导入幂等与错误收集 + 匹配锚点/容差 + 差异入队与自动销案 + 台账页筛选/详情/导入/重匹配/权限）+ D13 切片1 回归 `d13-reconciliation-cases-rspec` | ≤3 min |
| 退款审批（`refund_approvals` 表 + `refunds.request_key` 列、`refunds/{policy,submit}.rb`、`refunds/approvals/**`、后台 `/admin/refund_approvals`、Admin API 策略门 + `approval_status`） | + `harness verify d14-refund-approval-rspec`（策略归一化矩阵 + 自动/待批分支 + 请求键幂等 + 双人批准/拒绝 SoD + 工作台/策略卡/权限 + API 契约字段）+ 回归 `orders cancel` / refunds 既有 spec + `harness generated:check` | ≤3 min |
| 争议期限分档（`dispute_deadline_alerts` 表、`disputes/deadline_policy.rb`、`disputes/alert_deadlines.rb`、`dispute.evidence_deadline_tier` 事件 + 超期自动 lost 策略、后台期限看板/列/提醒历史） | + `harness verify d14b-dispute-deadlines-rspec`（策略归一化 + 台账幂等/跳档补齐 + 分档事件 + 策略门控自动 lost（默认关闭/单轮上限）+ sweeper 指标 + 订阅者分档 + 看板计数与筛选同源/历史/权限 + DSP-P7-5 回归） | ≤3 min |
| Admin Catalog Health（7 类商品健康 issue + 一键过滤列表） | + `harness verify admin-catalog-health-rspec`（口径逐项 + 计数==列表条数 + 筛选横幅 + 导航子项一致性） | ≤2 min |
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

**Knowledge sync gate**: for PRD-driven tasks, before closing `verify-test`, run `harness sync-check --id PRD-xxx` — it lists every knowledge asset (Skill / README / Agent files / style & technical standards / anti-patterns / scenarios) the change may require updating. Resolve each (update, or record "已评估，无需更新" in PRD §9/§10), then confirm with `harness sync-check --ack`.

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
