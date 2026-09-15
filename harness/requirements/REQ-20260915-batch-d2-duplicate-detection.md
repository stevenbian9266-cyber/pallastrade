# REQ-20260915 — Batch D-2（重复商品检测：三类信号候选发现 + 后台对比视图）

> 关联 PRD：`docs/prd/catalog/PRD-20260915-catalog-batch-d2-duplicate-detection.md`
> 任务：TASK-20260915121144-f174e9be ｜ Gate：GATE-2026-09-15T12-11-59（feature）

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — 宿主代码 | `backend/app/` | duplicate / 重复 / 去重 | **零命中** | 缺口：需新增（按本仓惯例落 gem：core 服务 + admin 页面） |
| Core Gem | `backend/pallastrade_gems/pallastrade_core/app/` | duplicate / sku / barcode / slug | `models/pallastrade/variant.rb:85`（sku 唯一性校验：大小写不敏感 + `deleted_at: nil` + 可 `disable_sku_validation` 关闭 + `allow_blank`）、`variant.rb` **无 barcode 校验**、`db/schema.rb:2822`（`variants.barcode` 列 + `index_pt_variants_on_barcode`）、`models/pallastrade/product/slugs.rb`（`ensure_slug_is_unique`：slug 冲突自动补 uuid → **slug 不是重复信号**）、`services/pallastrade/products/duplicator.rb`（克隆 ≠ 检测）、`services/pallastrade/catalog_health/{issues,report}.rb`（B-2 只读工作台定式） | **无检测能力** → 新增 `PallasTrade::Products::DuplicateCandidates` |
| API Gem | `backend/pallastrade_gems/pallastrade_api/app/` | duplicate | `admin/products_controller.rb:24`（`@resource.duplicate`，克隆动作） | ✅ 无检测端点；本批**不加 API / 不动契约** |
| Admin Gem | `backend/pallastrade_gems/pallastrade_admin/` | catalog_health / duplicate | `catalog_health_controller.rb`（BaseController + model_class）、`views/.../catalog_health/{index,_products_filter_banner}.html.erb`、`config/routes.rb:40`、`pallastrade_admin_navigation.rb:161`（`products.add :catalog_health`）、`config/locales/en.yml:282`（`admin.catalog_health.*`）、`spec/requests/.../catalog_health_spec.rb`、`spec/requests/.../navigation_consistency_spec.rb:107`（子项数组） | **完整模板可复用**（新增同构的第三个 Products 子项） |
| Storefront | `storefront/src/` | duplicate | 仅无关去重：`lib/utils/related-products.ts`（category ids 去重）、`lib/webhooks/handlers.ts`（幂等守卫）、`lib/utils/express-checkout.ts`（rate id 去重） | ✅ 本批不动前台 |
| Platform | `platform/packages/` | duplicate | 文档 `developer/core-concepts/products.md`（`client.products.clone()`）；SDK/CLI 无检测能力 | ✅ 本批不动 SDK/CLI |

### 搜索结论

- 重复商品**在数据层是允许存在的**（`name` 无约束；`slug` 自动去重所以不暴露冲突；`barcode` **完全没有唯一性校验**；`sku` 校验可通过配置关闭且允许为空）→ 三个信号全部真实有效。
- 后台**只有克隆没有发现**：`Products::Duplicator`（core）与 API `duplicate` 是「复制商品」，与「找出已经重复的商品」相反 → 本批补齐后者。
- 呈现层复用 B-2 的只读工作台四件套（Core 口径服务 + BaseController 页面 + Products 子菜单 + i18n），**零迁移、零契约、零前台**。
- 范围切分依据（方案原文 §十二）：「Merge Product … 会牵涉 Variant、Reviews、Redirects 和历史交易关系」→ 本批只做**检测与对比**，合并为 D-3 独立专项。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 「I need to add a 'Loyalty Points' page to the admin sidebar」范式：**用 admin navigation API 加子项，不需要 decorator**；页面内部用 partials API 注入而非覆盖视图 → 本批沿用（新增 Products 子菜单 + 独立页面，零 gem 视图覆盖） |
| `ai/skills/pallastrade-admin/SKILL.md`（领域） | ✅ 已读 | Catalog Health 四件套定式（口径单一权威 → 过滤接线 → 注入点 → 导航与权限），其中第 4 条明确「`products.add …` + `BaseController` + `model_class = Product` 锚定商品权限，**必须同步 `navigation_consistency_spec.rb` 子项数组**」→ 本批为第三个 Products 子项，按同一定式实现 |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | §4 阶段 2 步骤 6：「实施中和提交前运行 `harness supervise diff`，guard 模式阻断 error/critical；finding 须可追溯到 Standard ID 与源码位置」→ 本批收尾按此执行 |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-catalog` | ☑ 涉及 | ✅ 已读 | 「The **Variant** is the SKU — what gets added to a cart, what has a price, what has inventory」→ SKU/条码冲突必须落在**变体**维度分组；master 变体是默认属性载体（单 SKU 商品也会参与） |
| `pallastrade-data-model` | ☑ 涉及（判断为零改动） | ✅ 已读 | 迁移须可回滚、`schema.rb` 禁手改——本批**零迁移**（只读聚合），风险为零 |
| `pallastrade-testing` | ☑ 涉及 | ✅ 已读 | RSpec 容器内跑；verifier 需注册到 `harness.config.mjs`；导航类改动必须同步既有 `navigation_consistency_spec.rb` |
| `pallastrade-security` | ☑ 涉及（只读聚合） | ✅ 已读 | 原生 SQL 一律经参数化入口（`sanitize_sql_array` / Arel 常量表达式）；本批聚合键为**常量表达式**（表名取自 AR 常量），无用户输入拼接 |
| `pallastrade-api-v3` | ⬜ 不涉及 | — | 无 v3 端点变更 |
| `pallastrade-storefront` | ⬜ 不涉及 | — | 无前台改动 |

---

## 需求标题

重复商品检测：条码 / SKU / 名称三类信号在后台自动分组候选，并提供并排对比视图（只读，零迁移）。

## 任务类型

新功能（商品域数据治理，只读工作台）

## 需求描述

商家在 `/admin/duplicate_products` 看到三类重复候选与计数，按信号过滤，点开进入对比页并排查看关键属性，据此人工裁决（改 SKU/条码或归档其一）；合并商品留 D-3。

## 影响范围（harness affected 输出）

```json
{
  "filesChanged": 20,
  "affectedComponents": ["ai", "backend", "docs", "harness"]
}
```

> 注：计数含并行会话未提交文件；本任务自身改动集中在 `backend/pallastrade_gems/pallastrade_core`（1 服务）、`backend/pallastrade_gems/pallastrade_admin`（控制器/2 视图/路由/导航/locale）、`backend/spec/requests/pallastrade/admin`（1 新 spec + 1 同步）、`ai/skills/`、`harness/`、`AGENTS.md`、`docs/prd/`。

## 技术方案（初步）

- **Core**：`Products::DuplicateCandidates`（`SIGNALS`；按 `LOWER(TRIM(...))` 分组 + `HAVING COUNT(DISTINCT product_id) > 1`；`Group = {signal, key, products, total_count}`；`count(store, signal)` 与列表同源）。
- **Admin**：`DuplicateProductsController#index/#compare` + 两个视图 + 路由 + Products 子菜单 + `admin.duplicate_products.*`。
- **测试**：request spec 覆盖 AC-001~012 + `navigation_consistency_spec.rb` 同步。

## 风险点

- 误报（同名不同款）→ 页面定性为「候选」+ 文案提示人工裁决；不自动合并、不自动改数据。
- 大目录查询成本 → `GROUP BY/HAVING` + `limit`（默认 50 组 / 每组 5 商品）。
- 聚合 SQL 触发静态扫描（Brakeman/STD-SEC）→ 只用常量表达式 + Arel（无插值），并在提交前跑 `brakeman` 与 supervisor。
- 回滚难度：**极低**（纯新增只读页面；无迁移、无数据写入、无契约变更）。

## 决策节点

> ⏸️ 用户已授权（2026-09-15 原话：「继续」，指按《商品升级方案》分批推进）；本 PRD 为方案 §十二「第三步：Duplicate Detection」的忠实切片，**Merge Product 按方案原文留作独立专项（D-3）**。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| Core 检测服务 | `products/duplicate_candidates.rb` | `harness verify duplicate-products-rspec --task …` | 三类信号口径/计数同源/店铺与软删除作用域均绿（14 例） | ✅ |
| Admin 页面/路由/导航/locale | `duplicate_products_controller.rb` + 2 视图 + `routes.rb` + 导航 + `en.yml` | 同上 | 工作台页/对比页/权限/空态/过滤/i18n 全绿 | ✅ |
| 导航一致性回归 | `navigation_consistency_spec.rb` 子项数组 | 同上 | 与 B-2 catalog_health 同时跑：58 例 0 失败（导航 27 + Catalog Health 17 + 本批 14） | ✅ |
| 静态扫描 | 聚合 SQL（Arel 零插值） | 容器内 `brakeman` + `supervise diff` | <!-- 回填 --> | ⏳ |
| 知识同步 | admin/catalog Skill、GS-135、verifier、AGENTS §6 | `eval-ai --scenarios`（136/136 valid）+ `doc-impact` | <!-- 回填 --> | ⏳ |

### 验证结论

<!-- 收尾时回填 -->

- **测试**：`duplicate-products-rspec` 定向 **14 例绿**；连同导航一致性与 Catalog Health（B-2）**一次跑 58 例绿**。
- **规格期踩坑（已写进 Skill）**：
  1. `where.not(name: [nil, ''])` 生成 `NOT (col = NULL OR col IS NULL)` → 对真实行恒为 NULL，**永远不命中**；且 Mobility 翻译属性上 `not_eq('')` 会被转成 `!= NULL` → 改为「分组后 `keys.reject(&:blank?)`」。
  2. 变体无 `store_id` 列 → 跨店隔离靠 `joins(:product).merge(product_scope)`。
  3. 路由助手名是 `admin_compare_duplicate_products_path`（namespace 前缀在前）。
- **零迁移声明**：无表/列/索引变更；`git status` 可验。
- **零契约声明**：未触碰 `backend/public/api-docs/**`、`platform/**`、`storefront/**`。
