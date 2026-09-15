# REQ-20260915 — Batch E-1（AI Product Copilot 第一版：描述生成 + SEO 生成，Generate → Preview → Accept）

> 关联 PRD：`docs/prd/catalog/PRD-20260915-catalog-batch-e1-ai-copilot.md`
> 任务：TASK-20260915143447-998cfbdd ｜ Gate：GATE-2026-09-15T14-35-05（feature）

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — 宿主代码 | `backend/app/` | ai / copilot | 零命中 | 缺口：需新增（按本仓惯例落 gem） |
| AI Gem（本批主战场） | `backend/pallastrade_gems/pallastrade_ai/` | capability / gateway / run / schema | 见下表 | **后端齐备**，只缺能力定义与 UI 接线 |
| Core Gem | `backend/pallastrade_gems/pallastrade_core/app/` | description / meta_title | `models/pallastrade/product.rb`（`description` / `meta_title` / `meta_description` 均为翻译字段 + `TRANSLATABLE_FIELDS`；D-1 的 `ProductHistory` 在保存后自动留痕） | ✅ 只读即可 |
| API Gem | `pallastrade_api/app/` | ai | 无 | ✅ 不加 v3 端点 |
| Admin Gem | `pallastrade_admin/app/` | product form / seo / stimulus | `products/form/_base.html.erb`（描述 textarea `pallastrade-rte`）、`products/_form.html.erb`（`data-controller="product-form slug-form seo-form"`）、`shared/_seo.html.erb`（`meta_title`/`meta_description` + `seo-form` 的 `titleInput`/`descriptionInput`/`updatePreviews`）、D-1 注入点 `product_form_sidebar_partials` | **注入点与既有交互齐备** → 加按钮 + 新 Stimulus + 控制器动作 |
| Storefront | `storefront/src/` | ai | 无 | ✅ 不涉及 |
| Platform | `platform/packages/` | ai | 无 | ✅ 不涉及 |

### AI Gem 能力面盘点（本批最关键的事实）

| 组件 | 事实 |
|---|---|
| `PallasTrade::AI::Gateway` | `call(capability:, store:, actor:, input:, resource:, idempotency_key:)` → 可用性检查 → schema 校验（输入/输出）→ 建 `Run` → provider 适配器调用 → 成功/失败归一；`input[:messages]` + `input[:system_instructions]` 由**调用方**组装 |
| `AvailabilityService.check` | 零副作用预检：能力注册 → 系统开关 → 店铺 `Setting` → `CapabilitySetting` 启用 → 主模型 → provider active → model active → 凭证 → 预算/并发 |
| `CapabilityRegistry#register` | 代码级注册：`handler:` / `input_schema:` / `output_schema:` / `authorization:` / `execution: :sync|:async` / `allowed_parameters:` / `required_model_capabilities:` / `data_classification:` |
| 现有能力 | **仅 `test.echo`**，且 `config/initializers/test_capabilities.rb` 用 `unless Rails.env.production?` 包住 → 生产零能力 |
| Handler 契约 | `build_messages(run)` + `apply_result(run, response)`（`schemas/test_echo.rb` 为样板） |
| Admin API | `/api/v3/admin/ai/*`：providers / models / capability_settings / runs / usage / credentials / connection_tests —— **全部是配置面，没有执行端点** |
| 审计 | `PallasTrade::AI::Run`（actor/capability/模型/状态/用量）+ `Artifact` |

### 搜索结论

- 方案 §七 原话「真正需要开发的主要是 **Admin UI 和 capability wiring**，而不是重新建设 AI backend」与本次盘点完全一致：Gateway/注册表/审计/降级/预算全部已存在。
- 因此本批的边界很清晰：**能力定义（2 个）+ 业务服务（提示词组装）+ Admin UI（按钮 → 预览 → 接受）**；不碰 Gateway 契约、不加 v3 端点、零迁移。
- 安全边界依据方案 §7.2：禁止自动价格/库存/上架/渠道/无人审核保存 → 所有生成走 **Generate → Diff/Preview → Accept → Save**，且服务层**不写商品字段**。
- 范围依据方案 §十五（一期 Scope 只列 Description Assistant + SEO Assistant）→ Translation 留 E-2。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树优先级：能在既有能力上「加维度/接线」就不要新造平台——本批遵循「AI 后端已存在 → 只做 capability wiring + Admin UI」；admin 侧栏/表单改动走 partials API 而非另建页面 |
| `ai/skills/pallastrade-admin/SKILL.md`（领域） | ✅ 已读 | 新增 admin 交互三件套：① 控制器动作 + `authorize!`（`ResourceController#update` 已锚定商品权限）；② 视图改 gem 源 + `# PALLAS-CUSTOM:` 标记；③ Stimulus 控制器须在 admin controllers 清单登记；i18n 断言用 `PallasTrade.t(key, default: nil)` |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | §4 阶段 2：PRD → REQ → gate prep → `supervise plan/diff`（guard 阻断 error/critical）→ §8 知识同步门 `sync-check --ack` |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-security` | ☑ 涉及 | ✅ 已读 | 凭证一律经 `ProviderSecret`（不回显）；错误信息不得带密钥；新增端点必须走既有授权链 |
| `pallastrade-testing` | ☑ 涉及 | ✅ 已读 | RSpec 容器内跑；verifier 注册到 `harness.config.mjs`；生成类用例必须 stub provider（不打真实 API） |
| `pallastrade-data-model` | ☑ 涉及（判断为零改动） | ✅ 已读 | 迁移可回滚 + `schema.rb` 禁手改 → 本批**零迁移**（复用 `pallastrade_ai_*` 既有表） |
| `pallastrade-api-v3` | ⬜ 不涉及 | — | 不加 v3 端点（AI 配置面已存在） |
| `pallastrade-storefront` | ⬜ 不涉及 | — | 无前台改动 |

---

## 需求标题

商品编辑页 AI 助手：描述生成/重写 + SEO 生成，全程 Generate → Preview → Accept → Save（AI 不写库）。

## 任务类型

新功能（Admin UI + AI capability wiring；零迁移、零 v3 契约变更）

## 需求描述

商家在商品编辑页点按钮触发 AI，结果先进入预览（描述对照/SEO 双字段），显式 Accept 后才填入表单，保存仍由商家完成；AI 未配置时按钮禁用并给出原因。

## 影响范围（harness affected 输出）

```text
（实施前预估）backend/pallastrade_gems/pallastrade_ai/** + pallastrade_admin/**（views/controller/routes/locales/stimulus）
+ backend/spec/services/pallastrade/ai/** + backend/spec/requests/pallastrade/admin/**
+ ai/skills/pallastrade-admin/SKILL.md + harness/scenarios + harness.config.mjs + AGENTS.md + docs/prd/**
```

## 技术方案（初步）

- **能力**：`catalog.product_description` / `catalog.product_seo`（`execution: :sync`、`data_classification: 'internal'`、`authorization: { action: :update, subject: 'PallasTrade::Product' }`）+ Input/Output schema。
- **服务**：`PallasTrade::AI::Catalog::ProductCopy`（组装 messages/system instructions → `Gateway.call` → 返回文本 + run_id；不写库）。
- **Admin**：两个 JSON 动作（`ai_description` / `ai_seo`）+ 视图按钮 + 预览容器 + `ai-assist` Stimulus（fetch → 预览 → Accept/Discard）；i18n `admin.products.ai.*`。

## 风险点

- 真实调用成本 → 规格 stub adapter；生产沿用既有预算/并发门与 availability 预检。
- 提示词携带商品数据 → 只发必要字段；Run 仅存 `input_digest`，不存提示词正文。
- 误覆盖文案 → 预览 + Accept 双保险；AI 无任何写库路径（AC-006 断言「接受前字段不变」）。
- 回滚难度：**低**（纯新增能力/服务/视图/端点；无迁移、无数据形态变更）。

## 决策节点

> ⏸️ **等待用户确认**（R3/R7）：方案 §十五 一期 Scope 含「Description Assistant / SEO Assistant」，本 PRD 以此为范围（Translation 留 E-2）。用户确认「实施」后才 clear `user-confirmed` 并开始编码。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| 能力注册 + schema | `pallastrade_ai/config/initializers/catalog_capabilities.rb` + `schemas/catalog/{product_description,product_seo}.rb` | `harness verify ai-copilot-rspec --task …` | 注册键 `["catalog.product_description", "catalog.product_seo", "test.echo"]`（容器内核对）；schema 校验用例绿 | ✅ |
| 业务服务 | `services/pallastrade/ai/catalog/product_copy.rb` | 同上 | 7 例绿（Run 审计 + 事实进提示词 + 未配置降级 + **不落库**） | ✅ |
| Admin 端点/视图/Stimulus/i18n | `ai_controller.rb` / `routes.rb` / `products/form/_base.html.erb` / `shared/_seo.html.erb` / `products/_form.html.erb` / `ai_assist_controller.js` / `application.js` / `en.yml` | 同上 | 7 例绿（两个端点 + 跨店 404 + 降级 422 + 页面 3 个按钮 disabled + 权限 + i18n） | ✅ |
| 安全边界回归 | 全流程 | 断言「接受前商品字段不变」+ 无写库路径 | AC-006 直接断言 `product.reload.attributes` 前后相等 | ✅ |
| 知识同步 | admin Skill / GS-137 / verifier / AGENTS §6 | `eval-ai --scenarios`（138/138）+ `doc-impact` + `sync-check` | 见 PRD §9 | ✅ |

### 验证结论

- **测试**：`ai-copilot-rspec` 定向 **14 例绿**（service 7 + request 7）。
- **实施期踩坑（已写进 Skill）**：① Zeitwerk 因 `inflect.acronym 'AI'` 要求 helper 定义为 `AIAssistHelper`（首版 `AiAssistHelper` 直接启动失败）；② `ResourceController#resource_not_found` 在 `skip_before_action :load_resource` 的控制器上会拿 `PallasTrade::AI` 当 model_class 而炸 → copilot 动作自行 rescue 并返回 JSON 404；③ 前端必须用**前缀 id**（`prefixed_id`）而不是 slug；④ 未配置时门店开关先于能力开关命中，返回 `ai_disabled`（测试断言按真实门位）。
- **零迁移 / 零契约声明**：未新增表/列；未动 `/api/v3` 端点与 OpenAPI/SDK 契约。
- **关键不变量**：端点只返回草稿，接受前商品字段零变化（AC-006），保存仍由商家完成。
