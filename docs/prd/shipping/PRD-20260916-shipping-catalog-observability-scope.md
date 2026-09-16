# PRD-20260916-shipping-catalog-observability-scope

> 商品域收口批次：配送方式作用域修正 + 三处埋点补齐（Related/RecentlyViewed 归因 + Back-in-stock 转化）

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-16 |
| 来源 | 「实施」→ 商品域审计（`docs/research/RESEARCH-20260916-catalog-domain-audit.md`）的 G-1（P0）+ G-2/G-3/G-4（P1） |
| 分类 | shipping（自动判定） |
| 关联 Skill | pallastrade-catalog、pallastrade-storefront、pallastrade-testing |
| 关联 REQ | `harness/requirements/REQ-20260916-catalog-observability-scope.md`（实施时回填） |
| 关联 PRD | N/A（审计产出的新方向。与 `PRD-20260916-catalog-batch-f2-stock-shipping` 同域但不同问题：F-2 是**功能上线**，本批是**口径修正 + 可测性**） |
| 需求类型 | 优化迭代（含 1 项口径修复） |

## 1. 背景与目标

- **一句话需求原文**：实施（承接商品域审计结论：G-1 + G-2/G-3/G-4）
- **背景**：
  商品域升级方案 A/B/C/D 四批能力**已全部上线**，但审计发现两件事：
  1. **一处口径缺陷（G-1）**：`PallasTrade::Shipping::Estimate#scoped_methods` 只按 `display_on` 过滤，**不排除数字商品专用配送方式**。数字商品用的 `Calculator::Shipping::DigitalDelivery` 方式是零价且 `display_on='both'`，会被算进 `zero_price_method?`，让**实体商品**的 `free_shipping` 变成 true，并抬高 PDP 的 `methods` 计数。
     （F-2 批次修复 CI 时，9 例失败中的 3 例正是该口径造成；当时只做了**测试隔离**，**生产口径未改**。）
  2. **三处可测性缺口**：方案 §十六 要求衡量的指标里，Related CTR、Recently Viewed 归因、Back-in-stock 订阅转化**没有任何数据来源** —— 功能上线了却无法衡量收益。
- **目标**：
  - 配送方式只返回**真正适用于该商品**的前台方式；免运费提示不再由数字商品方式触发。
  - Related / Recently Viewed 的点击可归因到具体列表；Back-in-stock 订阅转化可统计。
- **成功指标**：
  - PDP 上实体商品的 `free_shipping` 不再被数字商品方式触发（回归断言钉死）。
  - GA4 能区分 `related-products` / `recently-viewed` 的 `select_item`；`back_in_stock_subscribe` 事件可在 GA4 里出转化率。
  - F-2 既有 16 例断言**不回归**（只增不改）。

## 2. 用户故事 / 场景

- 作为**顾客**，我在实体商品页看到的配送方式应当是我真能用的，而不是数字商品用的配送方式；"免运费"提示不应凭空出现。
- 作为**运营/增长**，我要能回答"Related 位带来了多少点击""缺货订阅有多少人下单了"，才能判断这些能力是否值得继续投入。
- 边界：
  - 商品未设置配送分类，或配送方式未关联任何分类 → 保守处理（见 D1），不得让商品突然"没有任何配送方式"。
  - 数字商品（`variant.digital?`）走既有短路分支，本批不改其行为。
  - 埋点发送失败/抛错 → 不得影响订阅与点击行为（AP-009b 精神：失败要保留原状态，不能假装成功）。

## 3. 功能需求（FR）

### A 组：配送方式作用域（G-1）

- FR-001：`Shipping::Estimate#scoped_methods` 排除**数字商品专用**配送方式（计算器为 `PallasTrade::Calculator::Shipping::DigitalDelivery` 的方式）。
- FR-002：当配送方式**关联了配送分类**时，只保留与商品配送分类（`product.shipping_category`）匹配的方式；方式**未关联任何分类**时保守保留（向后兼容）。
- FR-003：`free_shipping` 只由"适用于该商品的零价方式"或"店铺运行中的免运费促销"决定；数字商品方式不得使实体商品为 true。
- FR-004：响应契约**只增不改** —— 既有键（`available`/`digital`/`min_days`/`max_days`/`free_shipping`/`free_shipping_threshold`/`business_day_source`/`methods[]`）全部保留，语义不变。

### B 组：埋点归因（G-2 / G-3 / G-4）

- FR-005：Related 列表渲染的商品卡把列表标识传下去（`listId='related-products'`、`listName` 可读名），使 `select_item` 事件带上 `item_list_id`。
- FR-006：Recently Viewed 同上（`listId='recently-viewed'`）。
- FR-007：Back-in-stock 订阅在**成功后**发送事件（含商品 id、SKU、是否已登录），失败时发送失败事件且**不改变**按钮既有状态与文案。
- FR-008：埋点不得阻塞交互：事件发送在业务成功之后，且其异常不得冒泡影响订阅/点击结果。
- FR-009（已评估，本批不做，记录理由）：`WishlistButton` 目前也无埋点，但方案 §十六 **没有** Wishlist 指标 → 本批不扩范围，仅在 Skill 中登记"如需衡量再补"。

## 4. 非功能需求（NFR）

- **性能**：`scoped_methods` 的过滤在既有查询上完成，不得引入 N+1（配送方式数量级小，允许按分类 `joins` 一次过滤）。
- **兼容**：不改任何 API 字段名与类型；不改 Store API 文档结构（若 `methods[]` 内容变少属**数据**变化，非契约变化）。
- **安全**：埋点不得携带顾客邮箱、SKU 之外的个人信息；沿用既有 GA4 事件白名单。
- **可维护性**：过滤口径集中在 `Estimate` 一处，避免 admin 与前台各写一套。

## 5. 验收标准（AC，与测试一一映射）

| AC | ← FR | 判定条件 |
|---|---|---|
| AC-001 | FR-001 | 存在数字商品方式（`DigitalDelivery`、`display_on='both'`）时，实体商品的 `methods` **不含**它 |
| AC-002 | FR-001 | 数字商品（`variant.digital?`）仍走既有短路分支（`available=false, digital=true`），行为不变 |
| AC-003 | FR-002 | 商品分类 A、方式只关联分类 B → 该方式**不出现在**结果里 |
| AC-004 | FR-002 | 方式**未关联**任何分类 → 仍出现在结果里（保守保留） |
| AC-005 | FR-003 | 只有零价数字商品方式存在时，实体商品 `free_shipping=false` |
| AC-006 | FR-003 | 店铺有运行中的免运费促销 → `free_shipping=true`（不回归） |
| AC-007 | FR-004 | 响应键集合是既有键的**超集**（逐键断言） |
| AC-008 | FR-005 | Related 列表渲染时，商品卡收到的 `listId` 为 `related-products`（单测断言） |
| AC-009 | FR-006 | Recently Viewed 同上，`listId='recently-viewed'` |
| AC-010 | FR-007 | 订阅成功 → 发出含商品 id 与 SKU 的事件；失败 → 发出失败事件且按钮状态/文案不变 |
| AC-011 | FR-008 | 埋点函数抛错时，订阅流程依旧返回成功、按钮进入成功态 |
| AC-012 | FR-004 + 回归 | F-2 既有 16 例（`estimate_spec` + `stock_status_and_shipping_spec`）全绿 |

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `shipping\|estimate` | 仅 typelizer 生成物 | ❌ 无（须改 gem） |
| Core | `pallastrade_gems/pallastrade_core/app/` | `scoped_methods\|DigitalDelivery\|zero_price` | `services/pallastrade/shipping/estimate.rb`（**唯一口径点**）、`models/pallastrade/store.rb#default_shipping_category`、`models/pallastrade/product.rb#ensure_default_shipping_category`、`services/pallastrade/seeds/digital_delivery.rb`（零价方式来源） | ✅ 需修正此处 |
| API | `pallastrade_gems/pallastrade_api/app/` | `shipping_estimate` | `store/shipping_estimates_controller.rb`、`store/shipping_methods_controller.rb` | ✅ 只读，无需改 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | `shipping_method` | `shipping_methods_controller.rb` + 视图（新建方式时默认 `ShippingCategory.first`） | ✅ 无需改 |
| Storefront | `storefront/src/` | `listId\|track\|BackInStockNotify\|RelatedProducts` | `components/products/{RelatedProducts,RecentlyViewed,BackInStockNotify,ProductCard}.tsx`、`lib/analytics/gtm.ts` | ⚠️ 三处缺口（G-2/3/4） |
| Platform | `platform/packages/` | `shippingEstimate` | `sdk/src/store-client.ts`（只读封装） | ✅ 无需改（契约不变） |

**结论**：
- G-1 的修正点是 **Core 层的 `Estimate` 一个类**；API/Admin/Platform 全部只需回归，无需改动。
- G-2/G-3/G-4 的修正点是 **Storefront 三个组件**（`ProductCard` 已支持 `listId`，无需改）。
- **防重复判定**：`pallastrade_shipping_methods` 表**无 `store_id`**（已核对 `schema.rb`）→ 配送方式是全局资源，本批**不涉及跨店问题**，只处理"数字商品方式污染实体商品"这一条。审计报告 G-1 中"多店跨界待复核"的措辞据此更正。

## 7. 技术影响

| 组件 | 文件 | 变更 |
|---|---|---|
| Core 读模型 | `pallastrade_core/app/services/pallastrade/shipping/estimate.rb` | `scoped_methods` 增加过滤（排除 digital 计算器 + 按商品配送分类匹配），`zero_price_method?` 语义随之收敛 |
| Storefront 组件 | `components/products/RelatedProducts.tsx`、`RecentlyViewed.tsx` | 传 `listId`/`listName` 给 `ProductCard` |
| Storefront 组件 | `components/products/BackInStockNotify.tsx` | 成功/失败后发事件（不阻塞、异常不外抛） |
| Storefront 埋点 | `lib/analytics/gtm.ts` | 新增 back-in-stock 事件构造函数 |
| 测试 | 后端 2 个 spec + 前台 3 个组件测试 | 见 §8 |

**接口契约**：`GET /api/v3/store/shipping_estimate` 字段不变（仅 `methods[]` 内容更准确）→ `generated:check` 应无漂移；若确认有漂移按 A-007 走生成与同步。

## 8. 测试计划

| 文件 | 变更 | 覆盖 AC |
|---|---|---|
| `backend/spec/services/pallastrade/shipping/estimate_spec.rb` | 扩：digital 方式排除、按分类匹配、无分类保守保留、`free_shipping` 语义 | AC-001/003/004/005/006 |
| `backend/spec/requests/api/v3/store/stock_status_and_shipping_spec.rb` | 扩：响应键超集 + 数字商品短路不变 | AC-002/007/012 |
| `storefront/src/components/products/__tests__/RelatedProducts.test.tsx` | 新/扩：`listId` 传递 | AC-008 |
| `storefront/src/components/products/__tests__/RecentlyViewed.test.tsx` | 同上 | AC-009 |
| `storefront/src/components/products/__tests__/BackInStockNotify.test.tsx` | 新/扩：成功/失败事件、埋点抛错不阻断 | AC-010/011 |
| `f2-stock-shipping-rspec`（`harness.config.mjs`） | 保持（命令覆盖上述两个后端 spec） | AC-012 |

**验证器**：后端沿用 `f2-stock-shipping-rspec`；前台按 AGENTS §6「UI 组件变更」跑 `harness e2e storefront` 或 `storefront-test`（以 harness.config 既有项为准）。

## 9. 文档同步清单（知识同步门）

- [ ] `ai/skills/pallastrade-catalog/SKILL.md`（配送读模型口径：排除数字商品方式 + 分类匹配 + 保守回退）
- [ ] `ai/skills/pallastrade-storefront/SKILL.md`（列表归因 `listId` 约定 + back-in-stock 事件 + 埋点不阻塞交互）
- [ ] `harness/scenarios/scenarios.json`（新增场景：配送提示不得由不适用方式产生；列表点击必须可归因）
- [ ] `docs/research/RESEARCH-20260916-catalog-domain-audit.md`（G-1 措辞更正：无 store 维度）
- [ ] 本 PRD 状态 + `docs/prd/README.md` 索引（`prd-status-sync --fix`）
- [ ] API 文档：**预计无需改**（字段不变）；以 `harness generated:check` 结果为准

## 10. 关键决策

| # | 决策 | 取值 | 理由 |
|---|---|---|---|
| D1 | 分类不匹配时的行为 | **有分类关联 → 按交集过滤；未关联任何分类 → 保守保留** | 直接"只显示交集"会让大量历史方式突然消失（历史数据多数未关联分类），造成"商品没有配送方式"的严重前台事故 |
| D2 | 是否按店铺过滤 | **不做**（本批） | `pallastrade_shipping_methods` 无 `store_id`（已核对 schema），全局资源；若未来引入店铺维度再单独立项 |
| D3 | 数字商品方式处理 | **从实体商品结果中排除**；数字商品仍走既有 `digital?` 短路 | 数字商品不需要"配送方式"列表；实体商品不该看到数字交付方式 |
| D4 | Wishlist 是否一并埋点 | **不**（本批记录理由，见 FR-009） | 方案 §十六 未定义该指标，避免范围膨胀 |
| D5 | 埋点失败策略 | 只记录不阻断（异常吞掉并保留 UI 原状态） | 与 AP-009b 一致：失败不得伪装成状态变化 |

## 11. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-16 | 0.1 | 初稿：由商品域审计 G-1/G-2/G-3/G-4 提炼为「口径修正 + 可测性」单批次 | AI |
| 2026-09-16 | 1.0 | 用户「实施」确认；补 D1~D5 决策、AC 表、测试与文档同步清单 → 状态 approved | AI |
