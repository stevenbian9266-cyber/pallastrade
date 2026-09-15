# PRD-20260915-catalog-batch-d2-duplicate-detection

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-15 |
| 来源 | 《商品升级方案 V1.0》§十二「中长期：商品治理」第三步 —— Duplicate Detection（用户授权原话：「继续」，2026-09-15） |
| 分类 | catalog（商品域 / 数据治理） |
| 关联 Skill | pallastrade-admin / pallastrade-catalog / pallastrade-testing |
| 关联 REQ | REQ-20260915-batch-d2-duplicate-detection.md |
| 关联 PRD | 同治理线：`PRD-20260915-admin-catalog-health-v1`（第一步）→ `PRD-20260915-catalog-batch-d1-product-history`（第二步）→ 本 PRD（第三步·检测）；**Merge Product（合并）另行立项 = D-3** |
| 需求类型 | 新功能（只读治理工作台，零迁移、零 API 变更） |

> 🔁 **查重**：`harness prd new` 通过。**范围切分（方案原文）**：「第三步再进入 Duplicate Detection / Merge Product，这是明显的独立专项，因为商品合并会牵涉 Variant、Reviews、Redirects 和历史交易关系」→ 本批只做**检测与对比**（只读），合并留 D-3。

## 1. 背景与目标

- **背景**（《商品升级方案》§十二）：商品数量增长后真正棘手的不再是「怎么编辑」，而是重复商品（同一件商品被建了两次/三次）。现状盘点（6 层搜索）：
  - `PallasTrade::Variant#sku` **有**唯一性校验（大小写不敏感、可 `disable_sku_validation` 关闭、允许为空）→ 冲突仍可能发生；
  - `pallastrade_variants.barcode` **有列有索引、但无任何唯一性校验** → 重复条码完全静默；
  - 商品 `name` 无任何唯一性约束；`slug` 由 `Product::Slugs` 自动去重（冲突时补 uuid），因此 **slug 不是重复信号**；
  - 后台只有「克隆商品」（`Products::Duplicator` / API `duplicate`），**没有任何重复发现能力**。
- **目标**：建立**重复候选发现**（只读工作台）——① 三类信号（条码 / SKU / 名称）自动分组候选；② 每个候选给出命中商品与关键属性对比；③ 商家据此人工裁决（改 SKU/条码 or 归档其一），为 D-3 合并专项提供输入。
- **成功指标**：① 造两个同名商品（大小写/多余空格不同）→ 出现在 `duplicate_name` 候选；② 两个变体共用条码 / 共用 SKU → 各自出现在对应候选；③ 每个信号的**计数 == 候选组数**（同 B-2 口径一致性铁律）；④ 归档商品、已删除变体、其他店铺一律不出现。

## 2. 用户故事 / 场景

- 作为**运营**，我打开 Products → Duplicate Products，看到「条码重复 3 组 / SKU 重复 1 组 / 名称重复 5 组」，点信号只看该类。
- 作为**运营**，我点开一组候选，进入**对比页**并排看到两个商品的状态、变体/SKU、条码、价格、库存、渠道，判断「这是同一件商品被建了两次」。
- 作为**运营**，确认后我去编辑其中一个（改 SKU 或归档）——本批**不做合并写操作**（D-3）。
- 边界：商品只有 master 变体（无 SKU/条码）→ 不参与条码/SKU 信号；名称为空 → 不参与名称信号；跨店同名 → 各自店铺内独立分组。
- 异常：某类信号查询失败 → 该信号计 0、页面仍 200（沿用 Catalog Health 的降级惯例）。

## 3. 功能需求（FR）

- **FR-001 检测服务（口径唯一权威）**：`PallasTrade::Products::DuplicateCandidates`——`SIGNALS = %w[duplicate_barcode duplicate_sku duplicate_name]`、`call(store, signal: nil, limit:)`、`count(store, signal)`、`valid_signal?`；读侧**零迁移**。
- **FR-002 信号口径**（一律：同店 + 商品未删除 + 商品非 archived + 变体未删除）：
  - `duplicate_barcode`：`LOWER(TRIM(barcode))` 相同且非空，且组内**商品数 > 1**；
  - `duplicate_sku`：`LOWER(TRIM(sku))` 相同且非空，且组内商品数 > 1；
  - `duplicate_name`：`LOWER(TRIM(name))` 相同且非空，且组内商品数 > 1。
- **FR-003 分组与截断**：每个候选 = `{ signal, key, products(≤ per-group 上限), total_count }`；组数受 `limit` 限制；计数与列表**同源**（同一构造器）。
- **FR-004 工作台页**：`GET /admin/duplicate_products` —— 三类信号计数概览 + 候选列表（信号徽标 / 组键 / 商品链接 / 组内商品数）+ `?signal=` 过滤 + 空态文案；只读（无表单、无写操作）。
- **FR-005 对比视图**：`GET /admin/duplicate_products/compare?product_ids[]=…` —— 并排展示名称、slug、状态、创建/更新时间、变体数、SKU 列表、条码列表、基础价、库存合计、渠道数；缺失值显示占位符。
- **FR-006 权限与导航**：Products 子菜单新增 `duplicate_products`（`if: -> { can?(:read, PallasTrade::Product) }`，位于 `catalog_health` 之后）；控制器 `BaseController` + `model_class = PallasTrade::Product` 锚定授权；**必须同步 `navigation_consistency_spec.rb` 子项数组**。
- **FR-007 多店隔离**：所有查询经 `current_store` 派生 scope；绝不跨店；策略与 B-2/B-1 一致（`store_id` 过滤）。
- **FR-008 i18n**：`admin.duplicate_products.*`（标题/说明/信号名与提示/列头/空态/对比页字段与占位符），规格断言用 `PallasTrade.t(key, default: nil)`。
- **FR-009 明确不做**：不做商品合并（D-3）、不做自动修复、不加迁移、不改任何 API/契约、不改前台。

## 4. 非功能需求（NFR）

- **性能**：按组聚合查询（`GROUP BY … HAVING COUNT(DISTINCT product_id) > 1`），单信号一次查询取组键 + 一次批量取商品；`limit` 默认 50 组 / 每组 5 商品，避免大目录全表扫描。
- **安全**：聚合键表达式为**常量字符串**（表名取自 AR 常量，无用户输入拼接）；无 raw SQL 插值 → 不引入 Brakeman SQL Injection 告警（B-2 修复后的既定要求）。
- **可运维**：单信号异常降级为 0 并记日志；页面恒 200。
- **可测试性**：request spec 覆盖三类信号 + 计数一致性 + 过滤 + 对比渲染 + 权限 + 导航；注册 verifier。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-002：两个商品同名（规范化后相同）→ 同一 `duplicate_name` 组。
- AC-002 ← FR-002：名称仅大小写/首尾空格不同 → 仍视为同名。
- AC-003 ← FR-002：两个变体共用条码 → `duplicate_barcode` 组；条码为空不分组。
- AC-004 ← FR-002：两个变体共用 SKU（大小写不同）→ `duplicate_sku` 组。
- AC-005 ← FR-003：**每个信号的计数 == 该信号候选组数**（页面概览与列表同源）。
- AC-006 ← FR-002/FR-007：archived 商品、已删除变体、其他店铺的同名/同 SKU/同条码 → 不出现。
- AC-007 ← FR-004：`GET /admin/duplicate_products` 渲染标题、三类信号计数与候选行（含商品链接）。
- AC-008 ← FR-004：`?signal=duplicate_sku` 只显示该类候选；非法 signal 忽略（回全量）。
- AC-009 ← FR-005：对比页并排渲染所选商品的关键字段；缺失值显示占位符。
- AC-010 ← FR-006：Products 子菜单含 `duplicate_products` 且顺序紧随 `catalog_health`；无权限用户访问被拒绝。
- AC-011 ← FR-008：i18n 键集合齐备（`PallasTrade.t(key, default: nil)` 非空）。
- AC-012 ← FR-004：无任何候选时显示空态（页面仍 200）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | duplicate / 重复 | **零命中** | 缺口：需新增（按本仓惯例落 gem：core 服务 + admin 页面） |
| Core | `pallastrade_core/` | duplicate / sku / barcode / slug | `models/pallastrade/variant.rb`（sku 唯一性校验，**barcode 无校验**）、`db/schema.rb`（`variants.barcode` 列 + 索引）、`models/pallastrade/product/slugs.rb`（slug 自动去重 → 非信号）、`services/pallastrade/products/duplicator.rb`（克隆，非检测）、`services/pallastrade/catalog_health/{issues,report}.rb`（B-2 定式） | **无检测能力** → 新增 `Products::DuplicateCandidates` |
| API | `pallastrade_api/` | duplicate | `admin/products_controller.rb`（`@resource.duplicate` = 克隆动作） | ✅ 无检测端点；本批**不加 API** |
| Admin | `pallastrade_admin/` | catalog_health / duplicate | `catalog_health_controller.rb` + `index.html.erb` + `_products_filter_banner.html.erb` + `routes.rb:40` + `pallastrade_admin_navigation.rb:161` + `en.yml` `admin.catalog_health.*` + `spec/requests/.../catalog_health_spec.rb` + `navigation_consistency_spec.rb:107` | **完整模板可复用**（只读工作台四件套） |
| Storefront | `storefront/src/` | duplicate | 仅无关去重（related-products 去重、webhook 幂等） | ✅ 本批不动前台 |
| Platform | `platform/packages/` | duplicate | 文档提到 `client.products.clone()`（克隆）；无检测 | ✅ 本批不动 SDK/CLI |

**结论**：缺口 = **检测与呈现**；存储/权限/导航/页面模板/降级惯例全部已存在，因此本批**零迁移、零契约变更、零前台改动**。

## 7. 技术影响

- **Core（新增）**：`app/services/pallastrade/products/duplicate_candidates.rb`（信号口径 + 分组 + 计数，含 `Group` 结构）。
- **Admin（新增/改动）**：
  - 新增 `app/controllers/pallastrade/admin/duplicate_products_controller.rb`（`index` + `compare`，`model_class = PallasTrade::Product`）
  - 新增 `app/views/pallastrade/admin/duplicate_products/{index,compare}.html.erb`
  - 改 `config/routes.rb`（`get 'duplicate_products'` + `get 'duplicate_products/compare'`）
  - 改 `config/initializers/pallastrade_admin_navigation.rb`（Products 子菜单）
  - 改 `config/locales/en.yml`（`admin.duplicate_products.*`）
- **数据库**：**无迁移**（只读聚合）。
- **契约**：无 API 变更 → `generated:check` 无影响。
- **测试（新增/改动）**：`backend/spec/requests/pallastrade/admin/duplicate_products_spec.rb`（AC-001~009/011/012）+ `navigation_consistency_spec.rb`（AC-010 数组同步）。
- **风险**：大目录聚合查询成本 → 用 `limit` + `GROUP BY/HAVING` 限制；误报（同名但确为不同商品）→ 页面定性为「候选」，文案与 Skill 明确「人工裁决」。

## 8. 测试计划

- `spec/requests/pallastrade/admin/duplicate_products_spec.rb`：AC-001~009、AC-011、AC-012（三类信号夹具 + 计数一致性 + 过滤 + 对比 + i18n + 空态）。
- `spec/requests/pallastrade/admin/navigation_consistency_spec.rb`：AC-010（子项数组 + 权限）。
- 注册 verifier：`duplicate-products-rspec`（2 个 spec 文件）。
- 回归：B-2 的 `catalog_health_spec.rb` 同跑（导航数组变化的影响面）。

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-admin/SKILL.md`（新增「Duplicate Detection」章节：三类信号口径 + 五条实现定式（含 `where.not(col: [nil,''])` 的 NULL 语义坑）+ 与 D-3 的边界）
- [x] `ai/skills/pallastrade-catalog/SKILL.md`（新增「重复商品」节：sku 校验可关闭 / barcode 零校验 / slug 自动去重不是信号）
- [x] `harness/scenarios/scenarios.json`（GS-135；`harness eval-ai --scenarios` → **136/136 valid**）
- [x] `harness.config.mjs`（verifier `duplicate-products-rspec`）+ `AGENTS.md` §6 行
- [x] 本 PRD 状态（done）+ `docs/prd/README.md` 索引（`prd-status-sync --fix/--check`）
- [x] `pallastrade-data-model` / `pallastrade-api-v3`（已评估，无需更新：零迁移、零契约变更）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-15 | 0.1 | 初稿（Batch D-2：FR-001~009 / AC-001~012；范围=检测与对比，合并留 D-3） | AI |
| 2026-09-15 | 1.0 | 实施完成：`DuplicateCandidates`（三信号 Arel 聚合 + 同源计数）+ 后台工作台/对比视图 + 路由/导航/i18n；规格 14 例绿（含导航一致性回归 58 例一次跑绿）；知识同步齐备 | AI |
