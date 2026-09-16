# 商品域能力审计与下一轮升级方向（2026-09-16）

> **任务**：`TASK-20260916110551-67b8013d` · **Gate**：`GATE-2026-09-16T11-06-01`（type: audit）
> **审计对象**：《商品域升级方案 V1.0》（`豆包梳理业务需求/商品升级方案.md`，§一~§十八）
> **审计方式**：6 层跨层搜索 + 关键文件精读 + 方案章节逐项对照

## 1. 结论摘要

1. **方案 A/B/C/D 四批能力已全部落地**，且多数带独立 PRD、注册验证器与领域 Skill 章节 —— 功能面**不缺**。
2. **真正的缺口在"可测性"**：方案 §十六 列了 11 项上线指标，其中 **6 项目前没有任何数据来源**（详见 G-2~G-7）。也就是说：功能已上线，但**方案自己要求的衡量方式无法执行**。
3. **一处口径正确性缺陷（G-1，P0）**：`Shipping::Estimate#scoped_methods` 是全局查询，既不看店铺、也不排除数字商品用配送方式 —— 本批 F-2 修复时的 9 例 CI 失败正是该口径造成的（seed 的 `Digital delivery` 让实体商品 `free_shipping` 变成 true）。这条**影响真实前台展示**，不是测试问题。
4. **暂缓项结论未变**：Subscription / Bundle / Recommendation AI / 自动 AI 运营 Agent / Brand 新模型 / 重构 Product-Variant 仍不建议进入下一轮（§六 复核）。

---

## 2. 方法与范围（6 层跨层搜索记录）

| 层 | 搜索路径 | 命中与结论 |
|---|---|---|
| **L1 App**（宿主） | `backend/app/` | 仅 typelizer 生成物（`javascript/types/serializers/*`）与导出配置；商品域实现**全在 gem 侧**，宿主未接管 |
| **L2 Core** | `backend/pallastrade_gems/pallastrade_core/app/` | `models/pallastrade/product.rb`、`variant.rb`、`product_publication.rb`、`product_merge.rb`、`product_option_type.rb`、`product_promotion_rule.rb`；服务目录 `services/pallastrade/products/`：`bulk_operation`、`bulk_price_update`、`bulk_inventory_adjust`、`bulk_channel_assignment`、`duplicate_candidates`、`duplicator`、`merge_preview`、`merge`、`undo_merge`、`auto_match_taxons`、`prepare_nested_attributes` |
| **L3 API** | `backend/pallastrade_gems/pallastrade_api/app/controllers/pallastrade/api/v3/` | Store：`products_controller.rb`（含 `products/filters_controller.rb`）、`categories_controller.rb`、`reviews_controller.rb`、`review_helpful_votes_controller.rb`、`back_in_stock_subscriptions_controller.rb`、`shipping_estimates_controller.rb`、`shipping_methods_controller.rb`、`wishlists_controller.rb`；Admin 侧同样齐备 |
| **L4 Admin** | `backend/pallastrade_gems/pallastrade_admin/app/` | `products_controller.rb`（65 个方法：search/show/update/clone、`bulk_status_update`、`bulk_*_taxons`、**批量运营 2.0** 六动作 `bulk_{price,inventory,channels}_{preview,update/adjust}`、Catalog Health drill-down scope、Product history 记录）；视图 26 个；旁路控制器 `catalog_health_controller`、`duplicate_products_controller`、`product_translations_controller`、`stock_items_controller`、`price_lists_controller` |
| **L5 Storefront** | `storefront/src/` | PDP：`products/[slug]/ProductDetails.tsx` + `page.tsx`（JSON-LD）；组件 24 个（`ProductCard`/`VariantPicker`/`MediaGallery`/`AvailabilityStatus`/`ShippingEstimate`/`BackInStockNotify`/`ProductReviews`/`RelatedProducts`/`RecentlyViewed`/`WishlistButton`/`InfiniteProductList`/`filters/`…）；SEO：`lib/seo.ts`（Product/Breadcrumb/CategoryItemList/Organization/Website JSON-LD）；埋点：`lib/analytics/gtm.ts` |
| **L6 Platform** | `platform/packages/sdk/src/` | `store-client.ts`（`shippingEstimate` 等只读封装）、`types/index.ts`（`ShippingEstimate*`）、生成的 typelizer 类型 |

**旁证**：`backend/pallastrade_gems/pallastrade_ai/`（独立 gem：`gateway`、`providers/{open_ai,deep_seek}`、`middleware/ssrf_protection`、`schemas/catalog/{product_description,product_seo,product_translation,health_fix_suggestion}`、`catalog/{product_copy,product_translation,health_fix_suggestion}`）。

---

## 3. 能力盘点（对照方案 §十四 Roadmap）

| 批次 | 方案能力 | 落地位置 | 证据 | 状态 |
|---|---|---|---|---|
| **A — PDP Correctness** | Variant Deep Link | `storefront/src/lib/utils/variant-selection.ts` + `ProductDetails.tsx` | `PRD-20260915-catalog-pdp-state-correctness`（done）；8 例前台测试 | ✅ |
| | Preorder / Backorder 前台化 | `components/products/AvailabilityStatus.tsx`（5 桶 + ship-by） | 同上（AC-005~007） | ✅ |
| | Multi-variant JSON-LD | `lib/seo.ts`（`buildProductJsonLd` + `PreOrder`/`BackOrder` availability） | `lib/__tests__/seo.test.ts` | ✅ |
| **B — Merchant Operations** | Bulk Price / Inventory / Channels | `services/pallastrade/products/bulk_*.rb` + admin 六动作（**预览零写入 → 确认执行**） | `harness verify admin-products-bulk-rspec` | ✅ |
| | Catalog Health V1 | `admin/catalog_health_controller.rb`（7 类 issue、计数与列表同源） | `harness verify admin-catalog-health-rspec` | ✅ |
| **C — Conversion** | Related / Recently Viewed / Wishlist | `RelatedProducts.tsx`、`RecentlyViewed.tsx`、`WishlistButton.tsx`（+ Store API `wishlists`） | 组件 + 前台测试 | ✅ 功能 |
| | Variant Back-in-stock | `BackInStockNotify.tsx`（SKU 级）+ `services` 事件层 + Store API | `harness verify back-in-stock-rspec`；`PRD-20260915-catalog-batch-c2-sku-back-in-stock` | ✅ |
| **D — Intelligence & Governance** | AI Copilot（描述/SEO） | `pallastrade_ai/catalog/product_copy.rb` + admin Generate→Preview→Accept | `harness verify ai-copilot-rspec`；`PRD-20260915-catalog-batch-e1-ai-copilot` | ✅ |
| | AI Translate Missing | `ai/catalog/product_translation.rb` + 抽屉 | `harness verify ai-translate-rspec` | ✅ |
| | AI Fix Suggestion | `ai/catalog/health_fix_suggestion.rb` + 工作台行内 + 侧栏卡片 | `harness verify ai-health-suggestion-rspec` | ✅ |
| | Review Enhancement（§十） | 评分分布 / 分页 / 图片评论 / 排序 / 批量审核 / Helpful Vote | `reviews-f1-rspec`、`f3-review-bulk-rspec`、`f4-review-sorting-rspec`、`f5-helpful-vote-rspec` | ✅ 全 5 项 |
| | History（§十二 第一步） | `product_history/**` + 后台时间线 | `harness verify product-history-rspec` | ✅ |
| | Data Governance（§十二 第二、三步） | Duplicate Detection（三类信号）+ **Merge Product（预检/执行/撤销）** | `duplicate-products-rspec`、`d3-product-merge-rspec` | ✅ |
| **§十一 库存与配送** | 库存分桶 + 配送估算 | `catalog/stock_status.rb`、`shipping/estimate.rb` + PDP 徽章/配送区块 | `f2-stock-shipping-rspec` | ✅ 功能（口径见 G-1） |
| **§九 SKU 化** | SKU 级 Back-in-stock | 同 C 批 | `back-in-stock-rspec` | ✅ |

> 结论：**方案里承诺的能力，除 §十六 的衡量手段外，已全部交付。**

---

## 4. 缺口清单（本审计核心）

### G-1 `Shipping::Estimate#scoped_methods` 是全局查询 —— 正确性（P0）

- **位置**：`backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/shipping/estimate.rb`（`scoped_methods`）
- **现象**：该方法只按 `display_on IN ('both','front_end')` 过滤，**不按 store 过滤**，也**不排除数字商品用配送方式**；随后 `zero_price_method?` 把任何零价配送方式当作"免运费"，`free_shipping` 因此变 true。
- **实证**：本批 F-2 修复中，CI（`bin/rails db:prepare` 会 seed）的 9 例失败里，3 例正是该口径造成 —— `Seeds::DigitalDelivery` 建的 `display_on='both'` 零价 `Digital delivery` 让**实体商品**的 `free_shipping` 变成 true，并抬高 PDP 的 `methods` 计数。修复只是让**测试**不再受它影响（spec 里先 `ShippingMethod.destroy_all`），**生产口径未变**。
- **影响**：前台 PDP 可能向实体商品展示"免配送费"，以及一个并不适用的数字商品配送方式；多店部署下需复核是否还跨店展示。
- **建议**：`scoped_methods` 显式收敛作用域（店铺 + 排除 `Calculator::Shipping::DigitalDelivery`，或要求配送方式与商品配送分类匹配），再复核 `zero_price_method?` 的语义。
- **验证方式**：新增或扩展 `f2-stock-shipping-rspec`，断言"仅返回本店/与本商品配送分类匹配的方式"，且 digital 方式不出现在实体商品结果里。

### G-2 Related Product CTR 不可归因（P1）

- **位置**：`storefront/src/components/products/RelatedProducts.tsx`（全文件无 `listId` / `listName` / `track`）
- **现象**：`ProductCard` 支持 `listId/listName` 并据此发 `select_item`（`ProductCard.tsx` → `trackSelectItem(product, listId, listName, index, currency)`），但 Related 列表未传 → GA4 事件缺少列表标识，**无法区分 Related 点击与 PLP 点击**。
- **影响**：方案 §十六 指标「Related Product CTR」无法计算。
- **建议**：Related/Recently Viewed/Wishlist 列表统一传 `listId`（如 `related-products` / `recently-viewed`），并把列表标识写进事件契约。

### G-3 Recently Viewed 同上（P1）

- **位置**：`storefront/src/components/products/RecentlyViewed.tsx`（无 `listId` / `track`）
- 与 G-2 同因、同修。

### G-4 Back-in-stock 订阅转化不可测（P1）

- **位置**：`storefront/src/components/products/BackInStockNotify.tsx`（只调 `createBackInStockSubscription`，无任何 analytics 调用）
- **影响**：方案 §十六 指标「Back-in-stock subscription conversion」无数据 —— C-2 能力上线了却无法衡量收益。
- **建议**：提交成功/失败各发一个事件（含 SKU、商品、是否登录）。

### G-5 AI 接受率与"采纳前编辑"不可测（P1）

- **位置**：`backend/pallastrade_gems/pallastrade_ai/`（`grep accept|accepted|adopted` 仅命中注释里的 `Generate → Preview → Accept → Save` 流程描述，**没有一条记录**）
- **现象**：Accept 只是客户端交互步骤，后端不落库；因此既算不出「AI Generation acceptance rate」，也看不出「AI 生成内容在保存前被改了多少」。
- **建议**：在 admin 的 Accept/Save 路径记录一次轻量审计（capability、run id、accepted?、最终文本与草稿的差异摘要），语义与既有 `Audit` 一致。
- **注意**：本节与 §7.2「AI 安全边界」一致 —— 记录**不等于**让 AI 直接落库。

### G-6 后台运营指标无数据源（P2）

- **位置**：admin 是 Rails 服务端渲染，**没有埋点层**；`Product#history` 已经记录了单条与批量操作（含批量每商品一条、变更字段），数据**存在**但**没有报表**。
- **影响**：方案 §十六 的「Bulk operation products / operation」「Average product maintenance operations」无法计算。
- **建议**：基于 `product_history` + `Audit` 出一张只读运营报表（按周期聚合：批量操作次数/覆盖商品数/人均维护动作），复用既有 `PallasTrade::Admin::ReportsController` 模式。

### G-7 Catalog Health 无趋势 / 无快照（P2）

- **位置**：`backend/pallastrade_gems/pallastrade_admin/app/controllers/pallastrade/admin/catalog_health_controller.rb`（只有**当前**计数，无 history/trend/snapshot）
- **影响**：§十六 指标「Unresolved Catalog Health Issues」缺少时间维度 —— 无法回答"治理在变好还是变差"。
- **建议**：增量快照表（store × issue × 日）+ 工作台迷你趋势；口径必须复用 `CatalogHealth` 的既有 scope（保持"计数==列表"这条不变量）。

### G-8 多店作用域未系统化（P3 / 建议立专项）

- **证据**：G-1 是一个已证实的实例（catalog 读取路径未收敛 store）。仓库既有的多店审计（`/memories/repo/pallastrade-multistore-support-audit.md`、`pallastrade-admin-multistore-audit-20260909.md`）也提示同类风险面广。
- **建议**：把"所有面向顾客的 catalog 读取路径必须显式收敛 store"做成一次**专项扫描 + 回归清单**（类似 AP-005 的机器化检查），而不是逐个 bug 修。

---

## 5. 建议的下一轮升级方向（按 ROI 排序）

| 优先级 | 方向 | 解决缺口 | 成本 | 依赖 | 风险 |
|---|---|---|---|---|---|
| **P0** | 配送方式作用域与数字商品排除口径修正 | G-1 | 小（1 个服务 + 1 组断言） | 无 | 低（改的是只读读模型） |
| **P1** | 前台埋点补齐：列表标识 + back-in-stock 事件 | G-2 G-3 G-4 | 小（3 个组件 + 事件契约） | 无 | 低 |
| **P1** | AI 采纳审计（acceptance / 采纳前编辑摘要） | G-5 | 中 | AI Run 既有审计 | 低（只增审计，不碰安全边界） |
| **P2** | 运营报表（批量操作与维护频次） | G-6 | 中（复用 product_history） | 无 | 低 |
| **P2** | Catalog Health 趋势快照 | G-7 | 中（1 表 + 1 图） | 无 | 低（须保"计数==列表"） |
| **P3** | 多店作用域专项扫描（机器化检查 + 回归清单） | G-8 | 大 | 需先定口径 | 中 |

**建议的下一步**：P0（G-1）与 P1 的**埋点三项**打包成一个小批次（都属于"让已上线的能力变得可信任 / 可衡量"），再评估 P2。

---

## 6. 暂缓项复核（方案 §十三）

| 能力 | 当时的暂缓理由 | 今天是否仍成立 |
|---|---|---|
| Subscription | 涉及支付与周期订单 | ✅ 仍成立（属支付域，不在商品域） |
| Bundle | 涉及 LineItem / 库存拆分 | ✅ 仍成立（会牵动订单编排与库存预留） |
| Recommendation AI | 数据基础尚不足 | ✅ 仍成立 —— 而且审计发现**连 C 批的行为数据都还没埋点**（G-2~G-4），先补数据更合理 |
| 自动 AI 运营 Agent | 风险与审计成本过高 | ✅ 仍成立（G-5 说明连"接受率"都还没有记录，先建立可观测性） |
| Brand 新模型 | 当前 metafield 足够 | ✅ 仍成立 |
| 重构 Product / Variant | 缺乏收益 | ✅ 仍成立（D-3 合并已在既有模型上解决治理诉求） |

---

## 7. 证据索引

- 方案：`豆包梳理业务需求/商品升级方案.md`
- PRD（20 份）：`docs/prd/catalog/`；索引 `docs/prd/README.md`
- 领域 Skill：`ai/skills/pallastrade-catalog/SKILL.md`（§Stock buckets / §重复商品 / §商品合并 / §AI 修复建议）、`pallastrade-admin/SKILL.md`、`pallastrade-storefront/SKILL.md`
- 验证器（`harness.config.mjs`）：`reviews-f1-rspec`、`f2-stock-shipping-rspec`、`f3-review-bulk-rspec`、`f5-helpful-vote-rspec`、`duplicate-products-rspec`、`d3-product-merge-rspec`、`product-history-rspec`、`admin-catalog-health-rspec`、`admin-products-bulk-rspec`、`back-in-stock-rspec`、`ai-copilot-rspec`、`ai-translate-rspec`、`ai-health-suggestion-rspec`
- G-1 的实证：`backend/spec/services/pallastrade/shipping/estimate_spec.rb`、`backend/spec/requests/api/v3/store/stock_status_and_shipping_spec.rb`（2026-09-16 F-2 修复提交 `bdb8ff6f`）
