# REQ-20260916-catalog-observability-scope

> 关联 PRD：`docs/prd/shipping/PRD-20260916-shipping-catalog-observability-scope.md`（done，实施 `81f3e451`；2026-09-18 回填）
> 任务：`TASK-20260916112140-489b50f0` · Gate：`GATE-2026-09-16T11-21-50`
> 来源：商品域审计 `docs/research/RESEARCH-20260916-catalog-domain-audit.md` 的 G-1（P0）+ G-2/G-3/G-4（P1）

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | `shipping` / `estimate` / `delivery` | 仅 typelizer 生成物 | ❌ 无（实现须在 gem 侧） |
| App — views/decorators | `backend/app/` | 同上 | 无 | ❌ 无 |
| Core Gem — models | `backend/pallastrade_gems/pallastrade_core/app/models/` | `shipping_method` / `shipping_category` | `shipping_method.rb`、`shipping_category.rb`（`UniqueName`、`DEFAULT_NAME`）、`store.rb#default_shipping_category`、`product.rb#ensure_default_shipping_category` | ⚠️ 提供背景（seed 会建 Default/Digital 分类与零价 digital 方式），本批不改模型 |
| Core Gem — services | `.../pallastrade_core/app/services/` | `scoped_methods` / `zero_price` / `free_shipping` | **`shipping/estimate.rb`（唯一口径点）**；`seeds/digital_delivery.rb`（零价方式来源） | ✅ **G-1 修正点在此** |
| API Gem — controllers | `.../pallastrade_api/app/controllers/` | `shipping_estimate` / `shipping_methods` | `store/shipping_estimates_controller.rb`、`store/shipping_methods_controller.rb` | ✅ 只读，无需改 |
| Admin Gem — controllers | `.../pallastrade_admin/app/controllers/` | `shipping_method` | `shipping_methods_controller.rb`、`shipping_categories_controller.rb` | ✅ 无需改 |
| Admin Gem — views | `.../pallastrade_admin/app/views/` | `shipping_method` | `shipping_methods/**`（新建方式默认 `ShippingCategory.first`） | ✅ 无需改 |
| Storefront | `storefront/src/` | `listId` / `track` / `BackInStock` / `RelatedProducts` | `components/products/{RelatedProducts,RecentlyViewed,BackInStockNotify,ProductCard}.tsx`、`lib/analytics/gtm.ts` | ⚠️ **G-2/G-3/G-4 修正点在此**（`ProductCard` 已支持 `listId`，无需改） |
| Platform | `platform/packages/` | `shippingEstimate` | `sdk/src/store-client.ts`（只读封装）+ 生成类型 | ✅ 无需改（契约不变） |

### 搜索结论

- **G-1**：修正点集中在 **Core 的 `Shipping::Estimate` 一个类**；API / Admin / SDK 只需回归。
  `pallastrade_shipping_methods` **无 `store_id`**（已核对 `schema.rb`）→ 配送方式是全局资源，**不涉及跨店**，本批只处理"数字商品方式污染实体商品"。
- **G-2/G-3/G-4**：修正点是 **Storefront 三个组件**；埋点复用既有 `ProductCard#select_item`（Storefront Skill §"埋点复用"已写明该约定）。
- **零新增模型/表/接口**；无 API 契约变更（`shipping_estimate` 字段不变，仅 `methods[]` 内容更准确）。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：**"Settings → Configuration → Events → Dependencies → Admin/Ransack APIs → Generators → Decorators → Extensions"**；且"Decorators are reserved for *structural* changes… for behavioral changes use Events"。本批 G-1 是**框架内部读模型的口径修正**（`pallastrade_gems` 为团队产品，AGENTS §1 明确可直接修改），不属于宿主定制的任何一级 → 直接在 gem 内改，不加装饰器/订阅者 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | 后台约定（`tables.register` + 逐列 `.add`、动作需 `data: { turbo_method: }`）；**本批不改 admin**，仅确保 Catalog Health/配送相关后台不受影响 |
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已读 | §"Stock buckets for shoppers（Catalog F-2）"定义配送读模型的服务面；§"商品合并（D-3）"记录了口径类改动的写法（先只读、后写台账）。本批修正 F-2 读模型的**适用性口径** |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-storefront` | ✅ 涉及 | ✅ 已读 | **"埋点复用：新 rail 直接用 `ProductCard` 的 `select_item`（传 `listId` / `listName` 区分区块），不新增埋点代码。"**（本批正是补上未传的两处）；另："Client-component SDK calls go through server actions"（`PALLASTRADE_API_URL` 为 server-only）与 **"A `"use server"` module may only export async functions (build breaker)"** |
| `pallastrade-testing` | ✅ 涉及 | ✅ 已读 | 新增 gotcha："Spec passes locally but fails only in CI (seeded test database)"——CI 的 `db:prepare` 会执行 `Seeds::All`，spec **不得假设测试库为空**；本批回归必须按 CI 等价条件跑 |
| `pallastrade-api-v3` | ⬜ 不涉及 | — | `shipping_estimate` 字段集合不变，无端点增删 |
| `pallastrade-decorators` | ⬜ 不涉及 | — | G-1 直改 gem 内服务（团队产品），不加装饰器 |
| `pallastrade-dependencies` | ⬜ 不涉及 | — | 不替换核心服务的计算实现，仅修正其内部过滤 |
| `pallastrade-events-webhooks` | ⬜ 不涉及 | — | 无新领域事件/订阅者；埋点是浏览器侧 GA4 事件 |
| `pallastrade-i18n` | ⬜ 不涉及 | — | 无新增用户可见文案（GA4 `listName` 用稳定英文标识，非 UI 文案） |

---

## 需求标题

商品域收口批次：配送方式作用域修正 + 三处埋点补齐

## 任务类型

功能优化（含 1 项口径修复）

## 需求描述

1. 顾客在实体商品页看到的配送方式，必须是他真能用的：数字商品专用的「Digital delivery」（零价、`display_on='both'`）不该出现，也不该让实体商品显示"免运费"。
2. 运营需要能衡量已上线的转化能力：Related 与 Recently Viewed 的点击要能归因到各自列表；Back-in-stock 缺货订阅要能统计转化。
3. 埋点绝不能拖累交互：发事件失败不得影响订阅或点击的结果。

## 影响范围

| 变更文件 | 说明 |
|---|---|
| `pallastrade_core/app/services/pallastrade/shipping/estimate.rb` | `scoped_methods` 过滤 + `zero_price_method?` 语义收敛 |
| `storefront/src/components/products/RelatedProducts.tsx` | 传 `listId`/`listName` |
| `storefront/src/components/products/RecentlyViewed.tsx` | 传 `listId`/`listName` |
| `storefront/src/components/products/BackInStockNotify.tsx` | 成功/失败埋点（不阻塞） |
| `storefront/src/lib/analytics/gtm.ts` | 新增 back-in-stock 事件构造函数 |
| 测试（后端 2 + 前台 3） | 见 PRD §8 |

**不可触碰**：API 契约字段、Admin 后台、SDK 类型、`ProductCard`（已支持 `listId`）。

## 技术方案（初步）

- **G-1**：`scoped_methods(store, country, product)` 增加两个过滤：
  1. 排除 `calculator_type == 'PallasTrade::Calculator::Shipping::DigitalDelivery'` 的方式；
  2. 当方式**关联了配送分类**时，取与 `product.shipping_category_id` 的交集；方式**未关联任何分类**时保守保留（D1）。
  `zero_price_method?` 只作用于过滤后的集合 → `free_shipping` 自动收敛。
- **G-2/G-3**：两个 rail 复用 `ProductCard` 的既有 `select_item`，传 `listId='related-products'` / `'recently-viewed'`（不新增埋点代码）。
- **G-4**：`gtm.ts` 增 `trackBackInStockSubscribe(...)`；组件在业务成功/失败后调用，调用包 `try/catch` 保证异常不外抛（D5、AP-009b）。

## 不变量（不得破坏）

1. `shipping_estimate` 响应键集合是既有键的**超集**（逐键断言）。
2. 数字商品（`variant.digital?`）仍走既有短路分支。
3. 运行中的免运费促销仍使 `free_shipping=true`。
4. 埋点抛错时，订阅流程仍成功、按钮进入成功态。
5. `ProductCard` 与 `gtm.ts` 既有事件签名不变（只新增）。
6. F-2 既有 16 例断言不变且全绿。

## 文件级实施计划

1. `estimate.rb`：`scoped_methods` 增加 `product:` 入参（或内部取 `product.shipping_category_id`），实现 D1/D3 过滤；`call` 传入 product。
2. `gtm.ts`：新增 `trackBackInStockSubscribe({ productId, variantId, success })`。
3. `BackInStockNotify.tsx`：成功/失败分支各调用一次，`try/catch` 包裹。
4. `RelatedProducts.tsx` / `RecentlyViewed.tsx`：向 `ProductCard` 传 `listId`/`listName`。
5. 测试：后端扩 2 个 spec；前台新增/扩 3 个组件测试。
6. 知识同步：catalog Skill（读模型口径）+ storefront Skill（归因与埋点不阻塞）+ scenarios.json 场景 + 审计报告 G-1 措辞更正。

## 证据计划

| 改动类型 | 证据 |
|---|---|
| 后端读模型 | `harness verify f2-stock-shipping-rspec`（16+ 例） |
| 前台组件 | storefront 单测（`pnpm vitest run`）+ `pnpm check`（biome） |
| 文档 | `doc-impact` + `sync-check` |

## 用户确认

用户于 2026-09-16 明确回复「**实施**」（承接审计建议的下一轮方向），PRD 状态置 approved。
