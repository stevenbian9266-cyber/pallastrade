# REQ-20260915 — Batch E-2（AI Translate Missing：商品缺失翻译的 AI 补全，Generate → Preview → 手工保存）

> 关联 PRD：`docs/prd/catalog/PRD-20260915-catalog-batch-e2-ai-translate-missing.md`
> 任务：TASK-20260915163159-67973c9a ｜ Gate：GATE-2026-09-15T16-53-16（feature）
> 用户确认：2026-09-15 「确认实施」（此前已确认三项范围：排除 slug / 翻译抽屉入口 / 店铺默认语言→当前 tab）

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — 宿主代码 | `backend/app/` | ai / translation | `app/controllers/pallastrade/admin/ai_controller.rb`（E-1：`product_description` / `product_seo` JSON 动作 + `find_copilot_product`（前缀 id）+ `render_copilot_result`（422 + `error.code`）） | 复用：**只加一个动作**，不新建控制器 |
| AI Gem（本批主战场） | `backend/pallastrade_gems/pallastrade_ai/app/` | capability / schema / catalog | `config/initializers/catalog_capabilities.rb`（E-1 全环境注册，幂等）、`app/services/pallastrade/ai/schemas/catalog/{product_description,product_seo}.rb`（Input/Output + Handler 壳）、`app/services/pallastrade/ai/catalog/product_copy.rb`（Gateway 调用 + `Result`）、`availability_service.rb`（7 道门，零副作用） | **后端齐备** → 加 1 能力 + 1 服务 |
| Core Gem | `backend/pallastrade_gems/pallastrade_core/app/` | translatable / locale | `models/concerns/pallastrade/translatable_resource.rb`（`translatable_fields` / **`get_field_with_locale(locale, field, fallback:)`** / `upsert_translations`）、`models/pallastrade/product.rb`（`TRANSLATABLE_FIELDS = %i[name description slug meta_description meta_title]`、`RICH_TEXT_TRANSLATABLE_FIELDS = %i[description]`）、`services/pallastrade/catalog_health/issues.rb`（`missing_translations` 口径）、`services/pallastrade/locales.rb`、`presenters/pallastrade/csv/product_translation_presenter.rb` | ✅ **只读复用，core 零改动** |
| API Gem | `backend/pallastrade_gems/pallastrade_api/app/` | translation / locale | `controllers/concerns/pallastrade/api/v3/locale_and_currency.rb`（`x-pallastrade-locale` → Mobility 回退）、`store/locales_controller.rb` | ✅ 不加 v3 端点（无契约变更） |
| Admin Gem | `backend/pallastrade_gems/pallastrade_admin/app/` | translations / drawer / tab | `controllers/pallastrade/admin/translations_controller.rb`（`translation_fields = "#{field}_#{normalized_locale}"`、`normalized_locale` = downcase + `-`→`_`、`@locales = supported_locales_list - [default_locale]`）、`views/.../translations/edit.html.erb`（turbo frame 抽屉 + 语言 tab + `hidden_field_tag :translation_locale`）、`views/.../translations/products/_form.html.erb`、`views/.../translations/translation_rows/{text_field_row,textarea_row,tinymce_row}.html.erb`、`helpers/.../ai_assist_helper.rb`（E-1 `ai_assist_state`）、`javascript/.../controllers/ai_assist_controller.js`（E-1 按钮 → fetch → 预览 → Accept/Discard + TinyMCE 同步） | **注入点与既有保存链路齐备** → 抽屉加 AI 区块 + Stimulus 加 `translation` 分支 |
| Storefront | `storefront/src/` | locale | `lib/pallastrade/middleware.ts`（locale cookie/路由）等；翻译内容经既有 API 按 locale 输出 | ✅ 不涉及 |
| Platform | `platform/packages/` | translation | 无翻译相关能力（SDK/CLI/dashboard 均未接） | ✅ 不涉及 |

### 搜索结论

- **商品翻译链路全部已存在**：翻译抽屉（语言 tab + 按 `translatable_fields` 渲染 `#{field}_#{locale}` 输入 + `PUT admin_translation_path` 保存）、覆盖率页（`ProductTranslationsController`，`name_<locale>` 非空计）、Catalog Health 的 `missing_translations` 口径。缺的只是 **AI 补全**这一环。
- **AI 后端全部已存在（E-1 已验证）**：Gateway / 能力注册表 / Run 审计 / 7 道可用性门 / 预算并发 / 前端 `ai-assist` 交互范式。
- 因此本批边界 = **1 个能力 + 1 个业务服务 + 1 个 JSON 动作 + 抽屉 AI 区块**；**core 与 API 层零改动、零迁移、无 v3 契约变更**。
- 安全边界依据方案 §7.2：`Generate → Preview → Accept → Save`，服务层**不写任何翻译**；`slug` 不在本批范围（避免自动改 URL 与唯一性/重定向风险）。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树优先级「Settings → Configuration → Events → Dependencies → Admin/Ransack APIs → Generators → Decorators → Extensions」：本批属于**在既有 admin 页面接线**（比新造模型/装饰器更靠前），且 admin 注入走既有 partials/视图而非新建资源页 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | §「AI Product Copilot」既有五条铁律沿用：能力注册在 `catalog_capabilities.rb`（全环境）、提示词在**业务服务**里组装（不靠 handler `build_messages`）、端点用**前缀 id** 且自处理 404、按钮状态走 `ai_assist_state`（AI 引擎未安装返回 nil）、Accept 写值后 dispatch input + 同步 TinyMCE；Zeitwerk `inflect.acronym 'AI'` → helper 必须 `AIAssistHelper` |
| `ai/skills/pallastrade-i18n/SKILL.md` | ✅ 已读 | **`get_field_with_locale(locale, field, fallback: false)` 是官方推荐的「检测缺失翻译」方式**（请求上下文里 store 级回退会把默认语言值当译文返回；`fallback: false` 才拿到 nil）；数据翻译存 `pallastrade_product_translations`（`(product, locale)` 唯一）；`PallasTrade::Product` 可翻译字段 = name/description/slug/meta_description/meta_title |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-testing` | ☑ 涉及 | ✅ 已读 | RSpec 容器内跑（`DISABLE_SIMPLECOV_MINIMUM=1`）；生成类用例必须 stub provider adapter（不打真实 API）；**CI 不注入 `ACTIVE_RECORD_ENCRYPTION_*`** → 规格里不要真造 `ProviderSecret`（用内存替身满足可用性 Gate 7，见 E-1 修复 `8e0efa2b`） |
| `pallastrade-catalog` | ☑ 涉及 | ✅ 已读 | 商品域既有能力清单（D-1 Product History / D-2 Duplicate Detection）——翻译补全属商品内容治理，**不改 core 模型**；口径类断言要「计数 == 列表条数」一致 |
| `pallastrade-security` | ☑ 涉及（轻） | ✅ 已读 | 不新增凭证面；错误信息不带密钥；新端点必须走既有授权链（`authorize! :update, PallasTrade::Product`） |
| `harness-prd` | ☑ 涉及 | ✅ 已读 | §2 阶段 0：PRD 必须自动扩充（背景/目标/用户故事/FR/AC/技术影响/测试计划/文档同步）→ §3 用户确认 → 阶段 2-5 gate → 实施 → `prd verify` → 知识同步 |
| `pallastrade-api-v3` | ⬜ 不涉及 | — | 不加 v3 端点、无 OpenAPI/SDK 变更（`generated:check` 无影响） |
| `pallastrade-data-model` | ⬜ 不涉及 | — | 零迁移（复用 `pallastrade_product_translations` 既有表） |
| `pallastrade-storefront` | ⬜ 不涉及 | — | 无前台改动 |

---

## 需求标题

商品翻译抽屉里，对**当前语言 tab** 的**缺失字段**做 AI 翻译：`[AI Translate Missing]` → 预览 → Accept 填入表单 → 商家自行 Save（AI 不写库）。

## 任务类型

新功能（Admin UI + AI capability wiring；零迁移、零 v3 契约变更）

## 需求描述

运营把商品翻译成某语言时，只需在翻译抽屉的对应语言 tab 点一次按钮：系统以**店铺默认语言**为源、按**只补空缺**的原则翻译 `name / description / meta_title / meta_description`，结果先进入预览（字段 → 译文），商家 Accept 后填入各输入框（描述同步富文本编辑器），最后点抽屉既有的 Save 落库。没有缺失字段时不发请求、不建 Run，直接给出「无缺失」提示；AI 未配置时按钮禁用并说明原因。

## 影响范围（预估）

```text
backend/pallastrade_gems/pallastrade_ai/config/initializers/catalog_capabilities.rb          （+1 能力）
backend/pallastrade_gems/pallastrade_ai/app/services/pallastrade/ai/schemas/catalog/product_translation.rb  （新）
backend/pallastrade_gems/pallastrade_ai/app/services/pallastrade/ai/catalog/product_translation.rb          （新）
backend/app/controllers/pallastrade/admin/ai_controller.rb                                   （+1 动作）
backend/config/routes.rb                                                                     （+1 路由）
backend/pallastrade_gems/pallastrade_admin/app/views/pallastrade/admin/translations/products/_form.html.erb （AI 区块 + 行标记）
backend/pallastrade_gems/pallastrade_admin/app/javascript/pallastrade/admin/controllers/ai_assist_controller.js （translation 分支）
backend/pallastrade_gems/pallastrade_admin/config/locales/{en,zh-CN}.yml                     （admin.translations.ai.*）
backend/spec/services/pallastrade/ai/catalog/product_translation_spec.rb                     （新）
backend/spec/requests/pallastrade/admin/products_ai_translation_spec.rb                      （新）
harness.config.mjs / AGENTS.md / harness/scenarios/scenarios.json / ai/skills/** / docs/prd/**
```

## 技术方案（初步）

- **能力**：`catalog.product_translation`（`execution: :sync`、`data_classification: 'internal'`、`authorization: { action: :update, subject: 'PallasTrade::Product' }`）+ Input（`product_name` / `source_locale` / `target_locale` / `fields`）/ Output（`translations`）schema。
- **服务**：`PallasTrade::AI::Catalog::ProductTranslation` —— `missing_fields(product, target_locale:)`（`fallback: false` 判定，排除 slug）→ 组装 messages（源值 = 店铺默认语言）→ `Gateway.call(capability:, store:, actor:, input:, resource: product)` → `Result(translations, target_locale, run_id, error_code, missing_fields)`；无缺失 → `no_missing_fields`（不调用 Gateway）；**零写库**。
- **端点**：`POST /admin/ai/product_translation`（`product_id` = 前缀 id、`target_locale`）；成功 200 `{ translations, locale, fields, run_id }`；失败 422 `{ error: { code } }`；权限与跨店 404 复用 E-1。
- **UI**：`translations/products/_form.html.erb` 顶部 AI 区块（按钮 + 状态行 + 预览 + Accept/Discard），每个字段行包 `data-ai-translation-row="<field>"`；`ai-assist` Stimulus 加 `kind: 'translation'`（读 `locale`，按字段写 `#{field}_#{locale}` 输入并同步 TinyMCE）；**保存仍走既有 `PUT admin_translation_path`**。
- **i18n**：`admin.translations.ai.*`（en + zh-CN）。

## 风险点

| 风险 | 缓解 |
|---|---|
| 把源语言值误判为「已有译文」（Mobility 回退） | 缺失判定一律 `fallback: false`（AC-003 断言：已有译文不进列表） |
| 语言后缀错位（`zh-CN` vs `zh_cn`）导致填错字段 | 复用 `TranslationsController` 的 `normalized_locale` 规则；端到端断言写入的输入名 |
| 富文本字段被填 HTML | 提示词要求纯文本段落；accept 走 `writeValue` + input 事件，商家可再编辑 |
| 误覆盖已有译文 | V1 只补缺失、绝不覆盖（AC-006 断言请求前后 DB 一致） |
| 无缺失时空跑模型（成本/噪音） | `missing_fields` 为空 → 直接 `no_missing_fields`，不发请求不建 Run（AC-007） |
| 规格在 CI 因加密密钥缺失失败（E-1 教训） | 不真造 `ProviderSecret`，用内存替身满足可用性 Gate 7 |

## 验证方案（AC ↔ 命令映射）

| AC | 验证方式 |
|---|---|
| AC-001/002/003/004/007 | `product_translation_spec.rb`（能力注册幂等、schema、`missing_fields` 口径、messages/resource、无缺失零 Run） |
| AC-005/006/008/009/010 | `products_ai_translation_spec.rb`（端点 200 + Run；**接受前翻译零变化**；降级 422 + 抽屉按钮 disabled；权限拒绝零 Run；跨店 404；i18n 键） |
| 回归 | `harness verify ai-translate-rspec --task TASK-20260915163159-67973c9a`；抽屉/翻译既有链路回归（`translations` 相关请求规格）+ `ai-copilot-rspec`（E-1 不回退） |
| 知识同步 | `harness sync-check --id PRD-20260915-catalog-batch-e2-ai-translate-missing` → 处理 → `--ack` |

## 用户确认

- 2026-09-15 用户经问答确认三项范围（字段排除 slug / 翻译抽屉入口 / 店铺默认语言→当前 tab）；
- 2026-09-15 用户回复「确认实施」（PRD 摘要呈现后）→ 进入 gate 与实施。
