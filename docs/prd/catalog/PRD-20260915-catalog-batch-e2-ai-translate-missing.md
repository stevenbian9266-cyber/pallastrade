# PRD-20260915-catalog-batch-e2-ai-translate-missing

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-15 |
| 来源 | 《商品升级方案 V1.0》§七.1「Translation → Translate missing fields」+ §七.2「Generate → Diff / Preview → Accept → Save」安全边界（用户授权原话：「开下一批」，2026-09-15） |
| 分类 | catalog（商品域 / AI 辅助 / 翻译） |
| 关联 Skill | pallastrade-admin / pallastrade-i18n / pallastrade-testing |
| 关联 REQ | REQ-20260915-batch-e2-ai-translate-missing.md（实施时回填） |
| 关联 PRD | 上游批次：E-1（AI Copilot：描述 + SEO，本批为其 §10 预留的第三项 Translation）；D-1（Product History）/ D-2（重复商品检测）/ B-2（Catalog Health：`missing_translations` 口径） |
| 需求类型 | 新功能（Admin UI + capability wiring，零迁移） |

> 🔁 **查重**：`harness prd new` 通过（相似度未触发阻止）。**范围依据**：方案 §七.1 三个能力中 Description / SEO 已由 E-1 交付，本批 = 第三项 Translation；§七.2 的安全边界（AI 不得自动改价格/库存/上架/渠道、不得无人审核保存）在本批沿用。
> **用户已确认的三项范围选择（2026-09-15）**：① 字段 = `name / description / meta_title / meta_description`（**排除 `slug`**）；② 入口 = **商品翻译抽屉**（编辑页 → 翻译 → 当前语言 tab）；③ 源语言 = **店铺默认语言 → 当前 tab 目标语言**（不做手选源语言）。

## 1. 背景与目标

- **背景**：PallasTrade 的商品内容翻译是 **Mobility 多语言表**（`PallasTrade::Product::Translation`），可翻译字段为 `TRANSLATABLE_FIELDS = %i[name description slug meta_description meta_title]`（其中 `description` 是富文本）。后台**已有**翻译编辑链路：商品编辑页头部的 `link_to_edit_translations(product)` → 翻译抽屉（`admin/translations/edit`，turbo frame）+ **语言 tab**（`@locales = supported_locales_list - [default_locale]`）+ `translations/products/_form.html.erb`（按 `translatable_fields` 渲染 `#{field}_#{locale}` 输入）+ 保存（`PUT admin_translation_path`，`TranslationsController#permitted_resource_params` 只放行当前语言后缀字段）。**缺的是**：把「翻译这件事」从纯人工录入变成 AI 辅助——运营面对 102 条缺失翻译（Catalog Health 口径）只能逐个语言、逐个字段手打。
- **缺口**：① `pallastrade_ai` 无翻译能力（能力注册表里只有 E-1 的 `catalog.product_description` / `catalog.product_seo`）；② Admin 翻译抽屉里没有任何 AI 入口；③ 没有「哪些字段在该语言下是空的」的服务端口径（只有 SQL 聚合的覆盖率页 `ProductTranslationsController#build_coverage`，按 `name_<locale>` 是否非空计）。
- **目标**：在翻译抽屉中提供 `[AI Translate Missing]`——服务端按「**店铺默认语言 → 当前 tab 语言**」把该商品**当前缺失**的字段翻译出来，前端**预览**后由商家 **Accept** 填入表单，**保存仍由商家点抽屉的 Save**（沿用 §七.2 的安全边界，AI 全程不写库）。翻译**排除 slug**（避免自动改 URL / 破坏唯一性与重定向链路）。
- **成功指标**：① 运营在任一目标语言 tab 点一次按钮即可得到缺失字段的译文草稿，Accept 后 4 个字段（存在缺失时）填入表单；② 每次生成在 AI Runs 留痕（actor / capability / 模型 / 用量）；③ 无缺失字段时按钮旁给出「本语言无缺失字段」而不是报错或静默；④ 未配置 AI 的店铺：按钮禁用 + 原因提示，抽屉其余功能与保存链路零变化；⑤ **接受前/后 DB 翻译值可断言零变化**（AI 无写库路径）。

## 2. 用户故事 / 场景

- 作为**运营**，我把某商品翻译到 `zh-CN`：抽屉里 `name/description/meta_title/meta_description` 多为空 → 点 `[AI Translate Missing]` → 预览区显示「字段 → 译文」清单 → 点 Accept → 四个输入框被填入（描述走富文本编辑器同步）→ 我核对后点抽屉 Save 落库。
- 作为**运营**，某商品只缺 `meta_description` → 按钮只翻译这一个字段（其余字段保持原样，不被覆盖）。
- 作为**运营**，某商品在该语言下**没有缺失** → 点按钮得到「本语言无缺失字段」的提示，不产生 Run、不发模型请求。
- 作为**运营**，我想改已有译文 → 先手工清空该字段再点按钮（V1 只补缺失，不做「重译/覆盖」）。
- 作为**店主**，我没有配置 AI Provider → 按钮禁用并提示「AI 未配置」，翻译抽屉可正常手填与保存。
- 边界：商品在目标语言已有值 → 不进 `missing`，不会被覆盖；`description` 为空但 `name` 有值 → 只补 `description`。
- 异常：能力未启用 / 无主模型 / 凭证缺失 / 超预算 / 限流 → 后端返回原因码，前端展示对应文案，表单内容不受影响；重复点击 → 请求中禁用按钮（防重）。

## 3. 功能需求（FR）

- **FR-001 能力注册（代码级，生产可用）**：在 E-1 的 `pallastrade_ai/config/initializers/catalog_capabilities.rb` 中新增
  `catalog.product_translation`：`display_name: 'Product translation'`；input `{ product_name, source_locale, target_locale, fields: { name?, description?, meta_title?, meta_description? } }`；output `{ translations: { name?, description?, meta_title?, meta_description? } }`；`execution: :sync`；`allowed_parameters: %i[temperature max_output_tokens]`；`data_classification: 'internal'`；`authorization: { action: :update, subject: 'PallasTrade::Product' }`；注册幂等。
- **FR-002 业务服务**：`PallasTrade::AI::Catalog::ProductTranslation`
  - `.missing_fields(product, target_locale:)` → 该商品在目标语言下**值为空**的可翻译字段（**只取 `name/description/meta_title/meta_description`**；用 `get_field_with_locale(locale, field, fallback: false)` 判定，避免 Mobility 回退把源语言值当译文）。
  - `.generate_missing(product:, actor:, target_locale:)` → 源值取**店铺默认语言**；只把缺失字段放进 `fields`；组装 `messages` + `system_instructions`（说明目标语言、保持品牌名/规格不译、富文本输出纯文本段落）→ `PallasTrade::AI::Gateway.call(capability:, store:, actor:, input:, resource: product)` → 返回 `Result(status, translations, target_locale, run_id, error_code, missing_fields)`；**服务不写任何商品/翻译字段**。
  - 无缺失字段 → 直接返回 `status: :rejected, error_code: 'no_missing_fields'`，**不调用 Gateway**（零模型成本、零 Run）。
- **FR-003 Admin 端点**：`POST /admin/ai/product_translation`，params `{ product_id: <prefixed_id>, target_locale: 'zh-CN' }` → 成功 `200 { translations: {...}, locale: 'zh_cn', fields: [...], run_id }`；无缺失 → `422 { error: { code: 'no_missing_fields' } }`；AI 不可用 → `422 { error: { code: <reason> } }`；权限沿用 E-1（`authorize! :update, PallasTrade::Product` + `current_store` 作用域，跨店商品 → JSON 404）。
- **FR-004 翻译抽屉 UI**：`translations/products/_form.html.erb` 增加 AI 区块（按钮 `[AI Translate Missing]` + 状态行 + 预览面板 + `Accept / Discard`），并把每个字段行包在带 `data-ai-translation-row="<field>"` 的容器里（**不改共享的 `translation_rows/*` partial**，避免影响其它可翻译资源）；Stimulus 复用/扩展 E-1 的 `ai-assist` 控制器（新增 `kind: 'translation'` + `locale`），Accept 时按字段写入 `#{field}_#{locale}` 输入（`description` 同步 TinyMCE 并 `dispatch input`）。
- **FR-005 可用性与降级**：抽屉渲染时经 E-1 的 `ai_assist_state(capability)`（零副作用）决定按钮 enabled/disabled；不可用 → disabled + `title` 原因；服务端不可用 → 422 原因码；两者文案一致。
- **FR-006 审计**：每次真实生成产生 `PallasTrade::AI::Run`（actor、capability_key、模型、状态、用量）；响应携带 `run_id` 便于排障。
- **FR-007 安全边界（§七.2）**：AI 无写库路径（接受前 DB 可断言零变化）；不自动保存；不改 slug；不改价格/库存/上架/渠道；不无人审核保存。
- **FR-008 i18n**：`admin.translations.ai.*`（`translate_missing` / `generating` / `review_hint` / `accept` / `discard` / `idle` / `accepted` / `preview_heading` / `no_missing_fields` / `errors.<code>`），键落在 admin gem 的 `config/locales/en.yml`（与 E-1 的 `admin.products.ai.*` 同约定：仓库现状只维护 en，其他语言由 i18n 包/后续覆盖）。
- **FR-009 不做（V1 边界）**：不做 slug 翻译；不做「重译/覆盖已有译文」；不做批量/整店翻译；不做 Product Translations 覆盖页入口（留后续批次）；不做源语言手选；不新增 API v3 端点（仅 Admin HTML + JSON 端点）；不改 AI Gateway/Registry 契约；**零迁移**。

## 4. 非功能需求（NFR）

- **隐私**：提示词/响应正文不落库（Run 只留 `input_digest` + 用量 + 状态）；不翻译/不存储任何凭证信息；错误信息不回显密钥。
- **性能**：同步调用；只翻译缺失字段（通常 1–4 个），输入体积可控；无缺失时零模型调用零 Run。
- **一致口径**：①「缺失」判定与覆盖率页的 SQL 口径（`name_<locale>` 非空）**方向一致**；② 目标语言取自抽屉当前 tab（`@selected_translation_locale`），落库字段名与 `TranslationsController#translation_fields` 的 `#{field}_#{normalized_locale}` 完全一致。
- **可测试性**：能力注册 / 服务 / 端点 / 抽屉渲染四层各有规格；用 **stub provider adapter**，不打真实 API。
- **可运维**：未配置 AI 的店铺零影响；原因码沿用 `AvailabilityService` 既有枚举 + 本批新增 `no_missing_fields`。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：`catalog.product_translation` 在非测试环境注册成功且重复注册幂等；`authorization` = `{ action: :update, subject: 'PallasTrade::Product' }`。
- AC-002 ← FR-001：schema 校验生效（input 缺 `target_locale` → 无效；input `fields` 为空 → 无效；output 缺 `translations` → 无效）。
- AC-003 ← FR-002：`missing_fields` 只返回**目标语言为空**的字段（已有译文不进列表），且排除 `slug`；源值取店铺默认语言。
- AC-004 ← FR-002：服务把商品事实（名称、源语言值、目标语言）组装进 `messages`，并把 `resource:` 传为商品；译文返回在 `Result#translations`。
- AC-005 ← FR-003：`POST /admin/ai/product_translation` 成功 → `200 { translations, locale, run_id }`，且创建 Run（`capability_key == 'catalog.product_translation'`）。
- AC-006 ← FR-007：**Accept 前不落库**——请求前后 `PallasTrade::Product::Translation` 的目标语言值逐字段一致。
- AC-007 ← FR-002/FR-003：无缺失字段 → `422 no_missing_fields`，**不创建 Run**、不调用 provider。
- AC-008 ← FR-005：AI 未配置 → 端点 `422 <reason>`；抽屉渲染 `[AI Translate Missing]` 为 disabled 且带 `title` 原因。
- AC-009 ← FR-003：无商品 `update` 权限 → 拒绝且不创建 Run；跨店 `product_id` → JSON 404。
- AC-010 ← FR-008：i18n 键齐备（`PallasTrade.t(key, default: nil)` 非空；en 为基准语言，同 E-1 约定）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App（宿主） | `backend/app/` | ai / translation | `app/controllers/pallastrade/admin/ai_controller.rb`（E-1：`product_description` / `product_seo` 两个 JSON 动作 + `find_copilot_product` 前缀 id + 自 rescue 404） | 复用：新增一个 `product_translation` 动作即可 |
| Core Gem | `pallastrade_core/` | translatable / locale | `models/concerns/pallastrade/translatable_resource.rb`（`translatable_fields` / `public_translatable_fields` / `RICH_TEXT_TRANSLATABLE_FIELDS` / **`get_field_with_locale(locale, field, fallback:)`** / `upsert_translations`）、`models/pallastrade/product.rb`（`TRANSLATABLE_FIELDS = %i[name description slug meta_description meta_title]`、`RICH_TEXT_TRANSLATABLE_FIELDS = %i[description]`）、`services/pallastrade/catalog_health/issues.rb`（`missing_translations` 口径）、`services/pallastrade/locales.rb`、`presenters/pallastrade/csv/product_translation_presenter.rb`（CSV 导入导出翻译的既有列定义） | ✅ 只读复用（**不改 core**） |
| API Gem | `pallastrade_api/` | translation / locale | `controllers/concerns/pallastrade/api/v3/locale_and_currency.rb`（`x-pallastrade-locale` → Mobility 回退）、`controllers/pallastrade/api/v3/store/locales_controller.rb`（前台语言列表）、序列化器按 `current_locale` 输出 | ✅ 无需改动（本批不加 v3 端点） |
| Admin Gem | `pallastrade_admin/` | translations / drawer | `controllers/pallastrade/admin/translations_controller.rb`（`translation_fields` = `#{field}_#{normalized_locale}`；`@locales = supported_locales_list - [default_locale]`；`normalized_locale` = downcase + `-`→`_`）、`views/.../translations/edit.html.erb`（turbo frame 抽屉 + 语言 tab + `hidden_field_tag :translation_locale`）、`views/.../translations/products/_form.html.erb`（按 `translatable_fields` 渲染行）、`views/.../translations/translation_rows/{text_field_row,textarea_row,tinymce_row}.html.erb`（`f.pallastrade_text_field "#{field}_#{locale}"`）、`controllers/pallastrade/admin/product_translations_controller.rb`（覆盖率页：`where.not(name: [nil,''])` 逐语言计数）、`helpers/pallastrade/admin/ai_assist_helper.rb`（E-1 的 `ai_assist_state`）、`javascript/.../controllers/ai_assist_controller.js`（E-1 按钮 → fetch → 预览 → Accept/Discard；`writeValue` 同步 TinyMCE） | **注入点齐备** → 抽屉加 AI 区块 + 控制器加翻译动作 |
| Storefront | `storefront/src/` | locale | `lib/pallastrade/middleware.ts`（locale cookie/路由）、`app/[country]/[locale]/**` | ✅ 不涉及（翻译内容经既有 API 按 locale 输出） |
| Platform | `platform/packages/` | translation | 无翻译相关能力（SDK/CLI/dashboard 均未接翻译） | ✅ 不涉及 |

**结论**：本批缺口只有三块 —— ① **能力定义**（注册 + schema，落在 `pallastrade_ai`）；② **业务服务**（缺失字段判定 + 源值组装 + Gateway，**只读商品**）；③ **抽屉 UI 接线**（按钮 → 预览 → Accept 填表单，保存仍走既有 `PUT admin_translation_path`）。后端 AI 基础设施（Gateway / Registry / Run / 7 道可用性门 / 预算并发）全部复用，**core 与 API 层零改动、零迁移**。

## 7. 技术影响

- **AI Gem（改动/新增）**：`config/initializers/catalog_capabilities.rb`（+1 能力，幂等）；`app/services/pallastrade/ai/schemas/catalog/product_translation.rb`（Input/Output + Handler）；`app/services/pallastrade/ai/catalog/product_translation.rb`（服务 + Result）。
- **宿主 App（改动）**：`app/controllers/pallastrade/admin/ai_controller.rb`（+`product_translation` 动作，复用 `find_copilot_product` / `render_copilot_result`）；`config/routes.rb`（+`post :ai_product_translation`）。
- **Admin Gem（改动）**：`views/.../translations/products/_form.html.erb`（AI 区块 + `data-ai-translation-row` 包裹）；`javascript/.../controllers/ai_assist_controller.js`（`kind: 'translation'` 分支：按字段写值 + TinyMCE 同步）；`config/locales/{en,zh-CN}.yml`（`admin.translations.ai.*`）。
- **数据库/契约**：**零迁移**；不新增 v3 端点 → `generated:check` 无影响；不改 OpenAPI / SDK 类型。
- **测试（新增）**：`spec/services/pallastrade/ai/catalog/product_translation_spec.rb`、`spec/requests/pallastrade/admin/products_ai_translation_spec.rb`；`harness.config.mjs` 注册 verifier `ai-translate-rspec`。
- **风险**：① 误把源语言值当译文（必须 `fallback: false` 判定缺失）→ AC-003 覆盖；② 目标语言后缀格式错（`zh-CN` vs `zh_cn`）→ 复用 `TranslationsController#translated` 的 `normalized_locale` 规则并加断言；③ 富文本字段被填成 HTML → 提示词要求纯文本段落 + Accept 用 `writeValue`（含 input 事件）让商家可改；④ 幻觉/串语言 → 输出 schema 校验 + 预览人工确认；⑤ 成本 → 只翻缺失字段、无缺失不发请求。

## 8. 测试计划

- **服务规格**（`spec/services/pallastrade/ai/catalog/product_translation_spec.rb`）：AC-001~004 / AC-007（注册幂等、schema 校验、`missing_fields` 口径（含已有译文与 slug 排除）、messages 组装与 `resource`、无缺失 → `no_missing_fields` 且不建 Run）。
- **请求规格**（`spec/requests/pallastrade/admin/products_ai_translation_spec.rb`）：AC-005~010（成功路径 200 + Run；**接受前翻译零变化**；无缺失 422；未配置降级 422 + 抽屉按钮 disabled 带 title；权限拒绝且不建 Run；跨店 404；i18n 键齐备）。
- **渲染断言**：翻译抽屉 HTML 出现 `[AI Translate Missing]` 按钮（`data-ai-assist-role="generate"`）+ 预览容器 + `data-ai-translation-row` 标记（4 个可翻译字段，`slug` 不在内）。
- **注册 verifier**：`ai-translate-rspec`（2 个 spec 文件）→ `harness verify ai-translate-rspec --task <ID>`。
- **不测**：真实 provider 调用（stub adapter）；storefront（不涉及）。

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-admin/SKILL.md`（新增「AI Translate Missing」小节：缺失口径 `fallback:false` / 两种语言写法与 `resolve_locale` / 只补不覆盖 / 抽屉接线不动共享 partial / 回归命令）
- [x] `ai/skills/pallastrade-i18n/SKILL.md`（新增「Detecting missing translations（含 AI 补全）」：`fallback:false` 官方写法 + 语言代码 vs 表单后缀 + E-2 能力行为）
- [x] `harness/scenarios/scenarios.json`（GS-139：只补缺失、不覆盖、无缺失零 Run、locale 映射；`eval-ai --scenarios` → **140/140 valid**）
- [x] `harness.config.mjs`（verifier `ai-translate-rspec`）+ `AGENTS.md` §6 行
- [x] `docs/prd/README.md` 索引 + 本 PRD 状态（`prd-status-sync`）
- [x] `pallastrade-api-v3`（已评估，无需更新：不加 v3 端点、无 OpenAPI/SDK 变更）、`pallastrade-data-model`（零迁移）、`pallastrade-catalog`（core 只读，无模型/口径变更）
- [x] `harness sync-check --id PRD-20260915-catalog-batch-e2-ai-translate-missing` 评估结论：① **API 端点变更**（`backend/config/routes.rb`）——本批新增的是宿主 **admin JSON 端点**（`/admin/ai/product_translation`），不在 `/api/v3/**` 契约面 → `harness generated:check` = **no drift detected**，OpenAPI/SDK 无需更新；② **Skill/PRD 机制**变更清单里命中的 `pallastrade-prd` Skill 与 `copilot-instructions.md`：PRD 工作流与硬规则本身未变 → 无需更新（`scenarios.json` 已补 GS-139）；③ 清单中其余项（storefront checkout、SDK dist、payments skill 等）来自并行批次的改动，非本 PRD 范围。

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-15 | 0.1 | 初稿（Batch E-2：FR-001~009 / AC-001~010；范围=Translation，排除 slug；入口=翻译抽屉；源=店铺默认语言；用户已确认三项范围） | AI |
| 2026-09-15 | 1.0 | 用户确认「确认实施」→ 状态 approved；实施：能力 `catalog.product_translation` + schema/服务（缺失口径 `fallback:false`、`resolve_locale` 后缀→代码映射、无缺失零 Run）+ `POST /admin/ai/product_translation` + 抽屉 `[AI Translate Missing]`（`data-ai-translation-row` 标记、`ai-assist` 加 `translation` 分支）+ en 文案；规格 17 例绿（含 CI 无加密密钥场景） | AI |
| 2026-09-15 | 1.1 | 收尾：verifier `ai-translate-rspec`（含 CI 无密钥环境回归 17 例绿）、`prd verify` 全部 AC 覆盖、`sync-check --ack`、supervise 本批 0 发现、（standard 风险集 test/review/knowledge 证据齐全）→ 状态 **done**，提交 `6d99acf6` 推送 dev | AI |
