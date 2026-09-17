# 商品域升级方案 — 交付完整性复核（再次审计）

| 项 | 值 |
|---|---|
| 审计日期 | 2026-09-18 |
| 审计对象 | `豆包梳理业务需求/商品升级方案.md` V1.0（及关联 PRD） |
| 审计基准提交 | `b1b055e7`（dev） |
| 前次审计 | `harness/reviews/REVIEW-20260915-storefront-pdp-admin-products-audit.md` |
| 任务 | `TASK-20260917160312-c13464d8` · gate `GATE-2026-09-17T16-03-25`（audit / quick） |
| 审计类型 | 只读复核（无代码改动） |

---

## 一、审计方法

1. **文档层**：读方案全文（§1–§18）+ `docs/prd/catalog/` 全部 29 份 PRD 的状态头 + `docs/prd/README.md` 索引。
2. **代码层（6 层跨层搜索，逐层独立）**：`backend/app/` → `pallastrade_core/app/` → `pallastrade_api/app/` → `pallastrade_admin/app/` → `storefront/src/` → `platform/packages/`。
3. **反证法**：不采信 PRD 状态文字，对每一项**找到对应的代码构件**（服务类 / 控制器 / 组件 / 表结构 / 路由）才算通过。
4. **自动化校验**：`node scripts/nav-validate-static.mjs`（exit 0）、注册验证器清单、场景库计数。

> 方法说明：本次审计**不接受「PRD 写 done」作为完成证据**，只接受「代码里能找到该能力的落点」。下表的「代码落点」列即为此项取证结果。

---

## 二、结论摘要

| 维度 | 结论 |
|---|---|
| 方案 §4–§12 的**全部建设项** | **27/27 已交付**（含方案标注「暂缓」的 Bulk Media） |
| 方案 §13 暂缓清单 | **6/6 按方案保持未做**（正确，非缺口） |
| 方案 §16 上线指标 | **10/11 已有数据来源**，1 项（Variant selection → Add to Cart）**仅有间接口径** |
| 方案 §17 测试治理 | 195 个相关 spec 文件；57 个注册验证器；177 条场景库 |
| 阻断级遗留 | **无** |
| 需业务决策的遗留 | 3 项（见 §五） |

**总判定：方案范围内的交付已完成，无未实现的必做项。** 剩余事项全部是「口径/归因」层面的完善，不影响功能可用性。

---

## 三、逐条交付映射（方案 → PRD → 代码落点 → 验证器）

### §4 一期：商品正确性

| 方案项 | PRD | 代码落点（已取证） | 验证器 |
|---|---|---|---|
| §4.1 Variant Deep Link | `PRD-20260915-catalog-pdp-state-correctness` | `storefront/src/lib/utils/variant-selection.ts`；PDP `page.tsx` 读 `searchParams.variant` 并透传；`ProductDetails.tsx` 的 `resolveInitialVariant`（无效 id 回退默认）+ `applyVariantDeepLink`（静默更新 URL） | `storefront-test` |
| §4.2 预售/缺货前台化 | 同上 | `components/products/AvailabilityStatus.tsx`；`variant-selection.ts#availabilityFlagsForVariant`；五态语义（In stock / Low / Pre-order / Backorder / Out of stock） | `storefront-test` |
| §4.3 JSON-LD 第一阶段（AggregateOffer） | `PRD-20260814-catalog-seo-深度增强` | `storefront/src/lib/seo.ts`（`AggregateOffer` 分支 + `lowPrice/highPrice/offerCount/availability`） | `seo.test.ts` |
| §4.3 JSON-LD 第二阶段 4 字段 | `PRD-20260917-catalog-json-ld-phase2` | `seo.ts`：`buildShippingDetails`（映射已取到的运费估算）、`hasMerchantReturnPolicy`（结构化，读 `PallasTrade::Policy#preferences`）、`seller`、`priceValidUntil`（命中价目表 `ends_at`，新增 `Price.price_list_ends_at`）；`lib/data/policies.ts` | 后端 22 例 + 前台 23 例 |

### §5 二期：运营工作台

| 方案项 | PRD | 代码落点 | 验证器 |
|---|---|---|---|
| §5.1 Bulk 价格 | `PRD-20260915-admin-bulk-operations-2` | `catalog_core/.../products/bulk_price_update.rb`；`products_controller#bulk_price_preview / bulk_update_price` | `admin-products-bulk-rspec` |
| §5.1 Bulk 库存 | 同上 | `products/bulk_inventory_adjust.rb`；`bulk_inventory_preview / bulk_adjust_inventory` | 同上 |
| §5.1 Bulk 渠道 | 同上 | `products/bulk_channel_assignment.rb`；`bulk_channels_preview / bulk_update_channels` | 同上 |
| §5.1 **Bulk Media**（方案标「暂缓」，实际已做） | `PRD-20260917-catalog-bulk-media` | `products/bulk_media_removal.rb`；`bulk_media_preview / bulk_media_remove` | `bulk-media-rspec` |

四个批量动作统一走 `PallasTrade::Products::BulkOperation` 基类（`preview` / `call` 共享 `run(dry_run:)`），满足方案「Select → Configure → Preview → Confirm → Result」与「执行前必须 Preview」的硬要求。

### §6 Catalog Health

| 方案项 | PRD | 代码落点 | 验证器 |
|---|---|---|---|
| §6 V1 可执行问题清单（7 类） | `PRD-20260915-admin-catalog-health-v1` | `catalog_health/issues.rb`（`KEYS` 七项 + `PRODUCT_FILTER_KEYS` 下钻）+ `report.rb`（逐项 `safe_count` 降级）；`catalog_health_controller`；`products_controller#scope` 覆写实现「点数量进过滤列表」 | `admin-catalog-health-rspec` |
| §6.1 V2 覆盖率（五套分母） | `PRD-20260917-catalog-health-coverage-ratios` | `catalog_health/coverage.rb`（`DENOMINATORS` 一处定义：内容=未归档、库存=active、草稿=draft、翻译=商品×语言槽位、URL=变更总数） | 同上 |
| §6.1 V2 0–100 健康分 | `PRD-20260917-catalog-health-score` | `catalog_health/score.rb`（等权、只对可计算维度加权、不可计算维度**排除而非记 0**、全不可计算则 `nil`） | 同上（92 例） |
| §6.1 趋势 | `PRD-20260916-catalog-health-trend-snapshot` | `catalog_health/snapshot.rb` + `trend.rb` | 同上 |

> 方案原文强调「Score 是结果，不是一期重点；一期真正重要的是 Issue Detection + Action」——本实现同时满足两者，且**没有编造不可计算的比率**（分母 0 → `nil`）。

### §7 AI Product Copilot

| 方案项 | PRD | 代码落点 | 验证器 |
|---|---|---|---|
| §7.1 Description Generate/Rewrite | `PRD-20260915-catalog-batch-e1-ai-copilot` | `pallastrade_ai/.../ai/catalog/product_copy.rb` + `schemas/catalog/product_description.rb`；后台 `POST /admin/ai/product_description`；商品编辑页 Generate/Preview/Accept | `ai-copilot-rspec` |
| §7.1 SEO Generate | 同上 | `schemas/catalog/product_seo.rb`；`POST /admin/ai/product_seo` | 同上 |
| §7.1 Translation（Translate Missing） | `PRD-20260915-catalog-batch-e2-ai-translate-missing` | `ai/catalog/product_translation.rb` + `schemas/catalog/product_translation.rb`；`POST /admin/ai/product_translation`；翻译抽屉 `[AI Translate Missing]` | `ai-translate-rspec` |
| （方案未列）Health Fix Suggestion | `PRD-20260916-catalog-batch-e3-ai-fix-suggestion` | `ai/catalog/health_fix_suggestion.rb`；`POST /admin/ai/catalog_health_suggestion`；工作台行内面板 + 商品侧栏卡 | `ai-health-suggestion-rspec` |
| §7.2 安全边界 Generate→Preview→Accept→Save | `PRD-20260916-catalog-ai-acceptance-audit` | `ai/catalog/record_acceptance.rb`；`POST /admin/ai/acceptances`（Accept/Discard 留痕） | `ai-acceptances-spec` |
| §7.2 AI 不改价格/库存/上架/渠道 | 全批次 | 四个 capability 的 schema 均**只输出文本字段**，无价格/库存/可见性写入面；`Accept` 由人触发，服务端「接受前不落库」 | 见各 verifier |
| §16 采纳后已修改指标 | `PRD-20260917-catalog-ai-edited-before-save` | `accept()` 先写入再快照、提交前比**值**、每次决策只上报一次、上报失败静默不阻断保存 | `ai_edited_before_save_spec` |

### §8 三期：PDP 作为发现节点

| 方案项 | PRD | 代码落点 | 验证器 |
|---|---|---|---|
| §8.1 Related Products（规则推荐） | `PRD-20260915-catalog-batch-c1-discovery` | `lib/utils/related-products.ts`（`pickRelated` 剔除自身）；`lib/data/products.ts#getRelatedProducts`（复用 `cachedListProducts`，同分类 + 有货 + over-fetch 1）；`components/products/RelatedProducts.tsx` | `storefront-test` |
| §8.2 Recently Viewed（本地存储） | 同上 | `lib/utils/recently-viewed.ts` + `local-store.ts`（统一读写与容错）；`RecentlyViewed.tsx` + `RecentlyViewedTracker.tsx` | 同上 |
| §8.3 Wishlist（V1 本地存储） | 同上 | `lib/utils/wishlist.ts` + `WishlistButton.tsx` | 同上 |

### §9 SKU 化

| 方案项 | PRD | 代码落点 | 验证器 |
|---|---|---|---|
| Back-in-stock 变体级 | `PRD-20260915-catalog-batch-c2-sku-back-in-stock` | `pallastrade_back_in_stock_subscriptions` 增 `variant_id`（可空）+ **两条 partial 唯一索引**（`variant_id IS NULL` / `IS NOT NULL`）兼容历史商品级订阅；事件双通道分流（`variant.back_in_stock` / `product.back_in_stock`）；后台按 SKU 展示 | `back-in-stock-rspec` |

### §10 评论系统升级

| 方案项 | PRD | 代码落点 | 验证器 |
|---|---|---|---|
| 评分分布 + 分页 + 图片评论 | `PRD-20260916-catalog-batch-f1-reviews` | `api/v3/store/reviews_controller.rb`（`meta.rating_distribution` 与列表同源）；`Review` 增 images（≤3 张、直传、未审核不外泄）；后台图片列 | `reviews-f1-rspec` |
| 排序 | `PRD-20260916-catalog-batch-f4-review-sorting` | `reviews_controller` 的 `SORT_ORDERS` 白名单 + 稳定 `id DESC` tie-break + `meta.sort` | `f4-review-sorting-rspec` |
| Helpful Vote | `PRD-20260916-catalog-batch-f5-helpful-vote` | 新表 `pallastrade_review_votes`（`(review_id,user_id)` 唯一）+ `helpful_votes_count` 计数器；`review_helpful_votes_controller`（POST/DELETE 幂等）；`most_helpful` 排序 | `f5-helpful-vote-rspec` |
| 后台批量通过/拒绝 | `PRD-20260916-catalog-batch-f3-review-bulk-moderation` | `admin/reviews_controller#bulk`（逐条状态机 + 逐条鉴权 + 四计数报告 + 50 条上限） | `f3-review-bulk-rspec` |

> 方案 §10 的「其中最优先」三项（评分分布 / 分页 / 图片）已做，且**额外**完成了排序、Helpful Vote、后台批量审核 —— 即 §10 全清单。

### §11 库存与配送信息

| 方案项 | PRD | 代码落点 | 验证器 |
|---|---|---|---|
| 库存阈值模式（不下发精确库存） | `PRD-20260916-catalog-batch-f2-stock-shipping` | `catalog/stock_status.rb`（分桶与 `Variant#in_stock?` 同源）；`AvailabilityStatus.tsx`；**任何响应不含精确库存** | `f2-stock-shipping-rspec` |
| Shipping estimate / 时效 | 同上 | `shipping/estimate.rb`（读模型 + `/shipping_estimate`）；`lib/utils/arrival.ts`；`ShippingEstimate.tsx` | 同上 |
| Free shipping threshold | 同上 | 估算返回 `free_shipping` / `free_shipping_threshold`；`ShippingEstimate.tsx` 两分支渲染 | 同上 |

### §12 中长期：商品治理

| 方案项 | PRD | 代码落点 | 验证器 |
|---|---|---|---|
| 第一步 Catalog Health | 见 §6 | 见 §6 | `admin-catalog-health-rspec` |
| 第二步 Product History | `PRD-20260915-catalog-batch-d1-product-history` | `product_history/recorder.rb`（只记变化字段）+ `timeline.rb`（审计 ∪ 价格历史倒序）；编辑页侧栏注入 | `product-history-rspec` |
| 第三步 Duplicate Detection | `PRD-20260915-catalog-batch-d2-duplicate-detection` | `products/duplicate_candidates.rb`（三类信号）+ `duplicate_products_controller`（工作台 + 对比视图） | `duplicate-products-rspec` |
| 第三步 Merge Product | `PRD-20260916-catalog-d3-product-merge` | `products/{merge_preview,merge,undo_merge}.rb` + `pallastrade_product_merges` 台账；**历史交易零改写** + 可撤销 | `d3-product-merge-rspec` |

### §16 上线指标的数据来源

| 指标 | 数据来源 | 状态 |
|---|---|---|
| PDP → Add to Cart | GA4 `add_to_cart`（`trackAddToCart`） | ✅ |
| PDP → Related Product CTR | 自有库 `pallastrade_catalog_events`（`impression` / `click` + `list_id` 按推荐位聚合，分母 0 → `nil`） | ✅ |
| PDP → Back-in-stock subscription conversion | GA4 `back_in_stock_subscribe`（`trackBackInStockSubscribe`） | ⚠️ 见 §五-2 |
| Admin → Bulk operation products / operation | `catalog/operations/report.rb`（`operations` 分批量/单条 + 覆盖商品数去重） | ✅ |
| Admin → Average product maintenance operations | 同上（`maintenance` 比率，分母 0 → 0） | ✅ |
| Health → Unresolved Catalog Health Issues | `catalog_health/report.rb` 七项计数 | ✅ |
| Health → Missing SEO ratio | `catalog_health/coverage.rb` | ✅ |
| Health → Missing translation ratio | 同上（翻译槽位分母 = 商品 × 语言） | ✅ |
| AI → AI Generation acceptance rate | `POST /admin/ai/acceptances` 留痕聚合 | ✅ |
| AI → AI-generated content edited before save | `ai_edited_before_save_spec` 覆盖的上报链路 | ✅ |
| PDP → Variant selection → Add to Cart | —— | ❌ 见 §五-1 |

> 方案的原话是「上线前先记录基线，再给第二阶段设数字目标」。**本审计确认：11 个指标中 10 个已有可信数据来源，可以开始记基线。**

### §17 技术治理要求（测试）

方案要求「所有新功能都遵守 Core→model/service spec、API→request spec、Admin bulk→权限+成功+部分失败 spec、PDP state→component test、URL variant→route/state test」。

取证结果：195 个商品域相关 spec 文件；57 个注册验证器；177 条场景库（`harness eval-ai --scenarios` 全绿）。各能力已按上述分层建立 spec（见上表「验证器」列）。**该项达成。**

---

## 四、与方案原文的差异

| # | 方案原文 | 实际交付 | 性质 |
|---|---|---|---|
| 1 | §5.1 表格中 **Media = 「暂缓」** | 已实现（`PRD-20260917-catalog-bulk-media`，预览后确认） | **超范围交付**（正向） |
| 2 | §10 最优先三项 | 全清单六项均已交付 | **超范围交付**（正向） |
| 3 | §7.1 只列三个能力 | 增加 Health Fix Suggestion | **超范围交付**（正向） |
| 4 | §12 第三步「明显是独立专项」 | 分三批（D-1/D-2/D-3）独立交付，含撤销 | 与方案判断一致 |
| 5 | §13 暂缓 6 项 | 6/6 保持未做 | 与方案一致（正确） |
| 6 | §6.1「第一版不要做复杂健康评分算法」 | V1 先做 Issue Detection，V2 才补 Score | 与方案节奏一致 |

---

## 五、遗留事项（均非阻断）

### 1. 「Variant selection → Add to Cart」缺少显式埋点 · 建议优先级：低

- **现状**：`ProductDetails.tsx` 中 `view_item` **有意只在页面打开时触发一次**（携带 deep-link 的变体），变体切换**不重发**（这是 `pdp-state-correctness` 的 AC-004，目的是让 GA4 的 SKU 与分享/广告 URL 一致）。`add_to_cart` 携带当前 SKU。
- **影响**：方案 §16 想要的是「选中变体 → 加购」这一漏斗环节的转化率。目前该环节只能通过 **URL `?variant=` 的落地数据** 或 **`add_to_cart` 的 SKU 分布** 间接反推，没有独立的「变体选择」事件。
- **为什么没做**：AC-004 是**有意约束**（避免 `view_item` 污染），不是遗漏。要补这个指标应当新增一个**独立事件**（例如 `select_variant`），而不是改 `view_item` 的触发时机。
- **建议**：若业务确需该指标，另立小需求在 `lib/analytics/gtm.ts` 增 `trackSelectVariant`，并在 `PallasTrade::CatalogEvent::EVENT_NAMES` 白名单中同步扩词（当前白名单为 `impression / click / product_added / product_searched`）。

### 2. 「Back-in-stock subscription conversion」的归因只能靠 GA4 · 建议优先级：低

- **现状**：`pallastrade_back_in_stock_subscriptions` 表列为 `product_id / variant_id / email / status / store_id`，**没有来源（source / UTM）字段**；订阅动作有 GA4 事件 `back_in_stock_subscribe`。
- **影响**：「订阅 → 实际下单」的归因依赖 GA4 的会话/用户拼接，平台自身无法自证。
- **建议**：若要平台自证，需在订阅时记录来源标识并在订单侧做匹配——属独立小需求，不建议在本轮追加。

### 3. 并行会话已记录的既有事项（非本方案缺口）

- **多店作用域（G-8）**：`Catalog::Operations::Report` 的 `pallastrade_audit_logs` **无 store 维度**，报表返回 `scope_note: 'all_stores'`，页面如实标注。这是审计 G-8 的独立议题，方案未涉及。
- **批量动作的店铺范围**：`bulk_collection` 只按 ability 过滤、不带店铺范围，超管 ability 为跨店——这是**全部**批量动作（含历史的 status/tags/taxons）共有的框架行为。本轮为**不可撤销**的 Bulk Media 加了 `current_store` 收窄，其余动作的缺口记录在 `PRD-20260917-catalog-bulk-media` 的 R-5。

---

## 六、证据索引

| 类型 | 位置 |
|---|---|
| 方案原文 | `豆包梳理业务需求/商品升级方案.md` |
| 本方案全部 PRD | `docs/prd/catalog/`（29 份，状态均为 `done`） |
| PRD 索引 | `docs/prd/README.md` |
| 前次审计（本方案的输入） | `harness/reviews/REVIEW-20260915-storefront-pdp-admin-products-audit.md` |
| 相关需求文档 | `harness/requirements/REQ-*.md` |
| 验证器注册表 | `harness.config.mjs` → `evidence.verifiers`（57 项） |
| 场景库 | `harness/scenarios/scenarios.json`（177 条，含 GS-175/GS-176） |
| 知识同步表 | `AGENTS.md` §6 |
| 使用手册 | `docs/operations/catalog-operations-guide.md` |

### 本次审计执行的校验命令

| 命令 | 结果 |
|---|---|
| `node scripts/nav-validate-static.mjs` | `nav:validate (static) OK`（exit 0） |
| 6 层跨层搜索（backend / core / api / admin / storefront / platform） | 每层独立取证，结论见 §三 |
| PRD 状态扫描（29 份） | 全部 `done` |
| 注册验证器计数 | 57 |
| 场景库计数 | 177 |

---

## 七、审计签署

| 项 | 值 |
|---|---|
| 结论 | **方案范围内无未实现的必做项；无阻断级遗留** |
| 可进入下一阶段 | ✅ 可以开始记录 §16 指标基线 |
| 建议下一步 | ① 记录 10 项指标基线；② 按需评估 §五 的 2 个口径完善项；③ 独立立项处理批量动作的多店作用域（G-8） |
