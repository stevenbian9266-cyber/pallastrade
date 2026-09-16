# REQ-20260916 — Batch E-3（Catalog Health 的 AI 修复建议：工作台级 + 商品级，只读不落库）

> 关联 PRD：`docs/prd/catalog/PRD-20260916-catalog-batch-e3-ai-fix-suggestion.md`
> 任务：TASK-20260916010742-a54d61ef ｜ Gate：GATE-2026-09-16T01-11-03（feature）
> 用户确认：2026-09-16「确认实施」+ 范围扩大＝**工作台级 + 商品级**（呈现＝行内折叠面板）

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — 宿主代码 | `backend/app/` | catalog_health / ai | `app/controllers/pallastrade/admin/ai_controller.rb`（E-1/E-2 的 JSON 端点范式：`find_copilot_product` / `render_copilot_result` / `authorize!`）；宿主无 catalog health 代码 | 复用：**只加一个动作 + 分派** |
| AI Gem | `backend/pallastrade_gems/pallastrade_ai/app/` | capability / schema / catalog | `config/initializers/catalog_capabilities.rb`（E-1/E-2 三个能力的注册点，幂等）、`app/services/pallastrade/ai/catalog/*`（业务服务 + Result 范式）、`schemas/catalog/*`（Input/Output + Handler 壳）、`availability_service.rb`（7 道门，零副作用） | **后端齐备** → 加 1 能力 + 1 服务 |
| Core Gem | `backend/pallastrade_gems/pallastrade_core/app/` | CatalogHealth | `services/pallastrade/catalog_health/issues.rb`（`KEYS` 7 类 / `valid?` / `valid_filter?` / `product_relation(base_scope,key,store:)` / `count(store,key)` / `missing_translations_count` / `redirect_unresolved_count`）、`services/…/report.rb`（`Issue(key,count,target,params)` / `count_for` / `TARGETS`） | ✅ **只读复用，core 零改动** |
| API Gem | `backend/pallastrade_gems/pallastrade_api/app/` | catalog_health | 无 | ✅ 不加 v3 端点 |
| Admin Gem | `backend/pallastrade_gems/pallastrade_admin/app/` | catalog_health / partials | `controllers/pallastrade/admin/catalog_health_controller.rb`（`Report.call` + `catalog_health_target_path`）、`views/.../catalog_health/index.html.erb`（7 行表格）、`views/.../catalog_health/_products_filter_banner.html.erb`、`config/initializers/pallastrade_admin_partials.rb`（**`products_header` 与 `product_form_sidebar` 注入点注册范式**）、`views/.../products/_form.html.erb`（`render_admin_partials(:product_form_sidebar_partials, f:, product:)`）、D-1 的 `views/.../products/_history.html.erb`、E-1 的 `helpers/…/ai_assist_helper.rb` + `javascript/…/controllers/ai_assist_controller.js` | **注入点与交互范式齐备** |
| Storefront | `storefront/src/` | catalog health | 无 | ✅ 不涉及 |
| Platform | `platform/packages/` | catalog health | 无 | ✅ 不涉及 |

### 搜索结论

- **B-2（Catalog Health V1）已把口径与工作台建好**：7 类 issue、计数、过滤、去修复链接；本批**不改口径**，只加「怎么修」的建议层。
- **E-1/E-2 已把 AI 接线范式建好**：能力注册（`catalog_capabilities.rb`，幂等）、业务服务（Gateway + Run 审计 + 零写库）、JSON 端点（前缀 id / 跨域 404 / 422 原因码）、`ai-assist` Stimulus + `ai_assist_state` 降级、`product_form_sidebar_partials` 注入点。
- 因此本批缺口 = **1 个能力 + 1 个服务（两种粒度）+ 1 个端点动作 + 2 处 UI（工作台行内面板 / 商品编辑页侧栏卡片）**；core 与 API 零改动、零迁移、无契约变更、**零写库**。

---

## Step 1：Skill 文件咨询（新功能 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树优先级：能在既有页面/注入点接线就不要新造页面 —— 本批用 `products_header` / `product_form_sidebar` partials 注入点（B-2/D-1 已用的官方机制），不复制 gem 视图 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | AI 章节五条铁律沿用：能力注册在 `catalog_capabilities.rb`（全环境）、提示词在业务服务里组装、端点用前缀 id 并自处理 404、按钮状态走 `ai_assist_state`、Accept 写值需 dispatch input + 同步 TinyMCE（本批**无 Accept**——没有可写入目标）；`render_admin_partials(section, options)` 只对注册过的 partial 生效（未注册 → 页面原样） |
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已读 | Catalog Health 的「计数 == 列表条数」同源铁律（B-2）：建议里的 `count` 必须来自 `Report.count_for`，不得另算；`missing_translations` 的既有口径是「product × locale 缺 `name` 的对数」 |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-testing` | ☑ 涉及 | ✅ 已读 | 生成类用例 stub provider（不打真实 API）；**CI 环境差异两条教训**——`ACTIVE_RECORD_ENCRYPTION_*` 未设 → `ProviderSecret` fail-closed、`PALLASTRADE_AI_ENABLED` 未设 → 可用性 Gate 1 拦截 → 规格内需显式处理（E-1/E-2 已用「内存替身 + 显式打开系统开关」） |
| `pallastrade-security` | ☑ 涉及（轻） | ✅ 已读 | 采样必须最小化（不含客户/订单/成本）；错误信息不回显凭证；新端点走既有授权链（`authorize! :read, PallasTrade::Product`） |
| `harness-prd` | ☑ 涉及 | ✅ 已读 | PRD 扩充 → 用户确认 → gate → 实施 → `prd verify`（AC↔测试标注）→ 知识同步门 |
| `pallastrade-api-v3` | ⬜ 不涉及 | — | 不加 v3 端点、无 OpenAPI/SDK 变更 |
| `pallastrade-data-model` | ⬜ 不涉及 | — | 零迁移 |
| `pallastrade-i18n` | ⬜ 不涉及 | — | 无内容翻译变更（翻译是 E-2 能力，不属本批） |
| `pallastrade-storefront` | ⬜ 不涉及 | — | 无前台改动 |

---

## 需求标题

Catalog Health 的 AI 修复建议：工作台每类 issue 一行 `[AI Fix Suggestion]`（行内折叠面板）+ 商品编辑页侧栏「Catalog Health」卡片（该商品命中的问题 → 一个修复计划）；**只读建议，不写任何数据**。

## 任务类型

新功能（Admin UI + AI capability wiring；只读、零迁移、无 v3 契约变更）

## 需求描述

运营在 Catalog Health 看到某类问题（例如 31 个商品缺描述）时，点一次按钮就应拿到「先做什么、按什么顺序、每一步在哪个入口做」的可执行步骤；在单个商品上，也能看到该商品命中的全部健康问题与一份针对它的修复计划。所有产物都只是**建议文本**：AI 不改价格/库存/上架/渠道，不写商品与翻译，保存仍由商家在既有入口完成。

## 影响范围（预估）

```text
backend/pallastrade_gems/pallastrade_ai/config/initializers/catalog_capabilities.rb                （+1 能力）
backend/pallastrade_gems/pallastrade_ai/app/services/pallastrade/ai/schemas/catalog/health_fix_suggestion.rb  （新）
backend/pallastrade_gems/pallastrade_ai/app/services/pallastrade/ai/catalog/health_fix_suggestion.rb          （新）
backend/app/controllers/pallastrade/admin/ai_controller.rb                                          （+1 动作，两种粒度分派）
backend/config/routes.rb                                                                            （+1 路由）
backend/pallastrade_gems/pallastrade_admin/app/views/pallastrade/admin/catalog_health/index.html.erb          （行内按钮 + 面板）
backend/pallastrade_gems/pallastrade_admin/app/views/pallastrade/admin/catalog_health/_product_card.html.erb  （新：商品侧栏卡片）
backend/pallastrade_gems/pallastrade_admin/config/initializers/pallastrade_admin_partials.rb        （注册卡片 partial）
backend/pallastrade_gems/pallastrade_admin/app/javascript/pallastrade/admin/controllers/ai_assist_controller.js （suggestion 分支）
backend/pallastrade_gems/pallastrade_admin/config/locales/{en,zh-CN}.yml                             （admin.catalog_health.ai.*）
backend/spec/services/pallastrade/ai/catalog/health_fix_suggestion_spec.rb                          （新）
backend/spec/requests/pallastrade/admin/catalog_health_ai_suggestion_spec.rb                        （新）
harness.config.mjs / AGENTS.md / harness/scenarios/scenarios.json / ai/skills/** / docs/prd/**
```

## 技术方案（初步）

- **能力** `catalog.health_fix_suggestion`：input `{ scope: 'catalog'|'product', issue_key? / issue_keys?, count?, sample?: [...] }`，output `{ summary, steps: [{ title, detail?, entry }] }`；`execution: :sync`、`authorization: { action: :read, subject: 'PallasTrade::Product' }`、`data_classification: 'internal'`。
- **服务** `PallasTrade::AI::Catalog::HealthFixSuggestion`：`ENTRIES` 白名单（`product_edit_ai` / `translations_drawer` / `product_media` / `variant_inventory` / `redirects` / `publishing`）；工作台级 `.generate(store:, actor:, issue_key:)`（`Issues.valid?` + `Report.count_for` + `product_relation` 采样 ≤5）；商品级 `.generate_for_product(product:, actor:)`（逐键 `product_relation(Product.where(id:), key, store:).exists?` + `missing_translations` 按语言计数）；两者都**只读**、零写库、steps 入口白名单过滤。
- **端点** `POST /admin/ai/catalog_health_suggestion`：`{ issue_key }` 或 `{ product_id }` 分派；`authorize! :read, PallasTrade::Product`；未知 key → `unknown_issue`；无命中/计数 0 → `nothing_to_fix`（零 Run）。
- **UI**：工作台每行按钮 + 行内折叠面板；商品编辑页侧栏卡片（`product_form_sidebar` 注入）；`ai-assist` 的 `suggestion` 分支（**无 Accept**）。

## 风险点

| 风险 | 缓解 |
|---|---|
| 建议里编造不存在的入口/能力 | `ENTRIES` 白名单过滤（AC-007），未知 entry 丢弃 |
| 采样越界（跨店 / 含敏感字段） | 作用域 `current_store` + 最小字段断言（AC-003） |
| 被误当「一键修复」 | 文案为「建议」、**无 Accept 按钮**、零写库断言（AC-005） |
| 与 B-2 计数漂移 | 计数一律 `Report.count_for`（同源），端点返回的 `count` 与页面一致 |
| 商品级列表夸大成不存在的问题 | 逐键 `exists?` 判定 + AC-011 断言 `issue_keys` 只含实际命中项 |
| CI 环境差异（加密密钥 / 系统开关） | 规格沿用 E-1/E-2 的「内存替身 + 显式打开系统开关」范式 |

## 验证方案（AC ↔ 命令映射）

| AC | 验证方式 |
|---|---|
| AC-001/002/003/006/007 | `health_fix_suggestion_spec.rb`（能力注册与 authorization=read、schema、采样范围与字段最小化、计数 0/未知 key 不发请求不建 Run、steps 白名单） |
| AC-004/005/008/009/010/011/012 | `catalog_health_ai_suggestion_spec.rb`（工作台端点 200 + Run、商品级端点 200 + `issue_keys`、**零写库**、工作台渲染三态、商品卡片渲染三态 + 跨店 404、权限拒绝零 Run、i18n 键） |
| 回归 | `harness verify ai-health-suggestion-rspec --task TASK-20260916010742-a54d61ef`；另跑 `ai-copilot-rspec` / `ai-translate-rspec` / catalog health 既有规格回归（共 70 例）；E-1 编辑页按钮计数断言改为排除健康卡片（E-3 新增 1 个建议按钮） |
| 知识同步 | `harness sync-check --id PRD-20260916-catalog-batch-e3-ai-fix-suggestion` → 处理 → `--ack` |

## 用户确认

- 2026-09-16「直接开下一批」（授权开 E-3）；
- 2026-09-16 经问答确认：**确认实施**；范围扩大＝**工作台级 + 商品级**；呈现＝**行内折叠面板**。
