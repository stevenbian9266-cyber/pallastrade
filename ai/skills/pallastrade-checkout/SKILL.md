---
name: pallastrade-checkout
description: Use when the user is working on PallasTrade's checkout flow — cart pipeline, order state machine, address handling, the transition from cart to completed order, customizing checkout steps, payment sessions, guest checkout. Common phrasings include "checkout broken", "order stuck in X state", "skip address step", "guest checkout", "cart not advancing", "payment session", "customize checkout flow", "add a checkout step". Provides the order state machine, the cart pipeline, and the customization hooks.
---

# PallasTrade Checkout

Checkout is how a cart becomes a completed order. In PallasTrade, an Order is the cart (while in cart state) AND the completed transaction (post-complete); the `state` column tracks which phase you're in.

## Order splitting (P2, 能力层服务)

> P2（2026-08-26）新增**统一拆单引擎**（默认不接入任何流程，P5 自动拆单 / P6 手动拆单负责接入）。

- **`PallasTrade::Orders::Splitter`**：`split(order:, groups:, options)`，把订单行项目按分组拆成多笔子订单。
  - `groups = { group_key => [line_item_id, ...] }`（支持 `li_` 前缀或整型 id）
  - `options[:parent_order]` 指定父订单（默认源订单自身为父）
  - 子订单复制 store/user/channel/market/currency/email/地址 + `parent_id`/`split_from_id` 指向源订单
  - **调整项**：line_item 级调整随行项目迁移；order 级非税 eligible 调整（promo）按行项目金额比例分摊到子订单（**分摊调整创建后强制 closed 冻结**，防 `AdjustmentsUpdater` 用 source 重算覆盖）；分摊后删除源订单的原 order 级调整（防父容器金额重复）
  - **已付分摊**：源订单有 completed 支付时，按行项目金额比例创建 `PaymentSplit`（`payment_combination` 为空——记账分摊，P4 合并支付归入组合）
  - **金额重算**：子订单/源订单各跑 `OrderUpdater`（注意先 `line_items.reload`，避免缓存旧关联）
  - **幂等**：重复拆分返回失败（源订单行项目已迁移/为空）
  - 发布 `order.splitted` 事件（payload 含 `child_order_ids`）
- **策略分组**：`PallasTrade::Orders::SplitStrategies::ByStockLocation`（按变体主供仓库分组）、`ByStore`（按商品归属店铺）；自定义策略继承 `SplitStrategies::Base#groups_for(order)`。
- 关键约定：拆单前后**总额守恒**（Σ子订单 + 源订单剩余 = 原订单）；源订单全部分出后成为空父订单容器（金额派生见 P3）。

### 发货状态聚合（P3, 2026-08-27）

> 父订单（有 children）的发货状态由 `Order#combined_shipment_state` 派生（只读，不覆写核心 `shipment_state`）：聚合 own shipments + children 状态，套用 `OrderUpdater#update_shipment_state` 规则（任一 backorder → `backorder`；多状态含 shipped → `partial`；含 pending → `pending`；否则 `ready`）。Store/Admin `OrderSerializer` 的 `fulfillment_status` 在父订单时输出该聚合值。

### 组合支付订单完成（P4, 2026-08-27）

> 合并支付成员订单没有本地 payment（资金在组合上）。两个配套点使其可完成：

- **checkout 状态机放行**：`before_transition to: :complete` 在 `payment_required? && payments.valid.empty?` 时，若订单存在**已捕获的 `PaymentSplit`**（`captured_amount > 0`）则放行（无需本地 payment、不再 `process_payments!`）；否则维持原 `no_payment_found` 错误。单订单场景行为不变。
- **完成入口**：`PaymentCombinations::Complete` 阶段 2 逐个用 `checkout_complete_service`（`PallasTrade::Checkout::Complete`）完成成员订单；失败标 `balance_due` + 入 `CombinationSettleJob` 重试。详见 `pallastrade-payments` SKILL。

### 自动拆单 + Buy Now（P5, 2026-08-27，flag 灰度）

- **自动拆单**：`PallasTrade::Carts::AutoSplit` 在 `Carts::Complete` 完成（支付确认后）按配置策略拆分。策略列表来自 `store.preferred_auto_split_orders`（JSON 数组字符串，如 `'["PallasTrade::Orders::SplitStrategies::ByStockLocation"]'`）回退 `Config[:auto_split_orders]`，默认 `[]`（关闭）。**不在 cart 中途拆**；拆单失败不影响订单完成（`Rails.error.report`）。
- **Buy Now**：商品详情页 `BuyNowButton`（`storefront/src/components/products/BuyNowButton.tsx`）——`createBuyNowCart`（`lib/data/buy-now.ts`）创建含当前商品的独立 cart 直接进入确认页，不污染购物车。

### 手动拆单 + 父子树（P6, 2026-08-28，flag 灰度）

- **编排服务**：`PallasTrade::Orders::ManualSplit`（`pallastrade_core/app/services/pallastrade/orders/manual_split.rb`）复用 P2 `Splitter` 之上补齐 P6 语义：
  - **不可拆已发货**：勾选行项目含 `shipped` inventory_units → 明确业务错误（不部分执行）；
  - **子订单补 completed**：源订单 completed 时子订单 `update_columns(state: 'complete', completed_at:)`（绕过状态机，不重走 checkout）；
  - **子订单建 shipment**：stock_location 取源订单首个未取消 shipment，迁移 inventory_units；**运费保留在父订单**——子订单 shipment `cost: 0`，且不调 `OrderUpdater#update_shipments`（会对 completed 子订单 `refresh_rates` 重复计运费），手动派生 `shipment_total/shipment_state/payment_total/payment_state/total`（`payment_total` 从 P2 `PaymentSplit` 刷新）。
- **Admin API**：`POST /api/v3/admin/orders/:id/split`（`groups` 分组 + `parent_order_id` + `store_id` 同店校验；flag 关闭 404）。详见 `pallastrade-api-v3`。
- **flag**：`store.preferred_manual_split_enabled` / `Config[:admin_manual_split_enabled]`，默认关闭。

### 售后父子单化（P7, 2026-08-28，flag 灰度）

- **子订单退款**（拆单/组合支付后资金在组合 payment，子订单无本地 payment）：
  - `ReimbursementType::OriginalPayment#reimburse`：`order.payments.completed` 为空时从 `order.payment_splits`（P2/P4 已建）定位关联 payment（含组合 payment）退款，且退款上限按 `split.captured - refunded`（`reimbursement_helpers#create_refunds` 新增 `payment_credit_limits` 参数）。
  - `Refund#update_order`：`payment.order` 为 nil（组合支付）时更新对应子订单 `PaymentSplit.refunded_amount`（P4 语义：部分退款只更新对应子订单 split，不碰兄弟单）+ 触发子订单 updater。
  - `Refund#order`/`editable?`：`payment.order` nil 时从 reimbursement→customer_return→return_items→inventory_unit.order 推导（`reimbursement_target_order`）。
- **父订单批量售后**：`PallasTrade::Returns::ParentOrderReturns`（`call(parent_order:, stock_location:, reason:, memo:)`）——展开父订单 + 全部 children，为每个有 shipped（且未被既有 RA 关联）inventory_units 的订单创建 `ReturnAuthorization` + return_items；单订单失败跳过（尽力而为），幂等（已关联 units 自动排除）。
- **Admin**：父订单详情 dropdown「Parent Order Returns」入口（flag + `can?(:create, ReturnAuthorization)`）+ `parent_order_returns` 批量创建页。
- **flag**：`store.preferred_returns_parent_order_handling` / `Config[:returns_parent_order_handling]`，默认关闭。

### 前置校验 / 风控 / 锁存双模式（P8, 2026-08-28，flag 灰度）

- **风控引擎**：`PallasTrade::Risk`（`lib/pallastrade/risk.rb`）——`rules` 可注册（`PallasTrade::Risk.rules << RuleClass`，规则实现 `#call(order:, user:, store:)` → nil 或 `{ code:, message: }`）；`evaluate` 返回首个命中。内置：`BlacklistRule`（`users.blacklisted_at`）与 `OrderFrequencyRule`（同用户 N 分钟内完成订单数 > `order_frequency_limit`，默认关闭）。
- **前置校验**：`PallasTrade::Checkout::Preflight`（`call(order:)`）——`Carts::Complete` 支付处理前评估 Risk，命中返回 `failure(order, { code:, message: })`；登录强制已由既有 `guest_checkout_disallowed?` 覆盖。flag `checkout_preflight_enabled` 默认关闭。
- **统一错误**：`render_service_error` 支持 `ResultError` 解包 + `{ code:, message: }` Hash 结构化错误（黑名单/风控/防刷单等）。
- **锁存双模式**：`Config[:stock_reservation_strategy]`（`:order` 默认 / `:payment`）——`:order` = cart 操作时 Reserve（现状）；`:payment` = cart 操作只校验不落 reservation（`Reserve.call(order:, validate_only: true)`，调用点：add_item/set_quantity/update/remove_line_item），支付确认后（`Carts::Complete` 内 `payment_total > 0` 时）真正 Reserve → complete 后 Release。

### 订单模块：单笔 checkout / 多笔合并支付新流程（2026-08-29，PRD-20260829-checkout 订单模块）

账户订单页勾选待支付订单时的分流与新合并流程（Storefront `OrderCombinedPay` → `CombinedPaymentCheckout`）：

- **分流**：`OrderCombinedPay`（`storefront/src/components/account/OrderCombinedPay.tsx`）——恰好 1 笔 → `/checkout/[orderId]`（单订单 checkout，沿用订单地址/配送，只确认 + 支付，复用 P1 `OrderPaymentContent`）；2+ 笔 → `POST /payment_combinations` → `/combined-payment/[pcom_id]`。
- **合并流程两步骤**：`CombinedPaymentCheckout`（`storefront/src/components/checkout/CombinedPaymentCheckout.tsx`）：
  1. **收货**：`GET /payment_combinations/:id?expand=orders` 展开成员订单；逐单确认/编辑收货地址，保存走 `PATCH /customers/me/orders/:order_id/shipping_address`（`Store::Customer::Orders::ShippingAddressController` → `PallasTrade::Orders::UpdateShippingAddress`，仅当前用户自己的未支付订单可改，防 IDOR）；无地址订单强制填写后才能进入支付（AC-004）。
  2. **商品 + 支付**：展示各成员订单商品明细（订单号/商品/数量/小计/运费/合计）与组合总金额；Stripe PaymentElement 区域无任何地址输入（AC-007）。
- **订单收货地址更新 API**：`PATCH /api/v3/store/customers/me/orders/:order_id/shipping_address`——复用 `Carts::Update` 的地址赋值模式（`shipping_address_id` 引用用户已存地址 / 就地更新挂载地址，country_iso/state_abbr 由 Address 模型解析），已下单订单不重置 checkout 状态机，同步已有 shipment 的 address_id。
- **SDK**：`paymentCombinations.get(id, { expand: ['orders'] })`；`orders.updateShippingAddress(orderId, { shipping_address | shipping_address_id })`。

## The order state machine

Default checkout flow on an Order:

```
cart  →  address  →  delivery  →  payment  →  confirm  →  complete
```

Each step is conditional. Looking at `PallasTrade::Order.checkout_flow`:

```ruby
checkout_flow do
  go_to_state :address
  go_to_state :delivery, if: ->(order) { order.delivery_required? }
  go_to_state :payment,  if: ->(order) { order.payment? || order.payment_required? }
  go_to_state :confirm,  if: ->(order) { order.confirmation_required? }
  go_to_state :complete
end
```

So:
- **All-digital orders** are not skipped via `delivery_required?` — in core that method unconditionally returns `true` (decorate it to change). Instead, digital-only orders (`requires_ship_address?` is `!digital?`) still transition *into* `delivery`, then an `after_transition to: :delivery` hook (`move_to_next_step_if_address_not_required`) immediately calls `next!` to auto-advance past it.
- **Zero-total orders** (free orders) skip `payment` — `payment_required?` is simply `total.to_f > 0.0`. Note gift cards do NOT zero the total: applying one creates a store-credit payment for the covered amount, so a gift-card-covered order still has `total > 0` and still goes through the `payment` step, where that payment satisfies it.
- **`confirm`** is opt-in — disabled by default; some payment integrations enable it.

The transition driver is `state_machines-activerecord`. Advance with `order.next!` (raises on failure) or `order.next` (returns false on failure).

```ruby
cart.state                # => "cart"
cart.next!                # => transitions to "address" (if validation passes)
cart.state                # => "address"
```

### `state` vs `status` columns

Order has BOTH `state` (the checkout state machine — values from the flow above) and `status` (the high-level lifecycle: `PallasTrade::Order::STATUSES = %w[draft placed canceled]`). `payment_state` and `shipment_state` are separate denormalized columns reflecting the rollup of child Payment and Shipment states.

## The cart pipeline (recalculate chain)

Whenever a cart changes (item added, removed, address updated, promo applied), PallasTrade runs a **recalculate chain** to keep derived state correct. The chain is `PallasTrade.cart_recalculate_service` (default: `PallasTrade::Cart::Recalculate`):

```
PallasTrade::Cart::Recalculate
  ├── Update item totals
  ├── Recalculate adjustments (taxes, discounts, fees)
  ├── Apply promotion actions
  ├── Update shipment costs
  ├── Recompute order totals
  └── Persist
```

The chain is composed of services swappable via `PallasTrade.dependencies`:

```ruby
# config/initializers/pallastrade.rb
PallasTrade.cart_add_item_service       = MyApp::Cart::AddItem
PallasTrade.cart_recalculate_service    = MyApp::Cart::Recalculate
PallasTrade.cart_remove_item_service    = MyApp::Cart::RemoveItem
PallasTrade.cart_update_service         = MyApp::Cart::Update
```

To inject behavior into the cart pipeline, **subclass the service**, override `call`, and register. Don't decorate `PallasTrade::Order` to add a callback — that fires on every save and confuses the state machine.

For the full `PallasTrade.dependencies` system (catalog of swappable services, introspection rake tasks, per-API-surface overrides), see the `pallastrade-dependencies` skill.

```ruby
module MyApp
  module Cart
    class AddItem < PallasTrade::Cart::AddItem
      def call(order:, variant:, quantity: nil, metadata: {}, public_metadata: {}, private_metadata: {}, options: {})
        ApplicationRecord.transaction do
          run :add_to_line_item
          run :handle_stock_reservations     # keep the parent's stock reservation step
          run :my_custom_step                # your custom logic
          run PallasTrade.cart_recalculate_service
        end
      end

      def my_custom_step(order:, line_item:, line_item_created:, options:)
        # ... your custom logic ...
        success(order: order, line_item: line_item, line_item_created: line_item_created, options: options)
      end
    end
  end
end
```

When you subclass `PallasTrade::Cart::AddItem`, keep all the parent's `run` steps and slot yours in — don't drop `:handle_stock_reservations` or you'll silently break stock reservations for orders in checkout. Every `run` step receives the previous step's `success(...)` hash as keywords and must itself end with `success(...)`/`failure(...)` — that's why `my_custom_step` above takes the keys `handle_stock_reservations` returns and passes them along.

## Customizing the checkout flow

Add, remove, or reorder steps via `PallasTrade::Order#checkout_flow` (decorator). The state machine is rebuilt when the flow is re-declared.

```ruby
# backend/app/models/pallastrade/order_decorator.rb — REMOVE the address step (e.g. digital-only store)
module PallasTrade::OrderDecorator
  def self.prepended(base)
    base.checkout_flow do
      go_to_state :delivery, if: ->(order) { order.delivery_required? }
      go_to_state :payment,  if: ->(order) { order.payment? || order.payment_required? }
      go_to_state :complete
    end
  end

  PallasTrade::Order.prepend self
end
```

To **insert** a new step (e.g. a "review" step between `payment` and `confirm`):

```ruby
base.insert_checkout_step :review, after: :payment
```

To **remove** a single step there's also `base.remove_checkout_step :address` (one step per call) — no need to re-declare the whole flow unless you're redefining it entirely.

Common gotchas:

- **Existing in-progress orders have a `state` that may not exist in your new flow.** Add a backfill rake task that resets them to `cart` or migrates to the new state.
- **State machine guards run on every transition** — `delivery_required?`, `payment_required?`, etc. Decorating these to lie about the cart's state breaks the flow.

## Address handling

`PallasTrade::Address` is used for both billing and shipping. Order has `bill_address_id` and `ship_address_id`. Both can point at the same address (one-form checkout); the validator allows nil for both during the `cart` state.

Country/State are normalized to `PallasTrade::Country` and `PallasTrade::State` records (not free text). Form input from the storefront is validated against the country's `PallasTrade::State` set. State validation is gated by `PallasTrade::Config[:address_requires_state]` (marked deprecated in 5.5, but still honored) and the country's `states_required` flag — countries with `states_required: false` skip it entirely. A country with `states_required: true` but no seeded `PallasTrade::State` records still requires a free-text `state_name`.

### Guest checkout vs logged-in

`Order.user_id` is nullable. Guest orders have `email` set instead. After completion, the guest's order token remains the credential for viewing the order — `GET /api/v3/store/orders/:id` with the `X-PallasTrade-Token` header. If the guest opts into account creation at checkout, `PallasTrade::Orders::CreateUserAccount` links the order to a new user (or an existing user with the same email) at completion. There is no number+email claim flow, and registering later does not auto-link past guest orders.

For the storefront, the guest cart is tracked via a **cart token** (`Order.token` — a random per-cart string). The token is in a cookie or returned to the API client. JWT auth replaces token auth once the customer logs in.

## Payment sessions (5.4+)

The classic PallasTrade payment flow created a Payment record + processed it inline. The 5.4+ refactor introduced **PaymentSession** — an intermediate object that handles redirect-based provider flows (Stripe Checkout, Adyen drop-in, PayPal Smart Buttons).

```
Order (cart)
  ↓
PaymentSession  ← provider-specific session data
  ↓             (created by pallastrade_stripe / pallastrade_adyen / pallastrade_paypal_checkout)
Customer redirects to provider
  ↓
Customer returns OR provider webhook fires
  ↓
PaymentSession.complete!
  ↓
Payment record created
  ↓
Order transitions to `confirm` or `complete`
```

Events: `payment_session.processing`, `payment_session.completed`, `payment_session.failed`, `payment_session.canceled`, `payment_session.expired`. See the `pallastrade-events-webhooks` skill.

In your subscriber, the `payment_session.completed` event payload includes the `order_id` — you can hook in custom logic after the customer returns from the provider but before the order finalizes.

## The complete transition

When the order transitions to `complete`:

1. Inventory is allocated via shipment finalization (`shipment.finalize!`); stock reservations from checkout are released (deleted) by `PallasTrade::StockReservations::Release` once the order completes.
2. `PallasTrade::OrderUpdater` finalizes totals.
3. `order.completed_at` is set.
4. `order.publish_event('order.completed', payload)` fires — subscribers run, webhooks deliver.
5. For guests, the order token remains the credential for viewing the completed order — the Store API scopes guest order lookup by `token` (`X-PallasTrade-Token` header). The order's human-facing `number` (e.g. `R123456789`, assigned at creation) is for display and support, not API lookup.

After complete, the order should be immutable from the customer's side. Admins can still adjust (refunds, return authorizations, edits) but those go through dedicated controllers, not the cart pipeline.

## Common checkout problems

### "Order stuck in checkout"

- Missing line items: `order.line_items.count == 0`. `ensure_line_items_present` runs on every transition out of `cart` — this is the only thing that blocks leaving `cart` itself.
- Missing address: `order.bill_address` or `order.ship_address` is nil. This doesn't block leaving `cart` — it surfaces at `address → delivery` (no ship address means no proposed shipments, so `ensure_available_shipping_rates` fails). Run `order.next!` and check the validation errors.
- A variant became discontinued or out of stock: blocks the transition to `complete` (and `resumed`), and the order gets bounced back to the start of checkout via `restart_checkout_flow`. Check `order.line_items.map(&:variant).map(&:purchasable?)`.

### "Customer redirected to Stripe but never returned"

- PaymentSession is still in `processing` state. Either Stripe's webhook never fired (check `pallastrade_stripe`'s endpoint config) or the customer abandoned. The session has a TTL (`expires_at`) — core filters timed-out sessions via the `not_expired`/`active` scopes, but the `payment_session.expired` event only fires when something explicitly triggers the `expire` transition (typically the gateway extension reacting to a provider webhook).
- The redirect-back URL is wrong. Check `pallastrade_stripe`'s configured `return_url`.

### "Cart total doesn't match what's displayed"

- The cart pipeline didn't run after the last change. Trigger `PallasTrade::Cart::Recalculate.call(order: order, line_item: order.line_items.last)` manually and inspect.
- A custom adjustment isn't being applied. Check `order.adjustments.eligible.sum(:amount)`.
- Promotions are eligible but not applied. See the `pallastrade-promotions` skill — common cause is promotion `usage_limit` exhausted.

### "Skip the payment step for a free order"

`order.payment_required?` returns false when the order total is zero (`total.to_f > 0.0` is the implementation). If your custom flow needs to skip even more aggressively, override `payment_required?`:

```ruby
module PallasTrade::OrderDecorator
  def payment_required?
    return false if my_special_condition?
    super
  end

  PallasTrade::Order.prepend self
end
```

## Where to read further

- **Core concepts:** `node_modules/@pallastrade/docs/dist/developer/core-concepts/orders.md`, `payments.md`
- **Checkout customization:** `node_modules/@pallastrade/docs/dist/developer/customization/checkout.md`
- **Order source:** `PallasTrade::Order` and `PallasTrade::Order::Checkout` in the installed `pallastrade_core` gem — the state machine wiring.
- **Cart services:** `PallasTrade::Cart::AddItem`, `PallasTrade::Cart::Recalculate`, etc. in `pallastrade_core/app/services/pallastrade/cart/`.
