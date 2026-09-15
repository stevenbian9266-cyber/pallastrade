# PRD-20260915-admin-catalog-health-v1

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-15 |
| 来源 | 《商品升级方案 V1.0》Batch B 切片二（用户授权原话：「那就以此为作为 PRD 理想输入，实施」+「继续」，2026-09-15） |
| 分类 | admin（关键词命中：管理后台 / 运营） |
| 关联 Skill | pallastrade-admin / pallastrade-catalog |
| 关联 REQ | REQ-20260915-catalog-health-v1.md |
| 关联 PRD | 同批 Batch B-1 = `PRD-20260915-admin-bulk-operations-2`；Batch A = `PRD-20260915-catalog-pdp-state-correctness` |
| 需求类型 | 新功能（管理后台运营效率） |

> 🔁 **查重**：`harness prd new` 通过。切片划分：Batch B-1 = 批量运营（已交付）；Batch B-2 = Catalog Health V1（本 PRD）；V2（Health Score / Content Completeness 评分）另行立项。

## 1. 背景与目标

- **背景**（《商品升级方案》§六）：缺图、缺描述、翻译覆盖、URL 变更、库存、商品状态等信息**已经存在**，只是分散在 Products List / Product Translations / Redirects / Stock 等模块，商家没有「待办中心」，只能靠记忆逐个页面翻查。
- **目标**：Products 下新增一级运营页 **Catalog Health**，直接给 7 类 Actionable Issues 的**计数 + 一键下钻**（点数量 → 过滤后的商品列表或对应专页）。**一期不做健康分算法**（Score 属 V2，Score 是结果不是建设重点）。
- **成功指标**：① 7 类 issue 计数可复现，且与下钻目标页的语义一致；② 5 类商品级 issue 点击后进入**已过滤**的商品列表，**计数 == 列表条数**（同源 scope 保证）；③ 缺翻译 / URL 未处理分别直达既有 Translations / Redirects 页（零重复建设）；④ 本页与筛选链路**零写入路径**（纯只读，动作由下游批量运营承接）。

## 2. 用户故事 / 场景

- 作为**运营**，我早上打开 Catalog Health，看到「Missing image 26 / Missing description 31 / Missing SEO 58」，点击任一数字进入只含问题商品的列表，勾选后直接用 Batch B-1 的批量动作处理。
- 作为**翻译运营**，我点击 Missing translations，进入翻译覆盖页（按语言看覆盖率与缺名商品）。
- 作为**SEO 运营**，我点击 Redirect unresolved，进入重定向页的 URL 变更区块（可一键预填 301 表单）。
- 边界：店铺无商品 → 全部计数 0（页面显示空态引导）；单语言店铺 → 缺翻译恒 0；无 slug 历史 → URL 未处理 0；商品全部 archived → 商品级 issue 均为 0。
- 异常：`health_issue` 参数非法 → 忽略（不过滤、不显示横幅）；无 `read` Product 权限 → 拒绝访问（由既有权限体系处理）。

## 3. 功能需求（FR）

- **FR-001 待办中心页**：`GET /admin/catalog_health` 渲染固定 7 行 issue（label + count + 下钻链接）；页面只读，无表单。
- **FR-002 商品级过滤列表**：5 类商品级 issue 的下钻链接指向 `/admin/products?health_issue=<key>`，商品列表按同源 scope 过滤。
- **FR-003 缺翻译语义**：与既有 `ProductTranslationsController#build_coverage` **同一口径**（翻译行 `name` 非空视为已翻译），计数 = 非默认受支持语言上的 **(产品 × 语言) 缺失对数**；下钻 → `/admin/product_translations`。
- **FR-004 URL 未处理语义**：复用 `PallasTrade::ProductUrlChange.call(store)`，计数 = `handled == false` 的条数（已建 301 的不计）；下钻 → `/admin/redirects`。
- **FR-005 商品级 issue 口径**（唯一权威，见下表）。
- **FR-006 筛选态横幅**：商品列表顶部（`products_header_partials` 注入点）在筛选生效时显示「当前筛选：<issue 标签> + 清除筛选」链接；非法 key 不显示横幅。
- **FR-007 导航与权限**：Products 子菜单新增 **Catalog Health**（位于 Products List 之后）；导航项与控制器均以 `read`/`admin` + `PallasTrade::Product` 权限为守卫；导航一致性 spec 的子项数组同步。
- **FR-008 边界**：无新表、无迁移、无 v3 API 变更、无新 JS 控制器。

### 3.1 口径表（唯一权威）

| Issue key | 显示名 | 口径（一律排除 `archived`） | 下钻目标 |
|---|---|---|---|
| `missing_media` | Missing image | 产品层（`viewable_type = PallasTrade::Product`）与变体层（`viewable_type = PallasTrade::Variant`，含 master）**都没有资产** | 商品列表过滤 |
| `missing_description` | Missing description | **默认语言**的有效 `description` 为空（翻译行优先、回退 `pallastrade_products.description` 列——Mobility `column_fallback`） | 商品列表过滤 |
| `missing_seo` | Missing SEO | **默认语言**的有效 `meta_title` **或** `meta_description` 为空（任一缺失即计入） | 商品列表过滤 |
| `missing_translations` | Missing translations | 非默认受支持语言中，缺 `name` 翻译的 (产品 × 语言) 对数 | `/admin/product_translations` |
| `active_zero_stock` | Active + zero stock | `status = active` 且**无任何可卖变体**：不存在 `track_inventory = false`、`preorderable = true`、存在库存点 `count_on_hand > 0`、或 `backorderable = true` 的未删除变体 | 商品列表过滤 |
| `redirect_unresolved` | Redirect unresolved | `ProductUrlChange` 中 `handled = false` 的 URL 变更条数 | `/admin/redirects` |
| `old_drafts` | Old drafts | `status = draft` 且 `updated_at` 早于 **30 天**前 | 商品列表过滤 |

> 口径说明：`active_zero_stock` **不计**预售（`preorderable`）与可缺货销售（`backorderable`）变体，避免把「仍可下单」的商品误报为缺货；`missing_translations` 沿用既有翻译页口径，保证与下钻页数字自洽。

## 4. 非功能需求（NFR）

- **同源性**：计数与过滤列表使用**同一个 scope 构造器**（`PallasTrade::CatalogHealth::Issues`），禁止两套口径漂移；规格断言「计数 == 过滤后列表条数」。
- **性能**：商品级 issue 为索引友好 COUNT（`status` / `updated_at` / `media_count` / 翻译 `locale` 索引）；`ProductUrlChange` 为纯库内查询（无外部调用）。
- **降级**：任一项计算异常 → 该项显示 0 并记录日志，页面恒 200（沿用后台只读页降级范式）。
- **只读**：本页与筛选链路无 POST/PATCH/DELETE；不存在「一键修复」写路径（避免越权修改商品）。
- **兼容**：不影响既有 7 个批量动作、Products List 默认行为（无 `health_issue` 参数时零差异）。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：待办中心渲染 7 行 issue，计数与夹具一致。
- AC-002 ← FR-005：`missing_media` 口径——仅变体有图（产品无图）**不算**缺图；产品与变体都无图才计入。
- AC-003 ← FR-005：`missing_description` / `missing_seo` 口径——默认语言的翻译行覆盖列值；翻译行有值即不算缺失；`meta_title`/`meta_description` 任一为空即计入 SEO 缺失。
- AC-004 ← FR-005：`active_zero_stock` 口径——`preorderable` / `backorderable` / `track_inventory = false`、或任一库存点 `count_on_hand > 0` 的商品**不**计入；`draft` 商品**不**计入（只算 active）。
- AC-005 ← FR-005：`old_drafts` 口径——`draft` 且 30 天内更新过的不计入；`active` 不论多旧都不计入。
- AC-006 ← FR-003：`missing_translations`——多语言店铺按 (产品 × 语言) 缺失对数计数；单语言店铺恒 0；翻译行 `name` 非空即视为已翻译。
- AC-007 ← FR-004：`redirect_unresolved`——已存在 301 的 URL 变更不计入；未建 301 的计入。
- AC-008 ← FR-002：`?health_issue=<key>` 过滤商品列表：计数 == 列表条数；非法 key 忽略（等价于未过滤）。
- AC-009 ← FR-006：筛选态横幅仅在有合法 `health_issue` 时渲染，且包含清除链接（回到未过滤列表）；未筛选时不渲染。
- AC-010 ← FR-007：导航项存在且受 `PallasTrade::Product` 读权限守卫；无权限用户访问 `/admin/catalog_health` 被拒绝（重定向/403）。
- AC-011 ← FR-001/FR-006：i18n 键齐备（7 个 issue 标签 + 页面标题/说明 + 横幅文案），经 `PallasTrade.t` 断言。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | catalog_health / 健康 | 无 | 不适用（宿主零改动） |
| Core | `pallastrade_core/` | media_count / preorderable / backorderable / translations / Redirect / ProductUrlChange | `product.rb`（`STATUSES`、`not_archived`、`translates` + `column_fallback`、`has_media?`）、`variant.rb`（`preorder?`、`in_stock_or_backorderable`、`track_inventory`）、`redirect.rb`、`product_url_change.rb`（`handled` 标记）、`pallastrade_product_translations`（name/description/meta_*） | **数据齐备** → 新增 1 个查询服务（Issues）+ 1 个编排服务（Report） |
| API | `pallastrade_api/` | catalog health | 无 | 不适用（本批不动 v3 API） |
| Admin | `pallastrade_admin/` | translations / redirects / products index / partials | `product_translations_controller.rb`（覆盖率 `where.not(name: …)` 口径）、`redirects_controller.rb`（`@url_changes`）、`products_controller.rb#scope`、`resource_controller.rb#scope/#collection`、`products/index.html.erb`（`products_header_partials` 注入点）、`pallastrade_admin_navigation.rb`（`products.add`） | **框架就绪** → 新增页 + 过滤接线 + 横幅注入 |
| Storefront | `storefront/src/` | — | — | 不涉及 |
| Platform | `platform/packages/` | — | — | 不涉及（无 SDK/类型变更） |

**结论**：7 类问题数据全部已在库内（无需新表/迁移）；既有 Translations / Redirects 页可直接承接两类下钻，避免重复建设；缺口 = 一个待办中心页 + 5 类商品级过滤 + 横幅 + 导航。

## 7. 技术影响

- **Core（新增）**：`app/services/pallastrade/catalog_health/issues.rb`（口径唯一权威：7 个 key、商品 scope 构造器、翻译/URL 计数）、`app/services/pallastrade/catalog_health/report.rb`（编排 + 降级）。
- **Admin（改动）**：
  - `app/controllers/pallastrade/admin/catalog_health_controller.rb`（新增，`BaseController` 子类，`model_class = PallasTrade::Product` 锚定授权）
  - `app/controllers/pallastrade/admin/products_controller.rb`（`scope` 覆写：合法 `health_issue` → 追加同源过滤）
  - `app/views/pallastrade/admin/catalog_health/index.html.erb` + `_products_filter_banner.html.erb`（新增）
  - `config/initializers/pallastrade_admin_partials.rb`（横幅注册进 `products_header_partials`）
  - `config/initializers/pallastrade_admin_navigation.rb`（Products 子菜单新增 `catalog_health`）
  - `config/routes.rb`（`resources :catalog_health, only: [:index]`）
  - `config/locales/en.yml`（`admin.catalog_health.*`）
- **规格（新增）**：`backend/spec/requests/pallastrade/admin/catalog_health_spec.rb` + 同步 `navigation_consistency_spec.rb` 子项数组。
- **无 DB 迁移、无 v3 API 变更**（无 OpenAPI/SDK 同步）。
- **风险**：`ProductUrlChange` 为 Ruby 侧遍历（大目录有 N 查询风险）→ 一期接受（页面级只读统计），V2 再下推 SQL；回滚 = revert 提交（无数据迁移）。

## 8. 测试计划

- 新增 `backend/spec/requests/pallastrade/admin/catalog_health_spec.rb`：覆盖 AC-001~011（计数口径逐项夹具、过滤一致性、横幅、权限、i18n）。
- 同步 `backend/spec/requests/pallastrade/admin/navigation_consistency_spec.rb`（Products 子项数组 + 必要的 `stub_current_store!` 控制器清单）。
- 注册 verifier：`admin-catalog-health-rspec`（`harness verify admin-catalog-health-rspec --task <id>`）。
- 手动（可选）：本地 admin 点选验证（UI 冒烟），不作为门禁证据。

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-admin/SKILL.md`（Catalog Health 章节：7 类口径表 + 四件套接线定式 + verifier 指引）
- [x] `harness/scenarios/scenarios.json`（GS-131：Catalog Health worklist；`harness eval-ai --scenarios` → 132/132 valid）
- [x] `harness.config.mjs`（verifier `admin-catalog-health-rspec`）+ `AGENTS.md` §6 表格行
- [x] API 文档：**已评估，无需更新**（不动 v3 API）
- [x] SDK/反模式/任务规则：**已评估，无需更新**
- [x] 本 PRD 状态 + `docs/prd/README.md` 索引（`prd-status-sync --fix/--check`）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-15 | 0.1 | 初稿（Batch B-2：FR-001~008 / AC-001~011 / 7 类口径表） | AI |
| 2026-09-15 | 1.0 | 实施完成：2 个 core 服务（Issues/Report）+ Catalog Health 页 + `scope` 过滤接线 + `products_header` 横幅注入 + 导航子项 + en 键；规格 17 例全绿（verifier `admin-catalog-health-rspec` 含导航一致性回归）；知识同步（admin Skill + GS-131 + verifier + AGENTS §6）→ 状态 done | AI |
