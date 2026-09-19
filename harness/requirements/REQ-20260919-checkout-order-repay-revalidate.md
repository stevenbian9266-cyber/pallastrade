# REQ-20260919-checkout-order-repay-revalidate

> 关联 PRD：`docs/prd/checkout/PRD-20260919-checkout-结算页待支付订单再次支付重验-失效行剔除-优惠复核-订单金额变化提示-收银台弹窗退役.md`
> Task：`TASK-20260919180342-b99e7595`（risk: critical）｜Gate：`GATE-2026-09-19T18-03-48`

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | revalidate / preflight / line_item / payment_session / checkout | 仅 `app/javascript/types/serializers/*`（类型声明）与 build 产物 | ❌ 无业务实现（正确：逻辑属 Core） |
| App — views/decorators | `backend/app/` | 同上 | 无 | ❌ 无需改动 |
| Core Gem — models | `backend/pallastrade_gems/pallastrade_core/app/models/` | order updated/checkout state/promotion handler | `order_updater.rb`、`order.rb`（`update_with_updater!` / `combined_*_state` / `release_promotion_redemptions`）、`promotion_handler/coupon.rb`（`remove` 路径）、`line_item.rb`、`stock_reservation.rb`、`variant.rb` | ⚠️ 零件齐全、**缺编排** |
| Core Gem — services | `backend/pallastrade_gems/pallastrade_core/app/services/` | order_checkout / transactions / stock_reservations / line_items / cart_legacy | `order_checkout/{recalculate,refresh,readiness,expiration,policies,view,snapshot}.rb`、`transactions/{start,reserve_inventory}.rb`、`stock_reservations/release.rb`、`line_items/{destroy,helper}.rb`、`cart_legacy/{recalculate,remove_out_of_stock_items}.rb`、`carts/submit.rb`、`orders/cancel.rb` | ⚠️ 部分 → 新增 `OrderCheckout::Revalidate`，其余复用 |
| API Gem — controllers | `backend/pallastrade_gems/pallastrade_api/app/controllers/` + `config/routes.rb` | orders / checkout / payment_sessions / transactions | `store/orders/{checkout_controller,payment_sessions_controller,transactions_controller}.rb`、`OrderResolvable`；路由 `resource :checkout` / `resources :payment_sessions` / `resources :transactions` | ⚠️ 缺 preflight 端点 → 新增 |
| Admin Gem — controllers | `backend/pallastrade_gems/pallastrade_admin/app/controllers/` | line_item_destroy_service / remove_out_of_stock | `admin/line_items_controller.rb#destroy` → `PallasTrade.line_item_destroy_service` | ✅ 已有（作为「订单行删除」既有权威被复用，后台零改动） |
| Admin Gem — views | `backend/pallastrade_gems/pallastrade_admin/app/views/` | line_item / order 编辑 | 订单编辑页行删除表单（既有） | ✅ 无需改动 |
| Storefront | `storefront/src/` | OrderPaymentContent / PaymentCheckoutModal / OrderList / OrderPayButton / OrderCombinedPay | `(checkout)/checkout/[id]/page.tsx`（`cart_`→UnifiedCheckout、`or_`→OrderPaymentContent 同路由分流）、`components/checkout/OrderPaymentContent.tsx`、`components/checkout/PaymentCheckoutModal.tsx`、`components/account/{OrderList,OrderPayButton,OrderCombinedPay,OrderDetail}.tsx`、`lib/data/order-payment.ts`、`lib/checkout/recovery.ts`、`messages/{en,de,es,fr,pl}.json` | ⚠️ 部分（页在，preflight 未接；弹窗待退役） |
| Platform | `platform/packages/` | orders.transactions / paymentSessions | `sdk/src/store-client.ts`（`orders.transactions.create`、`orders.paymentSessions.*`）、`sdk/src/types/index.ts`、`sdk/src/zod/generated/*` | ⚠️ 缺 preflight 方法/类型 → 新增 |

### 搜索结论

- **已有能力（复用，禁止重写）**：金额重算（`OrderUpdater` / `OrderCheckout::{Recalculate,Refresh}`）、报价窗口（`Policies#quote_window` 30min / `Expiration`）、就绪度（`Readiness`）、库存预留与释放（`Transactions::ReserveInventory` / `StockReservations::Release`）、订单行删除（`LineItems::Destroy` → `CartLegacy::Recalculate`，admin 同款）、优惠应用/移除与核销台账（`PromotionHandler::Coupon`、`Promotions::Redemption::{Reserve,Release}`）、失效判定谓词（`CartLegacy::RemoveOutOfStockItems#valid_status?/stock_available?`）、支付会话（`PaymentSessions::Start`）、入口可用性（`Payments::Availability::Resolver`）。
- **需新建（唯一编排层）**：`OrderCheckout::Revalidate`（dry-run 报告 + 写路径）、preflight 端点 + serializer、SDK/BFF、or_ 页提示 UI、（微改）`StockReservations::Release#line_item`、两处 quote 门扩面、`Carts::Submit` 签窗与状态投影。
- **防重复判定**：不新建第二个「订单行删除 / 失效判定 / 优惠重算 / 金额重算」；失效谓词抽共享模块后被购物车与订单重验**共用一份**。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 「Lower-numbered options are easier to write, easier to test, and survive upgrades cleanly. Decorators are reserved for *structural* changes… for behavioral changes (callbacks, side effects, sync), use Events instead.」→ 本需求全部落在**既有服务的编排层**（`OrderCheckout::*` / `Transactions::*`），不引入 decorator、不改模型回调 |
| `ai/skills/pallastrade-checkout/SKILL.md` | ✅ 已读 | 「`PallasTrade::PaymentSessions::Start` validates the Order balance/method, reuses a matching active attempt, performs provider I/O outside database transactions, then reconciles concurrent sessions under a second Order lock.」+「Account single/multi-order cashier flows never submit a Cart or create an Order. They pay the existing `or_` / `pcom_` target.」→ 补付重验必须挂在 `Transactions::Start`/`PaymentSessions::Start` 这一侧，且账户侧只付既有 `or_` 单 |
| `ai/skills/pallastrade-promotions/SKILL.md` | ✅ 已读 | 「Redemption ledger: occupancy is tracked in `PallasTrade::PromotionRedemption` (`reserved → committed → released`; unique `(promotion_id, order_id)`)」+ 券移除走 `release_redemption_or_detach_code`（reason `coupon_removed`）→ 剔除商品后的优惠复核复用 `Coupon#remove`，不新造核销逻辑 |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-payments` | ✅ | ✅ 已读（要点） | 支付入口可用性以 `Payments::Availability::Resolver` 为唯一权威；`Start` 前门禁与入口级同源校验（D7/D8/D15c）不得绕过 |
| `pallastrade-storefront` | ✅ | ✅ 已读（要点） | 「Cashier modal（个人中心场景 D）`components/checkout/PaymentCheckoutModal.tsx`：only payment UI, never Cart submit/Order create」→ 本次退役该组件，账户入口改为跳 `or_` 支付页 |
| `pallastrade-testing` | ✅ | ✅ 已读（约定） | 后端 RSpec + Factory Bot；storefront vitest；测试头标注 `# PRD-xxx AC-xxx`（AC 必须完整 PRD-ID） |
| `pallastrade-i18n` | ✅ | ✅ 已读（约定） | storefront 五语言（en/de/es/fr/pl）键集必须一致，`pnpm check:locales` 强制 |
| `pallastrade-api-v3` | ✅ | ✅ 已读（约定） | 新端点须同步 `backend/public/api-docs/store.yaml` + `platform/docs/api-reference/`，`harness generated:check` 校验；响应恒 `or_` 前缀 id |
| `pallastrade-data-model` | ✅ | ✅ 已读（要点） | 订单金额列/状态列口径（`total/amount_due/payment_state/shipment_state`）由 `OrderUpdater` 派生，禁止手改 schema；本次**零迁移** |
| `pallastrade-customization` | ✅ | ✅ | 见上 |

---

## 需求标题

待支付订单再次支付前做一次**同源重验**（价格/可售/库存/配送可达/运费/税/优惠/抵扣/就绪度），失效商品**剔除后只付有效部分**并提示金额变化；同时把账户侧补付入口统一为**跳订单支付页**并退役收银台弹窗。

## 任务类型

功能优化（含 Bug 修复：订单状态投影缺失导致列表空列 + 无补付入口；含前台退役：收银台弹窗）

## 需求描述

- 用户拍板 4 项：
  1. 跳订单支付页，**移除收银台弹窗相关逻辑与代码**；
  2. **无需二次确认**新金额——页面直接回显新金额，但**必须有「订单金额已变化」提示**（多语言）；
  3. 阻断类商品不可支付：UI 提示商品失效，**只对有效商品实际扣款**；若使用了优惠，需复核优惠是否仍满足当前有效商品；
  4. 存量按 AI 建议（只回填近期状态投影，不迁移报价窗口）。

## 影响范围（harness affected 输出）

实施时执行 `npx harness affected --base origin/dev` 并回填（预期：Core 服务/模型、API 端点、SDK、Storefront 组件与页面、契约 yaml、Skill 与场景库）。

## 技术方案（初步）

1. **`OrderCheckout::Revalidate`（新，dry-run 默认）**：`order.with_lock` + 事务内执行（dry-run 结束 `Rollback`）——
   ① 失效行判定（共享谓词）②（写）`LineItems::Destroy` + 行级释放预留 ③ 窗口失效/缺失 → `update_line_item_prices!` ④ 优惠复核（`Promotion#eligible?` → `PromotionHandler::Coupon#remove`）⑤ 抵扣再平衡（`GiftCards::Apply` / `Checkout::AddStoreCredit` 口径）⑥ `OrderCheckout::Refresh`（重算 + 版本自增 + 窗口续期）⑦ 结构化报告。
2. **门扩面**：`Transactions::Start#quote_gate_active?` 与 `PaymentSessions::Start#gate_active?` → `standard_flow? && !completed?`（无窗口=陈旧 ⇒ 全量重验；窗口内=锁价）。
3. **`Carts::Submit`**：建单后签发 `checkout_expires_at`；提交后显式落 `payment_state`/`shipment_state`。
4. **preflight 端点**：`GET /api/v3/store/orders/:order_id/payment_preflight`（只读，`OrderResolvable`），SDK `orders.paymentPreflight.get`，BFF `GET /api/checkout/preflight`。
5. **写路径接线**：`Transactions::Start` 步骤 ① 扩为 `reconcile`（Revalidate 写路径 + 金额/版本比对 → 409 `quote_changed` 带 `changes[]`）。
6. **前台**：or_ 页消费 preflight，直接展示重验后金额 + 提示块；`PaymentCheckoutModal` 删除；列表/详情 Pay 跳订单支付页；列表三列修复（`completed_at ?? submitted_at` + 状态派生）。

## 风险点

- **最高风险**：金额不诚实（页面显示 ≠ 实际扣款）→ 以「同源 + 409 兜底 + 测试 AC-002」控制；
- 剔除行会触发 `CartLegacy::Recalculate`（移除礼品卡/清 store-credit checkout 支付）→ 以「抵扣再平衡」显式兜底（AC-005）；
- 弹窗退役影响账户侧既有路径 → 全仓 grep 0 引用 + 组件测试 + dev 真机；
- 回滚难度：中（无 schema 变更；回滚 = revert 提交，订单数据不受影响——重验只在支付时执行）。

## 决策节点

> ⏸️ 用户已确认（2026-09-19/20 两轮拍板 + 「实施」），状态 approved，直接进入实施。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| Core 服务 | `order_checkout/revalidate.rb` 等 | `harness verify order-repay-rspec` | | ⬜ |
| API 端点 | `payment_preflight_controller.rb` + routes + serializer | `harness generated:check` | | ⬜ |
| 契约/SDK | `store.yaml` / `platform/docs/api-reference` / `sdk` | `generated:check` + `pnpm typecheck`（platform） | | ⬜ |
| Storefront | or_ 页提示 / 弹窗退役 / 列表入口 | `harness verify storefront-test` + i18n 键集 | | ⬜ |
| 真机 | dev `#R729701382` 等 | 截图/日志（列表三列 + 补付重验提示） | | ⬜ |
