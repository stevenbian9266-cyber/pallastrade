# PRD-20260915-catalog-batch-e1-ai-copilot

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-15 |
| 来源 | 《商品升级方案 V1.0》§七「AI Product Copilot 第一版」+ §十五「一期建议正式 Scope」（用户授权原话：「继续下一个任务」，2026-09-15） |
| 分类 | catalog（商品域 / AI 辅助） |
| 关联 Skill | pallastrade-admin / pallastrade-customization / pallastrade-testing |
| 关联 REQ | REQ-20260915-batch-e1-ai-copilot.md |
| 关联 PRD | 上游批次：A（PDP 正确性）/ B-1（批量运营）/ B-2（Catalog Health）/ C-1（PDP 发现）/ C-2（SKU 到货订阅）/ D-1（Product History）/ D-2（重复商品检测） |
| 需求类型 | 新功能（Admin UI + capability wiring，零迁移） |

> 🔁 **查重**：`harness prd new` 通过。**范围依据**：方案 §十五 一期 Scope 明确列出「AI：Product Description Assistant / SEO Assistant」两项 → 本批 = 描述辅助 + SEO 辅助；§七 的第三项「Translation（AI Translate Missing）」不在 §十五 一期 Scope 内 → **留作 E-2**，在 §10 记录。

## 1. 背景与目标

- **背景**：AI 后端**已经建好且完整**——`pallastrade_ai` gem 提供统一 Gateway（`PallasTrade::AI::Gateway.call(capability:, store:, actor:, input:, resource:)`）、代码级能力注册表（`PallasTrade::AI.capabilities.register`）、Run/Artifact 审计、7 道可用性门（系统开关 → 店铺开关 → 能力开关 → 主模型 → 提供商 → 模型 → 凭证 → 预算/并发）、输入/输出 schema 校验；Admin API（`/api/v3/admin/ai/*`）只覆盖**配置**（providers/models/capability_settings/runs/usage），**没有执行端点**。
- **缺口**：Rails Admin **零引用**（审计结论）——商家看不到任何 AI 能力：没有能力定义（仓库里只有测试用的 `test.echo`，且 `unless Rails.env.production?`），没有「生成描述/生成 SEO」的入口与接受流程。
- **目标**：把方案 §七 的安全边界的两个能力接到商品编辑页——① `[Generate with AI]` / `[Rewrite]` 生成商品描述；② `[Generate SEO]` 生成 meta title + meta description；③ 全程 **Generate → Preview → Accept → Save**（AI 绝不直接落库）；④ 未配置 AI 时按钮禁用并给出原因。
- **成功指标**：① 商家在商品编辑页一键得到可读文案草稿，**接受后仍需自己点 Save**（AI 不写库）；② 每次生成在 AI Runs 里留痕（actor/capability/模型/用量）；③ 未配置/未启用 AI 时页面不报错、按钮禁用且给出原因；④ 无 AI 配置的店铺（默认）行为完全不变。

## 2. 用户故事 / 场景

- 作为**运营**，我在商品编辑页面对空描述点 `[Generate with AI]`，几秒后看到预览（含字数），点 Accept 后文案进入描述框，我确认无误后保存。
- 作为**运营**，我对已有描述点 `[Rewrite]`，预览里能看到**新旧对照**，Accept 覆盖 / Discard 放弃。
- 作为**运营**，我在 SEO 卡片点 `[Generate SEO]`，预览显示建议的 meta title / meta description（含长度提示），Accept 后填入两个字段（SEO 预览区同步刷新）。
- 作为**店主**，我没有配置 AI Provider → 按钮禁用并提示「AI 未配置」，其余功能不受影响。
- 边界：商品无名称为空 → 按钮禁用（缺输入）；生成失败/被限流 → 显示可读错误，表单内容不受影响；重复点击 → 请求中禁用按钮（防重）。
- 异常：能力未启用 / 无主模型 / 凭证缺失 / 超预算 → 后端返回原因码，前端展示对应文案。

## 3. 功能需求（FR）

- **FR-001 能力注册（代码级）**：新增两个能力定义（非测试专用，生产可用）：
  - `catalog.product_description`（`display_name: 'Product description'`，input：`{ product_name, category, attributes, existing_description, locale, tone, mode(generate|rewrite) }`，output：`{ text }`；`execution: :sync`；`allowed_parameters: %i[temperature max_output_tokens]`；`data_classification: 'internal'`）。
  - `catalog.product_seo`（input：`{ product_name, category, description, locale }`，output：`{ meta_title, meta_description }`；同上执行语义）。
  - 注册点：`pallastrade_ai` 的**生产可用** initializer（与 `test_capabilities.rb` 区分开，避免污染测试注册表）；重复注册需幂等守卫。
- **FR-002 业务服务**：`PallasTrade::AI::Catalog::ProductCopy`——把商品事实（名称、分类、关键属性/SKU、现有文案、店铺默认语言）组装为 `messages` + `system_instructions`，经 `Gateway.call` 执行，返回 `{ status, text/meta, run_id, error_code }`；**服务不写任何商品字段**（纯生成）。提示词只用于调用，不落库（Run 只留 `input_digest`）。
- **FR-003 描述辅助（Admin）**：商品编辑页描述字段旁 `[Generate with AI]` / `[Rewrite]`；`POST /admin/products/:id/ai/description`（`mode=generate|rewrite`）→ JSON `{ text, run_id }`。
- **FR-004 SEO 辅助（Admin）**：SEO 卡片（`shared/_seo`）`[Generate SEO]`；`POST /admin/products/:id/ai/seo` → JSON `{ meta_title, meta_description, run_id }`。
- **FR-005 预览与接受（安全边界，§7.2）**：结果先进入**预览面板**（描述：全文 + 字数 + 与现有文案的对照；SEO：两个字段 + 长度提示），用户显式 **Accept** 才写入表单控件（描述框 / meta 输入），**由商家自行 Save**；**Discard** 丢弃；AI 永不自动保存、永不改价格/库存/渠道/上架状态。
- **FR-006 可用性与降级**：触发前先 `PallasTrade::AI::AvailabilityService.check`（零副作用）；不可用 → 按钮禁用 + 原因提示；Gateway 返回 `unavailable/skipped/rejected` → 展示对应可读文案，表单不变、页面不报错。
- **FR-007 审计**：每次执行产生 `PallasTrade::AI::Run`（actor、capability_key、模型、状态、用量）→ AI → Runs 可见；响应携带 `run_id` 便于前端展示与排障。
- **FR-008 权限**：仅对商品有 `update` 权限的管理员可触发；控制器 `authorize! :update, PallasTrade::Product`；能力注册的 `authorization: { action: :update, subject: 'PallasTrade::Product' }`。
- **FR-009 i18n**：`admin.products.ai.*`（`generate` / `rewrite` / `generate_seo` / `preview_heading` / `accept` / `discard` / `word_count` / `length_hint` / `errors.<code>` / `disabled_reason.<code>`），en + zh-CN 同步（仓库现状两语言）。
- **FR-010 安全边界与不做**：不改 AI Gateway/Registry 契约；不给 AI 任何写库路径；不做 Translation 能力（E-2）；不新增 API v3 端点（仅 Admin HTML + JSON 端点）；零迁移。

## 4. 非功能需求（NFR）

- **隐私**：提示词/响应正文不写库；Run 仅存 `input_digest` + 用量 + 状态；错误信息不回显凭证。
- **性能**：同步调用（`execution: :sync`），前端请求中禁用按钮并显示 loading；无生成时的页面零额外查询（能力可用性检查只在按钮渲染时做一次轻量查询，失败即降级为禁用）。
- **可测试性**：能力注册/服务/控制器/渲染四层各有规格；用 gem 的测试工厂 + **stub provider adapter**（不打真实 API）。
- **可运维**：AI 未配置的店铺零影响；错误一律走 `AvailabilityService`/Gateway 的既有原因码。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：两个能力在非测试环境也注册成功，且重复注册不抛错（幂等）。
- AC-002 ← FR-001：输入/输出 schema 校验生效（缺 `product_name` → 输入校验失败；输出缺 `text`/`meta_title` → 输出校验失败）。
- AC-003 ← FR-002：服务用商品事实构造 messages（含名称/语言），并把 `resource:` 传为商品。
- AC-004 ← FR-003：`POST /admin/products/:id/ai/description` 成功 → `200 { text, run_id }`，创建 Run。
- AC-005 ← FR-004：`POST /admin/products/:id/ai/seo` 成功 → `200 { meta_title, meta_description, run_id }`。
- AC-006 ← FR-005：**接受前商品字段不变**（请求前后 DB 值一致）——生成只返回文本，不落库。
- AC-007 ← FR-006：AI 未配置（无 Setting/CapabilitySetting）→ 端点返回 `422/`可读原因码，页面渲染的按钮为 disabled 且带 `data-ai-state` 标记。
- AC-008 ← FR-008：无商品 update 权限的用户触发 → 被拒绝（403/重定向），不产生 Run。
- AC-009 ← FR-007：Run 记录包含 `capability_key`、`user`(actor)、`status`；失败时含 `error_code`。
- AC-010 ← FR-009：i18n 键齐备（`PallasTrade.t(key, default: nil)` 非空），en 与 zh-CN 同步。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | ai / copilot | 宿主 app 无 AI 相关代码 | 缺口：需新增（按本仓惯例落 gem） |
| AI Gem | `backend/pallastrade_gems/pallastrade_ai/` | capability / gateway / run | `app/services/pallastrade/ai/gateway.rb`（sync/async + Run + schema 校验 + 7 道门）、`availability_service.rb`（零副作用预检）、`lib/pallastrade/ai/capability_registry.rb`（`register(key, handler:, input_schema:, output_schema:, authorization:, execution:, allowed_parameters:, required_model_capabilities:)`）、`schemas/base_*_schema.rb` + `schemas/test_echo.rb`（Handler 契约 `build_messages(run)` / `apply_result(run, response)`）、`config/initializers/test_capabilities.rb`（**仅 dev/test 注册**）、Admin API `/api/v3/admin/ai/*`（**配置面，无执行端点**）；`app/models/pallastrade/ai/{run,artifact,capability_setting,provider,model,provider_secret}.rb` | **后端齐备** → 本批只做「能力定义 + 业务服务 + Admin UI 接线」 |
| Core Gem | `pallastrade_core/` | product description/seo | `models/pallastrade/product.rb`（`description` 翻译字段；`meta_title/meta_description`；`TRANSLATABLE_FIELDS`）、现有 `ProductHistory`（D-1）可记变更 → 保存后自动留痕 | ✅ 无需改动（只读商品事实） |
| API Gem | `pallastrade_api/` | ai | 无 AI 端点引用（AI 在自身引擎下挂 `/api/v3/admin/ai/*`） | ✅ 本批不加 v3 端点 |
| Admin Gem | `pallastrade_admin/` | description/seo/product form | `app/views/pallastrade/admin/products/form/_base.html.erb`（描述 textarea，`pallastrade-rte`）、`app/views/pallastrade/admin/products/_form.html.erb`（`data-controller="product-form slug-form seo-form"`，渲染 `shared/seo`）、`app/views/pallastrade/admin/shared/_seo.html.erb`（`meta_title`/`meta_description` 输入 + 预览 target）、既有 Stimulus（`seo-form` 有 `titleInput`/`descriptionInput`/`updatePreviews` target 与 action）、D-1 的 `product_form_sidebar_partials` 注入点 | **注入点与既有交互齐备** → 新增按钮 + 新增 `ai-assist` Stimulus + 控制器动作 |
| Storefront | `storefront/src/` | ai | 无 | ✅ 不涉及 |
| Platform | `platform/packages/` | ai | 无 | ✅ 不涉及 |

**结论**：AI 的模型/凭证/额度/审计/降级全部已由 gem 承担，本批缺口只有三块——**能力定义（注册 + schema）**、**业务服务（商品事实 → 提示词 → Gateway）**、**Admin UI（按钮 → 预览 → 接受）**。

## 7. 技术影响

- **AI Gem（新增）**：`config/initializers/catalog_capabilities.rb`（生产可用注册，幂等）、`app/services/pallastrade/ai/catalog/product_copy.rb`（提示词组装 + Gateway 调用）、`app/services/pallastrade/ai/schemas/catalog/product_description.rb`、`.../product_seo.rb`（Input/Output schema + Handler）。
- **Admin Gem（改动）**：`products/form/_base.html.erb`（描述按钮 + 预览容器）、`shared/_seo.html.erb`（SEO 按钮 + 预览容器）、`products_controller.rb`（`ai_description` / `ai_seo` 两个动作 + `authorize!`）、`config/routes.rb`（`post :ai_description` / `:ai_seo`）、`config/locales/en.yml` + `zh-CN`（`admin.products.ai.*`）、新增 Stimulus `ai_assist_controller.js`（按钮 → fetch → 预览 → Accept/Discard；注册到 admin 的 controllers 清单）。
- **数据库**：**零迁移**（复用 `pallastrade_ai_runs` 等既有表）。
- **契约**：不加 v3 端点 → `generated:check` 无影响。
- **测试（新增）**：`spec/services/pallastrade/ai/catalog/product_copy_spec.rb`、`spec/requests/pallastrade/admin/products_ai_spec.rb`（+ 能力注册/降级/权限/审计断言），注册 verifier `ai-copilot-rspec`。
- **风险**：真实 provider 调用成本（规格用 stub adapter；生产由既有预算/并发门控制）；提示词泄露业务数据（只发必要字段，`data_classification: internal`）；误点导致覆盖文案（预览 + Accept 双保险，且不落库）。

## 8. 测试计划

- `spec/services/pallastrade/ai/catalog/product_copy_spec.rb`：AC-001/002/003/009（注册幂等、schema 校验、messages 组装、Run 审计）。
- `spec/requests/pallastrade/admin/products_ai_spec.rb`：AC-004~008/010（两个端点成功路径、**接受前不落库**、未配置降级、权限、i18n）。
- 渲染断言：编辑页出现两个 AI 按钮 + 预览容器（`data-testid`），未配置时为 disabled。
- 注册 verifier：`ai-copilot-rspec`（2 个 spec 文件）。

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-admin/SKILL.md`（新增「AI Product Copilot」章节：能力注册点/提示词在业务服务/前缀 id 与 404/按钮可用性/Stimulus 同步 TinyMCE/AI 缩写 Zeitwerk 坑）
- [x] `harness/scenarios/scenarios.json`（GS-137：AI 只出草稿、必须 Accept；`eval-ai --scenarios` → **138/138 valid**）
- [x] `harness.config.mjs`（verifier `ai-copilot-rspec`）+ `AGENTS.md` §6 行
- [x] 本 PRD 状态 + `docs/prd/README.md` 索引（`prd-status-sync --fix/--check` 150/150）
- [x] `pallastrade-api-v3` / `pallastrade-data-model`（已评估，无需更新：零迁移、无 v3 端点变更）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-15 | 0.1 | 初稿（Batch E-1：FR-001~010 / AC-001~010；范围=描述 + SEO，Translation 留 E-2） | AI |
| 2026-09-15 | 1.0 | 用户确认「确认实施（描述 + SEO，按一期 Scope）」；实施完成：两个能力注册 + 业务服务（Gateway + Run 审计）+ 两个 admin 端点 + 描述/SEO 按钮与预览 + `ai-assist` Stimulus + 可用性降级；规格 14 例绿 | AI |
