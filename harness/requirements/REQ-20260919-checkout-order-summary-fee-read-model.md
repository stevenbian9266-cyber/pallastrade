# REQ-20260919-checkout-order-summary-fee-read-model

> 任务：`TASK-20260919072708-4d7efe5a` ｜ Gate：`GATE-2026-09-19T07-27-25`（feature）｜ 风险：quick（paths 因子被并行会话未提交后台文件抬为 critical → `--override quick` + recovery）

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

关键词：`order summary` / `shippingCalculatedAtSubmit` / `display_item_total` / `discount_total` / `tax_total` / `quote` / `CheckoutView`。

| 层 | 搜索路径 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|
| App — models/controllers/views | `backend/app/` | 无（宿主不承载结账页渲染） | 否（也无需改） |
| Core Gem — models | `backend/pallastrade_gems/pallastrade_core/app/models/` | `pallastrade/cart.rb`（**仅 `money_methods :item_total`**，车阶段无运费/税/总额） | ❌ 车级无定价能力（A1 不可行的关键证据） |
| Core Gem — services | `.../app/services/pallastrade/` | `order_checkout/view.rb`（`CheckoutView` **已下发** `delivery_total / discount_total / tax_total / amount_due / total` + `display_*`）；`carts/submit.rb`（权威金额在提交订单时经 Order 管线计算） | ✅ 权威字段齐备，**无需后端改动** |
| API Gem | `.../pallastrade_api/app/` | `store/shipping_methods_controller.rb`（注释：权威运费在提交订单时计算）；`serializers/.../shopping_cart_serializer.rb`（下发**抵扣意图** `discount_code` / `gift_card` / `store_credit`） | ✅ 意图字段已在前台载荷 |
| Admin Gem | `.../pallastrade_admin/app/` | 无关 | — |
| Storefront | `storefront/src/` | `components/checkout/UnifiedCheckout.tsx`（`UnifiedOrderSummary` `:129-260`：运费占位句当值、费用行条件渲染依赖 legacy `discountCart`、Total 用小计冒充）；`lib/checkout/server.ts#readQuote`（**未**取 tax 字段）；`app/api/checkout/coupon/route.ts`（仅 POST/DELETE，无 GET → 刷新后无计算值） | ✅ **本需求全部在前台读模型** |
| Platform | `platform/packages/` | SDK `ShoppingCart` 类型含 `display_item_total` / `discount_code` / `gift_card` / `store_credit`；无相关 UI | 否（无需改） |

### 搜索结论

- 权威金额**只在 Order 上产生**（`Carts::Submit` → `OrderUpdater` → `CheckoutView`），车阶段没有可复用的定价服务 → 真·A1（车级权威报价）须后端改造，本轮不做。
- 但 **`CheckoutView` 已下发 tax 等全量字段**，BFF 只是没取 → 扩 `readQuote` 即可让右栏显示权威税费（零后端改动）。
- 抵扣**意图**已在 `ShoppingCart` 载荷（`discount_code` / `gift_card` / `store_credit`）→ 费用行的"存在性"不再依赖 legacy `discountCart`，可修复"刷新后消失"。
- 变更面 = 2 个前台源码文件（+ 1 个类型文件）+ 5 个文案文件 + 测试 + 文档。

## Step 1：Skill 文件咨询（功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 优先级链最高档是"改设置/配置"，最低档是"改 gem/契约"；本次为**前台读模型修正**（消费既有字段），不触碰任何后端定制点 |
| `ai/skills/harness-prd/SKILL.md` | ✅ 已读 | 一句话需求 → PRD（背景/FR/AC/技术影响/测试计划/文档同步）→ 用户确认 → gate → 实施 → 知识同步 |
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ 已读 | **money 契约**：`raw` 字段只用于条件判断，`display_*` 只用于渲染，禁止 `parseFloat(display_*)`；"TOTAL SAVINGS" 只统计促销折扣；改 storefront 必跑 biome(80) + typecheck |

**按需 Skill（本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-checkout` | ✅ | ✅ 已读 | 两段语义：`Prepare`（`carts.update` + `carts.submit`，返回 `order_id/order/quote`）→ 页内确认区（`order-quote-confirm`，金额全用 `display_*` 只读渲染）→ 用户确认才 `Pay`。本次把同一份 `quote` 也投影到右栏摘要（同源同值） |
| `pallastrade-i18n` | ✅ | ✅ 已读 | 新增键必须五语言齐备并登记 `checkout-i18n-keys.test.ts` REQUIRED；删除键需确认无其它引用 |
| `pallastrade-api-v3` / `pallastrade-decorators` / `pallastrade-events-webhooks` / `pallastrade-dependencies` | ❌ | — | 零后端、零事件、零依赖注入 |

---

## 需求标题

修正 checkout 右栏订单摘要的费用口径，并在 Prepare 后同步 Order 权威金额。

## 任务类型

功能优化（前台读模型 + 文案；零后端）。

## 需求描述

右侧订单摘要里，运费位置显示的是一整句"提交订单时计算"，而折扣/税费/礼品卡这些行在没操作过优惠码时会整体消失，总额又拿小计顶替。要求：金额行语义正确、已应用的抵扣项始终可见（未知就写"提交订单时计算"）、总额在有权威报价后显示真实应付；右栏与主列确认区同源。

## 影响范围

- 前端：`UnifiedCheckout.tsx`（摘要组件 + 发布 effect）、`lib/checkout/server.ts`（`readQuote` 补 tax）、`lib/checkout-quote.ts`（类型）
- 文案：`messages/{en,de,es,fr,pl}.json`（新增/删除键）
- 测试：`UnifiedCheckout.test.tsx`、`checkout-i18n-keys.test.ts`
- 文档：PRD/REQ、A1 设计要点、storefront Skill、场景库 GS-191
- **零**后端 / 契约 / SDK 改动

## 技术方案（初步）

三级优先读模型：① `prepare` 返回的 Order 权威报价（`display_delivery_total` / `display_discount_total` / `display_tax_total` / `display_amount_due`）→ ② 既有 legacy 计算值（用户本次操作优惠码后得到）→ ③ 明确"提交订单时计算"标签。费用行的**存在性**改由 `cart.discount_code` / `cart.gift_card` / `cart.store_credit` 意图驱动；总额标签按是否有权威报价切换 `estimatedTotal` / `totalDue`。

## 验证方案（AC 映射）

| AC | 命令/测试 |
|---|---|
| AC-001 ~ AC-006 | `npx harness verify storefront-test --task TASK-20260919072708-4d7efe5a`（`UnifiedCheckout.test.tsx` 新增两组摘要用例 + 既有回归） |
| AC-007 | 同上（`checkout-i18n-keys.test.ts`） |
| 格式化/类型 | `pnpm -C storefront check`、`pnpm -C storefront typecheck`、`pnpm -C storefront check:locales` |

## 用户确认

✅ 已确认（2026-09-19）——用户原话：「**实施：第5项：方案A**」，随后「**自主决定**」授权按其可行性复核结论选择落地方式（A2 实施 + A1 出设计要点）。
