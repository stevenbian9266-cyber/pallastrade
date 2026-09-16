# PRD-20260916-catalog-batch-e3-ai-fix-suggestion

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-16 |
| 来源 | 《商品升级方案 V1.0》§3.3「商品智能辅助」第四项 `Catalog Health → AI Fix Suggestion`；§六「Catalog Health：待办中心」+ §六.1 V2（本批不做评分） |
| 分类 | catalog（商品域 / AI 辅助 / 健康治理） |
| 关联 Skill | pallastrade-admin / pallastrade-catalog / pallastrade-testing |
| 关联 REQ | REQ-20260916-batch-e3-ai-fix-suggestion.md（实施时回填） |
| 关联 PRD | 上游：B-2 Catalog Health V1（7 类 issue 工作台）、E-1 AI Copilot（描述/SEO）、E-2 AI Translate Missing（翻译补全） |
| 需求类型 | 新功能（Admin UI + capability wiring；**只读**、零迁移、无 v3 契约变更） |

> 🔁 **查重**：`harness prd new` 通过。**范围依据**：方案 §3.3 列出的四项智能辅助中，描述 / SEO（E-1）与翻译（E-2）已交付，本批 = 第四项 `Catalog Health → AI Fix Suggestion`；§七.1「第一版只做三个能力」的边界不复用（那是 AI 第一版），但本批仍遵守 §七.2 的安全边界：**AI 不得自动改价格/库存/上架/渠道，不得无人审核保存** —— 因此本批产物是**建议文本**，不是自动修复。

## 1. 背景与目标

- **背景**：Catalog Health V1 已把散落的商品问题收成**待办中心**（`/admin/catalog_health`：7 类 issue 计数 + 「去修复」链接 → 过滤列表 / Product Translations 覆盖页 / Redirects 页）；E-1/E-2 又给「内容类问题」装上了 AI 修复动作（描述 Generate/SEO Generate、翻译抽屉 `[AI Translate Missing]`）。**仍缺的一跳**是：运营看到 `missing_description = 31` 时，不知道**先做什么、按什么顺序、哪些商品最值得先修、每步落在哪个入口**——只能自己摸索。
- **缺口**：① 工作台每行只有「计数 + 去修复」，没有「怎么修」；② 采样既有数据（哪些商品、缺什么、库存/状态如何）从未被汇总成可读结论；③ `pallastrade_ai` 无「按 issue 生成修复建议」的能力。
- **目标**：在工作台每类 issue 行加 `[AI Fix Suggestion]`：服务端**只读采样**该 issue 下的少量商品事实 → 生成 **summary + 可执行步骤清单**（每步都能落到既有入口）→ 就地展开预览；**不写任何数据、不自动修复、不新建修复通道**。
- **成功指标**：① 一次点击得到 `summary` + 3–6 步步骤，步骤指向既有入口（商品编辑页 AI 助手 / 翻译抽屉 / 媒体 / 变体库存 / Redirects / 发布）；② **零写库**（请求前后 DB 可断言无变化）；③ 采样受限且只读（≤5 个商品、最小字段、不含客户/成本数据）；④ 计数 0、未知 issue、未配置 AI、无权限四类边界都有明确行为；⑤ 未装 AI 引擎或未配置 AI 的店铺，页面与今天**完全一致**。

## 2. 用户故事 / 场景

- 作为**运营**，我在 Catalog Health 看到 `missing_description = 31`，点 `[AI Fix Suggestion]`，拿到「先修哪 5 个（按库存/状态排序）→ 在商品编辑页用 Generate with AI → 保存后回工作台复核计数」这样的步骤清单，照着做。
- 作为**运营**，`missing_translations = 102` 这类**没有商品过滤列表**的 issue，我拿到的是按语言维度的推进顺序（先补 `de` 再补 `fr`）与入口（翻译抽屉 tab）。
- 作为**运营**，某个 issue 计数为 0 → 该行**不显示**按钮（无事可做，不给噪音）。
- 作为**店主**，我没有配置 AI Provider → 按钮禁用并提示原因，工作台其余部分与今天一致。
- 边界：AI 引擎未安装 → 页面渲染与今天**逐字节一致**（无按钮、无面板）；采样不足（该 issue 只有 1 个商品）→ 建议仍生成，措辞不夸大；采样为空（计数 >0 但采样取不到，例如已并发修复）→ 明确说明「当前样本为空」而不是编造。
- 异常：未知 issue key / 非法参数 → 422 + 稳定原因码；Gateway 失败/限流/超预算 → 预览区显示可读原因，工作台不受影响；重复点击 → 请求中禁用按钮。

## 3. 功能需求（FR）

- **FR-001 能力注册（代码级，生产可用）**：在 E-1/E-2 同一 `pallastrade_ai/config/initializers/catalog_capabilities.rb` 注册 `catalog.health_fix_suggestion`：
  - input `{ issue_key, issue_label, hint, count, sample: [ { name, status, missing: [...], stock, price_present } ] }`
  - output `{ summary, steps: [ { title, detail?, entry } ] }`（`entry` = 入口标识，取值限定在已知入口集合内）
  - `execution: :sync`、`data_classification: 'internal'`、`authorization: { action: :read, subject: 'PallasTrade::Product' }`（**只读建议**，与 E-1/E-2 的 `update` 区分）、`required_model_capabilities: %i[text]`、幂等。
- **FR-002 业务服务**：`PallasTrade::AI::Catalog::HealthFixSuggestion`
  - `.available_entries` = 已知修复入口白名单（`product_edit_ai` / `translations_drawer` / `product_media` / `variant_inventory` / `redirects` / `publishing`）。
  - `.sampled_facts(product_scope, key, limit: 5)` → 最小事实数组（**只读**：名称、状态、缺什么、库存是否存在、是否有价格；**不含**客户、订单、成本、供应商）。
  - `.generate(store:, actor:, issue_key:)` → **工作台级**：校验 issue key（`Issues.valid?`）→ 计数（`Report.count_for`）→ 计数 0 → rejected `nothing_to_fix`（不发请求、不建 Run）→ 采样（`Issues.product_relation` 可过滤时取前 5；`missing_translations` / `redirect_unresolved` 无商品关系 → 样本为空并附语言/URL 事实）→ 组装 messages + system instructions → `Gateway.call` → `Result(summary, steps, issue_key, count, run_id, error_code)`；**不写任何数据**。
  - `.generate_for_product(product:, actor:)` → **商品级**（FR-004b）：逐键判定该商品命中的 issue（复用 B-2 口径，见 FR-004b）→ 无命中 → rejected `nothing_to_fix`；有命中 → 组装「商品事实 + 命中问题列表 + 可用入口」→ Gateway → `Result`（同一结构，`issue_keys` 为命中集合）。
  - 输出归一：`steps` 只保留白名单 `entry`；丢弃未知 entry；`summary`/`step.title` 空则视为失败（output schema 兜底）。
- **FR-003 Admin 端点**：`POST /admin/ai/catalog_health_suggestion`，按参数分派两种粒度：
  - **工作台级**：params `{ issue_key }` → 成功 `200 { summary, steps, issue_key, count, run_id }`；未知/非法 key → `422 { error: { code: 'unknown_issue' } }`；计数 0 → `422 { error: { code: 'nothing_to_fix' } }`。
  - **商品级**：params `{ product_id: <prefixed_id> }` → 成功 `200 { summary, steps, issue_keys, run_id }`；商品不在本店/不存在 → JSON 404（复用 E-1 的 `find_copilot_product`）；无命中问题 → `422 nothing_to_fix`。
  - 两者共用：AI 不可用 → `422 { error: { code: <reason> } }`；权限 `authorize! :read, PallasTrade::Product`（复用 E-1 的 JSON 形态与 `ResourceController` 约定）。
- **FR-004 工作台 UI**：`catalog_health/index.html.erb` 每行（`count > 0`）新增 `[AI Fix Suggestion]` 按钮（`data-ai-assist-role="generate"`）+ 该行下方**行内折叠预览面板**（`summary` + `steps` 列表，每步显示 `entry` 对应的可读入口名；原「View / 去修复」链接**保持不动**）；复用 E-1 的 `ai-assist` Stimulus（新增 `suggestion` 分支：只有生成与收起，**没有 Accept**——本批没有可写入目标）。
- **FR-004b 商品级建议（用户 2026-09-16 追加确认）**：商品编辑页侧栏新增「Catalog Health」卡片（**复用 D-1 的 `product_form_sidebar_partials` 注入点**）：列出该商品**命中**的健康问题（`missing_media` / `missing_description` / `missing_seo` / `active_zero_stock` / `old_drafts` / `missing_translations`）——判定一律复用 B-2 口径（可过滤键走 `Issues.product_relation(scope, key, store:).exists?`；`missing_translations` 按该商品在店铺其它支持语言下 `name` 缺失的语言计数）；卡内 `[AI Fix Suggestion]` → 行内展示该商品的修复计划（summary + steps，入口指向同页动作：描述区 AI 助手 / SEO 卡 / 翻译抽屉 / 媒体 / 变体库存 / 发布）。**商品无命中问题时卡片显示空态且不出按钮**；`redirect_unresolved`（URL 变更）不属商品行可判定范围 → 本批在商品级**不列**（工作台级仍有），已记录于 FR-009。
- **FR-005 可用性与降级**：按钮状态经 `ai_assist_state('catalog.health_fix_suggestion')`（零副作用）；不可用 → disabled + `title` 原因；服务端不可用 → 422 原因码；**AI 引擎未安装时 `defined?` 守卫使页面保持原样**。
- **FR-006 审计**：每次真实生成产生 `PallasTrade::AI::Run`（actor/capability/模型/用量），只存 `input_digest`；响应携带 `run_id`。
- **FR-007 安全边界（§七.2）**：**只读建议**——不自动修复、不批量改状态/价格/库存/渠道、不写商品或翻译；采样最小化（≤5 商品、最小字段）；提示词与响应正文不落库；错误信息不回显凭证。
- **FR-008 i18n**：`admin.catalog_health.ai.*`（`button` / `generating` / `idle` / `summary_heading` / `steps_heading` / `dismiss` / `entries.<entry>` / `errors.<code>`），en（与 E-1/E-2 同约定：仓库现状只维护 en）。
- **FR-009 不做（V1 边界）**：不做一键自动修复/批量修复；不做健康评分（方案 §6.1 V2）；不改 `CatalogHealth::Issues` 口径与计数；商品级不列 `redirect_unresolved`（URL 变更不属商品行可判定范围，工作台级仍有）；不新增 v3 端点；零迁移；不动 B-2 工作台既有结构、导航与既有「去修复」链接。

## 4. 非功能需求（NFR）

- **只读保证**：服务与端点无任何写入路径（规格断言 DB 行数与关键字段零变化）。
- **成本与性能**：每类 issue 采样 ≤5 商品、单次同步调用；页面渲染阶段**不**调用 AI（只在点击时）；计数 0 时不发请求、不建 Run。
- **一致性**：`issue_key` 一律经 `CatalogHealth::Issues.valid?` 校验；计数经 `Report.count_for`（与工作台同源）→ 端点的 `count` 与页面计数**必然一致**。
- **可测试性**：能力/schema、服务采样与只读、端点、页面渲染四层各有规格；provider 用 stub（不打真实 API）；CI 环境差异已沉淀（`PALLASTRADE_AI_ENABLED` 与加密密钥需在规格内显式处理，见 E-1/E-2 教训）。
- **可运维**：未装/未配置 AI 的店铺零影响；错误一律走既有原因码；`Run` 与 `usage` 可追踪成本。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：`catalog.health_fix_suggestion` 在非测试环境注册且重复注册幂等；`authorization == { action: :read, subject: 'PallasTrade::Product' }`。
- AC-002 ← FR-001：schema 校验生效（input 缺 `issue_key`/`count` → 无效；output 缺 `summary` 或 `steps` 为空 → 无效）。
- AC-003 ← FR-002：采样**只取该 issue 作用域内**的商品且 ≤5；样本字段为最小集合（断言不含客户/订单/成本键）。
- AC-004 ← FR-002/003：`POST /admin/ai/catalog_health_suggestion` 成功 → `200 { summary, steps, issue_key, count, run_id }` 且创建 Run（`capability_key == 'catalog.health_fix_suggestion'`）。
- AC-005 ← FR-007：**零写库**——请求前后商品属性、商品数、翻译数、健康计数完全一致；服务与端点无写入路径。
- AC-006 ← FR-002/003：计数为 0 → `422 nothing_to_fix` 且**不产生 Run**；未知/非法 `issue_key` → `422 unknown_issue` 且不产生 Run。
- AC-007 ← FR-002：`steps` 经入口白名单过滤（未知 `entry` 被丢弃，不渲染成链接）；`steps` 全空 → 视为失败（原因码可读）。
- AC-008 ← FR-004/005：工作台渲染断言——`count > 0` 的行有 `[AI Fix Suggestion]` 按钮 + 预置面板；`count == 0` 的行**没有**按钮；未配置 AI → 按钮 disabled 且带 `title`。
- AC-009 ← FR-003：无 `read` 权限的用户 → 拒绝且不创建 Run。
- AC-010 ← FR-008：i18n 键齐备（`PallasTrade.t(key, default: nil)` 非空，含 `entries.*` 与 `errors.*`）。
- AC-011 ← FR-002/FR-003/FR-004b：**商品级**成功路径 —— `POST` 带 `{ product_id }` → `200 { summary, steps, issue_keys, run_id }`，`issue_keys` 只含该商品实际命中的键（不夸大）；无命中 → `422 nothing_to_fix` 且零 Run。
- AC-012 ← FR-004b：商品编辑页渲染断言 —— 侧栏出现「Catalog Health」卡片与命中的问题清单；无命中时为空态且**无**按钮；未配置 AI → 按钮 disabled + `title`；跨店 `product_id` → JSON 404。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App（宿主） | `backend/app/` | catalog_health / ai | `app/controllers/pallastrade/admin/ai_controller.rb`（E-1/E-2 的 JSON 端点范式：`find_*` + `authorize!` + `render_copilot_result`）；宿主无 catalog health 代码 | 复用：**只加一个动作** |
| Core Gem | `pallastrade_core/app/` | CatalogHealth | `services/pallastrade/catalog_health/issues.rb`（7 类 issue：口径、`valid?`、`valid_filter?`、`product_relation`）、`services/pallastrade/catalog_health/report.rb`（`Issue(key,count,target,params)`、`count_for`、`total`、`TARGETS`） | ✅ 只读复用（**core 零改动**） |
| API Gem | `pallastrade_api/app/` | catalog_health | 无 | ✅ 不加 v3 端点 |
| Admin Gem | `pallastrade_admin/app/` | catalog_health | `controllers/pallastrade/admin/catalog_health_controller.rb`（`Report.call` + `catalog_health_target_path(issue)`）、`views/.../catalog_health/index.html.erb`（7 行表格：issue/hint/count/View）、`views/.../catalog_health/_products_filter_banner.html.erb`、`products_controller.rb`（`health_issue` 过滤）、E-1 的 `helpers/…/ai_assist_helper.rb` + `javascript/…/controllers/ai_assist_controller.js` | **注入点与交互范式齐备** |
| Storefront | `storefront/src/` | catalog health | 无 | ✅ 不涉及 |
| Platform | `platform/packages/` | catalog health | 无 | ✅ 不涉及 |

**结论**：本批缺口三块 —— ① 能力（`catalog.health_fix_suggestion` + schema）；② 服务（issue 校验 + 只读采样 + Gateway）；③ 工作台 UI 接线（按钮 + 行内预览，复用 `ai-assist` 与新 i18n 键）。**core 与 API 零改动、零迁移、无契约变更**；采样与计数全部复用 B-2 既有口径，保证「页面计数 == 建议里的 count」。

## 7. 技术影响

- **AI Gem（新增/改动）**：`config/initializers/catalog_capabilities.rb`（+1 能力，幂等）；`app/services/pallastrade/ai/schemas/catalog/health_fix_suggestion.rb`（Input/Output + Handler 壳）；`app/services/pallastrade/ai/catalog/health_fix_suggestion.rb`（服务 + `Result`）。
- **宿主 App（改动）**：`app/controllers/pallastrade/admin/ai_controller.rb`（+`catalog_health_suggestion` 动作）；`config/routes.rb`（+`post 'ai/catalog_health_suggestion'`）。
- **Admin Gem（改动）**：`views/.../catalog_health/index.html.erb`（每行按钮 + 行内预览）；`views/.../products/` 侧栏 partial（**商品级「Catalog Health」卡片**，经 `product_form_sidebar_partials` 注入）+ `helpers/…/ai_assist_helper.rb` 复用；`javascript/.../controllers/ai_assist_controller.js`（`suggestion` 分支：无 Accept、按 `steps` 渲染列表、支持 `issue_key` 与 `product_id` 两种载荷）；`config/locales/en.yml`（`admin.catalog_health.ai.*`，en 与 zh-CN 同步）。
- **数据库/契约**：**零迁移**；无 v3 端点 → `generated:check` 无影响。
- **测试（新增）**：`spec/services/pallastrade/ai/catalog/health_fix_suggestion_spec.rb`、`spec/requests/pallastrade/admin/catalog_health_ai_suggestion_spec.rb`；`harness.config.mjs` 注册 verifier `ai-health-suggestion-rspec`。
- **连带断言更新**：`spec/requests/pallastrade/admin/products_ai_copilot_spec.rb`（E-1）在商品编辑页的按钮计数改为**排除健康卡片**后再断言 3 个（E-3 卡片新增 1 个建议按钮）——语义不变，只是作用域更精确。
- **风险**：① 建议里出现不存在的能力/入口 → 入口白名单 + `steps` 过滤（AC-007）；② 采样越界（跨店/含敏感字段）→ 作用域取 `current_store` + 最小字段断言（AC-003）；③ 被误读为「一键修复」→ UI 文案明确「建议」且**无 Accept 按钮**、无写路径（AC-005）；④ 工作台变慢 → 渲染阶段零 AI 调用（NFR）；⑤ 与 B-2 计数口径漂移 → 复用 `Report.count_for` 并断言一致（NFR/AC-004）。

## 8. 测试计划

- **服务规格**（`health_fix_suggestion_spec.rb`）：AC-001/002/003/006/007 —— 能力注册与幂等、schema、采样范围与字段最小化、计数 0 不发请求不建 Run、未知 issue 拒绝、steps 入口白名单过滤。
- **请求规格**（`catalog_health_ai_suggestion_spec.rb`）：AC-004/005/008/009/010/011/012 —— 工作台与商品级两条成功路径 + Run 审计、**零写库**断言、工作台渲染（count>0 有按钮、count==0 无按钮、未配置 disabled + title）、商品编辑页卡片渲染（命中/空态/跨店 404）、权限拒绝零 Run、i18n 键齐备。
- **注册 verifier**：`ai-health-suggestion-rspec`（2 个 spec 文件）；回归同时跑 `ai-copilot-rspec` / `ai-translate-rspec` / `admin-catalog-health` 相关规格（确保 B-2 工作台不回退）。
- **不测**：真实 provider 调用（stub）；storefront（不涉及）；健康评分（不做）。

## 9. 文档同步清单（知识同步门）

- [ ] `ai/skills/pallastrade-admin/SKILL.md`（AI 章节补 `Catalog Health → AI Fix Suggestion`：只读建议、入口白名单、无 Accept、采样最小化）
- [ ] `ai/skills/pallastrade-catalog/SKILL.md`（Catalog Health 段落补「AI 修复建议」：计数同源、无商品过滤列表的两类 issue 的采样行为）
- [ ] `harness/scenarios/scenarios.json`（新增 GS：AI 只给建议、绝不自动修复、采样最小化）
- [ ] `harness.config.mjs`（verifier `ai-health-suggestion-rspec`）+ `AGENTS.md` §6 行
- [ ] `docs/prd/README.md` 索引 + 本 PRD 状态
- [ ] `pallastrade-api-v3` / `pallastrade-data-model` / `pallastrade-i18n`（已评估：无 v3 端点、零迁移、无内容翻译变更 → 无需更新，理由记 §10）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-16 | 0.1 | 初稿（Batch E-3：FR-001~009 / AC-001~010；范围=工作台级只读修复建议；不做自动修复/评分；用户授权原话「直接开下一批」） | AI |
| 2026-09-16 | 1.0 | 用户确认「确认实施」并**扩大范围**：建议粒度 = 工作台级 **+ 商品级**（商品编辑页侧栏卡片，复用 D-1 注入点）；呈现 = 行内折叠面板 → 状态 approved；FR-004b / AC-011 / AC-012 已补 | AI |
| 2026-09-16 | 1.1 | 实施完成：能力 `catalog.health_fix_suggestion`（read 授权）+ schema/服务（采样 ≤5 且字段最小化、计数同源 `Report#count_for`、入口白名单、无命中零 Run）+ `POST /admin/ai/catalog_health_suggestion`（两种粒度）+ 工作台行内面板 + 商品侧栏卡片；规格 22 例绿（CI 等价环境同样 22 例），B-2 工作台 / E-1 / E-2 回归 70 例绿；侧栏 partial 需声明 `locals: (product:, f: nil)`（`render_admin_partials` 会多传 `f:`） | AI |
