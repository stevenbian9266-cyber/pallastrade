---
name: pallastrade-payments
description: Use when the user is working with PallasTrade's payment system — payment methods, gateways (Stripe, Adyen, PayPal), payment sessions, the payment state machine, refunds, store credits, gift cards. Common phrasings include "add payment gateway", "Stripe integration", "payment failed", "refund order", "store credit", "gift card", "payment state stuck", "configure PaymentMethod", "process payment manually". Provides the payment graph, the state machine, and the integration points.
---

# PallasTrade Payments

> Commands below use the PallasTrade CLI form (`pallastrade …`, Docker). On a classic Rails app without the CLI (typical pre-5.4), use the native mapping in the `pallastrade-project` skill — `bin/rails` / `bundle exec rake` from the app root, paths without the `backend/` prefix.

Payments in PallasTrade are layered:

```
PaymentMethod   — the configured way to pay (Stripe, Adyen, PayPal, store credit, …)
  ↓
Payment         — the actual charge against an Order via a PaymentMethod
  ↓
source          — the Payment's polymorphic source: a CreditCard, StoreCredit, or PallasTrade::PaymentSource (wallets/accounts)
```

(A PaymentSession is not a payment source — it links to the Payment via the gateway transaction id, `response_code`/`external_id`.)

A single Order can have multiple Payments (e.g. store credit or a gift card combined with a card payment), each with its own state. Creating a new non-store-credit payment auto-invalidates any other payment still in the `checkout` state (store credit payments are spared), so splitting an order across multiple cards at checkout isn't supported.

## Payment state machine

```
checkout  →  processing  →  pending  →  completed
        ↘              ↘            ↘
         invalid        failed       void
```

| State | What it means |
|---|---|
| `checkout` | Payment created during cart phase; no money moved yet |
| `processing` | Gateway call in flight |
| `pending` | Authorized but not captured (auth/capture flow, e.g. credit card pre-auth) |
| `completed` | Captured — money has actually moved |
| `failed` | Gateway returned an error during processing |
| `void` | Cancelled — usually before capture, but completed payments can also be voided (gateway permitting) |
| `invalid` | Superseded — a newer payment was added to the order (old `checkout` payments are auto-invalidated), or the source is unsupported by the gateway |

Transitions are events: `started_processing`, `pend`, `complete`, `failure`, `void`, `invalidate`. After-callbacks fire `payment.completed` / `payment.voided` events. See the `pallastrade-events-webhooks` skill.

## Payment methods

A PaymentMethod is configured in the admin (Settings → Payments). The model carries:

- `type` — the Ruby class implementing it (`PallasTradeStripe::Gateway`, `PallasTrade::PaymentMethod::StoreCredit`, etc.). Note the STI *column* stores the class name, but as of 5.5 the API-serialized `type` (and the value `POST /api/v3/admin/payment_methods` expects) is a stable shorthand — `stripe`, `adyen`, `paypal_checkout`, `check`, `store_credit` — see the 5.4→5.5 upgrade guide.
- `name` — what the customer sees ("Credit Card", "PayPal", etc.)
- `display_on` — where it's shown (`back_end`, `front_end`, `both`)
- `active` — whether it's currently accepting payments
- `auto_capture` — whether to capture immediately or hold as `pending`
- `preferences` — gateway credentials, stored as a YAML-serialized hash in a plain `text` column (NOT encrypted at rest — even values assigned from ENV are persisted in plain text, so treat database dumps and backups as containing live gateway secrets)

```ruby
stripe = PallasTrade::PaymentMethod.create!(
  name: 'Credit Card',
  type: 'PallasTradeStripe::Gateway',
  display_on: 'front_end',
  active: true,
  preferences: { publishable_key: ENV['STRIPE_PUBLISHABLE_KEY'], secret_key: ENV['STRIPE_SECRET_KEY'] }
)
```

Most production stores don't create PaymentMethods in code — they're created via the admin UI after installing the gem (e.g. `pallastrade_stripe`).

## Built-in payment method types

| Class | Source |
|---|---|
| `PallasTrade::PaymentMethod::StoreCredit` | pallastrade_core — pays from `PallasTrade::StoreCredit` balance |
| `PallasTrade::PaymentMethod::Check` | pallastrade_core — back-office "manual" payment |
| `PallasTradeStripe::Gateway` | pallastrade_stripe gem |
| `PallasTradeAdyen::Gateway` | pallastrade_adyen gem |
| `PallasTradePaypalCheckout::Gateway` | pallastrade_paypal_checkout gem |

Custom payment methods subclass `PallasTrade::PaymentMethod`, register via `PallasTrade.payment_methods << MyGateway`, and implement the Payment Session interface (`payment_session_class`, `create_payment_session`, `update_payment_session`, `complete_payment_session`, `parse_webhook_event`) — see docs/developer/how-to/custom-payment-method. Legacy card gateways subclass `PallasTrade::Gateway`, which delegates `authorize`/`purchase`/`capture`/`void`/`credit` to an ActiveMerchant-style provider. Most stores use an existing extension instead of writing custom.

## Payment sessions (5.4+) — the modern flow

Classic PallasTrade payments expected the storefront to collect card data and POST it. That doesn't work for hosted forms (Stripe Checkout) or drop-in widgets (Adyen). The 5.4+ `PallasTrade::PaymentSession` model wraps the customer redirect / return flow.

```
Customer hits checkout
  ↓
Storefront creates a PaymentSession via the Store API
  ↓
API returns provider-specific session data (Stripe Checkout URL, Adyen drop-in payload, etc.)
  ↓
Customer interacts with provider UI
  ↓
Provider redirects back to storefront OR fires a webhook to backend
  ↓
PaymentSession.complete! → Payment created → storefront (or webhook handler) calls cart completion to finish the order
```

The session has events: `payment_session.processing`, `payment_session.completed`, `payment_session.failed`, `payment_session.canceled`, `payment_session.expired`. Sessions carry an optional `expires_at` set by the gateway extension from the provider's own session expiry; expired sessions drop out of the `active`/`not_expired` scopes (and can be transitioned via the `expire` event, firing `payment_session.expired`), so abandoned sessions don't leave dangling payments.

For most stores, you don't interact with PaymentSession directly — the gateway extension (pallastrade_stripe, pallastrade_adyen) handles creation and completion. You just subscribe to the events if you need to react.

For an existing Order, start sessions through `PallasTrade::PaymentSessions::Start` (the Store Order payment-session controller already delegates to it). It validates the authoritative amount and store payment method, reuses a matching `pending`/`processing` session, and creates a new attempt only after the previous attempt is terminal. Provider network I/O runs **outside** the Order lock transaction; a second lock reconciles concurrent provider responses to one active local winner. Stripe receives a stable operation-level idempotency key for both Checkout Session and PaymentIntent creation. Do not replace this with a long database transaction around provider I/O or a cache-only request lock.

### Stripe PaymentIntent mode (5.6, PRD-20260831-payments)

`pallastrade_stripe` supports two session modes behind `external_data`:

| mode | external_id | client_secret | 用途 |
|---|---|---|---|
| Checkout Session（默认） | `cs_…` | `cs_…_secret`（Checkout 跳转） | 托管结账 / 组合支付 / Express Checkout / webhook 异步完成 |
| `payment_intent` | `pi_…`（直存） | `pi_…_secret`（`confirmCardPayment` 消费） | **前端自绘卡字段**（Stripe 经典 Elements 三字段）active confirm |

- 创建：`POST /orders/:id/payment_sessions` 传 `external_data: { mode: 'payment_intent' }`。
- 前端 active 流程：`createPaymentSession(mode: payment_intent)` → `elements.getElement(CardNumberElement)` → `stripe.confirmCardPayment(pi_secret, { payment_method: { card } })` → `PATCH /orders/:order_id/payment_sessions/:id/complete`。
- `complete` 端点（订单域嵌套路由）在会话完成后调用 `carts_complete_service`（Carts::Complete，幂等）——**必须**：webhook `handle_success` 对已完成会话提前返回，若前端 complete 后不驱动订单完成，订单永远停留 pending。
- webhook `payment_intent.*` 按 `external_id` 直查本地 session（未命中再反查 Checkout Session），兜底 webhook 完成路径不变。
- 卡数据经 `stripe.createPaymentMethod` 直传 Stripe（PCI SAQ-A），不经过本服务器。
- ⚠️ Stripe.js v8 已禁止自绘 HTML 卡字段调 `createPaymentMethod({ type: 'card', card: {...} })`——必须用 Elements（CardNumber/CardExpiry/CardCvc）构造 `card: element`。
- ⚠️ 嵌套路由 controller 解析父资源必须用 `params[:order_id]`（`params[:id]` 是子资源 id）。
- 正向 Cart checkout uses the same-origin Storefront `/api/checkout/start` Route Handler for Cart update → idempotent submit → session start, avoiding Server Action RSC refresh. The same Pay click then confirms Stripe and opens `/payment-result/[orderId]?session=...`; no second Pay on an `or_` page is required.

## Payment combinations + splits (数据层, P1)

> P1（2026-08-26）为后续「父子单 / 拆单 / 合并支付」铺数据地基。以下模型已存在但**尚未接入任何业务流程**（拆单/合并支付引擎在 P2/P4+）。

- **`PallasTrade::PaymentCombination`**（表 `pallastrade_payment_combinations`，前缀 `pcom_`）——一次合并支付的载体，与父子结构**解耦**：只管「收了多少钱、覆盖哪些订单」。
  - 字段：`store_id` / `customer_id` / `currency` / `amount` / `status` / `expires_at` / `completed_at` / metadata。
  - 状态机：`pending → processing → succeeded | failed | canceled | expired`；**非法迁移抛 `PallasTrade::PaymentCombination::InvalidTransitionError`（业务错误，非 `StateMachines::InvalidTransition`）**。
  - 成员订单通过 `payment_splits` 关联（非直接 FK）。
- **`PallasTrade::PaymentSplit`**（表 `pallastrade_payment_splits`，前缀 `psplit_`）——每成员订单一条分摊记录：`authorized_amount` / `captured_amount` / `refunded_amount` / `currency`。
  - 唯一索引 `[payment_combination_id, order_id]`（幂等基础）。
  - `credit_allowed = captured_amount - refunded_amount`。
- **既有表新增可空列**：`orders.payment_combination_id`、`payments.payment_combination_id`（合并支付时 payment 挂组合，`order_id` 可空）、`payment_sessions.payment_combination_id`（保持 `session ↔ payment` 1:1）。

设计约束（吸取上次 PaymentGroup 失败教训）：一个组合只允许一个 `PaymentSession` + 一个 `Payment`（挂 primary order），子订单用 `PaymentSplit` 记账，**禁止一个 session 对应多个 payment**。

### 支付聚合派生（P3, 2026-08-27）

> 父订单（有 children）的支付金额/状态由聚合方法派生（只读，不覆写核心 `payment_total`/`payment_state`）：

- `Order#combined_payment_total`：own completed payments + Σ children（递归）。
- `Order#combined_payment_state`：基于 `combined_outstanding_balance`（>0 → `balance_due`；<0 → `credit_owed`；=0 → `paid`；取消且 0 → `void`）。
- `Order#effective_payment_total`：有 `PaymentSplit` 时用 `captured - refunded`（拆单记账分摊），否则 `payment_total`。
- Admin `OrderSerializer` 输出 `payment_total`/`display_payment_total` 走 `combined_payment_total`（单订单时 == 原值）。

### 合并支付服务层（P4, 2026-08-27，能力层默认关闭）

> P4 实现 `PaymentCombination` 服务层闭环，**不暴露端点**（P5 收银台接线）。吸取 PaymentGroup 失败教训：先入账支付、再逐订单完成、部分失败补偿。

- **`PallasTrade::Payments::PaymentCombinations::Create`**：`(store:, customer:, orders:, payment_method:, primary_order:)`。
  - 校验同 store/同用户/同币种；仅未支付（`outstanding_balance > 0`）订单计入；金额**服务端计算** = Σ `amount_due`。
  - 创建组合（`pending → processing`）+ 每成员订单一条 `PaymentSplit`（`payment_id` 为空，支付后回填）+ primary 订单 `PaymentSession`（金额=组合合计，挂组合，`external_data` 含 `payment_combination_id`）。
- **`PallasTrade::Payments::PaymentCombinations::Complete`**：`(combination: nil, payment_session: nil)`。
  - **阶段 1 入账（组合事务）**：组合 `succeeded`；1 个 `Payment` 挂组合（`order_id=nil`、金额=组合合计、`completed`）；splits 按 `amount_due` 比例记 `captured_amount` + 回填 `payment_id`；各订单 `payment_total`/`payment_state` 更新。
  - **阶段 2 完成（事务外）**：逐个经 **`PallasTrade::Payments::CombinationMemberComplete`** 完成成员订单（RISK-01, 2026-09-04）——standard-flow 成员（Carts::Submit 产物，state=pending/paid）走 **`Carts::Complete`**（pay!+finalize!，其 `complete_standard_order!` 已支持 payment_splits captured>0 放行）；legacy 成员走 `checkout_complete_service`（`Checkout::Complete`，COMPATIBILITY）；失败**不回滚已入账支付**，订单标 `balance_due` + 入 `CombinationSettleJob` 重试（资金 >= 订单状态）。
  - **幂等**：组合 `succeeded` / session `completed` / 订单已完成 → 跳过；Webhook + API 双路径安全。
- **`PallasTrade::Payments::CombinationSettleJob`**：补偿队列，重试失败成员订单完成（幂等，耗尽保留 `balance_due` 供人工介入）。
- **`PallasTrade::Payments::CombinationMemberComplete`**（2026-09-04, RISK-01）：组合成员完成 primitive 分流器，`PaymentCombinations::Complete` 阶段 2 与 `CombinationSettleJob` 共用。背景：legacy `Checkout::Complete` 无 `from: pending` 迁移，无法完成 standard-flow pending 成员（否则组合资金已入账但成员永不完成）。见 docs/research/RESEARCH-20260904-txn-p2-0… §10。
- **Webhook 接线**：`HandleWebhook` 与 Stripe `CompleteOrderFromSessionJob`/`CompleteOrder` 在 session 挂组合时走 `PaymentCombinations::Complete`（单订单流程零改动）。
- **Store API（P5）**：`POST /api/v3/store/payment_combinations`（创建：order_ids + payment_method_id → 组合 + session）与 `GET /api/v3/store/payment_combinations/:id`（收银台详情）；`payment_sessions#complete` 对挂组合的 session 走 `PaymentCombinations::Complete`。SDK `paymentCombinations.create/get` + Storefront 收银台（`(checkout)/combined-payment/[id]`）+ 账户订单多选（`OrderCombinedPay`）。
- **配套数据/模型变更**：`payment_splits.payment_id` 改可空（支付前建 split）；`Payment#order` 改 optional（组合支付 `order_id=nil`，`update_order`/`invalidate_old_payments`/`currency` 已有 nil 守卫）；`PaymentCombination#payments` 关联；`OrderUpdater#update_payment_total` 有 `PaymentSplit` 时取 `captured - refunded`；checkout 状态机在订单有已捕获 split 时放行（无需本地 payment）。

## Adding a payment gateway

Stripe, Adyen and PayPal ship preinstalled in pallastrade-starter projects (the backend `create-pallastrade-app` scaffolds) — nothing to install; enable and configure them in the admin under Settings → Payment methods. For any other gateway gem:

```bash
pallastrade eject                           # switch to the dev compose: bind-mounts backend/ so Gemfile changes take effect
pallastrade bundle add pallastrade_other_gateway  # installs into the bundle_cache volume — no image rebuild needed
pallastrade rails g pallastrade_other_gateway:install
pallastrade migrate
pallastrade dev                             # restart so the new gem loads (Ctrl+C the running one first)
```

Then configure credentials via the admin Payment Methods UI (or via ENV-fed initializer for repeatability).

## Refunds + reimbursements

```
Payment (completed)
  ↓
Refund — partial or full credit back to the original payment source
```

Refunds carry a `PallasTrade::RefundReason` (admin-managed: "duplicate charge", "customer return", etc.) and an amount. The Refund's `transaction_id` links to the gateway's refund record.

```ruby
payment = order.payments.completed.first
refund = payment.refunds.create!(
  amount: 25.00,
  reason: PallasTrade::RefundReason.find_by(name: 'Goodwill'),
  refunder: current_user
)
```

`create!` performs the gateway refund automatically (after_create callback) and writes `transaction_id`; it raises if the gateway call fails.

For partial refunds with return authorizations, the chain is:
```
Customer requests return → ReturnAuthorization → CustomerReturn → Reimbursement → Refund / StoreCredit
```

### 父子售后退款（P7, 2026-08-28）

拆单/组合支付后**子订单无本地 payment**（资金在组合 payment 上），售后退款走：

- `OriginalPayment.reimburse` 在 `order.payments.completed` 为空时从 `order.payment_splits` 取关联 payment（组合 payment），退款上限 = `split.captured_amount - refunded_amount`（不超 split 未退部分，不碰兄弟单）。
- `Refund#update_order`：`payment.order` 为 nil（组合）→ 更新该子订单 `PaymentSplit.refunded_amount`；`Refund#order` 从 reimbursement 链推导。
- 普通单订单退款行为零变化（`payment.order` 存在时走原逻辑）。

See the `pallastrade-shipping-fulfillment` skill for the reverse-logistics chain.

## Store credits

`PallasTrade::StoreCredit` is built-in. Tracks balance per user per store per currency. Pays via `PallasTrade::PaymentMethod::StoreCredit`.

```ruby
user.store_credits.create!(
  store: current_store,
  currency: 'USD',
  amount: 50.00,
  category: PallasTrade::StoreCreditCategory.find_by(name: 'Goodwill'),
  created_by: current_admin_user
)
```

Categories are admin-managed via the CRUD pages at `/admin/store_credit_categories` (no admin navigation link — reachable by direct URL only).

**Cart-stage intent (PRD-20260914-checkout-cart-store-credits-canonical).** On a `cart_` canonical cart, store credit is only intent: `PallasTrade::Carts::ApplyStoreCredit` requires a logged-in customer, checks the customer has `available` credits in the cart currency, and stores the amount in `cart.private_metadata['store_credit_amount']` — **no payment, no balance movement** (`pallastrade_carts` has no payments). Redemption happens at `POST /carts/:id/submit` via the authoritative `PallasTrade.checkout_add_store_credit_service` (`Checkout::AddStoreCredit`, amount clamped to `outstanding_balance`, credits consumed by `order_by_priority`), which also runs *after* the amount pipeline so `outstanding_balance` is final; the submit creates the `PaymentMethod::StoreCredit` on demand (the service raises when it is missing). **Activation must be persisted**: `ensure_store_credit_payment_method!` has to `save!` whenever the record *changed* (an existing-but-disabled method keeps `available` empty → the authoritative service raises → a 500), and the caller must convert that raise into a failed submission with no Order. **Store credit and gift cards cannot be combined on one order** — `GiftCards::Apply` enforces `gift_card_using_store_credit_error`, so the cart intents are mutually exclusive up front.

## Gift cards

`PallasTrade::GiftCard` is built-in (5.x). Each gift card has a redemption code and a remaining balance. Customers can apply at checkout; partial redemption is supported.

**Two stages, one authority (PRD-20260914-checkout-cart-gift-cards-canonical).** On a `cart_` canonical shopping cart the gift card is only *intent*: `PallasTrade::Carts::ApplyGiftCard` validates it (`gift_card_not_found` / `gift_card_expired` / `gift_card_already_redeemed`) and stores the code in `cart.private_metadata['gift_card_code']` — **no payment is created and no balance is reserved**, because `pallastrade_carts` has no payments (funds live on `Order`/`Transaction` only). The redemption happens at `POST /carts/:id/submit`: `PallasTrade::Carts::Submit#apply_gift_card!` re-validates and calls the same `order.apply_gift_card` used by legacy carts (→ `gift_card_apply_service` → store-credit payment + `amount_used`), and a card that became unusable fails the submission instead of silently charging full price. **Ordering matters**: the gift card is applied only after the amount pipeline has persisted `order.total` (an earlier placement read a stale `total` of 0 and blew up on the zero-amount store credit), then a second `order.update_with_updater!` refreshes `payment_total`/`amount_due`; a zero-total order skips redemption entirely. Only `order.gift_card` / `gift_card_total` carry money; the cart serializer exposes just `code` + `display_amount_remaining`.

Events fired: `gift_card.redeemed`, `gift_card.partially_redeemed`. See the `pallastrade-events-webhooks` skill.

```ruby
gc = PallasTrade::GiftCard.create!(
  store: current_store,
  amount: 100.00,
  currency: 'USD',
  code: SecureRandom.alphanumeric(16).upcase,  # optional — PallasTrade generates if omitted
  expires_at: 1.year.from_now,                 # optional
  created_by: current_admin_user
)
```

## Common payment problems

### "Payment stuck in `processing`"

The gateway call started but never finished. Either the gateway timed out (network), or the result-handling code crashed before transitioning. Check `payment.log_entries` (each Payment has a paper trail of gateway responses). Manually transition with `payment.failure!` after investigating.

### "Payment completed but order didn't transition"

The Payment is in `completed` but Order is still in `payment` or `confirm`. The order-state-machine should advance automatically; if it doesn't, check `order.payment_state` and run `PallasTrade::OrderUpdater.new(order).update`.

### "Wrong amount captured"

By default, PallasTrade captures the **outstanding balance** at checkout. If you ran an authorize earlier with a different amount (e.g. customer used a gift card after authorization), you need to void + re-authorize OR partial-capture (gateway-dependent).

### "Webhook from Stripe but no PaymentSession found"

The webhook arrived before the storefront's redirect-back, OR the PaymentSession TTL expired. Stripe's webhook is the source of truth — always trust it over the redirect-back. The `pallastrade_stripe` gem handles this; if you're writing custom, idempotency keys are essential.

## Financial Fact Resolution（FIN-P4-1, 2026-09-06；P4 V2 拆包第 1 包）

> **Payment.state ≠ 现金事实**。在写 Financial Journal（FIN-P4-2）之前，任何消费方必须经
> `PallasTrade::FinancialFacts::ResolvePayment / ResolveRefund` 解析为标准只读 `FinancialFact`
> （transient Value Object，不落库）——**禁止在各服务复制裸 `payment.completed?` 判定**（FIN-INV-02）。

- `PallasTrade::FinancialFact`：字段 `fact_type / status / amount / currency / instrument_class /
  commerce_transaction_id / order_id / payment_id / refund_id / payment_session_id /
  payment_combination_id / payment_split_id / provider / provider_payment_reference / provider_refund_reference /
  effective_at / evidence / reason_code`。
  - `status`：`CONFIRMED / AUTHORIZED_ONLY / UNPAID / AMBIGUOUS / NOT_APPLICABLE / UNSUPPORTED`
  - `fact_type`：`CASH_CAPTURED / STORE_CREDIT_APPLIED / OFFLINE_PAYMENT_RECORDED / REFUND_SUCCEEDED /
    ORDER_ALLOCATION / NONE`（`ORDER_ALLOCATION` 于 FIN-P4-4 激活——组合资金归属投影，非 cash）
- `FinancialFacts::InstrumentClassifier`：`PSP_CASH / STORE_CREDIT / OFFLINE / UNKNOWN`（基于 payment_method
  类型与 `provider_class` 鸭子类型；未知绝不默认 PSP_CASH）。
- `FinancialFacts::CaptureEvidencePolicy`：PSP captured 判定唯一入口（本地只读、不发 provider 请求）——
  - auto-capture / manual-capture 成功：`payment.completed?` **且** `PaymentCaptureEvent` 存在 → `:captured`
  - 组合支付（Settlement 直接 `complete!`，**无 capture event**）：`completed` 且 combination `succeeded` → `:captured`
  - manual authorization：`pending` → `:authorized_only`（≠ captured）；`processing` → `:ambiguous`
  - `completed` 无 evidence / 证据冲突 → `:ambiguous`；`failed/void/invalid/checkout` → `:unpaid`
- `FinancialFacts::OwnershipResolver`：Payment/Refund → CommerceTransaction 可靠归属（显式 context →
  `PaymentSession.transaction_id` → `PaymentCombination.commerce_transaction`）。**禁止用 `response_code`/
  `pi_`/`cs_` 等 PSP reference 推断 txn**（`commerce_transaction_id` = txn_ 命名纪律）。
- `FinancialFacts::ResolvePayment / ResolveRefund`：编排 classify → ownership → amount/currency → evidence →
  FinancialFact（**只读、零副作用**、无 provider 网络查询、无 Journal 写入）。支持 1 txn N payment facts、
  short payment、multiple/partial refunds、`AMBIGUOUS` 不猜。
- `FinancialFacts::RetryPaymentSafetyPolicy`：旧 attempt 仍存在可权威确认 provider space（session `external_id` /
  payment `response_code`）时，新 charge 前必须先 provider verification（P2 `PaymentFactResolver` 已具备）。
- Adyen/PayPal legacy：本包无 captured predicate → `UNSUPPORTED/AMBIGUOUS`；provider reconciliation 能力
  （`CaptureEvidencePolicy.provider_reconciliation_capability`）——FIN-P4-5 起 Stripe/Bogus（已实现
  `fetch_financial_details`）为 `PROVIDER_RECONCILIATION_SUPPORTED`，Adyen/PayPal 仍 UNSUPPORTED。

## Immutable Financial Journal（FIN-P4-2, 2026-09-06；P4 V2 拆包第 2 包）

> **Journal = CommerceTransaction 级不可变资金账本**（`pallastrade_financial_ledger_entries`）。
> posting 输入**唯一合法来源是 FIN-P4-1 的 `PallasTrade::FinancialFact`**（CONFIRMED + 激活 entry_type +
> 可解析 txn）——禁止在 posting 路径重新判断 `payment.completed?`（FR-4P1-40 / FIN-INV-02）。

- `PallasTrade::FinancialLedgerEntry`（`fle_`）：`commerce_transaction_id` 必填（P4 §12 命名纪律）+
  可空 source FK（order/payment/refund/payment_combination/payment_split）+ `entry_type` + 带符号 `amount` +
  `currency` + `idempotency_key`(UNIQUE) + `reversal_of_id` + `state`(posted/reversed) + `effective_at`/`recorded_at`。
  - **append-only（FIN-INV-01/07）**：amount/currency/source/entry_type/ownership 创建后禁原地改
    （`ImmutableError`；before_update + update_columns 双层拦截）；唯一原地变化 = reversal 状态流转
    （`mark_reversed!` 写 state/reversed_at 白名单）。
  - entry_type 与 `FinancialFact::FACT_TYPES` 同名单对齐：激活 CASH_CAPTURED / STORE_CREDIT_APPLIED /
    OFFLINE_PAYMENT_RECORDED / REFUND_SUCCEEDED / ORDER_ALLOCATION（FIN-P4-4 激活）；PSP_FEE/PSP_NET_SETTLEMENT
    （FIN-P4-5）仍预留不激活。
  - `Post` 回填 `payment_split`（FIN-P4-4 split-aware posting）——ORDER_ALLOCATION 溯源。
- `FinancialLedger::Post.call(financial_fact:, idempotency_key:)`：幂等 posting 原语——门禁（CONFIRMED +
  激活 type + txn 可解析）→ 查 key → 命中返回既有；insert；`RecordNotUnique` 竞态 rescue 重查返回。
- `FinancialLedger::Reverse.call(entry:)`：append-only 冲销——生成 amount 相反 + `reversal_of` 指向原 entry
  的新 entry（`reversal:<原key>` 幂等 key），原 entry → reversed；已 reversed / 已有 active reversal 拒绝
  （DB partial UNIQUE on reversal_of WHERE state='posted' 兜底）。reversal 本身可再被 reverse（恢复语义）。
- 范围：本包不接 Payment/Refund 事件挂钩（FIN-P4-3）；不填 PSP fee/net（FIN-P4-5）；无 API/UI。

## Payment/Refund Posting（FIN-P4-3, 2026-09-06；P4 V2 拆包第 3 包）

> **业务接线**：payment captured / refund succeeded **自动、恰好一次**进入 Journal。FIN-P4-1
> Fact 解析 + FIN-P4-2 `Post` 原语已冻结，本包只做编排 + 事件订阅（**无 migration/API**）。

- **编排**：`FinancialLedger::PostPayment.call(payment:)` = `ResolvePayment` → 门禁
  （`FinancialLedger::Post.postable?(fact)` = CONFIRMED + 激活 entry_type + 可解析 txn + amount/currency）
  → `Post` → `success({ entry:, fact:, skipped: false })`；不可 post（AMBIGUOUS/UNSUPPORTED/无 txn）→
  `success({ entry: nil, skipped: true, reason: })`（不猜、不部分记录）。`PostRefund.call(refund:)` 同构
  （ResolveRefund → REFUND_SUCCEEDED）。**只读边界**：不创建/更新 Payment/Refund/Transaction，唯一写 =
  LedgerEntry。
- **事件接线（engine.rb subscribers.concat 注册）**：
  - `FinancialLedger::PaymentPaidSubscriber` ← `payment.paid`（`Payment::CustomEvents` after_commit on update
    state→completed 发布——提交后触发，ledger 失败不逆转支付 P4 §16）。
  - `FinancialLedger::RefundSucceededSubscriber` ← `refund.succeeded`（REV-P6-1 起；Refund state 迁移
    succeeded 的 after_commit 发布——Refund 创建=REQUESTED 不再隐含成功，见下文 REV-P6-1 章节）。
  - subscriber 默认 async（SubscriberJob）；posting 幂等（idempotency_key）→ 重试不重复；异常 rescue →
    Rails.logger（不阻断资金流）。payload id 支持 prefixed（py_/re_ → find_by_param）或 raw integer 双模式。
- **覆盖**：single / balance collection（独立 txn → 独立 entry）/ combination（1 Payment → 1 cash entry；
  PaymentSplit **不**产生额外 entry，ORDER_ALLOCATION 归 FIN-P4-4）；multiple partial refunds → N 独立 entries。

## Refund Durable Lifecycle（REV-P6-1, 2026-09-06；PRD-20260906-payments-rev-p6-1-durable-refund-lifecycle-foundation）

> **Refund = Durable Refund Execution Aggregate**（不再是 successful-refund-only row）。语义（REV-INV-01）：
> `Refund Request ≠ Provider Execution ≠ Refund Financial Fact`。源规格：`豆包梳理业务需求/P6 — Refund,
> Cancellation & Dispute Orchestration.md`（REV-P6，编号与内部拆单域 P5/P6/P7 不同）。

- **生命周期**：`requested → processing → succeeded | failed | ambiguous → manual_review`（+ requested→canceled）。
  常量 `Refund::STATES / ACTIVE_STATES(requested,processing,ambiguous) / CAPACITY_STATES(+succeeded) /
  TERMINAL_STATES`。**删除 `after_create :perform!`**（create 即 PSP 副作用反模式）。
- **Refunds::Execute**（`backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/refunds/execute.rb`，v1 同步）：claim（payment 锁内重校验
  capacity、排除自身 → requested→processing + 写 `provider_idempotency_key`(`refund:<prefixed_id>:execute`)）→
  provider I/O（携带稳定 idempotency key）→ 三态持久化：`apply_success!`（succeeded+transaction_id+split/order
  投影+audit，单事务可重放）/ `record_failure!`（failed+last_error）/ `record_ambiguous!`（ambiguous）。
  终态幂等不重复执行；`raise_on_failure: true` 保留 legacy（reimbursement/gateway cancel）raise 语义。
- **Capacity**：`Payment#refundable_capacity`（alias `credit_allowed`）= amount − offsets − Σ SUCCEEDED −
  Σ ACTIVE(requested/processing/ambiguous)；failed/canceled 释放。资金汇总（order_updater/order refunds_total/
  splitter/bogus financial details）只统计 `succeeded`。
- **接线**：Admin `POST /orders/:id/refunds` → durable 落库(requested) → 锁外 `Refunds::Execute`（响应带
  state/last_error）；Stripe/Adyen/PayPal gateway `cancel` 对 completed payment 的自动退款与 reimbursement
  `create_refund` 均改为「save(requested) → Execute(raise_on_failure: true)」。
- **Journal 守卫**：仅 `refund.succeeded` → PostRefund（REFUND_SUCCEEDED）；非 succeeded 不产生 ledger entry。
  `ResolveRefund` 需 `transaction_id.present? && refund.succeeded?` 才 CONFIRMED。
- **历史数据**：backfill transaction_id 存在→succeeded；NULL→manual_review（不猜）；ownership 只填可证明。
- **边界（后续包）**：async Job/Sweeper/ReverseCommerce::Recover=REV-P6-2/6；combination split active
  reservation=REV-P6-3；Cancellation Orchestrator=REV-P6-4；Return inspection=REV-P6-5；reimbursement 链事务
  拆解同属后续包（v1 中其 Execute 仍可能在外层事务内）。

## Refund Execution Orchestration（REV-P6-2, 2026-09-06；PRD-20260906-payments-rev-p6-2-refund-execution-orchestration）

> **执行主路径 async 化**：发起与资金执行彻底解耦（源文档 REV-P6 §12/§16/§57）。

- `Refunds::Request`（唯一发起入口）：capacity 校验 → durable `Refund(requested)` 落库（ownership 可证明冻结）
  → enqueue `Refunds::ExecuteJob`；自身绝不调 PSP。
- `Refunds::ExecuteJob`（Sidekiq，`queue_as PallasTrade.queues.default`）：async 调 `Refunds::Execute`
  （raise_on_failure: false）；claim 幂等（仅 requested→processing）→ 重试不重复退款；顶层 rescue 后不
  re-raise（避免 sidekiq 重试二次 PSP）；ambiguous 不自动重退（REV-P6-6 收敛）。
- **入口 async 化**：Admin `POST /orders/:id/refunds` → 201 + `state=requested`（轮询 GET list 观测终态）；
  Stripe/Adyen/PayPal gateway `cancel`（completed payment）→ `Refunds::Request`（不再链内同步 PSP/不再 raise
  回滚取消链）。
- **边界**：reimbursement/returns 退货链本包保留同步执行（REV-P6-1 `create_refund` 语义），完整 async 编排
  归 REV-P6-5（Return orchestration）；Recover/Sweeper 归 REV-P6-6。

## Partial / Combination Refund Allocation（REV-P6-3, 2026-09-07；PRD-20260907-payments-rev-p6-3-partial-combination-refund-allocation）

> **组合/部分退款 ownership 创建即冻结**（源文档 REV-P6 §58/§26-29）。消灭 Reimbursement 链推导歧义
> （RISK-REV-05）：一旦冻结，`update_order` 只投影冻结的 split/order，不再猜测兄弟单。

- **冻结**：Admin `POST /orders/:id/refunds` 可选 `payment_split_id` / `target_order_id`（prefixed，作用域内
  校验归属：split 必须属于该 payment 且带 order；target 必须 ∈ 组合 orders 或 = payment 自身订单，否则 422
  且不落库）。预检失败立即渲染返回（勿依赖 save 前 errors —— `valid?` 会清空预加错误）。
- **投影**：`Refund#update_order` 组合分支 `split = self.payment_split || target_order.payment_splits…
  （fallback）`——冻结列优先；无冻结 legacy 走 reimbursement_target_order fallback（行为不变）。
  成功只更新目标 split `refunded_amount`，兄弟 split 不动。
- **上限（双门禁，取严格者）**：全局 `payment.credit_allowed`（REV-P6-1）+ 冻结 split 上限
  `amount_within_frozen_split_limit`（`split.credit_allowed = captured − refunded`，创建期校验，超限拒绝且
  不 enqueue）。多笔 partial 顺序扣减，逐笔校验剩余 split 额度。
- **serializer**：admin refund（扁平 JSON）暴露 `payment_split_id` / `target_order_id`（只回显冻结列，
  不做链推导回填）。
- **分摊 authority（审计冻结，REUSE——本次无新 Calculator）**：REFUND_AMOUNT_AUTHORITY =
  `Calculator::Returns::DefaultRefundAmount`（按退货数量加权行金额 + 订单级 non-tax 调整按行占比）；
  REFUND_TAX_ALLOCATION_POLICY = `ReimbursementTaxCalculator`（pre_tax/refunded %）；SHIPPING/PROMOTION 走
  订单级 non-tax 调整按行占比。权威记录见 `pallastrade-pricing` skill。
- **边界**：Admin 对组合 child 订单的取支付路径（route 层 `@parent.payments` 不含组合 payment）与完整
  async 退货链编排归 REV-P6-5/6-8；Recover/Sweeper 归 REV-P6-6。

## Cancellation Orchestration（REV-P6-4, 2026-09-07；PRD-20260907-payments-rev-p6-4-cancellation-orchestration）

> **「是否退款」业务决策从 Gateway/state 副作用上收到 `Orders::Cancel`（=Cancellation Orchestrator）**
> （源文档 REV-P6 §30-38/§59/RV-R06/R07；RISK-REV-04）。REV-P6-2 后 gateway cancel 已 durable 化，
> 但 `Order#after_cancel` 仍无条件 `payments.completed.each(&:cancel!)` → 取消即隐式全退——本包修正。

- **决策矩阵**：`Orders::Cancel` 在 `order.cancel!` **之前**、事务内按取消时点 payment fact 决策：
  UNPAID → 无退款（保留 void/release，INV-P3-4）；PAID → 默认对每笔可退 PSP completed payment 经
  `Refunds::Request(..., enqueue: false)` 建 durable `Refund(requested)`（金额 = `refund_amount ||`
  `credit_allowed`，`refund_amount` 仅限单笔可退 PSP；reason=`RefundReason.order_canceled_reason`），
  事务提交后统一 `ExecuteJob.perform_later`（不事务内入队，避免回滚孤儿入队）。`refund_payments` 三态：
  nil=auto（PAID 默认退）/ true / false（显式不退款，AC-R64-03）。
- **`Order#after_cancel`（FR-R64-102）**：删除 PSP completed `each(&:cancel!)` 隐式退款。保留：
  store credit completed `cancel!`（店内账户 credit-back，非 PSP）、gift-card 覆盖时 store credit `void!`、
  incomplete 非 store credit `void_transaction!`、store credit pending `void!`、shipment cancel（restock
  REUSE）、updater/webhook/event。Order=canceled + PSP Refund=requested/processing 为合法并存态（§35）。
- **幂等**：重复取消 → `cancel!` InvalidTransition → failure，不产生第二笔 Refund；建单失败整体回滚
  （不留半取消）。
- **API**：`PATCH /api/v3/admin/orders/:id/cancel`（+ legacy admin）透传
  reason/note/refund_payments/refund_amount/restock_items/notify_customer；不传 = 旧语义（PAID 默认退）。
  服务内 coalesce：reason blank→'other'、restock_items/notify_customer nil→false。
- **fresh query**：编排与 after_cancel 走 `Payment.where(order_id:)`（避免 association 空 target 缓存——
  `Payment#invalidate_old_payments` 会把空 target 缓存到 order 实例导致 scope 读陈旧空集）。
- **边界**：组合（combination-level）完整取消编排 + OrderCancellation 状态机扩展归 REV-P6-5/6-8 与
  REV-P6-0 DB audit；Stripe UNPAID 失败/过期 webhook `order.cancel!` 行为不变（无 completed → 无退款）。

## Return Restock Decision & Exactly-Once Restock（REV-P6-5, 2026-09-07；PRD-20260907-shipping-rev-p6-5-return-restock）

> **Restock 是退货域的库存事实（与 Refund 分离，源 REV-P6 §39-42）**：Inspection/Acceptance → Restock
> Decision → exactly-once StockMovement(+)。REV-P6-5 收敛退货 restock（不再 receive 即入库）。

- **决策时机**：`ReturnItem` restock 从 `reception→received`（`process_inventory_unit!`）移到
  `acceptance→accepted`（`after_transition to: :accepted → restock_if_needed`）；`process_inventory_unit!` 只保留
  `inventory_unit.return!`。auto-accept（eligible）与手动 `accept!` 都 restock；`rejected`/`manual_intervention_required`
  未决不 restock（修复坏品提前入库）。
- **exactly-once**：`stock_movements.return_item_id`（可空）+ partial unique（not null）为退货 restock 的稳定幂等键
  （originator=RA 一对多不可作键）；重复/重试/并发 → `RecordNotUnique` 幂等跳过。迁移
  `20260908000000_add_return_item_to_pallastrade_stock_movements.rb`。REUSE：仍走 `StockMovement` 唯一写入通道。
- **Restock Fact（REV-P6-6 消费源）**：`Returns::RestockFact.resolve` → RESTOCKED / NOT_REQUIRED /
  NOT_RESTOCKABLE / PENDING / AMBIGUOUS；证据 = ReturnItem（accepted/restock_eligible?）+ StockMovement
  （return_item_id）；只读派生不持久化、存量不猜。
- **边界**：reimbursement 链完整 async 拆链与 ReverseCommerce::Recover（含 Restock 收敛）归 REV-P6-6/6-8；
  Shipment cancel / OrderInventory restock 通道不改。

## Refund Reverse Recovery（REV-P6-6, 2026-09-08；PRD-20260908-payments-rev-p6-6-refund-reverse-recovery）

> **Refund 自动收敛引擎**（源 REV-P6 §45/§46/§61；镜像 Transactions::RecoverSweeperJob 保守哲学）：
> 只处理可安全自动恢复的；ambiguous/manual 仅计数+warn（人工/REV-P6-8 同 idempotency key 裁决）。

- `Refunds::Recover`（with_lock + 状态守卫）：requested stale（>1h）& attempts<5 → 幂等
  `Refunds::Execute` 重跑（稳定 provider_idempotency_key，不重复 PSP）；processing stale（>6h）→
  `record_ambiguous!(RECOVERY_TIMEOUT)`（REV-INV-04 不自动重退）；其余不动。`MAX_AUTO_RETRY_ATTEMPTS=5`。
- `Refunds::RecoverJob`：per-refund；rescue 不 re-raise（避免 sidekiq 重试放大；sweeper 周期重扫）。
- `Refunds::RecoverSweeperJob`（sidekiq-cron */5，host schedule）：保守扫描 requested/processing stale →
  enqueue RecoverJob；attempts 达上限停自动；ambiguous/manual_review/failed 计数 + warn（structured metrics）。
- **边界**：`ReverseCommerce::Recover`（Restock/Journal 跨域）与 reimbursement async 拆链归 REV-P6-7/8。

## Financial Convergence（REV-P6-7, 2026-09-08；PRD-20260908-payments-rev-p6-7-financial-convergence-refund-posting）

> 源 REV-P6 §62。P4（Journal/Post/Resolve/Repair/Reconcile）已闭环不重做；本包=§62 最小缺口。

- **G1 补记闭环**：`ReconcileTransaction#build_reasons` 增 refund 侧 journal-missing 检测
  （succeeded+transaction_id 且无 REFUND_SUCCEEDED entry）→ 并入 `JOURNAL_POSTING_MISSING`
  → ReconcileSweeperJob enqueue RepairTransactionJob 幂等补记（subscriber 丢失/吞异常窗口闭合）。
- **G2 本地状态分类**：`ReconcileRefund` 读 refund.state：failed/canceled → NOT_APPLICABLE+
  NO_PROVIDER_REFUND（消噪音）；ambiguous/manual 无引用 → LOCAL_REFUND_AMBIGUOUS；有引用且
  provider MATCHED → MATCHED+LOCAL_AMBIGUOUS_RESOLVED_BY_PROVIDER。
- **G3 provider mismatch 语义**：Stripe InvalidRequestError/'no such refund' →
  `PROVIDER_REFUND_MISSING`；其余异常 → `PROVIDER_UNAVAILABLE`（对称 payment 侧）。
- 边界：ambiguous 确定性落地（retry_execution）与 provider 孤儿退款配对归 REV-P6-8。

## Refund Admin Ops 可见性（REV-P6-8a, 2026-09-08；PRD-20260908-payments-rev-p6-8a-refund-admin-ops）

> 源 REV-P6 §63（REV-P6-8 Admin/Ops/Legacy Convergence）。**纯只读可见性**（零资金副作用/不改状态机/
> 不新增 API）。Manual Review/Retry 动作 → 8b；legacy reimbursement 同步链 async 拆链 + 孤儿退款配对 +
> retry_execution 接线 → 8c。

- **Refund Ops 数据源**：持久层字段齐备（REV-P6-1/3/4/5/6/7）；缺口只在展示层。
  - `Refund.for_store(store)` scope：单订单退款（`joins(payment: :order)` store_id）∪ 组合退款
    （`joins(payment: :payment_combination)`，PaymentCombination 直连 store；组合 payment.order 为 nil）。
    子查询并集防重复行。退款无 store_id 列，勿假设单一路径。
  - `Refund#journal_entries` = `FinancialLedgerEntry(refund_id)`（REFUND_SUCCEEDED immutable 事实行）；
    reconciliation = `ReconcileRefund.call(refund:)` 返回 **ServiceModule::Result**（须 `success? → .value`
    取 SourceResult；异常降级 nil 不 500）；restock = `Returns::RestockFact.resolve(return_item:)`（只读五态）。
  - ransack 白名单：Refund 显式声明（RansackableAttributes 默认仅 id/name/时间/position）。
- **Rails Admin**（Orders → Refunds 叶子项，url `/admin/refunds`）：`RefundsOpsController`（继承
  ResourceController，object_name 'refund'，model_class Refund —— base scope 自动用 `for_store(current_store)`）
  + `views/.../refunds_ops/{index,show}` + tables 注册 `:refunds`（`link_to_action: :show`，custom 列 partial
  `tables/columns/refund_state|refund_order`）+ nav 注册 + i18n 双语（en + `admin_nav.zh-CN.yml`）。
  **index 零 provider I/O**（对账/restock 只在 show 页在线派生）。`refund_state_badge`/`refund_recovery_hint`
  放 `RefundsOpsHelper` 并在 `Admin::BaseController` 注册 → order 内嵌 `_refunds` 表共用。
- **Legacy #1**：order show `_refunds.html.erb` 状态列由 transaction_id 有无启发式改为真实 `refund.state`
  徽章（REV-P6-1 七态：succeeded/failed/ambiguous/manual_review/requested/processing/canceled）。
- 边界：Manual Review/Retry（dangerous ops 权限/确认）归 REV-P6-8b。

## Refund Manual Review / Retry（REV-P6-8b, 2026-09-08；PRD-20260908-payments-rev-p6-8b-refund-manual-review-retry）

> 源 REV-P6 §63（Manual Retry Query / Manual Review）+ §47 Recovery Matrix + §49（同 key 确定性解决）+
> §10 + REV-INV-04。人工触发的确定性解决工具（危险资金操作：权限 + 强确认 + 审计）。

- **确定性 resolve 原语（关键）**：`Refunds::Execute` claim 对 `processing` 以**同一 provider_idempotency_key**
  重跑（仅 requested 才重新 claim；processing → :claimed 直接 provider I/O）→ Stripe 幂等去重返回真实结果
  （succeeded→ApplySuccess+Journal / failed / ambiguous 如实）。单 refund 单键 = 永不第二笔退款。
- **状态机**：`Refund#retry_execution` 事件扩展 `manual_review → processing`（REV-P6-1 预留；
  原 failed/ambiguous → processing 不变）。manual_review 无自动副作用（§47），仅 operator 触发。
- `Refunds::ManualRetry.call(refund:, actor:)`：with_lock + reload；仅 failed/ambiguous/manual_review 且
  provider_idempotency_key 存在 → `retry_execution!` + attempt_count+1 → **enqueue ExecuteJob**（不同步
  Execute，AP-010）→ Audit('refund_manual_retry')。其余态/缺 key → failure 零副作用。并发双点由
  with_lock + processing 非 eligible 挡。
- `Refunds::MarkManualReview.call(refund:, actor:)`：仅 processing/ambiguous → `enter_manual_review!`
  (code:'OPERATOR_REVIEW') + Audit('refund_mark_review')；其余 failure。
- **Admin**：`RefundsOpsController#retry` / `#mark_review`（POST member；authorize_admin 把两者映射 :update；
  `audit_actor` = current admin user Hash 或 'admin'）；Show 页 `page_actions` 按钮仅 eligible+`can?(:update)`
  显示，危险操作 turbo_confirm；i18n 双语。模板 = `TransactionsController#recover`。
- **gotcha**：`provider_idempotency_key` 有 partial unique → spec fixture 用 `refund:<prefixed_id>:execute`
  派生唯一键，勿用固定字面量；`expect_any_instance_of(Execute)` 不支持 ServiceModule prepend（断言 enqueue）；
  `AuditLog.where(action:, resource_type:, resource_id:)`（无 `resource` 列）。
- 边界：孤儿退款配对 / retry 全自动 / ReverseCommerce::Recover 跨域 → REV-P6-8c。

## Reimbursement 退款链 async 收敛（REV-P6-8c, 2026-09-08；PRD-20260908-payments-rev-p6-8c）

> 源 REV-P6 §16/§46/§48/§57 + REV-P6-2 边界注记。**legacy Reimbursement#perform! 退款链 async 拆链**——
> 消除「事务内同步 Refunds::Execute.call(raise_on_failure:)」（AP-010/REV-INV-03 残留）。

- `ReimbursementType::ReimbursementHelpers#create_refund`（非 simulate）：`save!`（durable requested）→
  `Refunds::ExecuteJob.perform_later(refund.id)`（删同步 Execute；provider 拒绝不再 raise 到 Admin perform，
  refund failed 由 Refund Ops 呈现 + ManualRetry 收敛）。simulate 不变。
- **initiated（covering）记账**（REV-P6-2 根因）：`Reimbursement#refund_coverage_amount` = refunds state ∈
  `Refund::CAPACITY_STATES`（requested/processing/ambiguous/succeeded）合计（failed/canceled 不计）；
  `initiated_amount` = coverage + credits；`uninitiated_amount` = total − initiated。`perform!` 用
  `uninitiated_within_tolerance?` 判 reimbursed（=已发起）否则 errored+raise（容量不足，同旧）。`paid_amount`
  （succeeded）保留供资金事实/核算展示。
- **initiation 幂等**：`create_refunds` 先扣本 reimbursement covering 合计；拆单/组合 split 上限
  `credit_limits[payment_id] = captured − refunded − 该 split covering 合计`（`original_payment.rb#reimburse`）
  ——ExecuteJob 未跑完时重复 perform 不重复建 requested。
- 语义说明：reimbursement.reimbursed = 已发起（durable），资金终态看 refund 行（8a/8b）；refund 后续 failed
  不回退 reimbursement 状态。
- 边界（后续包）：provider 孤儿退款配对 / ReverseCommerce::Recover 跨域 / OrderCancellation 组合取消编排。

## Provider 孤儿退款配对（REV-P6-8d, 2026-09-08；PRD-20260908-payments-rev-p6-8d-provider-orphan-refund-pairing）

> 源 REV-P6 §62 边界 + FIN-P4-5。**只读配对**：provider 有退款引用而本地无行 → ORPHAN（资金流出不可见）。
> 零写/provider mutation、不自动退款（同 reconcile 不变式）。无 UI/API（service + rake + runbook）。

- 数据面：provider = `fetch_financial_details(payment_session:)` 的 `provider_refund_references`
  （Stripe charge refunds re_[]；Bogus 由本地 refunds 派生 `re_bogus_<id>`）；本地 =
  `payment.refunds.where.not(transaction_id: nil)`（transaction_id = provider refund id）。
- `Refunds::OrphanPairing.call(payment:)` → `OrphanPairingResult`（transient VO，freeze）：status
  matched/needs_attention/not_applicable/unsupported/unavailable + reasons + provider ids[] + matched[]
  + orphans[] + local_unmatched[]。能力/锚点镜像 ReconcilePayment：StoreCredit/Check→not_applicable；
  `CaptureEvidencePolicy.implements_financial_details?`→unsupported；session（payment 或组合 fallback）缺→
  unavailable(UNLINKED_LEGACY_PAYMENT)；provider 异常→unavailable(PROVIDER_UNAVAILABLE，捕获不 raise)。
  配对：provider_id ∈ 本地 → matched；provider-only → orphans(ORPHAN_REFUND)；本地缺 provider →
  local_unmatched(LOCAL_REFUND_NOT_ON_PROVIDER)；任一 → needs_attention。
- rake `pallastrade:refunds:orphans[store_id]`（core `lib/tasks/refunds.rake`）：扫单店 completed PSP 支付
  （单订单 ∪ 组合路径）→ TSV + summary；not_applicable/unsupported/matched 不逐行打印（汇总计数）。
  runbook：`docs/operations/refund-orphan-pairing-runbook.md`。
- **gotcha**：Bogus provider refs = `re_bogus_<local_refund_id>`，测试「matched」须把本地 transaction_id 设为该
  派生 id；孤儿/异常用例用 stub `payment.payment_method.fetch_financial_details`（普通实例 stub 可行）。
- 边界：单笔 provider refund 金额与 Admin/API 展示已由 REV-P6-8h 落地（见下节）。

## 孤儿金额 + Payment Ops（REV-P6-8h, 2026-09-09；PRD-20260908-payments-rev-p6-8h-orphan-amounts-payment-ops）

> 8d 边界落地：孤儿（provider-only）退款**只读金额** + Rails Admin Payment Ops 展示。零写/provider mutation，
> 金额不落库。risk critical（网关/金额关键词）→ 走 manual-only recovery plan。

- **金额能力**：`PaymentMethod#provider_refund_amount(provider_reference)`（base → nil；owner 判定同
  `CaptureEvidencePolicy`——覆写才算有能力）；Stripe 实现 = 只读 `retrieve_refund(ref)` →
  `{ amount: major units, currency: }`。Bogus 引用本地派生、无真实孤儿 → 继承 base 自然降级。
- **OrphanPairing 扩展**：orphan 条目 `{ provider_id:, amount:, currency: }`（不可得 nil）；逐条 rescue
  单条失败不中断其他孤儿；能力缺失/任一孤儿无金额 → reasons 追加 `ORPHAN_AMOUNT_UNAVAILABLE`。
  matched/local_unmatched 结构向后兼容（8d specs 仍绿）。
- **rake** `pallastrade:refunds:orphans` TSV +orphan amounts/currencies 列（`|` 对齐）。
- **Rails Admin Payments Ops**（Orders → Payments，只读）：`PaymentsOpsController` index（store completed PSP
  payments 含组合 payment）+ show 在线跑 `OrphanPairing`（异常降级 nil 不 500，8a ReconcileRefund 模式）——
  展示 matched/orphans(含金额)/local_unmatched。table/nav/routes only index+show/i18n；权限由
  `can :manage Payment`（order_management）覆盖。
- runbook `docs/operations/refund-orphan-pairing-runbook.md` 已更新（金额语义/列/页面）。
- 边界：Admin API v3 只读端点 + SDK → 后续。

## ReverseCommerce::Recover 自动调度化（REV-P6-8i, 2026-09-09；PRD-20260908-payments-rev-p6-8i-recover-auto-scheduling）

> 8e 边界落地：restock-AMBIGUOUS 收敛从手动 rake 升级为**周期自动调度**（镜像 Refunds::RecoverSweeperJob
> 保守哲学：只 enqueue 幂等 Recover、rescue 不 re-raise、capped 防风暴）。手动 rake/runbook 保留。

- `ReverseCommerce::RecoverJob`（core jobs）：`perform(order_id)` → `Recover.call(order:)`（幂等自愈）；
  rescue StandardError 仅 log（周期重扫兜底，防 sidekiq 重试放大）。order 缺失 no-op。
- `ReverseCommerce::RecoverSweeperJob`（`perform(store_id: nil, max_enqueues: 20)`）：候选 SQL =
  `ReturnItem.accepted` JOIN inventory_unit→order（store 归属）+ LEFT JOIN `pallastrade_stock_movements`
  （`return_item_id IS NULL`——8e 幂等键）→ 逐条 `restock_eligible?` + `RestockFact.resolve == AMBIGUOUS`
  复核 → order ids 去重 → enqueue RecoverJob；≥ cap 只 enqueue ≤ max_enqueues + warn；metrics log
  （event `reverse_commerce.recover_sweeper`）。
- 注册：`backend/config/sidekiq_schedule.rb`（PALLAS_CART_SCHEDULE）+`reverse_commerce_recover_sweeper`
  （cron `*/5`，args max_enqueues=20）。
- 边界：手动 rake/runbook 保留；ambiguous 之外仍人工/既有 sweeper；refund 域自动调度由
  Refunds::RecoverSweeperJob 覆盖（不重复）。

## OrderCancellation 状态机化 + 取消意图恢复（REV-P6-8j, 2026-09-09；PRD-20260909-payments-rev-p6-8j-ordercancellation-state-machine）

> 源 REV-P6 §34/35：取消意图 durable（OC 行 + durable Refund(requested) 同事务）但 OC 无显式生命周期 →
> 加 `state` 状态机 + **只读**审计 rake 检测「意图 applied 但资金未落地」。**不改资金/取消成功路径行为**
> （失败仍整体回滚不留半取消——REV-P6-4 不变式保持）。

- migration（host `backend/db/migrate/20260909000000_add_state_to_pallastrade_order_cancellations.rb`）：
  `pallastrade_order_cancellations.state` string default 'requested' null:false + index；reversible
  up 把存量行回填 'applied'（历史 OC 均为已应用取消；唯一写入方=Orders::Cancel，单点安全）。
- 状态机（`OrderCancellation::STATES` + state_machine，initial requested）：`apply`(requested→applied)、
  `fail`(requested/applied/recovery_required/manual_review→failed)、`flag_recovery_required`(applied→
  recovery_required)、`flag_manual_review`(applied/recovery_required→manual_review)、`reapply`
  (recovery_required/manual_review/failed→applied，人工裁决后重新标记)；scopes/predicates +
  `needs_attention`(recovery_required|manual_review) + `recovery_attention?`。**无 completed/processing**
  （apply 即 terminal=applied；refund 行终态由 Refund state 各自表达，避免重复聚合）。
- `Orders::Cancel` 接线：捕获 `cancellations.create!(state:'requested')` 返回值 → 事务内 order.cancel!
  成功后 `cancellation.apply!`（同原子；失败/回滚不留行）。
- 审计 rake `pallastrade:orders:cancellations:list_attention[store_id]`（core `lib/tasks/orders_cancellations.rake`，
  只读）：逐 applied OC（refund_payments=true & order canceled）查可退源 durable 退款（本地 PSP
  payments refunds ∪ 组合 splits refunds）→ 无任何行 → `ATTENTION_NO_DURABLE_REFUND`；state ∈
  recovery_required/manual_review 独立列出。TSV+summary（counts 总/attention）。
- 边界：失败路径持久 recovery_required 意图（改资金失败语义）不实施；Admin UI 展示 → 后续与 8g/8a Ops 合并。

## Admin v3 只读端点化（REV-P6-8l, 2026-09-09；PRD-20260909-payments-admin-api-v3-只读端点-payment_combinations-index-show-refunds-sh）

> 8a/8g/8h 边界「Admin API v3 只读端点/SDK → 后续」落地（**SDK**：platform 无 admin SDK 包，仅
> `@pallastrade/sdk` Store——新建 admin TS 客户端属独立工程，边界不实施）。把 Rails Admin 只读数据面
> 暴露为 `/api/v3/admin` JSON：

- `GET /admin/payment_combinations`（index：store 作用域 ransack + pagy meta；轻量字段 status/amount/
  currency/member_count/refunded_total）；`GET /admin/payment_combinations/:id`（扁平 serializer，
  `expand=members,payments,transaction` 内联 split captured/refunded/credit_allowed + 组合 payment +
  CommerceTransaction 摘要）——新 `Admin::PaymentCombinationSerializer`（`PallasTrade.api` 注册）。
- `GET /admin/orders/:oid/refunds/:rid`（refund 详情 show 补齐——8a serializer 字段已在，缺端点）。
- `GET /admin/payments/:id`（顶层——组合 Payment `order_id=nil` 无父订单可嵌套）+ `GET /admin/payments/:id/
  orphan_pairing`（在线 `Refunds::OrphanPairing` 只读：status matched/needs_attention/not_applicable/
  unsupported/unavailable + orphans 金额；**零写/零 provider mutation**，legacy 无 session → unavailable 降级
  不 500）。Payment store 作用域经锚点派生（combo.store_id ∪ order.store_id——Payment 无 store_id 列）。
- admin v3 read 为**扁平风格**（serializer hash 直接，无 type/attributes 嵌套——8a create 同款）；
  scope 需求 `read_orders`（API-key）/ ability read（JWT）。admin.yaml paths curated + schemas 生成 +
  api-reference 副本同步（generated:check）。

## 孤儿退款补记 backfill（REV-P6-8m, 2026-09-09；PRD-20260909-payments-孤儿退款补记-backfill-refunds-backfillproviderrefund-rake-dry-run-）

> RISK-REV-01 收口：8d/8h 孤儿只读配对/金额 → 本地**补记**（provider 已退、本地无 durable 行）。
> **补记 ≠ 发起退款**：记录已发生资金，绝不调 PSP/ExecuteJob（REV-INV-04 精神）。人工 rake 门（dry-run 默认）。

- `Refunds::BackfillProviderRefund.call(payment:, provider_id:, amount:, currency:, actor:)`：守卫（payment/
  amount 不可证明 → skip `orphan_amount_unavailable`）→ 幂等（同 payment+transaction_id 已存在 → noop
  `already_backfilled`）→ `payment.refunds.create!(transaction_id: provider_id, state:'requested', reason:
  RefundReason.orphan_backfill_reason, metadata:{backfilled_orphan:true,…})` → `apply_success!(authorization:
  provider_id)`（幂等 succeeded + update_order 可证明投影 + after_commit refund.succeeded → PostRefund =
  REFUND_SUCCEEDED Journal 自动闭合）→ `Audit.record(action:'refund_orphan_backfill')`。单条 rescue 隔离。
- `RefundReason.orphan_backfill_reason`（`ORPHAN_BACKFILL_REASON = 'Provider Refund Backfill'`，mutable:false，
  find_or_create——镜像 order_canceled_reason）。
- rake `pallastrade:refunds:backfill_orphans[store_id]`（core `lib/tasks/refunds_backfill.rake`）：默认
  **dry-run**（TSV 计划 + summary）；`APPLY=1` 才写。候选面 = 8d completed PSP payments（id 子查询 or，
  避免 joins or 不兼容）；逐 orphan 金额以 8h provider 权威为准。禁止自动调度。
- 边界：孤儿 target_order/payment_split 不可证明 → **不猜**（AC-6029；组合 order nil 仅 fact/journal 落）；
  对外只读查看已由 8l orphan_pairing 端点提供。

## ReverseCommerce::Recover 跨域收敛（REV-P6-8e, 2026-09-08；PRD-20260908-payments-rev-p6-8e-reverse-commerce-recover-cross-domain）

> 源 REV-P6 §45 + §39-42：Order 锚点的跨域收敛入口——restock 事实 AMBIGUOUS（accepted+eligible 但
> StockMovement 缺失）**幂等自愈** + **复用** `Refunds::Recover`（不重复实现）；Journal/Reconcile 修复归 P4
> sweeper（不重复派发）。无自动取消/无猜测/无新增资金副作用。

- `ReturnItem#restock_if_ambiguous!`（**public**，幂等）：仅 accepted? && restock_eligible? && 无
  `StockMovement(return_item_id:)` → 调私有 `restock_if_needed`（**唯一写入通道**，partial unique
  `stock_movements.return_item_id` 幂等）；返回 true=本次已回补 / false=守卫外。不改 acceptance 行为。
- `ReverseCommerce::Recover.call(order:)`（新服务，Order 锚点）→ Result `{order_id, restock:{healed,
  ambiguous,restocked,not_required,not_restockable,pending,errors}, refunds:{attempted,ok,noop,errors},
  errors}`：restock 域逐 return_item `RestockFact.resolve`——AMBIGUOUS→`restock_if_ambiguous!`（healed+1）、
  RESTOCKED/NOT_*/PENDING 计数不动作（PENDING 由上游裁决）；refund 域 `order.payments.refunds` 逐条
  `Refunds::Recover.call(refund:)`（fresh/terminal no-op 幂等）；**单条 rescue 不中断整单**。
- rake `pallastrade:reverse_commerce:{recover[order_id], list_ambiguous[store_id]}`（core
  `lib/tasks/reverse_commerce.rake`）+ runbook `docs/operations/reverse-commerce-recover-runbook.md`。
- 边界：Journal/Reconcile 修复派发（P4 sweeper 已拥有）、取消意图恢复、自动调度 → 后续。（组合级取消编排
  已由 REV-P6-8f 落地，见下节。）

## OrderCancellation 组合级取消编排（REV-P6-8f, 2026-09-08；PRD-20260908-payments-rev-p6-8f-combination-level-cancel-orchestration）

> 源 REV-P6 §27-28/§30-35/§45：succeeded 组合成员取消的**资金语义收敛**——修复 REV-P6-4 后「PAID 组合
> 成员取消零退款」（组合资金在组合 Payment order_id=nil + PaymentSplit 上，成员无本地 PSP payment 行），
> 并提供组合级取消编排入口。不改 CommerceTransaction/PaymentCombination 状态机（PAID 不走 cancel 态）。

- **split-aware 取消退款（Orders::Cancel，FR-R68F-101）**：`combination_member_split(order)`——订单无本地
  可退 PSP payment 且存在 succeeded 组合 split（payment 回填 + credit>0）→ 视为单一可退源；auto 取消建
  `Refunds::Request(payment: 组合 payment, payment_split: split, target_order: order, enqueue:false)`
  （冻结 ownership；split 上限 `amount_within_frozen_split_limit` + 组合 Payment capacity 双门禁）→ 提交后
  ExecuteJob。refund_payments=false/refund_amount 语义沿用单订单。**修复前**:`completed_refundable_payments`
  = `Payment.where(order_id:)` 对成员返回空 → 白取消（库存 restock 但资金滞留）。
- **`Orders::CombinationCancel`（FR-R68F-102，新编排器）**：`(combination:, canceler:, member_ids: nil,
  reason/note/restock_items/refund_payments/notify_customer)` → Result 聚合 `{members:{total,canceled,
  skipped,failed}, canceled[], skipped[{reason}], failed[{error}]}`。前置守卫：非 succeeded → failure（pre-payment
  取消仍是 PaymentCombination#cancel）。逐成员复用 Orders::Cancel（幂等/allow_cancel? 守卫在编排层显式裁决：
  已取消→skip(already_canceled)、不可取消→skip(not_cancellable)）；单成员异常 rescue 不中断整组合；重复调用幂等。
- **Admin API（FR-R68F-103）**：`POST /api/v3/admin/payment_combinations/:id/cancel`（scope `write_orders`；
  member_ids 子集可空；current_store 作用域 + `pcom_` prefixed id；authorize `:cancel`——order_management 权限集
  增 `can :cancel, PaymentCombination, &:succeeded?`）；响应 `{data:{id,type,attributes{status,members,
  canceled[],skipped[],failed[]}}}`（只暴露 prefixed id，无整型 PK）。退款终态经既有 refunds 端点观测。
- **边界**：OrderCancellation 状态机化与取消意图恢复已由 REV-P6-8j 落地；组合级 `payment_combination.*` 取消事件已由 REV-P6-8k 落地（见下节）。（Rails Admin 组合可视化已由 REV-P6-8g 落地，见下节。）

## 组合级取消编排事件（REV-P6-8k, 2026-09-09；PRD-20260908-payments-rev-p6-8f §11）

> 8f 边界「组合级取消事件订阅者暂缺」落地。**命名决策**：PaymentCombination 状态机 cancel 事件
> （pre-payment，pending/processing→canceled）已发布 `payment_combination.canceled`（零消费者）——那是组合
> 自身终态取消；8k 编排事件是 **succeeded 组合成员被取消**（组合仍 succeeded）。语义不同 → 用独立事件名
> `payment_combination.cancel_orchestrated`，状态机 canceled 事件不变（不合并）。

- **事件发布**：`Orders::CombinationCancel#call` 编排结束且 `canceled > 0` →
  `combination.publish_event('payment_combination.cancel_orchestrated', payload)`；payload =
  `{id: pcom_…, status:'succeeded', members:{total,canceled,skipped,failed}, canceled_order_ids[],
  skipped_order_ids[], failed_order_ids[], canceled_by(actor label/'system')}`；canceled==0（全 skip/失败）不发
  （防噪）；幂等重跑仅影响仍可取消成员，每次实际取消发一次。事件发布在编排层事务外（逐成员各自事务）。
- **订阅者**：`PallasTrade::Orders::CombinationCancelSubscriber`（core subscribers，注册于 core engine.rb）：
  `subscribes_to 'payment_combination.cancel_orchestrated'`（默认 async SubscriberJob）→
  `Audit.record(action:'payment_combination_cancel_orchestrated', actor: canceled_by, resource: combination,
  after:{members,canceled_order_ids})` + `OperationalMetrics.count('payment_combination.cancel_orchestrated',
  combination_id:, canceled:, skipped:, failed:)`；payload id 双模（pcom_/raw）；combination 缺失 no-op；
  rescue → log 不 raise（不阻断事件流；审计可重放）。
- **边界**：状态机 `payment_combination.canceled`（pre-payment）事件加消费者/加 payload；webhook 出站（组合
  取消通知）；组合「全部成员取消后自动转 canceled/closed」——均后续。

## Rails Admin 组合可视化（REV-P6-8g, 2026-09-09；PRD-20260908-payments-rev-p6-8g-combination-visibility-rails-admin）

> G6 落地：Admin → Orders → Payment Combinations —— PaymentCombination/split **只读**可视化（复刻
> REV-P6-8a RefundsOps 基建：ResourceController+TableConcern / tables / nav / helper / i18n）。零资金副作用。

- `PaymentCombinationsController`（pallastrade_admin，只读）：`index`（store 作用域列表：状态徽章/金额/成员数/
  已退合计）+ `show` **隐式渲染**（Admin ResourceController 无基类 show——RefundsOps 自实现、Transactions 省略
  show 同法；object_name=payment_combination → `@payment_combination`）。
- show 页卡片：组合头（状态徽章/金额/currency/成员数）+ 逐成员 `PaymentSplit`（captured/refunded/
  credit_allowed + 该 split 退款行：`Refund.where(payment_split_id:)`，8a 真实 state 徽章）+ 组合 Payment
  （order_id=nil，state/credit_allowed/refunds）+ CommerceTransaction（摘要 + `admin_transaction_path` 互链）。
  N+1 靠 ar_lazy_preload；组合退款行直接查（payment_split_id 或 combo payment.refunds）。
- 接线：table `register(:payment_combinations)` + custom 状态列 partial（helper 需在 Admin::BaseController
  `helper 'pallastrade/admin/payment_combinations'` 注册）；nav Orders position 45；routes `only [:index, :show]`
  （无写动作）；i18n en.yml + admin_nav.zh-CN.yml。
- 权限：order_management 增 `can :read, PaymentCombination` / `can :read, PaymentSplit`（OrderManager 可看）。
- 边界：写动作/组合取消退款走 8f Admin API；Admin API v3 组合只读端点与孤儿展示 → 8h 评估。

## Allocation Integrity（FIN-P4-4, 2026-09-06；P4 V2 拆包第 4 包）

> **ORDER_ALLOCATION = 组合资金对成员订单的归属投影（immutable journal fact），不是额外 cash inflow**
> （FIN-INV-05/AC-4013）。`CASH_CAPTURED` = 资金流入；`ORDER_ALLOCATION` = 这笔资金如何归属不同 Order。
> 恒等式（P4 §23/AC-4014）：`Σ active ORDER_ALLOCATION == Σ PaymentSplit.captured_amount`（per combination）。

- `FinancialFacts::ResolveAllocation.call(split:)`：只读 resolver——split → ORDER_ALLOCATION fact
  （order_id/payment_split_id/amount=split.captured_amount/currency + combination.commerce_transaction ownership；
  CONFIRMED）。不可证明（无组合 / 组合无 txn（legacy）/ captured=0）→ AMBIGUOUS + reason_code
  （`split_without_combination`/`combination_without_commerce_transaction`/`split_not_captured`）——不猜。
- `FinancialLedger::PostAllocation.call(split:)`：编排——Resolve → 门禁 → Post。幂等 key **显式稳定**
  `fact:ORDER_ALLOCATION:<txn_id>:<split_id>`（不含 effective_at 时刻 → 事件重放/retry 不重复）。
- `FinancialLedger::PostCombinationAllocations.call(combination:)`：组合批量（逐 split 独立；硬失败 → failure
  供 job 重试——已成功条目幂等跳过）。
- `FinancialLedger::AllocationIntegrity.call(combination:)`：只读恒等式 `{ allocation_total,
  split_captured_total, balanced? }`（active 集合；reversal 语义：原 entry → reversed 排除、冲销 entry active
  计入——未补记则 balanced?=false 如实暴露不一致，补记归 P4-8）。
- **接线**：`FinancialLedger::PaymentCombinationSucceededSubscriber` ← `payment_combination.succeeded`
  （after_transition；Settlement 锁内先写 splits captured 再 succeed!——async job 提交后读最终值）→
  PostCombinationAllocations（engine.rb 注册）。
- 不改 OrderUpdater/PaymentSplit/Settlement/Carts 行为；ORDER_ALLOCATION 不参与任何 cash/gross 聚合
  （按 entry_type 过滤天然隔离，AC-4013）。

## Stripe Provider Financial Facts（FIN-P4-5, 2026-09-06；P4 V2 拆包第 5 包）

> **只读 provider 财务明细**：`fetch_payment_status`（P2/P3）回答「paid 没有」；`fetch_financial_details`
> （本包）回答「财务明细是什么」——PI/Charge/BalanceTransaction/Refund 归一快照，供 FIN-P4-6 Source
> Reconciliation。fee/net 是 **Reconciliation Fact，不进 Journal**（P4 §35；PSP_FEE/PSP_NET_SETTLEMENT RESERVED
> 不变）。

- `PaymentMethod#fetch_financial_details(payment_session:)`：只读契约（base default raise
  NotImplementedError，镜像 fetch_payment_status）。
- `PallasTradeStripe::Gateway#fetch_financial_details`：cs_/pi_ 双模式 → PI → latest_charge（ch_；string id 或
  已展开对象双形态 P4 §33）→ BalanceTransaction（txn_；fee/net）→ Refunds（re_[]；refund_total）。金额
  cents→decimal（元）归一；settlement_status（`settled` 仅当 PI succeeded 且可算 fee/net；未捕获 → 如实
  status、fee/net nil 不猜）。新增 `retrieve_balance_transaction`（gateway 只读）。
- `PallasTrade::Gateway::Bogus#fetch_financial_details`：确定性替身（completed → settled/gross/fee 0/net；
  pending → processing + nil fee；本地 refunds 派生 refund_total）——P4-6 spec 确定性。
- `FinancialFacts::ProviderFinancialDetails`：transient 只读 VO（白名单 from_hash/freeze；gross/refund/fee/net/
  settlement/refs/observed_at/raw_reference；可空不猜）。
- `CaptureEvidencePolicy.provider_reconciliation_capability`：以 `fetch_financial_details` 实现存在性判定
  （method owner ≠ base PaymentMethod）——Stripe/Bogus → SUPPORTED；Adyen/PayPal → UNSUPPORTED；
  StoreCredit/Check → NOT_APPLICABLE。
- 不改 Payment/Refund/session state machine、Journal、PaymentFactResolver/fetch_payment_status 路径；快照 VO
  不落表（P4-6 决定 reconciliation 持久化形态）；无 migration/API。

## Source Reconciliation（FIN-P4-6, 2026-09-06；P4 V2 拆包第 6 包）

> **源级只读核对（第一层）**：local Payment/Refund ↔ PSP 财务明细逐单比对，输出 transient `SourceResult`
> 判定，**零本地写 / 零 provider mutation / 绝不自动 charge/refund**（P4 §44/AC-4023/4024——纯函数可重跑）。
> 落库/聚合/上报（P4-7/8）之前本包只回答「这一单对得上吗」。

- `Reconciliations::SourceResult`：transient 只读 VO。`STATUSES` = `PENDING MATCHED MISMATCH NEEDS_ATTENTION
  NOT_APPLICABLE UNSUPPORTED`（`const_set` 字符串常量）；`ATTRIBUTES` 白名单（source_type/source_id/status/
  reasons[]/local_amount/local_currency/provider_gross_amount/provider_currency/provider_settlement_status/
  provider_payment_reference/provider_charge_reference/provider_error/observed_at）；`to_h/as_json`；构造后 freeze。
  ⚠️ **构造端一律传 `SourceResult::XXX` 字符串常量，勿裸传 symbol**（谓词按 `status == 'MATCHED'` 字符串比较）。
- `Reconciliations::ReconcilePayment.call(payment:)`：`payment.payment_method` 分类——StoreCredit/Check →
  `NOT_APPLICABLE`；无 `fetch_financial_details` 实现（`CaptureEvidencePolicy.implements_financial_details?`，
  method owner）→ `UNSUPPORTED`（PROVIDER_CONTRACT_UNSUPPORTED）；无 `payment_session` 锚点 → `NEEDS_ATTENTION`
  （UNLINKED_LEGACY_PAYMENT，不猜）。local captured 判定**唯一入口** = `CaptureEvidencePolicy`
  （FIN-INV-02，禁裸 payment.completed?）。provider `fetch_financial_details` 异常（GatewayError/StripeError）
  → `NEEDS_ATTENTION`（PROVIDER_UNAVAILABLE，捕获不 raise，可重跑）。比对：币种 → CURRENCY_MISMATCH；
  金额（round 2）→ AMOUNT_MISMATCH；否则 MATCHED。local captured 而 provider 未 settled → `PENDING`
  （SETTLEMENT_PENDING，AC-4020 不误报）；local 未 captured 而 provider settled → `NEEDS_ATTENTION`
  （LOCAL_PAYMENT_MISSING）；两侧一致未结算（authorization-only）→ MATCHED。
- `Reconciliations::ReconcileRefund.call(refund:)`：StoreCredit/Check → NOT_APPLICABLE；无
  `fetch_refund_details` 实现（`self.implements_refund_details?` method owner）→ UNSUPPORTED；本地
  `refund.transaction_id` blank → NEEDS_ATTENTION（UNLINKED_LEGACY_PAYMENT）；provider status ≠ succeeded →
  PENDING（SETTLEMENT_PENDING）；币种/金额比对 → CURRENCY_MISMATCH/REFUND_MISMATCH/MATCHED。
- `PaymentMethod#fetch_refund_details(refund:)`：base 只读契约（default raise），镜像 fetch_refund_details。
- `PallasTradeStripe::Gateway`：`retrieve_refund(refund_id)`（Stripe::Refund.retrieve 只读）+
  `fetch_refund_details(refund:)`（re_ → Refund，amount cents→元 /100，currency/status 归一；transaction_id
  blank → GatewayError）。
- `PallasTrade::Gateway::Bogus#fetch_refund_details`：确定性替身（transaction_id blank → GatewayError；
  否则 amount/currency/succeeded）——spec 确定性。
- 不改任何 state machine / Journal / Payment / Refund / session；SourceResult 不落表（P4-7/8 决定持久化）；
  无 migration/API/UI。

## Transaction Reconciliation（FIN-P4-7, 2026-09-06；P4 V2 拆包第 7 包）

> **交易级只读聚合与核对（第二层）**：对一个 `CommerceTransaction` 聚合 Journal + Allocation + Provider Source
> Reconciliations，输出 `TransactionResult` + `TransactionFinancialSummary`，**零本地写 / 零 provider mutation /
> 零自动资金动作 / 绝无自动 charge/refund/倒退 transaction state**（§44/§46/AC-4023/INV-09/11——纯函数可重跑）。
> 支持 1 Transaction → N successful payments（INV-04/RV-F03）。落库/Admin/Repair（P4-8）之前本包只回答
> 「这单交易财务上对得上吗」。

- `Reconciliations::TransactionResult`：transient 只读 VO。六态 `STATUSES`（const_set 字符串常量）+ 谓词；
  `ATTRIBUTES`（transaction_id/status/reasons[]/summary/source_reconciliations[]/provider_gross_amount/
  provider_currency/provider_fee/provider_net/observed_at）；freeze。⚠️ 构造端一律字符串常量（P4-6 教训）。
- `Reconciliations::TransactionFinancialSummary`：transient 只读 VO（§25）。`CORE_ATTRIBUTES`（commercial_amount/
  cash_captured/store_credit_applied/offline_payment_recorded/refund_total/allocation_total/currency/
  provider_fee/provider_net/reconciliation_status）+ `DERIVED` 方法（gross_value_received = cash+store_credit+
  offline；net_customer_value = gross−refund；unallocated_amount = cash−allocation）；`short_paid?`/`overpaid?`
  （AC-4016 short-paid 合法业务态，非 ledger error）；`to_h/as_json` 含 derived；freeze。⚠️ derived 不进构造参数
  （重建用 `CORE_ATTRIBUTES`），否则 unknown-key。
- `Reconciliations::ReconcileTransaction.call(transaction:)`：只读编排。
  - **local 面权威 = immutable Journal**（FIN-P4-2）：`FinancialLedgerEntry.active.by_transaction(txn)` 按
    entry_type 聚合（CASH_CAPTURED→cash / STORE_CREDIT_APPLIED / OFFLINE_PAYMENT_RECORDED / REFUND_SUCCEEDED→
    refund_total abs / ORDER_ALLOCATION→allocation）。不从 Payment 现算 cash（避免与 immutable ledger 分歧）。
  - **provider 面复用 P4-6**：枚举 txn 可达 payments（`txn.payment_sessions.includes(:payment)` + 组合
    `txn.payment_combination.payments`）与 refunds（payment.refunds），逐个调 `ReconcilePayment`/`ReconcileRefund`
    → 聚合 provider gross/fee/net 与源级状态。P4-6 `SourceResult` 已 additive 增 `provider_fee/provider_net`
    （builder 从已 fetch 的 provider hash 提取，零额外 provider 调用）。
  - **核对矩阵（§38）**：allocation vs captured（有 ORDER_ALLOCATION 或组合）→ ALLOCATION_MISMATCH；refund vs
    captured（refund > cash+store_credit）→ REFUND_MISMATCH；over-collect（cash > commercial）→
    COMMERCIAL_AMOUNT_MISMATCH；short-paid **合法不 alarm**（AC-4016）。
  - **Journal 缺失检测**：captured payments（CaptureEvidencePolicy verdict=captured）无对应 CASH_CAPTURED
    entry → NEEDS_ATTENTION + JOURNAL_POSTING_MISSING（INV-09/12 不猜，repair 归 P4-8）。
  - **状态合成优先级**：NEEDS_ATTENTION（journal missing/源级 attention）> MISMATCH（源级 mismatch/本地
    reasons）> PENDING（settlement pending §43/AC-4020 不误报）> UNSUPPORTED（全源无契约 §41 不误报
    mismatch）> NOT_APPLICABLE（无 PSP / 无财务活动）> MATCHED。
- 不改任何 state machine / Journal / Payment / Refund / Transaction；结果 transient 不落表（P4-8 决定持久化）；
  SourceResult additive 字段向后兼容；无 migration/API/UI。

## Repair / Legacy / Operations（FIN-P4-8, 2026-09-06；P4 V2 拆包第 8 包 / 收官）

> **运维闭环**：Journal 缺记补记（repair）、reconciliation 周期重跑（sweeper）+ 手动重跑（rake）、
> 受控 backfill（三类语义 §50）、legacy 无法证明数据处置（不猜）。**绝不重新 Payment/Refund、绝不改任何
> state machine、绝不自动 charge/refund/倒退 transaction state**（§44/§46/INV-08/09/12）。

- `FinancialLedger::RepairTransaction.call(transaction:)`：Journal 幂等补记原语（§49）。
  - 枚举 txn 可达 payments/refunds/splits；按 journal-missing 检测（复用 P4-7 语义）分区：
    已存在（already_present）vs 缺失（补记）。
  - 修复委托既有幂等编排：captured payments 缺 CASH_CAPTURED → `PostPayment`；succeeded refunds
    （transaction_id present）缺 REFUND_SUCCEEDED → `PostRefund`；settled combination splits
    （combination.succeeded + captured>0）缺 ORDER_ALLOCATION → `PostAllocation`。
  - 不可证明源（无 transaction_id 的 refund 等）不修不猜；输出
    `success({ repaired: [entries], already_present: [{source_type, source_id}], skipped: [...] })`。
  - 幂等（Post idempotency key + already_present 检测）；唯一写 = Journal。
- `Reconciliations::ReconcileSweeperJob`（sidekiq-cron 周期，参考 RecoverSweeperJob **保守自动**）：
  - 扫描 completed/payment_confirmed/finalizing txn → 逐个 `ReconcileTransaction`（只读）→ 统计
    status_counts（结构化 metrics `event=reconciliations.sweeper`）。
  - **自动（安全子集）**：journal-missing → enqueue `FinancialLedger::RepairTransactionJob`（幂等补记）。
  - **绝不自动**：mismatch/needs_attention/pending → 仅计数 + warn（§44/§46 人工裁决）。
- `rake pallastrade:reconciliations:*`（core `lib/tasks/reconciliations.rake`）：
  `list_needs_attention`（实时 reconcile 状态 TSV）／`reconcile[txn_xxx]`（手动只读重跑）／
  `repair[txn_xxx]`（幂等补记）／`backfill[store_id?]`。
- **Backfill 三类**（§50/AC-4025）：PROVABLE（payment/provider ref/evidence/currency 可证明 → 补 journal）／
  PARTIALLY_PROVABLE（缺 provider settlement → 只补本地、reconcile PENDING/UNSUPPORTED 如实）／
  UNPROVABLE（无法证明 → 不写不猜、保留 legacy）。
- 范围外（P4-8 记入 PRD 供后续）：Admin Financial View UI / Financial Timeline / `finance.*` audit 目录全量；
  本包聚焦 core ops 原语 + sweeper metrics 日志 + runbook。
- 运维手册：`docs/operations/financial-reconciliation-runbook.md`。无 migration/schema/API。

## Dispute ingestion（DSP-P7-1, 2026-09-11；PRD-20260911-payments-dsp-p7-1）

> **非商户发起的资金逆转**（chargeback / inquiry / warning / representment）从本切片开始有 durable 事实。
> 边界（P7-0 冻结）：**Refund ≠ Dispute**；不改 CommerceTransaction 状态机；webhook = evidence 不是 authority；
> inventory 不变；journal append-only。本切片**零业务副作用**（只写 dispute 域）。

- **表/模型**：`pallastrade_disputes`（`dsp_` 前缀）+ `PallasTrade::Dispute`：`provider` +
  `provider_dispute_reference` 唯一（事件幂等键）、`kind`（inquiry/warning/chargeback/retrieval）、
  10 态状态机（`opened/needs_response/accepted/submitted/under_review/won/lost/expired/closed/manual_review`，
  **阶段序单向收敛**：允许向前跳级与同阶段纠偏，禁止倒退）、`evidence_due_at` 一等列、
  `attention_reason`（`unlinked_payment` / `non_positive_amount` / `invalid_transition`）。
- **入口**：`Gateway::WEBHOOK_EVENT_ACTIONS` 新增 5 个 `charge.dispute.*` 事件 →
  `parse_webhook_event` **对 dispute 族不要求 payment_session**（支付族行为不变）→ 控制器沿用
  `WebhookEventStore` + `HandleWebhookJob`（P0 的 dedupe/replay/retry 全部复用）→ Job 按事件族
  分流到 `PallasTrade::Disputes::HandleProviderEvent`（支付动作仍走 `Payments::HandleWebhook`）。
- **服务**：`Disputes::HandleProviderEvent` 解析 payload（`Disputes::ProviderPayload`，Stripe 形状 +
  零小数货币归一）→ 用 `payment_intent` 锚定本地 `Payment#response_code` → `Dispute.upsert_from_event!`；
  **无锚点不丢事件**（落行 + `unlinked_payment`）；provider 未知状态保持原状态；非法迁移记
  `invalid_transition` 而不抛错。
- **DI**：`PallasTrade::Dependencies.disputes_handle_provider_event_service`（默认为上述服务）。
- **部署**：新增订阅事件后必须**重新注册 Stripe webhook endpoint**（`CreateGatewayWebhooks` 用该配置下发），
  否则线上不会投递 dispute 事件。
- **后续切片**：P7-2 Fact 解析 / P7-3 Journal+对账（`FACT_TYPES`/`ENTRY_TYPES`/`fact_posting_key` 要扩展）/
  P7-4 Evidence / P7-5 Deadline sweeper / P7-6 Recovery / P7-7 Admin Console。

## Dispute 事实裁决（DSP-P7-2, 2026-09-11；PRD-20260911-payments-dsp-p7-2）

> 把 P7-1 的「单事件直译」升级为**可对账的事实裁决**：provider 只读快照 ↔ 本地状态 → `DisputeFact`
> （事实 + 确认度 + 裁决）。本切片**零写**（不写 order/inventory/payment/journal）。

- **只读契约**：`PaymentMethod#fetch_dispute_details(dispute:)`（base `NotImplementedError`；Stripe 实现
  `Stripe::Dispute.retrieve` → 归一 `{ provider_dispute_reference:, status:, amount:, currency:, reason:,
  network_reason_code:, evidence_due_at:, evidence_submitted_at:, has_evidence:,
  balance_transaction_references:, observed_at: }`；金额主单位、零小数货币不除 100）。
  capability = method owner ≠ base（同 `fetch_refund_details`）；同时作为 P7 线 O1–O5 取证工具。
- **事实 VO**：`Disputes::DisputeFact`（transient）—— `FACT_TYPES`（DISPUTE_OPENED / FUNDS_WITHDRAWN /
  FUNDS_REINSTATED / WON / LOST；P7-3 激活到 Journal 时**同名对齐**）、`STATUSES`（CONFIRMED / AMBIGUOUS /
  UNSUPPORTED / NOT_APPLICABLE）、裁决枚举 + `money_movement?`（仅两类资金事实为真，P7-3 入账输入）。
- **裁决矩阵**（`Disputes::ResolveFact.call(dispute:, fetch:)`）：provider 状态先取快照、回退
  `private_metadata['provider_status']` → `aligned / stale_local / stale_provider / conflict / unknown /
  unsupported / unavailable / not_applicable`；`manual_review` 一律 conflict；stale/conflict 标
  `needs_attention?`（P7-5 告警、P7-6 收敛输入）。
- **降级纪律**：无契约 → UNSUPPORTED + `PROVIDER_CONTRACT_UNSUPPORTED`；provider 故障 → AMBIGUOUS +
  `PROVIDER_UNAVAILABLE`；无 payment 锚点 → AMBIGUOUS + `UNLINKED_PAYMENT`；金额缺失/≤0 → AMBIGUOUS +
  `AMOUNT_UNPROVABLE`（**不产生资金事实**）。
- **funds 时间戳**：迁移新增 `funds_withdrawn_at` / `funds_reinstated_at`；`HandleProviderEvent` 在
  `dispute_funds_withdrawn` / `dispute_funds_reinstated` **首次观测写入**（重放不覆盖，幂等）。
- **后续切片**：P7-3 ✅（2026-09-12，见下节 Journal + 对账）/ P7-5 deadline sweeper / P7-6 收敛动作 / P7-7 Console。

## Dispute 资金入账与对账（DSP-P7-3, 2026-09-12；PRD-20260912-payments-dsp-p7-3-dispute-posting-and-reconcile）

> 把 P7-2 冻结的争议资金事实**激活进不可变 Journal**，并落地只读对账：争议扣款/返还可追溯、恰好一次。
> 范围外：Evidence（P7-4）、死线 sweeper（P7-5）、收敛动作（P7-6）、Console（P7-7）、历史 backfill。

- **词汇激活**：`FinancialFact::FACT_TYPES` 追加争议 5 类（与 `DisputeFact::FACT_TYPES` **同名单**）；
  `FinancialLedgerEntry::ENTRY_TYPES` **只激活 2 类现金事实**（`DISPUTE_FUNDS_WITHDRAWN` /
  `DISPUTE_FUNDS_REINSTATED`）；`DISPUTE_OPENED/WON/LOST` 为**非现金事实，永不激活**（防双记）。
- **方向约定**：扣回 = 流出 = **负数**；返还 = 流入 = **正数**（同一争议胜诉后两条账行净额为 0）。
- **事件作用域事实（关键）**：P7-2 `fact_type_for` 终态优先（won/lost 覆盖 funds 时间戳）——若入账层沿用
  「当前最强事实」，一个已 `won` 的争议的 `funds_reinstated` **将永不入账**（资金缺口）。因此
  `FinancialFacts::ResolveDispute.call(dispute:, fetch:, fact_type:)` 支持**事件提示**：subscriber 按事件名
  传 `DISPUTE_FUNDS_WITHDRAWN` / `DISPUTE_FUNDS_REINSTATED`；不传 hint 时保持 P7-2 语义（供证据/展示读取）。
- **入账编排**：`FinancialLedger::PostDispute.call(dispute:, fact_type:)` = `ResolveDispute` →
  `Post.postable?` 门禁 → `Post`（幂等）。skip reason 封闭枚举：`fact_status_not_confirmed` /
  `entry_type_not_activated` / `commerce_transaction_missing` / `amount_or_currency_missing` /
  `effective_at_missing` / `not_postable`。**只读边界**：唯一写 = `FinancialLedgerEntry`。
  `effective_at` 严格取 funds 时间戳（**无 fallback**：用 `Time.current` 兜底会让幂等键随重试漂移）。
- **幂等键修复**：`financial_ledger_entries` 新增 `dispute_id`；`fact_posting_key` 的 source 优先级变为
  **dispute > refund > payment > combination > split > order > txn** —— 一个 payment 可携带 **1:N 争议**
  （部分金额），旧优先级会让同秒同额的第二笔被**静默去重丢账**；非争议事实 key 逐字节不变。
- **接线**：`Dispute` 在 `funds_*_at` **由空变非空**时 after_commit 发布 `dispute.funds_withdrawn` /
  `dispute.funds_reinstated` → `FinancialLedger::DisputeFundsSubscriber`（async）→ `PostDispute`；
  异常 rescue 记录、不阻断争议落库（不在业务事务内写账本）。
- **只读对账**：`Reconciliations::ReconcileDispute.call(dispute:)` → 分类 `aligned` / `journal_missing` /
  `amount_mismatch` / `orphan_entry` / `not_applicable` + `reasons[]` + `expected_entries[]` + `entries[]`。
  **期望账行 = funds 时间戳集合**（不是「当前最强事实」，否则已 `won` 的争议会被误判缺账）；零写、
  零 provider I/O（`capability: JOURNAL_LOCAL_ONLY`），为 P7-5 补记/告警提供输入。

## Dispute 证据快照（DSP-P7-4, 2026-09-12；PRD-20260912-payments-dsp-p7-4-dispute-evidence-snapshot）

> 把既有事实投影为一张**可审阅的证据卡**（源计划 §41），供运营在截止前决定是否应诉；
> 为 P7-5 告警 / P7-6 收敛 / P7-7 展现提供输入。**不落库、不提交、默认不触网**。

- **入口**：`Disputes::EvidenceSnapshot`（transient 不可变 VO：`sections` / `missing_evidence` / `submission_ready` /
  `fact_type` / `fact_status` / `resolution`）+ `Disputes::BuildEvidenceSnapshot.call(dispute:, fetch: false)`（只读投影）。
- **分段与结构**：`order / transaction / payment / refunds / fulfillment / customer_communication / policy / provider /
  journal / reconciliation`，每段 `{ availability: available|not_available, reason: <封闭枚举>, data: {} }`。
- **禁推导铁律（源计划 §42）**：`delivered_at` / `proof_of_delivery` 恒 `not_available`（`not_recorded`）；客户沟通恒
  `not_available`；policy 恒 `not_recorded`（仅附 `store_url` 参考）。**绝不**由 `shipped_at` 推成「已送达」。
- **零触网**：默认 `fetch: false` → provider 段 `not_requested`；仅 `fetch: true` 且 capability 为真才调用只读契约，
  故障 → `provider_unavailable` 且不阻断其他段。capability 用**类级**判定（`class.instance_method(...).owner != PaymentMethod`）
  ——实例级会被测试打桩干扰（stub 会把方法装到 singleton 上，造成「假装有契约」）。
- **缺失清单**：`missing_evidence[]` 封闭枚举 —— `PROOF_OF_DELIVERY_NOT_AVAILABLE` / `CUSTOMER_COMMUNICATION_NOT_RECORDED` /
  `TRACKING_MISSING` / `SHIPPED_AT_MISSING` / `PROVIDER_SNAPSHOT_UNSUPPORTED` / `PROVIDER_SNAPSHOT_UNAVAILABLE` /
  `ORDER_MISSING` / `PAYMENT_ANCHOR_MISSING` / `JOURNAL_MISSING` / `REFUND_OVERLAP_PRESENT`。
- **不提交**：`submission_ready` 恒 `false`（源计划 §43/§67：Submit Evidence 属危险操作，归 P7-8，且需 permission + confirmation + audit）。
- **PII**：VO 内携带必要业务字段，但**日志/错误不写 PII**（仅 ids / 段名 / reason）。
- **后续切片**：P7-5 deadline sweeper（消费 `missing_evidence` 与 `evidence_due_at`）/ P7-6 收敛动作 / P7-7 Console 展示 / P7-8 多 provider + 提交。

## Dispute 证据期限扫描与告警（DSP-P7-5, 2026-09-12；PRD-20260912-payments-dsp-p7-5-dispute-deadline-sweep）

> 盯住 `evidence_due_at`：临近/逾期时提醒运营，**只提示、不替商户决策**（源计划 §44/§45）。

- **只读扫描**：`Disputes::ScanDeadlines.call(window_hours: 72, now:, limit: 500)` → `{ due_soon: [], overdue: [],
  window_hours:, scanned_at:, scanned_count: }`；只收「**未终态**（`Dispute.active`）+ **有** `evidence_due_at`」的争议，
  排序 `evidence_due_at` 升序 + `limit` 截断（命中既有复合索引）。**边界**：`due_at == now` 归 `due_soon`（`hours_remaining = 0.0`）。
- **可行动的告警**：每项携带 `hours_remaining` + P7-4 的 `missing_evidence[]`（缺送达证明/缺单号…）；
  证据投影失败 → `evidence_unavailable: true` + 空清单（**不假装「无缺口」**），且不阻断扫描。
- **Job**：`Disputes::DeadlineSweeperJob`（`queue_as PallasTrade.queues.default`）逐条发布
  `dispute.evidence_due_soon` / `dispute.evidence_overdue` + 结构化 JSON 日志；返回
  `{ published:, failed:, overdue:, due_soon:, window_hours:, scanned_at: }`；**单条异常隔离**（rescue + 日志，继续其余）。
- **零业务动作（铁律）**：不提交证据、不接受/关闭争议、不退款、不改任何 dispute/payment/order 状态、不调用 provider —— 用例以负向断言钉死。
- **调度**：宿主层 `backend/config/sidekiq_schedule.rb` 的 `dispute_deadline_sweep`（`0 1 * * *`，`window_hours=72`），
  由既有 `config/initializers/pallastrade_sidekiq_cron.rb` 注册 —— **每日一次**（而非每小时）以避免告警噪音。
- **后续切片**：P7-6 ✅（2026-09-12，见下节收敛动作）/ P7-7 Console 展示 / P7-8 多 provider + 证据提交（提交属危险操作，需 permission + confirmation + audit）。

## Dispute 收敛动作 Recovery（DSP-P7-6, 2026-09-12；PRD-20260912-payments-dsp-p7-6-dispute-recovery）

> 源计划 §47–§53：以 **Facts** 为输入（本地 Dispute + provider 当前只读快照 + FinancialFact + Journal + Reconciliation）
> 把「provider 真相」收敛回本地，**只修事实、不做资金决策**（§49/§50 铁律）。

- **单条收敛**：`Disputes::Recover.call(dispute:, fetch: true, apply: true)` → 决策封闭枚举 `DECISIONS`
  （`noop` / `lifecycle_repaired` / `journal_repaired` / `lifecycle_and_journal_repaired` /
  `manual_review_flagged` / `manual_review_pending` / `unavailable` / `unsupported`）+ `actions[]`
  （状态 `planned|applied|skipped|blocked`）+ `fact`/`reconciliation` 摘要 + `state_before/after`；
  `apply: false` = dry-run（返回**计划**、数据库零变化）。
- **生命周期收敛（唯一允许的状态写）**：仅 `stale_local`（provider 终局权威 + 单调前进）或 `manual_review → provider 终态`；
  `conflict` / `stale_provider` / 降级（`unsupported` / `unavailable`）一律**零写** —— webhook 的
  `private_metadata['provider_status']` **不是权威**（必须 `fact.source == 'provider_fetch'`；P7-0 §20）。
- **账行补记（唯一允许的账本写）**：`journal_missing` → 按 funds 时间戳逐条
  `PostDispute.call(dispute:, fact_type:, dispute_fact:)`（幂等键恰好一次）；`orphan_entry` / `amount_mismatch`
  **不改写既有账行**（append-only）→ 交人工。
- **人工通道**（`attention_reason` 自 P7-1 落地后**首次有 writer**）：`provider_conflict`（终局冲突）/ `journal_gap`
  （对账缺口不可自动补）/ `funds_evidence_missing`（provider 终局已示资金移动而本地无 funds 时间戳 → **不猜**）。
  标记 = `attention_reason`（**只补不覆盖**）+ `state = manual_review`；已在人工态且已有 attention →
  `manual_review_pending`（幂等，不重复标）。
- **审计**：有动作时 `private_metadata['recovery'] = { at, decision, actions, from, to }`（仅最近一次，非累积）。
- **批量**：`Disputes::ScanRecoveryCandidates.call(now:, limit: 50, verify_after_hours: 24)`（**零 provider I/O**）
  三类 selection —— `attention` / `journal_gap`（纯 SQL 反连接）/ `stale_active`，优先级去重后排序截断；
  `Disputes::RecoverSweeperJob` 每日 01:30（`journal_gap` 候选走 `fetch: false` 纯本地路径，其余 fetch 只读快照）。
- **出站事件**：`dispute.recovery_repaired` / `dispute.recovery_manual_review`（仅非 noop 且非降级）。
- **铁律（负向断言钉死）**：不重扣款、不自动退款、不建 Payment/Refund、不改 order/inventory/txn、
  不改写既有账行、不调任何 provider 写方法。
- **P7-3 服务扩展（加法式，默认行为逐字节不变）**：`FinancialFacts::ResolveDispute` / `FinancialLedger::PostDispute` /
  `Reconciliations::ReconcileDispute` 新增可选 `dispute_fact:` —— 复用**同一份**权威快照，避免重复 provider 只读
  调用，且不依赖本地元数据（否则缺元数据时会把可证事实降为 AMBIGUOUS → 漏补账）。
- **后续切片**：P7-7 ✅（2026-09-13，见下节 Admin Console）/ P7-8 多 provider + 证据提交（提交属危险操作，需 permission + confirmation + audit）。

## Dispute Admin Console（DSP-P7-7, 2026-09-13；PRD-20260913-payments-dsp-p7-7-admin-disputes-console）

> 源计划 §66/§67：把 P7-1…P7-6 已落地的能力**只读汇总**到后台一页（列表 + 七张详情卡），
> 让运营看清「有哪些争议、卡在哪、下一步该干什么」；**不新增任何资金动作**
> （Accept Dispute / Submit Evidence 是 P7-8 的危险操作，本切片连路由和按钮都不存在）。

- **列表**：`/admin/disputes`（`PallasTrade::Admin::DisputesOpsController#index`），列由注册表
  `PallasTrade.admin.tables.register(:disputes)` 驱动（7 列；`state` 用 `partial:` 自定义徽章）；
  Ransack 白名单在**模型层** `Dispute.whitelisted_ransackable_attributes`（state/kind/provider/outcome/
  attention_reason/amount/currency/三类时间戳…），列表恒经 `for_store` 作用域 → 跨店不可见。
- **详情（§66 七张卡）**：状态与金额 / Evidence 快照（P7-4）/ provider 对账（P7-3）/ 账本行（P7-3）/
  退款重叠 / 收敛记录（P7-6）/ 最近 provider 事件（P7-1）——**全部是只读投影**：每个投影各包一层
  rescue，异常降级为 `nil` 并渲染 "unavailable" 卡片，页面**绝不 500**。
- **动作（仅 5 个，全部叠在既有服务之上）**：`refresh`（provider 只读刷新，数据库零写）/ `dry_run`
  （`Recover.apply: false` 计划预览）/ `recover`（`Recover.apply: true`，唯一可写动作，仍然只修事实、不碰资金）/
  `snapshot`（重建 P7-4 证据快照，不落库、不提交）/ `mark_review`（`Disputes::MarkManualReview` →
  `attention_reason = operator_review` + `state = manual_review` + `Audit.record('dispute_mark_review')`）。
- **`operator_review` 写入纪律**：`attention_reason` 与 P7-1/P7-6 一致地**只补不覆盖**；已是人工态且已有
  reason 时返回 `already_marked`（幂等，不重复写、不重复审计）。
- **权限边界**：读 = `can?(:read, PallasTrade::Dispute)`（order_display / order_management 两侧均补）；
  写 = `:update`（仅 order_management 的 `modify` 覆盖）；权限注册表登记
  `reg.register(:disputes, model_class: PallasTrade::Dispute, actions: %w[read update], data_fields: %w[store_id])`。
- **导航/文案**：侧边栏 Orders 下 `disputes_ops`（bilingual key `admin.orders.disputes_ops`，双语硬门
  `nav_validate`）；按钮文案与确认框走 `PallasTrade.t`，不硬编码英文。
- **负向断言（钉死边界）**：无 Accept / Submit Evidence 路由或按钮；动作不创建 Payment/Refund、不改订单/库存/
  CommerceTransaction、不改写既有账行（append-only）；`dry_run` 与 `refresh` 数据库零写。
- **后续切片**：P7-8 ✅（2026-09-13，见下节危险操作与证据提交）。

## Dispute 危险操作与证据提交（DSP-P7-8, 2026-09-13；PRD-20260913-payments-dsp-p7-8）

> 源计划 §67/§68：`Submit Evidence` / `Accept Dispute` 是**危险操作**，若实现**必须** `permission + confirmation + audit`。
> 本片在**现有 provider（Stripe，dev 已具备 test 密钥）**上落地写路径；Adyen/PayPal 适配与合同**延后**至凭证齐备。

- **provider 写契约（capability-gated，零 I/O）**：`PaymentMethod#submit_dispute_evidence(dispute:, evidence:)` 与
  `#accept_dispute(dispute:, reason:)` —— 基类 `raise NotImplementedError`；能力探测 = **类级 method owner ≠ 基类**
  （同 `fetch_dispute_details` 范式）+ `#dispute_evidence_catalog` 非空。`Bogus`/Check/StoreCredit 自然降级（零崩溃）。
- **证据目录（provider-specific evidence types，源计划 §68）**：目录**来自适配器**（核心不内置任何 provider 字段名）：
  Stripe = 16 个文本键（`customer_name` / `customer_email_address` / `product_description` / `uncategorized_text` …）
  + 8 个文件键（`shipping_documentation` / `receipt` / `customer_communication` …）。校验：未知键拒、文本 ≤20k、
  文件 ≤4.5MB 且内容类型白名单（png/jpeg/gif/pdf）、空载荷拒。
- **编排**：`Disputes::SubmitEvidence`（校验 → provider 写 → **不可变回执** → 审计 → 事件）与 `Disputes::AcceptDispute`
  （不可逆；必填 reason；**不改本地 `Dispute#state`** —— 状态仍由 webhook/收敛推进）。
- **不可变回执表** `pallastrade_dispute_evidence_submissions`（append-only，模型层 `before_update`/`update_columns`/`before_destroy`
  拒绝修改）：`kind`（`evidence_submitted` / `accepted`）、`payload_digest`、`provider_reference`/`provider_status`、
  actor 三列、`late`、`accepted_reason`、`response_metadata`（jsonb）、文件附件（审计留存）。**无金额列**。
- **幂等**：`(dispute_id, kind, payload_digest)` 唯一 —— 同载荷重复提交**不再次调用 provider**，返回既有回执（`idempotent: true`）。
- **失败不落回执**：provider 抛错 → `failure('provider_error:…')` + 仅写审计（`dispute_evidence_submit_failed` / `dispute_accept_failed`），
  杜绝“半成品回执”污染幂等基准。
- **逾期策略**：`evidence_due_at` 之后提交需 `accept_late: true`（控制台勾选 + 二次确认），回执 `late: true` 留痕。
- **事件**：`dispute.evidence_submitted` / `dispute.accepted`（**回执落库后**发布；`publish_event` 在调用点派发）。
- **控制台**：`/admin/disputes/:id` 新增「危险操作」卡（证据表单 + 文件字段 + 接受争议表单）；
  可见性 `can?(:update, Dispute)`；危险动作**双重确认**（视图 `turbo_confirm` + 接受争议另需后端 `confirm=1`）；
  网关不支持时整卡降级为提示文案（不渲染表单）。
- **铁律（负向断言钉死）**：不建/改 Payment、Refund、`FinancialLedgerEntry`、Order、Inventory、CommerceTransaction；
  不自动退款、不重扣款 —— 资金结果仍由 **webhook** 驱动 P7-3 入账与 P7-6 收敛。
- **后续切片**：Adyen / PayPal 适配 + 合同（前置：sandbox 凭证，**用户已确认挂起**）；`advanced dispute capabilities` —— 边界已定，见下节 DSP-P7-10。

## 争议本地运营增强 B1（DSP-P7-10, 2026-09-13；PRD-20260913-payments-…-边界-c）

> 源计划 §68 边界 C 第 1 批（决策 **D1=B/C、D2=C、D3=否**：不修订 §71、**不做任何自动化**）。
> 三件套全部**零资金副作用**，且**不**新增提交入口 —— `Disputes::SubmitEvidence` 仍是唯一提交口。

- **证据素材库**（`PallasTrade::DisputeEvidenceAsset`，表 `pallastrade_dispute_evidence_assets`，前缀 `dea_`）：
  store 作用域（`store_id` 可空=全局）、`kind` ∈ text/file、可按 `evidence_key` / `reason_code` 归类、`active` 软停用；
  文件素材走 `has_one_attached :file`（挂素材自身，不回挂 Dispute）。
- **`Disputes::EvidenceAssets`**（门面，对齐 `EvidenceCatalog` 纯函数风格）：
  `list` / `create` / `retire`（此二者写素材表 + 审计 `dispute_evidence_asset_created|retired`）/ `insert`（**返回纯值** `{key,value}`，
  不触网、不建回执）/ `suggest`（按 provider 目录**仅建议**：无契约 → `supported:false` + 空建议，**不编造**）。
  坑：未附加的 file 素材 `insert` → `asset_value_missing`（`has_one_attached` 未附加时是代理对象，必须显式判 `attached?`）。
- **`Disputes::PreSubmitCheck`**（FR-003，**零写**：不建回执 / 不写审计 / 不发事件 / 不触网，可反复调用）：
  复用 `EvidenceCatalog#validate` 后补编排层判定 → `blocking[]`（`evidence_submission_unsupported` / `evidence_empty` /
  `unknown_evidence_key:*` / `evidence_too_long:*` / `evidence_missing_required:*` / `late_submission_requires_confirmation` /
  `dispute_terminal` …）、`warnings[]`、`missing_required[]`、`fix_hints{}`、`digest`（与提交幂等基准同算法）。
- **`Disputes::SubmissionTimeline`**（FR-004，只读）：按时间递增计 `version`（**按 kind 独立**），每条给出
  `diff{added,removed,kept,first}`、`provider_status` / `provider_reference`（如实呈现，缺失即 null）、`files_count`、`actor`；
  返回 `{entries（最新在前）, count, latest（最新一条）, versions, kinds}`；**不改写回执**（仍 append-only）。
- **边界（B2/B3 未做）**：审批/双人复核（FR-005）、运营报表（FR-006）、通知升级（FR-007）、RMA 入口（FR-008）、
  Stripe 回执状态机（FR-009）。
- **控制台接线（B1.5，2026-09-13）**：`/admin/disputes/:id` 新增两张只读卡 —— **提交历史**（版本 / provider 回执 / 证据键 diff / actor）
  与 **素材库·建议卡**（本店素材 + 按 provider 目录的建议；无契约则明示“不编造建议”）；
  危险操作表单新增 **Check draft** 按钮（`formaction` → `POST :precheck`，复用同一张表单的字段，零字段重复）。
  `precheck` 动作**零写**：只把阻断项/警告经 flash 回显（`disputes_precheck_blocked|ok|warnings`），不建回执、不写审计、不调 provider。

### 争议运营报表（DSP-P7-10 B2 / FR-006，2026-09-13）

> 只读、零写、不触网；**口径写死**以免同指标两种算法。落点：`/admin/disputes` 列表页顶部卡。

- `Disputes::OpsReport.call(store:, from:, to:, provider:, window_days:)` → 纯 Hash（默认窗口 90 天；`window_days: :all` 不限）：
  `totals`（disputes/active/terminal/needs_attention）/ `states` / `outcomes`（won/lost/decided/**win_rate**）/ `by_reason`（按 `reason`
  回退 `network_reason_code`，空则 `unknown`）/ `deadlines`（with_deadline/met/submitted_late/not_submitted/**met_rate**）/
  `handling`（仅 `resolved_at` 非空的：平均/中位/最快/最慢天数）/ `money` / `degraded`。
- **口径**：`win_rate = won/(won+lost)`（分母 0 → **nil，不用 0 伪装**）；`met_rate` = 截止前已提交 / 有截止时间者；
  处理时长 = `resolved_at - created_at`。状态词汇直接取 `Dispute::TERMINAL_STATES`（不在报表里另立口径）。
- **降级（不猜）**：币种多于一种 → `money.mixed_currency = true` 且金额全部置 nil（**不求和**）；
  入参异常 → 返回字段齐全的**降级信封** + `degraded: ['report_unavailable:<Err>']`；store 缺失 → `degraded: ['store_missing']`。
- **接线**：`index` 取 `@ops_report`（`safe_value` 包裹，失败→nil→卡片不渲染，列表页恒 200）；i18n 键 `disputes_report_*`。
- 报表**尚未包含**：按 provider/网络细分、导出 CSV、时间序列趋势、按运营人员维度（下一片评估）。

### 证据草稿双人复核（DSP-P7-10 B2 / FR-005，2026-09-13）

> **加强**而非替换：`Disputes::SubmitEvidence` 仍是唯一提交口（三件套不变）；签核只是它的**可选前置条件**。
> 开关：`PallasTrade::Config[:dispute_evidence_requires_second_review]`（**默认关闭 → 既有路径行为不变**）。

- 表 `pallastrade_dispute_evidence_approvals`（前缀 `dap_`）+ 模型 `DisputeEvidenceApproval`：**append-only**
  （`before_update` + `update_columns` 双拦，`ImmutableError`），无金额列。绑定的键是**载荷摘要**（与提交幂等基准同算法）
  —— 草稿改一个字，原签核自动失效（无需撤销机制）。
- `Disputes::ApproveEvidenceDraft.call(dispute:, actor:, evidence:|payload_digest:, decision:, note:, requested_by:)`：
  – 拒绝码：`dispute_terminal` / `invalid_decision` / `evidence_submission_unsupported` / `payload_digest_missing`（空草稿不签）/ `approval_requires_different_operator`（`requested_by` == 签发人）；
  – 幂等：同 `(dispute, digest, decision, actor)` 重复签核 → 返回既有记录（`idempotent: true`）；
  – 审计：`dispute_evidence_draft_approved|rejected`；**零 provider I/O、不建回执**。
- `SubmitEvidence` 新增 `require_approval:`（**默认 false**）：为 true 时缺签核 → `evidence_review_required`；
  签发人与提交人相同 → `approval_requires_different_operator`；通过后 `approval_id` 写进回执 `response_metadata` 与审计。
  幂等短路在签核校验**之前**（已提交过的同一幂等键不因复核开关而变失败）。
- 控制台：危险区新增 **Approve draft (second operator)** 按钮（`formaction` → `POST :approve_draft`，复用同一张表单 →
  签的正是即将提交的那份载荷）；展示签核列表（decision/actor/时间/requester/note）；开关开启时提示需要复核。

### 期限提醒与升级（DSP-P7-10 B2 / FR-007，2026-09-13）

> 扫描器保持**只读**，"通知/升级"放到**订阅者**（职责分离）：`ScanDeadlines` → `DeadlineSweeperJob`
> 逐条发 `dispute.evidence_due_soon` / `dispute.evidence_overdue` → `Disputes::DeadlineAlertSubscriber`（本次新增）。

- `due_soon`：**只留痕** —— 审计 `dispute_deadline_alerted` + 指标 `dispute.deadline_alert`；**不改状态、不打标记**。
- `overdue` ：**升级**为人工关注 —— 在 `attention_reason` 为空时写入 `evidence_overdue`（新增到 `Dispute::ATTENTION_REASONS`）；
  已有更具体原因（`provider_conflict` / `journal_gap` / …）**不覆盖**。该标记会出现在控制台与运营报表的 `needs_attention` 指标里。
- **零自动化**：绝不自动提交证据 / 自动接受争议 / 自动退款 / 改库存订单（§71 禁区）；终态争议、找不到的争议 → no-op；
  异常 rescue 记日志（不阻断 sweeper 或争议落库）；payload id 双模（`dsp_` / raw integer）。
- 注册：`PallasTrade.subscribers.concat [ …, Disputes::DeadlineAlertSubscriber ]`（engine.rb）——
  **忘注册 = 事件静默丢失**，故 spec 包含 `expect(PallasTrade.subscribers).to include(described_class)` 断言。

### 回执单向状态机（DSP-P7-10 B3 / FR-009，2026-09-13）

> **派生而非落表**：回执 `DisputeEvidenceSubmission` 是 append-only 不可变的，不允许改写 `provider_status`；
> 推进信号本来就存在 —— provider 回写推进 `Dispute#state`（needs_response → under_review → won/lost），
> 而"打回补证"会被状态机判为**倒退**并留下 `attention_reason = invalid_transition`。

- `Disputes::ReceiptStatus.call(dispute:, submission: nil)` → **只读派生**（零写、零事件、零触网）：
  `submitted(1) → acknowledged(2) → rejected(3)`，返回 `{state, rank, receipt_id, emitted_at,
  provider_status_at_submission, dispute_state, previous_state, reasons[]}`。
- 判据：`acknowledged` = 争议已到 `under_review` 阶段 / 回执提交时 provider 回 `under_review` / 存在更新的回执；
  `rejected` = `attention_reason = invalid_transition` **且** 净化的 provider 状态回到 `needs_response`；
  信号冲突 → `unknown`；无回执 → `state: nil`（`no_receipt`）。**不猜**。
- **单调性来源**：`Dispute#state` 拒绝倒退 + `attention_reason` 不被后续流程覆盖（`DeadlineAlertSubscriber` 只在空时写）
  → 派生值天然不回退（spec 有单调性用例）。
- 接线：`SubmissionTimeline` 输出多一个 `receipt:` 字段（时间线卡顶部徽章：submitted/acknowledged/rejected/no receipt yet）。
- 边界：provider 状态归一复用 `ProviderPayload::STATE_BY_PROVIDER_STATUS`（不在本服务另立一套词汇）。

### 退货/补货人工入口（DSP-P7-10 B3 / FR-008，2026-09-13）

> "处理争议"永远**不自己动库存与钱**：退货/补货仍走订单域既有显式流程，争议页只提供一个**人工跳转**。

- 争议详情页新增只读卡「Returns / restock (manual)」→ `PallasTrade.parent_order_returns_admin_order_path(dispute.order)`
  （admin routes 中 `resources :orders` 的 member 路由；同时存在 `orders/customer_returns` 嵌套资源）。
- 无锚点订单（`dispute.order` nil）→ **显式文案说明无法退货**，不隐藏入口、不报错。
- 零库存写：渲染入口不动 `InventoryUnit` / `StockMovement` / 订单 / 支付 / 回执（spec 有计数断言）。
- i18n：`disputes_return_entry` / `_help` / `_action` / `_missing_order`。

## Where to read further

- **Payment source:** `bundle show pallastrade_core`/app/models/pallastrade/payment.rb — the state machine and processing methods.
- **Payment processing:** `PallasTrade::Payment::Processing` concern — `process!`, `authorize!`, `purchase!`, `confirm!`, `capture!`, `void_transaction!`, `cancel!` methods.
- **PaymentSession:** `PallasTrade::PaymentSession` — the 5.4+ redirect-flow wrapper.
- **Docs:** `node_modules/@pallastrade/docs/dist/developer/core-concepts/payments.md` (the how-to companion is `dist/developer/how-to/custom-payment-method.md`).
- **Stripe gem:** `https://github.com/stevenbian9266-cyber/pallastrade` — best reference for a real-world payment integration.

## 部分争议 / 多争议 / 争议费用（DSP-P7-9, 2026-09-13；PRD-20260913-payments-dsp-p7-9-partial-and-multi-dispute-semantics）

> 把源计划 §68「advanced dispute capabilities」收窄为 Stripe 侧可验证范围：partial 语义、一个 payment 的 1:N 争议、
> **争议手续费**闭环（采集 → 落库 → 独立入账 → 对账）、provider 能力矩阵只读降级。**零新增资金自动化**。

- **手续费事实（O1 落地）**：Stripe 把「扣款 + fee」放在**同一条** `adjustment` BalanceTransaction
  （`amount=-争议额, fee=固定金额, net=-(争议额+fee)`）；胜诉返还 BT 的 `fee = 0` ⇒ **fee 永不退回**（净损失）。
  因此 `fetch_dispute_details` 追加 `balance_transaction_details[{reference,type,amount,fee,net,currency}]` 与
  派生 `fee_amount`（adjustment BT 的最大正 fee；缺失 → nil，**不猜、不写死金额**）。
- **fee 落库**：`Disputes::CaptureFee` 只写 `Dispute#fee_amount` 一列（**空→非空**，重放不覆盖；fee 币种取 dispute `currency`，
  因为表无 `fee_currency` 列——零迁移边界）。无 payment 锚点/无契约/异常 → 降级枚举且零写。
  采集点在 `Disputes::Recover`（`fetch && apply` 时；dry-run 零写；已有 fee 时零额外网络调用）。
- **fee 入账**：`FACT_TYPES` / `ENTRY_TYPES` 追加 `DISPUTE_FEE`（**追加式**；`PSP_FEE` 仍为 FIN-P4-5 预留）；
  `FinancialFacts::ResolveDispute` 的 `DISPUTE_FEE` 分支金额取 `fee_amount`（**负数**）、`effective_at` 取 `funds_withdrawn_at`
  （**无 fallback**）；`Dispute` 在 fee 空→非空时发布 `dispute.fee_recorded` → `DisputeFundsSubscriber` → `PostDispute`。
  **fee 条目永不冲销**（胜诉只记 `DISPUTE_FUNDS_REINSTATED`）。
- **对账**：期望账行新增 fee（仅当「fee 已证 + 有扣款时间戳」）；缺账走既有 `journal_missing`
  （reason `JOURNAL_POSTING_MISSING_DISPUTE_FEE`）→ P7-6 `Recover` 自动补记（**无需新分类枚举**）；
  结果新增只读 `fee` 视图 `{ evidence:, amount:, currency:, posted:, returned: false }`。
- **partial 语义**：`Dispute#partial?`（只读派生；`payment` 缺失 → false，**未知 ≠ 部分**）；金额**一律**取 dispute 快照，
  禁止用 `payment.amount` 推导争议金额（P7-0 §9.2 铁律；spec 含 grep 级负向断言）。
- **payment 级多争议（只读）**：`Disputes::PaymentDisputeSummary` → `{ dispute_count, active_count, disputed_total,
  remaining_amount, exceeds_payment, mixed_currency, disputes[] }`；**零写、零 provider I/O、零决策**
  （币种不一致则不给合计；超限只是提示）。
- **provider 能力矩阵（RV-D10）**：`PaymentMethod#dispute_capabilities` 基类 = `UNSUPPORTED` 形态；
  Stripe 覆写为 `{ supported: true, evidence_submission:, accept_dispute:, fee_capture:, evidence_text_keys:, evidence_file_keys: }`；
  控制台只读卡片按矩阵渲染，不支持时给出原因且不渲染写表单。

## Credentials & environments — 凭据生命周期（D9 首版, 2026-09-15；PRD-20260915-payments-d9）

- **环境维度**：`PallasTrade::PaymentMethod#environment`（`test` / `live`，列默认 `live` → 存量零回归）。`test` provider 不产生真实资金：前台列表过滤（Resolver frontend）+ `PaymentSessions::Start` 在 `session_data['test_mode'] = true`，`PaymentSession#find_or_create_payment!` 同步写入 Payment `metadata['test_mode']`。
- **切换不重启**：后台改 `environment` 即生效（无进程缓存/环境变量依赖）；切到 test 时强制 `storefront_visible = false`。
- **凭据读取**：`PaymentMethod#{credential_level, credential_status, credentials_status, resolved_preference}`；`env:` 引用只在读取侧解析（写路径只存引用）。
- **到期巡检**：`PaymentMethods::CredentialExpiryCheckJob`（日）—— 30/7/1/expired 阈值，同级别幂等（`credential_alerts` + `AuditLog`），零 provider 网络调用。
- 回归：`harness verify d9-credentials-rspec`。

## Frontend key delivery — 前台密钥下发（D10 首版, 2026-09-15；PRD-20260915-payments-d10-client-config）

凭据**下发面**（业务方案 §68.4/§76.1）：服务端在支付方式 payload 里下发 `client_config`，取代构建期 `NEXT_PUBLIC_*`（换环境/换支付商不再重建镜像）：

- **唯一组装点**：`PallasTrade::PaymentMethods::ClientConfig.call(payment_method)` → `{ provider:, environment:, publishable: {...}, session_token: nil }`。
  - `provider` = `Gateway.api_type`；`environment` = D9 的 test/live；`session_token` 是**短时令牌预留位**（本期恒 nil，provider 侧签发属后续批次）。
- **只下发 publishable 级**：键来源 = `PaymentMethod#public_preferences`（provider 用 `public_preference_keys` 声明）；`secret` / `internal` 永不进入 payload。
  声明的键**必须是 symbol**（preferences 以 symbol 存储，string 键会取到 nil）；Stripe 声明 `[:publishable_key]`。
- **`env:` 引用**：值形如 `env:STRIPE_PUBLISHABLE_KEY` 时写路径只存引用，下发前经 `resolved_preference` 解析（缺 ENV → 省略该键）。
- **下发通道**：store `CheckoutSerializer.payment.available_payment_methods[].client_config` + store `PaymentMethodSerializer`（cart / order / shopping_cart）→ admin 序列化器继承同字段（publishable 非密）。
- 回归：`harness verify d10-client-config-rspec`；前端 `storefront-test`。

## Webhook 治理 — 入站事件运营面（D12 首版, 2026-09-15；PRD-20260915-payments-d12-webhook-governance）

business方案 §69：把「已具备但看不见」的入站事件变成可看/可筛/可处置（排障不再写 SQL）。

- **事件壳状态机**：`PaymentWebhookEvent` 新增 `quarantined`（+ `quarantined_at` / `quarantine_reason` 两列）。
  `replayable?` = `!processing? && !quarantined?`（隔离事件不得直接进业务链）；`unquarantine!` 回到 `failed`。
- **人工标记**：`mark_processed_manually!`（已线下核实，不重放）；`mark_quarantined!(reason:)` 拒绝在 `processing` 时调用。
- **筛选**：`PaymentWebhookEvent.filter_by(provider:, action:, status:, from:, to:, order_number:)`
  （订单号经 `payment_session` → `order` 反查）；`#order` / `#processing_duration_seconds` 供详情页。
- **处置服务**（均写 `Audit` + trace；不做业务写）：`Payments::QuarantineWebhookEvent`、
  `Payments::MarkWebhookEventProcessed`；重放仍走既有 `Payments::ReplayWebhookEvent`。
- **健康聚合**：`Payments::WebhookHealth.call` → 入站（24h 各状态/失败率/积压/平均耗时）+ 出站（成功失败/积压/成功率）。
- **订阅清单**：`Payments::WebhookSubscriptionChecklist.call` → 每 provider `missing`（期望 − 实收 = **漏订候选**）/ `unknown`（实收 − 期望）。
  provider 声明：`PaymentMethod#webhook_event_subscriptions`（provider 事件名，基类空集）→ `#webhook_expected_actions`（本地 action 口径）；
  Stripe 覆写为 `WEBHOOK_EVENT_ACTIONS`（12 事件名 / 9 个 action）——覆写方法必须 **public**（该文件此处处于 private 区段后方）。
- **后台**：`/admin/webhook_events`（Developers 区，`can?(:manage, PallasTrade::PaymentWebhookEvent)`）：筛选 + 详情 + 三个动作
  （重放/隔离/人工标记），健康与清单卡逐个降级（异常 → 区块不渲染，页面恒 200）。
- 回归：`harness verify d12-webhook-governance-rspec`。

## 入口展示元数据 — 前台支付方法行（D16 切片1, 2026-09-16；PRD-20260916-payments-d16-payment-method-presentation）

业务方案 §73/§76.1：把「入口（PaymentOption）级展示名」下发到前台，取代「方法行只能显示 provider 名」。
**只做展示读模型，不改行基数**（每 provider 仍一行）。

- **读模型**（`PallasTrade::PaymentMethod`）：
  - `effective_payment_option` —— 选项化 provider 取 `effective_payment_options.first`（受 D8 范围求值后的可见入口），
    否则回落 `default_payment_option`；`option_display_name` = 该入口 `display_name`，空则回 `name`。
  - `option_identifier(kind = nil)` —— `"#{prefixed_id}:#{kind}"`（如 `pm_xxx:card`），kind 取入口 `kind` → `default_option_kind`。
    与后台 line item 的 `prefixed_id:kind` 口径**同源**，便于前后台对齐同一条入口。
  - ⚠️ 入口 metadata **当前没有** `icon` / `description` 键（只有 `active` / `display_name` / `position` / `kind` / `rule_set` 等）；
    `description` 仍归 provider 语义。要加图标/副标题先扩 metadata 契约，不得在序列化器里臆造字段。
- **下发契约**（additive）：
  - store `CheckoutSerializer`（`payment.available_payment_methods[]`）：`option_id` / `method_key` / `display_name`；
  - store `PaymentMethodSerializer`（cart / order / shopping_cart 同族）：同三字段；
  - `method_key` = 入口 `kind` || `default_option_kind`；`option_id` = `option_identifier`。
- **前台渲染**：方法行 `display_name ?? name`（`OrderPaymentContent` / `PaymentCheckoutModal` / `UnifiedCheckout` 三处），
  缺失 `display_name` 的行**必须**回落 provider 名（老数据零回归）。
- **回归**：`harness verify d16-payment-presentation-rspec` + 前端 `storefront-test`。

## 入口级支付区 — 列表展开 + 钱包快付（D7, 2026-09-18；PRD-20260918-payments-d7-payment-section-express；业务方案 §76.1 / §78-D7）

**问题**：投影只带 `effective_payment_option`（**单入口**）→ 前台一 provider 一行，配了 Apple Pay / Google Pay 也看不见；
商家只能「关掉卡支付」才逐个暴露钱包（与业务需求背离）。

- **读模型（入口级投影，additive）**：`PallasTrade::PaymentMethod#payment_option_entries(available_kinds: nil)`
  —— 选项化 provider → **每个启用入口一条**（按 `position`）；未选项化 → **1 条**隐式入口（`default_option_kind`）。
  字段：`option_id`（`"pm_x:card"`）/ `method_key`（kind）/ `display_name` / `frontend_kind` / `group` / `position`。
  辅助：`option_group(kind)`（manual → wallet → card(inline) → redirect 归一）、`option_frontend_kind(kind)`（未配置入口回落 wallet=express）。
- **入口集合 = 服务端唯一求值点**：`Payments::Availability::Resolver.available_option_kinds(order:, payment_method:)`
  （D8 范围规则 / D11 熔断 / D15c 认证闸门）。checkout 投影在**有订单上下文**时按该集合过滤；无上下文回退不过滤（安全降级）。
- **下发契约（additive）**：
  - store `CheckoutSerializer.payment.available_payment_methods[]`：新增 `entries[]`（每入口含上述六字段）+ provider 级 `group` / `position`；
  - store `PaymentMethodSerializer`：新增 `group` / `position` **与 `entries[]`**（cart/order/shopping_cart 同族；
    该通道无订单上下文 → 入口集合为「已配置且启用」的**未过滤**集合，可用性仍由 `Start` 带订单上下文复算）；
- **`option_kind` 全链路**：cart legacy 会话（`POST /carts/:id/payment_sessions`，此前**静默丢弃**该参数）、
  orders 会话（`POST /orders/:id/payment_sessions`）、durable 交易（`POST /orders/:id/transactions` → `Transactions::Start` → `PaymentSessions::Start`）
  三处均把入口传进门禁；`Transactions::Start` 新增 `option_kind:` 关键字参数（不传 = 零回归）。
- **失败语义不变**：不可用入口 → **建会话前** `422 payment_option_not_available`（orders/transactions；cart legacy 沿用
  `validation_error` 通道错误码），**零 session 行**；前台按 D8 既有约定「刷新列表 + 提示重选」。
- **前台红线**：**零筛选**——只按 `frontend_kind` 选渲染槽（`inline` 自绘卡字段 / `express` 钱包按钮 / `manual` 说明行），
  隐藏与否一律由服务端决定。旧响应无 `entries` → 回落「一 provider 一行」（零回归）。
  - **补口 3（设备能力，2026-09-18）**：**设备钱包能力**是客户端唯一可知的第二个轴 —— 读数模型
    `storefront/src/lib/checkout/wallet-availability.ts`（**改钱包行为先看它**）：
    - **点谁显示谁**：`expressPaymentMethodsFor(method_key)` 把选中钱包设 `always`、其余设 `never`
      （Stripe 文档脚注：非 Safari 桌面端 Apple Pay、Firefox/Safari/iOS 的 Google Pay **只在 `always` 时才支持**；
      `auto` 会让 PC 端 Apple Pay 永不初始化）；`link` 只接受 `auto|never`。无入口上下文（抽屉）→ 两个钱包 `always`。
    - **三态 + 原因**：`unknown`（仅 onReady 未触发）/ `available` / `unavailable` + 原因（`device` / `timeout` /
      `unsupported` / `unconfigured`）。**`onReady` 触发后的 `availablePaymentMethods === undefined` 是确定性**
      「没有任何钱包可显示」（官方类型原文），必须立即判 `device`，不得当作还在加载；10s 看门狗超时 → `timeout`（可重试），
      文案不得写成「本设备不支持」。
    - **可恢复 + 重试**：不可用 → 父级标注（`PaymentSection.unavailableEntries`，行内按原因给短文案）+
      **自动回落**卡支付；重新点该入口 = 重试（清标注 + 探针令牌递增 → 重挂载元素）；后续上报 `available` → 解除标注。
      **入口集合仍不删除**（服务端决定，D15c 红线）；行不 `disabled`（否则无法重试）。
    - **能力矩阵**：前台 express 元素只启用 `applePay` / `googlePay` / `link`；服务端 `WALLET_OPTION_KINDS` 里的
      `paypal` / `paypal_checkout` / `shop_pay` / `amazon_pay` 目前**无前台渲染**（走说明行，不建会话）。
    测试环境/设备差异：Windows 上 Apple Pay 必然不可用；`canMakePayment()` 可返回 `null` —— 复现口径与两页接线见
    `pallastrade-storefront` Skill「设备钱包能力与降级」。
- **回归**：`harness verify d7-payment-section-rspec` + 前端 `storefront-test`。

## 对账差异队列 — 只读结论 → 可运营案例（D13 切片1, 2026-09-16；PRD-20260916-payments-d13-reconciliation-cases）

业务方案 §70.1：P4-6/7 的对账结论此前**不落表**（只 warn + rake），差异没有队列/指派/备注/关单/导出。
本切片把它变成可运营工作队列，**零资金副作用**（只写案例表 + 审计，绝不动 Payment/Refund/Journal/订单/库存，零 provider 调用）。

- **模型**：`PallasTrade::ReconciliationCase`（表 `pallastrade_reconciliation_cases`）+ `ReconciliationCaseNote`（备注留痕）。
  - 唯一键 `dedupe_key = "txn:<transaction_id>:<signature>"`；`signature` = 排序去重后的原因码（空 → 状态名）。
  - 字段：`kind`（transaction/payment/refund）、`status`（open/investigating/explained/fixed/dismissed）、
    `difference_type`、`severity`、`reason_codes`、`summary`（P4 金额摘要快照）、`expected_amount` / `observed_amount`、
    `provider`、`currency`、`detected_at` / `last_seen_at` / `occurrences`、`resolved_at` / `resolution_source`（human/auto）、`assignee_id`。
  - ⚠️ 关联名是 **`commerce_transaction`**（`belongs_to :transaction` 与 ActiveRecord 内建 `transaction` 方法冲突）。
  - 映射（确定性，唯一权威）：`AMOUNT_MISMATCH|CURRENCY_MISMATCH|COMMERCIAL_AMOUNT_MISMATCH → amount_mismatch`、
    `ALLOCATION_MISMATCH → allocation_mismatch`、`REFUND_MISMATCH → refund_mismatch`、
    `LOCAL_*_MISSING|PROVIDER_*_MISSING → one_sided`、`SETTLEMENT_PENDING → settlement_pending`、
    `JOURNAL_POSTING_MISSING → journal_missing`、`PROVIDER_* → provider_issue`、`UNLINKED_LEGACY_PAYMENT|AMBIGUOUS_CAPTURE → duplicate`、
    其余 → `needs_attention`；status `UNSUPPORTED → unsupported`。严重级：MISMATCH→critical、NEEDS_ATTENTION→attention、其余→info。
- **唯一写入口**：`Reconciliations::SyncCases.call(transaction:)` —— 读 `ReconcileTransaction`（只读）→ upsert/触碰/自动销案。
  自动 vs 人工边界：自动只处理**开放态**（open/investigating）；人工判定（explained/fixed/dismissed）**永不被覆盖**；
  签名被取代 → 旧案 `fixed`+auto（队列不残留陈旧项）。
- **巡检接入**：`Reconciliations::ReconcileSweeperJob` 每轮调 `SyncCases`（异常降级 warn 不中断）；metrics 增补
  `cases_opened` / `cases_auto_closed`；既有 journal-missing 自动 repair 行为**不变**。
- **后台**：`/admin/reconciliation_cases`（Orders → 对账队列；权限 `can?(:manage, PallasTrade::ReconciliationCase)`）：
  筛选（status/类型/严重级/provider/责任人/搜索）+ 计数 + 分页 + 详情（事实/备注时间线/审计）+ 动作
  （assign / note / mark_investigating / mark_explained / mark_fixed / dismiss（原因必填）/ reopen）+ **CSV 导出**（与筛选同口径，上限 10k）。
- **回归**：`harness verify d13-reconciliation-cases-rspec` + P4 全套 `harness verify finance-reconciliation-rspec`。

## 结算台账 — provider 结算报表 → 可核对明细（D13 切片2, 2026-09-16；PRD-20260916-payments-d13b-payout-ledger）

业务方案 §70.2：切片1 让差异**有队列**，但 provider 侧**结算批次**（批次号/手续费/净额/到账日）此前无处落地 ⇒ 「日终可对平」缺一半。
本切片把结算 CSV 变成可核对台账：导入 → 逐行匹配本地支付/退款 → 差异自动进切片1 队列。
铁律：**零资金副作用** —— 只写 2 张台账表 + 案例表 + `AuditLog`；绝不改 Payment/Refund/Journal/订单/库存，零 provider 调用。

- **模型**：
  - `PallasTrade::Payout`（`pallastrade_payouts`）：`store_id` / `provider` / `reference`（provider 批次号）/ `status` /
    `currency` / `gross_total` / `fee_total` / `net_total` / `period_start` / `period_end` / `settled_at` / `imported_at` /
    `import_source` / `metadata`；唯一键 `(store_id, provider, reference)`；索引 `(store_id, status)`。
  - `PallasTrade::PayoutLine`（`pallastrade_payout_lines`）：`kind`（charge/refund/fee/adjustment）/ `provider_reference` /
    `gross_amount` / `fee_amount` / `net_amount` / `match_status`（pending/matched/unmatched/amount_mismatch）/
    `match_details` / `matched_at` / `payment_id` / `refund_id` / `raw`（导入行快照）；唯一键 `(payout_id, provider_reference, kind)`。
  - **状态合成**（唯一权威，`refresh_status!`）：`difference`（任一行 unmatched/amount_mismatch，差异优先）→
    `settled`（无差异且 `settled_at` 存在）→ `in_transit`；`recalculate_totals!` 由行汇总（provider 报表值原样求和）。
  - 金额容差：`PayoutLine::AMOUNT_TOLERANCE = 0.01`。
- **服务（唯一写入口）**：
  - `Reconciliations::Payouts::ImportCSV.call(store:, provider:, csv:, source: nil, actor: nil)` —— 必需列
    `payout_reference, kind, provider_reference, gross`；可选 `fee`（默认 0）/ `net`（默认 gross − fee）/ `currency` /
    `arrived_on`（→ `settled_at` 当日零点）/ `period_start` / `period_end`；按 `payout_reference` 分组 →
    upsert payout + 逐行 upsert line（幂等：重复行计入 `lines_skipped`）→ 汇总 + 状态合成 + 审计 `payouts_imported`；
    行级错误收集不中断（`errors: [{row:, message:}]`）；缺列 / 空 CSV / 超 5 MB → 失败且**不落库**。
  - `…::Match.call(payout:, actor: nil)` —— 锚点（唯一口径）：`charge` → `Payment#response_code` →
    `PaymentSession#external_id` → 该会话首笔 payment；`refund` → `Refund#transaction_id`；`fee` / `adjustment` =
    provider 侧项目 → 直接 `matched`。金额一致（±0.01）→ `matched`；不一致 → `amount_mismatch`（写 `difference`）；
    无本地记录 → `unmatched`；命中的行写回 `payment_id` / `refund_id`；结束后汇总 + 状态合成 + 审计 `payout_matched`。
  - `…::SyncCases.call(payout:)` —— 差异行 → `ReconciliationCase`（`kind: 'payout'`、`difference_type`
    `payout_unmatched` / `payout_amount_mismatch`、原因码 `PAYOUT_LINE_UNMATCHED` / `PAYOUT_AMOUNT_MISMATCH`、
    `severity: attention`、`dedupe_key = "payout:<payout_id>:<provider_reference>:<签名>"`）；行恢复 `matched` → 开放案例**自动销案**；
    签名变化 → 旧案取代；**人工判定（explained/dismissed）永不被覆盖**；审计 `payout_cases_synced`。
- **后台**：`/admin/payouts`（Orders → 结算台账；权限 `can?(:manage, PallasTrade::Payout)`）：
  列表（provider/status/到账日筛选 + gross/fee/net 汇总卡 + 分页 + 差异行计数）；详情（批次事实 + 行表 + 匹配摘要 + 审计轨迹）；
  `GET /admin/payouts/new` + `POST /admin/payouts/import`（粘贴 CSV 或上传文件 → 导入后**自动** Match + SyncCases）；
  `POST /admin/payouts/:id/match`（重新匹配）。台账页用整数 id（页内使用，不进 API 契约）。

## 费率模型与支付成本报表 — 「成本可下钻到入口」（D13 切片3, 2026-09-16；PRD-20260916-payments-d13c-fee-cost-report）

业务方案 §70.3：平台此前只知道「收了多少」与「结算单实际扣了多少」，没有**事前费率模型** ⇒ 算不出某笔/某入口应花多少，也无法对比「约定费率 vs 实际扣费」，更没法支撑 §67.1 成本路由。
本切片建费率（rate card）+ 只读成本报表：成本可**下钻到入口**，并并列结算实际扣费。
铁律：**零资金副作用 + 零 provider I/O** —— 报表与计算不写 Payment/Refund/账本/库存，不调 provider；模型费用是**核算口径**，不是资金事实。

- **模型**：`PallasTrade::PaymentFeePolicy`（`pallastrade_payment_fee_policies`）：
  `store_id`（可空 = 全局）/ `name` / `scope_type`（`global`/`store`/`provider`/`method`）/ `scope_id`（provider = `payment_method_id`；method = **入口 method_key**）/
  条件 `currency` / `card_type` / `region`（空 = 全部）；分量 `percent_fee` / `fixed_fee` / `platform_percent` / `cross_border_percent` /
  `cross_border_fixed` / `currency_conversion_percent`；保底封顶 `min_fee` / `max_fee`；判定基准 `home_country` / `settlement_currency`；
  窗口 `effective_from` / `effective_until`；`status`(active/revoked) / `revoked_at` / `metadata`；索引 `(scope_type, scope_id)`（§74.1）、`(store_id, status)`、`(status, effective_from)`。
  - **归一化**：`global`/`store` 的 `scope_id` 归零；`currency`/`region`/`home_country`/`settlement_currency` 大写、`card_type` 小写；百分比 0..100、金额非负、`min ≤ max`。
  - **生效口径**：`active` + `effective_at(at)`（未撤销 + 窗口内）；`for_store(store)` = 全局 + 本店（店铺隔离硬边界）。
- **服务（全部只读）**：
  - `Payments::Fees::Resolver`（+ `Resolver::Context.from_payment`）：按 `by_priority`（`method`4 > `provider`3 > `store`2 > `global`1，同优先级 `effective_from` 更晚者，再取 id 更大者）取**唯一命中**策略；
    条件不匹配 → `skipped[{policy_id, reason}]` 留痕；**声明了条件但本地无法判定 → 不命中**（`card_type_undetermined` / `region_undetermined`），绝不臆造。
    批量场景传 `candidates:`（预加载），避免 N+1。`Context` 只取本地可得事实（币种取 `order.currency`；卡类型取 `payment.source#cc_type`；地区取账单国 ISO），**不隐式访问 `order.store`**（调用方注入）。
  - `Payments::Fees::Calculate`：`variable = 金额×(percent + platform)/100 + 跨境(条件成立时) + 转换(条件成立时)`；`variable` 受 `min_fee`/`max_fee` 约束（**固定费在封顶之后相加**）；
    `total = clamped + fixed`、`net = amount − total`；无策略 → `priced=false` + `no_policy`；跨境/转换基准不可证明 → 不计费 + signal。
  - `Payments::Costs::Report`：统计域 = 本店 + `Payment.completed` + `[from, to)`（左闭右开，最多 366 天，超限标记 `clamped`）；输出
    `totals`（gross/fee/net/`fee_rate`/单均成本（**按订单去重**）/订单数/笔数/未定价笔数/实际扣费/偏差/`variance_coverage`）、
    `by_entry`（入口 = `payment_method` × `method_key`，按 fee 降序 + key 升序 tie-break）、`by_provider`、`by_currency`、`detail`（有界 500，超出标记）、`unpriced_reasons`。
  - **实际 vs 模型**：`actual_fee` 取 `payout_lines.fee_amount`（`refund_id IS NULL`，单次分组查询）；`variance = actual − modelled`。
  - **入口身份** = `PaymentMethod#effective_payment_option['kind']`（与 API 序列化器同源）；**未选项化**的支付方式返回 default kind（如 `check`/`bogus`）→ 报表页显式标注「入口按**当前映射**归因」（逐笔支付未持久化所选 option，历史归因留后续切片）。
- **后台**（权限 `can?(:manage, PallasTrade::PaymentFeePolicy)`）：
  - `/admin/payment_costs`（Orders → 支付成本）：期间 + provider/币种/入口筛选 → 汇总卡（`data-cost-metric`）+ 入口排名（`data-cost-table="by_entry"`，行可**下钻**）+ 逐笔明细 + 未定价原因 + CSV 导出（含 `entry_key`，**无凭证/卡号**）+ 导出审计 `payment_cost_report_exported`。
  - `/admin/payment_fee_policies`（Orders → 费率策略）：列表（适用范围/状态/币种筛选 + **同源计数** + 分页）+ 新增/编辑 + **软撤销**（保留历史行）；审计 `payment_fee_policy_changed` / `payment_fee_policy_revoked`（before/after 快照）。
- ⚠️ **踩坑**：
  - 命名空间 `PallasTrade::CSV` 会遮蔽 Ruby 标准库 → 控制器内必须写 `::CSV.generate`。
  - `joins(:order)` 与 `includes(order:)` 同用会让预加载失效（每笔支付一次查询）→ 用 `where(order_id: 子查询)` + `includes`；报表批量解析时**显式注入 store 对象**。
- **回归**：`harness verify d13c-cost-report-rspec`（162 例，含后台导航一致性）；下游 §67.1 成本路由复用 `Resolver` + `Report` 作为成本数据源。

## 汇率快照与结算汇率对比 — 「只做结算差核算」（D13 切片4, 2026-09-16；PRD-20260916-payments-d13d-fx-snapshot）

业务方案 §70.4：跨币种订单「展示汇率」此前无处记录，结算汇率差异也无处归属。本切片建汇率域：多源汇率表 → 下单锁汇快照 → 结算汇率逐笔对比 → 差异进对账队列。
铁律：**零资金副作用 + 零外呼** —— 不改订单/支付金额与状态、不换汇、不写账本/库存、不调任何外部汇率 API；市场定价与多币种标价属多市场方案。

- **模型**：
  - `PallasTrade::CurrencyRate`（`pallastrade_currency_rates`）：`store_id`（可空 = 全局；**本店优先于全局**）/ `base_currency`（结算侧）/ `quote_currency`（展示侧）/ `rate` decimal(20,10) /
    `source`（manual/provider/third_party）/ `priority`（默认 provider 30 > third_party 20 > manual 10，可显式覆写）/ `effective_from` / `effective_until` / `status`+`revoked_at` /
    `identity_key`（SHA256(scope:base:quote:source:effective_from)，**唯一**）/ `note` / `metadata`。
  - `PallasTrade::FxSnapshot`（`pallastrade_fx_snapshots`）：`order_id` / `payment_id` / `currency_rate_id` / `base_currency` / `quote_currency` /
    `display_rate` + `up_charge_percent` + `effective_rate`（加点后）/ `rate_source` / `locked_at` / `locked_on`；
    结算侧 `settlement_rate` / `settlement_source`（provider_reported/implied）/ `settlement_currency` / `settled_gross_amount` /
    `variance_bips` / `variance_status`（pending/matched/mismatch/undetermined）/ `compared_at` / `reconciliation_case_id` / `occurrences` / `signals`。
    唯一键 `(order_id, base_currency, quote_currency)` = **一单一种币对只锁一次**。
- **汇率语义**：`rate` = 1 个 quote（展示币种）对应的 base（结算币种）数量；快照 `base = store.default_currency`、`quote = order.currency`。
- **服务（全部只读事实 + 只写快照/案例/审计）**：
  - `Currencies::Rates::Resolver` —— `priority DESC` → 本店 > 全局 → `effective_from DESC` → `id DESC`；无候选 → `no_rate`（不猜）。
  - `Currencies::Rates::Upsert` —— 汇率唯一写入口（身份键幂等 / 软撤销保留历史 / 审计 `currency_rate_changed`・`currency_rate_revoked`）。
  - `Currencies::Fx::Policy` —— 店铺 `private_metadata['fx_policy']`：`enabled`(true) / `up_charge_percent`(0) / `variance_tolerance_bips`(**50**) / `auto_reconcile`(true) / `default_source`。
  - `Currencies::Fx::Lock` —— 锁汇：加点后 `effective_rate`；**同币种 / 无汇率 / 策略关闭 → 不写行**（不猜）；幂等（`occurrences` 递增）。
  - `Currencies::Fx::Compare` —— 结算汇率来源优先：结算行 `raw['fx_rate']`（报文） → `line.gross_amount / payment.amount`（推导，要求结算币种 == base） → `undetermined`；
    `variance_bips = (settlement_rate − effective_rate)/effective_rate × 10000`；`|bips| <= tolerance` → matched，否则 mismatch；无结算 → 保持 pending。
    扫描集合：`pending`/`undetermined` + 结算行在上次比对后**被改动**的 `mismatch`（修正后翻回 matched 并自动销案）。
  - `Currencies::Fx::SyncCases` —— 差异 → `ReconciliationCase`（`kind: 'fx'`、`difference_type: 'fx_rate_mismatch'`、`dedupe_key = "fx:<snapshot_id>:<status>"`）；
    恢复一致 → 自动销案（`fixed` + auto）；人工判定不被覆盖；新开案例发布 `fx.settlement.mismatch`。
- **接线**：订阅者 `Currencies::Fx::OrderSubmittedSubscriber`（`order.submitted` → 锁汇；异常只日志，**绝不阻断下单**）；巡检 `Currencies::Fx::CompareSweeperJob`（`*/30 * * * *`）；
  结算导入（§70.2）新增**可选**列 `fx_rate` → `line.raw['fx_rate']`（非法值行级报错但不阻断；缺列行为不变）。
- **后台**（权限 `can?(:manage, PallasTrade::CurrencyRate)`）：`/admin/currency_rates`（汇率表：筛选/计数同源/新增幂等/软撤销）与 `/admin/fx_snapshots`（快照工作台：汇总卡 + 状态与期间筛选 + 明细偏差 + **重新比对** + CSV）；差异跳转既有对账队列（`kind=fx`）。
- **回归**：`harness verify d13d-fx-snapshot-rspec`（103 例）。
- **与成本域边界**：切片3 的 `currency_conversion_percent` 是**费用**口径，本切片是**汇率**口径，互不替代。

## 拒付率看板与卡组织阈值预警 — 「比率有分母才有意义」（D14 切片3, 2026-09-16；PRD-20260916-payments-d14c-dispute-rate-board）

业务方案 §71.3/§72.5：既有的 `Disputes::OpsReport` 只回答「争议侧质量」（胜诉率/时限/时长），**无分母**也**无卡组织维度**，因此算不出拒付率，更无法预警。本切片补齐「比率 + 双阈值 + 台账 + 下钻」：
铁律：**只读统计 + 零资金副作用 + 零 provider** —— 不改支付/订单/退款/账本/库存/争议状态，不调外部接口。

- **口径（唯一权威，写死在 `Disputes::RateReport` 文档里）**：
  - 窗口：默认 **30 天**（策略可配 1–365），`to = 评估时刻`，`from = to - window_days`；
  - **分子**：`Dispute.for_store(store).where(created_at: 窗口)`（开案时间口径与 `OpsReport` 一致）；
  - **分母**：`Payment.completed`、`order_id ∈ store.orders`、`payment.created_at ∈ 窗口`，按组织判定时**只计该组织品牌的卡支付**；
  - **卡组织归因**：`dispute → payment → source`（`PallasTrade::CreditCard` 的 `cc_type`），归一 `mastercard|maestro → master`、`amex → american_express`；**不可判定 → `unknown` 且不参与任何阈值判定**；
  - **金额比只算店铺默认币种**（跨币种不混算）；其他币种的支付/争议计入 `excluded_other_currency_*` 计数明示；
  - 分母 0 → 比率 `nil`（**不用 0 伪装**）；组合支付（`order_id` 为空）不属任何店铺 → 不进分母。
- **策略**（`Store#private_metadata['dispute_rate_policy']`，无新表）：`enabled`（默认 true）/ `window_days` / `warning_ratio`（**默认 0.8** = §72.5「接近阈值 80% 预警」）/ `networks['<卡组织>'] = {count_bps, amount_bps}`。
  - **不硬编码卡组织公示数字**：默认无阈值；`RatePolicy.suggested_networks` 只是「建议模板」（带来源说明），必须运营**显式应用**才生效；
  - 判定：`breached`（任一比率 ≥ 阈值）> `approaching`（≥ 阈值 × warning_ratio）> `ok`；**未配置 → `unconfigured`（不判定、不预警）**；
  - 归一化保守：非法窗口/比例回默认，非法 bps 视为未配置（不猜）。
- **服务**：`Disputes::RatePolicy`（值对象，`classify` 是**唯一判定口径**）、`Disputes::RateReport`（只读：汇总 + 四维度下钻 + 降级信封 + 查询数恒定）、`Disputes::RateAlert`（写台账 + 档位升级发事件 + 审计）。
- **台账** `pallastrade_dispute_rate_alerts`：唯一键 `rate:<store>:<network>:<评估日>`；只落 approaching/breached；同日**不降档**（保留更高档 + 刷新观测值 + 记 `metadata['relaxed_at']`）；升级更新同一行 + `escalated_at`。
- **事件** `dispute.rate_threshold`（**只在档位变化**时发布）+ 巡检 `Disputes::RateAlertSweeperJob`（`45 * * * *`，单店失败隔离 + JSON 指标）。
- **后台** `/admin/dispute_rates`（Orders position 64）：组织卡片（两比率×两阈值×状态）+ 下钻（**卡指纹/国家/入口/客群**，入口复用 `PaymentMethod#effective_payment_option`）+ 阈值设置（含「应用建议值」）+ 立即评估 + CSV + **一键加黑**（复用 D15 `Risk::Lists::Upsert`）。
- ⚠️ **卡指纹一律脱敏**（复用 D15 `PaymentRiskList#masked_value` 的 `abcd***3456` 口径）；页面**只提交掩码**，服务端在窗口下钻结果里**唯一反解**才写入，不唯一则拒绝（不猜）。
- **与其他域边界**：D13c 的费率模型是「成本」口径，本切片是「风险比率」口径；D16「支付入口」只作为下钻维度复用，不另立口径。
- **回归**：`harness verify d14c-dispute-rates-rspec`（79 例）。
- **命名陷阱（实测踩坑）**：Rails 把 `CSV` 注册为 acronym ⇒ `import_csv.rb` 必须定义 **`ImportCSV`**（Zeitwerk 报
  `uninitialized constant …ImportCsv`）；`PallasTrade` 命名空间内引用 stdlib 一律写 `::CSV`（裸 `CSV::…` 会被解析成 `PallasTrade::CSV::…`）。
- **回归**：`harness verify d13b-payouts-rspec`（52 examples）+ 切片1 `d13-reconciliation-cases-rspec` + P4 `finance-reconciliation-rspec`。

## 退款审批 — 阈值 + 双人复核（D14 切片1, 2026-09-16；PRD-20260916-payments-d14-refund-approval）

业务方案 §71.1：人工退款此前**无额度约束、无第二人**，一次误操作即出款。本切片给「人工退款」加**策略门**：
`≤` 阈值自动执行；`>` 阈值**落库待批**，必须**第二人**批准才入队执行。
铁律：**零资金副作用** —— 审批只决定「是否入队」；provider I/O 与资金日志仍只发生在 `Refunds::ExecuteJob`（REV-INV-03）。

- **策略**（`Refunds::Policy`，只读值对象；存 `Store#private_metadata['refund_policy']`）：
  `enabled`（默认 **false** = 行为与今天完全一致）/ `auto_approve_limit`（`≤` 自动；严格 `>` 才需审批）/ `currency`（空 = 全部币种）。
  归一化**保守**：非法值（负数/非数值）→ 不启用 + `reason`；`enabled: true` 但阈值缺失 → 阈值按 **0**（全部需审批）。
  **读策略零写库**、零 provider I/O。
- **策略门的位置**：只在 `Refunds::Submit`（人工入口），**不放进** `Refunds::Request` —— 编排与网关退款必须无人值守
  （`Orders::Cancel`、stripe/adyen/paypal 回调行为零变化；把门放进内核会让「取消订单退款」因超阈值挂起）。
- **`Refunds::Submit.call(payment:, amount:, reason:, refunder_id:, request_key: nil, ...)`**：
  `request_key` 命中既有退款 → 直接返回（`pallastrade_refunds.request_key` partial unique index 兜底并发）；
  `≤` 阈值 → `Request(enqueue: true)` + 审计 `refund_auto_approved`；`>` 阈值 → `Request(enqueue: false)`（durable `requested`、
  **不入队**）+ `RefundApproval(pending)` + 审计 `refund_approval_requested`；策略未启用 → 等价今天（不建审批行、无额外审计）。
- **`Refunds::Approvals::Approve.call(approval:, approver_id:, note: nil, actor: nil)`** —— 第二人批准：
  `approver_id` 必填且 **≠ `requester_id`**（`approver_must_differ`）；仅 `pending` 可批（已批 → 幂等返回现状，**绝不重复入队**；
  已拒 → `approval_already_rejected`）；批准 → `approved` + `decided_at` → `Refunds::ExecuteJob.perform_later(refund_id)`
  + 审计 `refund_approval_approved`（metadata `approver_id` / `enqueued`）。
- **`Refunds::Approvals::Reject.call(approval:, approver_id:, note:, actor: nil)`** —— 第二人拒绝：
  同样不允许自拒；`note` 必填（`note_required`）；拒绝 → `rejected` + `refund.cancel_request!`（`requested → canceled`，
  **释放可退额度**）+ 审计 `refund_approval_rejected`（metadata `refund_canceled`）；重复拒绝幂等返回现状。
- **模型** `PallasTrade::RefundApproval`（`pallastrade_refund_approvals`）：`status`（pending/approved/rejected）、`amount` / `currency`、
  `requester_id` / `approver_id` / `decided_at` / `note`、`policy_snapshot`（「当时按什么规则挂起」）、`metadata`；
  `refund_id` **唯一**（一笔退款最多一条审批）；`Refund#approval`（has_one，dependent: :destroy）；SoD 判定 `requester?(actor_id)`。
- **Admin API**：`POST /api/v3/admin/orders/:id/refunds` 改走 `Refunds::Submit`（策略门生效，支持可选 `request_key`）；
  `Admin::RefundSerializer` 增 `approval_status`（pending/approved/rejected；无审批 → null）。契约产物需重生成（见 `generated:check`）。
- **审计五连**：`refund_auto_approved` / `refund_approval_requested` / `refund_approval_approved` / `refund_approval_rejected` /
  `refund_policy_updated`。
- **回归**：`harness verify d14-refund-approval-rspec`（64 examples）+ `Orders::Cancel` 与 refunds 既有 spec + `harness generated:check`。

## 争议期限分档提醒与超期处置（D14 切片2, 2026-09-16；PRD-20260916-payments-d14b-dispute-deadlines）

业务方案 §71.2：DSP-P7-5 只在「72h 窗口」发一次提醒、超期后**无人收口**（证据没交 → 争议自动流失 = 直接亏钱）。
本切片把「快到期」变成**分档 / 幂等 / 可运营**的提醒台账，并给出**策略门控**的超期处置（默认关闭）。
铁律：**零资金副作用** —— 不写 funds 时间戳（因此不触发资金入账事件）、不改 Payment / Refund / Journal / Order / 库存、零 provider 调用。

- **策略值对象** `Disputes::DeadlinePolicy.for(store)`（只读；存 `Store#private_metadata['dispute_deadline_policy']`）：
  `tiers_days`（默认 `[3, 1]` → 档位键 `t3` / `t1`）、`auto_lose_on_overdue`（默认 **false** = 行为与今天一致）、`auto_lose_limit`（默认 100）。
  归一化**保守**：非法/空 `tiers_days` → 回默认（绝不因配置错误变成「无档位 = 不提醒」）；档位去重 + 只留正整数 + 降序（最宽松在前）。
  `latest_tier` / `reached_tiers` / `max_window_hours` 是**唯一口径**（服务、看板、列表列共用）。
  实测语义：`50h → t3`；`10h → t3 + t1`；`-3h → t3 + t1 + overdue`（`overdue` = 已过期）。`tier_hours('t3') = 72`。
- **台账模型** `PallasTrade::DisputeDeadlineAlert`（`pallastrade_dispute_deadline_alerts`，append-only）：
  `tier`（`t{n}` / `overdue`，格式校验）、`alerted_at`、`evidence_due_at`、`hours_remaining`、`metadata`；
  **唯一键 `(dispute_id, tier)`** —— 「不遗漏」靠达到即写、「不重复」靠唯一键；`metadata['backfilled']` 标记**跳档补齐**。
  `Dispute#deadline_alerts`（has_many，`dependent: :delete_all`）；scope `recent_first` / `for_tier` / `filter_by(store_id:, tier:, from:, to:)`。
  实例方法 `overdue?` / `backfilled?` / `days_before_due` / `human_tier`（**不是** scope —— 写成 `relation.overdue?` 会 NoMethodError）。
- **唯一写入口** `Disputes::AlertDeadlines.call(store: nil, now:, limit: nil)`：
  扫描**复用** `Disputes::ScanDeadlines`（只读、唯一筛选口径）；全局 sweeper 时**逐店策略**生效
  （`scan_window_hours`：显式店铺 → 该店最宽档；全局 → 至少 `GLOBAL_WINDOW_HOURS = 7*24`，覆盖 `t7` 之类更宽档位）。
  ⚠️ **店铺隔离硬边界**：`store:` 显式传入 → **只处理本店争议**（`skipped_other_store` 留痕）。
  扫描底座是**全局只读**（DSP-P7-5 契约不改），但**写侧**（台账 / 事件 / 置 lost）绝不越店 ——
  否则会把 A 店策略套到 B 店争议上，极端情况**替 B 店自动置 lost**（2026-09-16 修复；踩坑背景：只在单店测试时看不见）。
  每档 `create_alert`（`RecordNotUnique` / `RecordInvalid` → nil，幂等）；**只有本轮新记录的最新档**才发事件，历史档只落台账 + `backfilled` 标记（不补发过期提醒）。
  返回 `{ scanned:, window_hours:, tiers_recorded:, alerted:, backfilled:, auto_lost:, skipped_submitted:, failed:, policy:, scanned_at: }`；单条异常隔离（`failed` 计数 + 日志，不断其余）。
- **超期处置（策略门控）**：`auto_lose_on_overdue` 开启 **且** 已超期 **且** 状态 ∈ `AUTO_LOSE_STATES`（`opened` / `needs_response` / `under_review`）
  **且** 未提交证据（`evidence_submitted_at` 空 + 无 `evidence_submissions`）→ `transition_to!('lost')`（**复用**状态机阶段序保护，不新增状态机）
  + `attention_reason = 'evidence_overdue'`（**不覆盖**非空）+ 审计 `dispute_auto_lost_overdue`；单轮 `auto_lose_limit` 上限；
  非候选（已提交证据 / `submitted` / 终态）→ 只计 `skipped_submitted`，**不动**；重复跑幂等（终态不再处理）。
- **事件** `dispute.evidence_deadline_tier`（payload `id` / `tier` / `state` / `due_at` / `hours_remaining` / `missing_evidence`）：
  **只在有新档位时**发布；既有 `dispute.evidence_due_soon` / `dispute.evidence_overdue` **名称与 payload 不变**，但发布时机收窄为「有新档位时」。
- **审计**：`dispute_deadline_tier_recorded`（落台账，含 `backfilled` / `policy` 快照；payload 记在 `AuditLog#after`）、
  `dispute_deadline_tier_alerted`（订阅者：`t3`/`t1` 只留痕）、`dispute_auto_lost_overdue`（`actor: 'system'` 字符串 actor → `actor_type` / `actor_id` 为 nil，断言查 `after`）。
- **回归**：`harness verify d14b-dispute-deadlines-rspec`（41 examples，含 DSP-P7-5 `scan_deadlines` / `deadline_sweeper_job` / `deadline_alert_subscriber` 回归）。

## 风控名单与订单风险评估（D15 切片1, 2026-09-16；PRD-20260916-payments-d15-risk-lists）

业务方案 §72.3/§72.2：风控此前只有**支付响应驱动**的启发式（`Order#is_risky?` = `payments.risky`）与只读 AVS/CVV 面板 —— 名单不可维护、决策无留痕。
本切片给风控打地基：**名单台账 + 评估留痕**，并把结果接回**既有复核闭环**。
铁律：**本切片零资金副作用、零 provider** —— 不阻断下单、不改支付/订单金额与状态、不做 3DS 下发（切片3）。

- **名单表** `pallastrade_payment_risk_lists`（§74.1 规划表名）：`list_type`（`denylist`/`allowlist`）× `subject_type`
  （`card_fingerprint`/`bin`/`email`/`ip`/`device`/`customer`/`address`/`country`）× **归一化值**；
  **唯一键 `(list_type, subject_type, value_hash)`**（`value_hash = SHA256("type:subject:归一化值")`）→ 幂等的唯一依据。
  `store_id` **可空 = 全局名单**；生效率 = `status='active'` 且（`expires_at` 空或未来）→ `active` scope 是唯一口径；撤销用 `status='revoked'`（**保留历史**）。
- **归一化**（`PaymentRiskList.normalize_value`，维护/导入/评估共用）：邮箱与设备小写、国家大写、BIN 只留数字、
  卡指纹去空白 + 小写、IP 去空白 + 小写、地址小写 + 折叠空白。
- **留痕表** `pallastrade_payment_risk_assessments`：`order_id` / `store_id` / `decision`（`allow`/`review`/`block`）/ `matched_entry_ids` / `signals` / `evaluated_at`。
- **唯一写入口** `Risk::Assess.call(order:, now:)`：先算 **allowlist**（命中 → `allow` **短路**，白名单优先于黑名单），
  再算 **denylist**（命中 → 决策取 `PallasTrade::Config[:risk_denylist_action]`，**默认 `review`**：只标记待复核；
  仅显式配 `block` 才是 `block`；非法值回落 `review`）；无命中 / 主体不足 → `allow` + `signals['insufficient_subject']`（**不猜**）。
  可解析主体 = 订单本地字段（`email` / `last_ip_address` / `user_id` / 账单地址国家）——**零 provider I/O**。
- **留痕幂等**：重复投递（5 分钟窗口内**同决策 + 同命中集**）→ **复用已有行**；命中集/决策变化或窗口之外 → 新增一行（审计不丢）；
  兼底唯一键 `(order_id, evaluated_at)`（同一秒并发只落一行）。
- **接线**（FR-006）：订阅 `order.submitted`（`Carts::Submit`）→ `Assess` → 非 `allow` 且订单**未审批**时 `order.considered_risky!`
  （**复用**既有字段 + `Orders::Approve` 人工复核闭环）；异常 rescue + 日志，**绝不阻断下单**。
  ⚠️ 既有发布点把 payload 嵌在 `payload` 键下（`{ 'payload' => { 'order_id' => or_… } }`）→ 订阅者兼容 `id` / `order_id` / 嵌套 `payload.order_id` 三种形态。
- **店铺隔离**：评估只取「全局 + 本订单店铺」；A 店名单绝不命中 B 店订单（与 D14b 同纪律）。
- **脱敏**（页面 / 审计唯一口径）：邮箱 `d***@example.com`、IP `203.0.*.*`、BIN `4242***`、卡指纹 `abcd***3456`；
  CSV 导出保留原值（权限 + 审计保护），审计 payload **不落明文**。
- **回归**：`harness verify d15-risk-lists-rspec`（43 例，含后台导航一致性）。

## 熔断与健康 — 入口级软置灰（D11 切片1, 2026-09-16；PRD-20260916-payments-d11-circuit-breaker-health）

业务方案 §67.3：provider 抖动时**先把入口从前台摘掉**（软置灰），而不是让用户一路踩到支付失败。
铁律：**零资金副作用** —— 只写 `metadata` + 审计；不取消会话、不改支付/订单/库存，零 provider 调用。

- **状态机**（`PallasTrade::PaymentMethod`，状态存 metadata）：
  - 已选项化 provider → `metadata['options'][i]['breaker']`（**入口级**）；未选项化 → `metadata['breaker']`（单入口）。
  - 字段：`opened_at` / `until` / `reason` / `manual` / `failure_rate` / `sample_size`。
  - `soft_disabled?(kind = nil, now:)` —— 手动置灰（`manual: true`）**粘性**（生效至人工解除）；
    自动置灰**到期即失效**（状态行由 `Evaluate`/`SweepJob` 清理）。
  - 写入口：`soft_disable!(kind:, reason:, manual:, until_at: nil, ...)` / `soft_enable!(kind = nil)`；
    底层 `update_columns(private_metadata:)`（不触发 provider 校验/远端调用）。
  - 阈值：`breaker_thresholds` = 默认 `{ min_samples: 10, failure_rate_threshold: 0.5, cooldown_seconds: 900 }`
    + `metadata['breaker_thresholds']` 覆盖。
- **指标口径**（`Payments::Health::Metrics.call(payment_method:, window: 24.hours, now:)`，卡面/判定**唯一口径**）：
  `attempts`（窗口内 `PaymentSession` 行数）/ `failed`（status = failed；canceled/expired 不计）/ `failure_rate` /
  `avg_seconds`（终态会话 `updated_at - created_at` 近似；无终态 = nil）/ `top_error_codes`
  （入站事件 `action='failed'` 的 `last_error_class` Top5）。
  ⚠️ **粒度是 provider 级**：会话不持久化入口（`PaymentSessions::Start#option_kind` 只做建会话前校验，D8），
  入口级失败率无数据来源 → 自动判定按 provider 级聚合，对**全部生效入口**落状态；入口级粒度体现在状态与手工动作。
- **判定/恢复**（`Payments::CircuitBreaker::Evaluate.call(payment_method:, now:)`，返回 `{ opened:, restored:, observed: }`）：
  样本 ≥ `min_samples` 且失败率 ≥ 阈值 → 自动软置灰 `cooldown_seconds`（审计 `payment_option_auto_soft_disabled`）；
  到期且非手动 → 自动恢复（`payment_option_breaker_restored`）；未达标/小样本/冷却中 → 不动（幂等）。
- **巡检**：`Payments::CircuitBreaker::SweepJob`（`config/sidekiq_schedule.rb` 每小时 `15 * * * *`，
  name `payment_circuit_breaker_sweep`）；单个 provider 异常只 warn 不中断；`perform(now:)` 传 **Time**（传字符串精度只到秒）。
- **前台/Start 门禁**：`Availability::Resolver#option_allowed?` 先判 `soft_disabled?` → 软置灰入口从
  「可用入口」消失（前台列表与 `PaymentSessions::Start` 同源）；`Resolver.evaluate` 额外给
  `{ dimension: 'breaker', reason: 'breaker_open' }` 便于解释「为什么这个入口没出现」。
- **后台**：provider 编辑页「熔断与健康」卡（24h 指标 + 逐入口状态/动作）；
  `POST /admin/payment_methods/:id/soft_disable`（**必填 reason**，`manual: true` 粘性）/ `soft_enable`，
  两者写审计（`payment_option_manually_soft_disabled` / `payment_option_manually_soft_enabled`），权限 = 资源 `update`。
- **回归**：`harness verify d11-circuit-breaker-rspec`。

## Payment availability scope —— 适用范围引擎（D8 首版, 2026-09-15；PRD-20260915-payments-d8）

入口（PaymentOption）级可用范围，栖于入口层 `metadata['options'][i]['rule_set']`（业务方案 §66）：

- **规则集**：`{ match: "all"|"any", include: [cond], exclude: [cond] }`，`cond = { dimension, operator, values }`；
  **维度上线 4/14**：`market` / `country` / `zone` / `currency`（§66.1 余下 10 个维度待续）。
  归一在 `PallasTrade::Payments::Availability::RuleSet`（读/写都过一遍）：market/zone 用**原始 ID**、
  country/currency 用**大写 ISO**；非法维度/算子/空 values 丢失；`exclude` 命中即排除；**无规则 = 全局可用**。
- **求值**：`Availability::Resolver` 组合「Provider 级 scope（`frontend` / `back_end`）+ 入口级 `rule_set` +
  目录收窄（provider 声明 `currencies`/国家时）」；`Context` 从订单取四维上下文（country 由国家 + 州成员
  推导、zone 含 `order.market.tax_zone`），`Evaluator` 返回 `{ allowed:, reasons: [{dimension, operator,
  values, observed, outcome}] }`（**可解释**，排障可读）。
- **同源硬约束（§66.5）**：`Order#payment_methods`（前台/后台收集）与 `PaymentSessions::Start`（入口级门禁）
  **必须**用同一份 `Resolver` 求值——禁止任何一侧自算（『选得上、付不了』的根因防线）。
- **失败语义**：Start 判不可用 → 422 `payment_option_not_available`（**不建会话**）；前台收到该码 →
  刷新支付方式列表 + 提示重选（不得拿旧列表重试）。
- **零回归**：无 `rule_set` 的 provider / 未选项化 provider / 无 market 上下文的店铺 → 行为与 D8 前一致。
- **回归**：`harness verify d8-availability-rspec`。

## 3DS / SCA —— 认证策略、订单级判定与 provider 下发（D15 切片3, 2026-09-17；PRD-20260917-checkout-d15-切片3）

业务方案 §72.1 落地：「要不要挑战」从「provider 默认值」变成**商家可配置策略 + 订单级风险决策 → 单一判定 → 入口闸门 → provider 下发**的闭环（§78-D15 验收锚点：**高风险订单只给 redirect+3DS**）。**零迁移**（全部落在既有 jsonb）。

- **策略（store 级，唯一读/写口径）**：`Payments::ThreeDSecure::Policy`，存 `store.private_metadata['three_d_secure_policy']`（与 `dispute_rate_policy` 同先例）。
  - `mode`：`always` / **`risk_based`（默认）** / `off`；`low_amount_threshold`（**仅订单币种 == 店铺默认币种**时参与比较，否则记 `threshold_skipped='currency_mismatch'`，**不跨币种猜**）；`allowlisted_countries`（ISO-2）；`allowlisted_option_kinds`（入口白名单）。
  - **两条路径语义不同**：`normalize`（读）**永不抛错** —— 运营写坏一个键不能让结账 500，非法值回落默认并记 `reasons`；`storable`（写）用于后台表单校验，非法值返回 `errors` **不落库**（未知 `mode` / 负阈值 / 非法国家码）。
  - 保存写审计 `store_three_d_secure_policy_updated`。
- **订单级判定（唯一入口、只读、零 provider）**：`Payments::ThreeDSecure::Required.call(order:, store:, risk_action:, now:)` → `{ required:, mode:, source: 'policy'|'risk_rule'|'policy+risk', reason:, exemptions:, exemption_policy:, risk_action:, policy_off_overridden_by:, threshold_used:, threshold_skipped: }`。
  - 语义（写死）：`always` → 是（豁免可放宽为否）；`risk_based` → **仅当**最近一次 `PaymentRiskAssessment` 的决策是 `force_3ds` 时为是；`off` → 否，**但显式 `force_3ds` 优先**（`policy_off_overridden_by='risk_rule'`，且此时**不评估豁免**）。
  - 请求内复用：`Required.for_order(order)` 以「最新留痕 `[id, decision]`」为指纹缓存 —— **N 个入口只查一次**（NFR：查询数不随入口数增长）；评估/策略变化后调用 `Required.reset_cache_for(order)`。
- **规则动作**：`force_3ds`（见 `pallastrade-security` SKILL「3DS/SCA 认证需求」——严重度 `allow<review<force_3ds<block`，`force_3ds` 覆盖 `review`、不覆盖 `block`，白名单 `allow` 仍短路）。
- **入口闸门（扩展 D8 同源求值，不新建第二套筛选）**：`Availability::Resolver` 逐入口多出一个原因维度 `{ dimension: 'three_d_secure', reason: 'authentication_required' }`；认证需求 = 是 → 只保留**入口目录声明 `three_d_secure: 'supported'`** 的入口（**未声明按 unsupported 处理，不猜**）。
  - 前台列表（`Order#payment_methods` 投影）与 `PaymentSessions::Start` **自动同源生效**：客户端绕过 → 建会话**前** 422 `payment_option_not_available` + `reason='authentication_required'`（**不新增错误码家族**，沿用 D8 的「刷新列表 + 重选」约定），**零 session 行**。
  - 「一个入口都没有」时**不静默空白**：契约给 `requires_authentication` 标志，前台显式提示；**不**自动降级到弱认证入口。
- **provider 下发（诚实优先）**：`Payments::ThreeDSecure::ProviderHint.call(payment_method:, option_kind:, required:)`：
  - 入口声明 `three_d_secure: 'supported'` 且要求认证 → `{ applied: true, hint: 'three_d_secure', external_data: { 'three_d_secure' => true } }`；Stripe 把它落到 `payment_intent_data.payment_method_options.card.request_three_d_secure = 'any'`（`CheckoutSessionPresenter` 透传），会话 `metadata` 记 `three_d_secure_hint`；
  - `unsupported` / 不认识的入口 / 未要求认证 → `{ applied: false, hint: 'none' }`，**绝不发送 provider 不认识的参数**（宁可不下发）；无法强制认证的入口**本来就不可选**（由闸门保证），所以不存在「静默跳过」。
- **契约**：checkout 投影的支付方式项新增 `requires_authentication`（布尔，additive；隐藏 = 不出现）；Typelizer 生成的 `StoreCheckoutCheckout` 类型随契约更新（`harness generated:check` 零漂移；平台副本由 `scripts/ci/contracts.sh` 同步）。
- **后台**：门店编辑页「3DS / SCA 策略」区块（模式 + 阈值 + 两个白名单，en↔zh-CN 键集相等）+ 支付方式入口表**只读**「可强制认证」列（来自 catalog）。
- **铁律**：判定与闸门**零 provider I/O、零写库、零资金副作用**；不改 `Checkout::Preflight` 的启用条件与阻断行为；不改「支付成功 → 订单完成」链路；MIT 豁免、其它 provider 落地、挑战率看板属后续切片。
- **回归**：`harness verify d15c-three-d-secure-rspec`（181 例；含 D8 / D11 / D16 / 契约 / 切片1·2 回归 + 导航）。

## 风控看板与阈值告警 —— 5 水位读模型 + 双档阈值（D3, 2026-09-17；PRD-20260917-payments-d3）

业务方案 §78-D3 / §60.2-P3 落地：运营要「一眼看清 5 个水位」，但**看到数字 ≠ 知道真相** —— 空窗口或报表降级时，页面必须能说「我不知道」。

- **只读读模型（唯一口径）**：`Risk::DashboardReport.call(store:, window_days:, now:)` → `success(scope:, policy:, metrics:, evaluated_at:, degraded:)`；`metrics` = 5 个 `{ key, value, unit, available, reason, window, detail, sources }`。
  - `risky_orders`（bps）= 窗口内 `PaymentRiskAssessment.flagged` 去重订单 / `store.orders` 已提交数。
  - `three_ds_challenge_rate`（bps）= 窗口内会话数中 `external_data ->> 'three_d_secure_hint' = 'three_d_secure'` 的占比（D15c 下发留痕）。
  - `dispute_rate`（bps）= **委派** `Disputes::RateReport`（D14c 唯一权威，**禁止重算**）；抽出 `rate_report` 接缝以便规格注入失败/降级。
  - `refund_rate`（bps）= 窗口内 Refund 金额 / 同窗口 `completed` Payment 金额。
  - `review_queue_duration`（minutes）= 当前 `manual_review` 交易**排队最久** + 窗口内已处理（D2 裁决审计）**P90**。
- **不可判定不猜（铁律）**：分母为 0 / 报表降级或失败 → `value: nil`、`available: false`、`reason` ∈ `no_denominator` / `report_unavailable` / `report_degraded:*`；**绝不回落 0**（0 在本页语义 = 健康）。整页级降级（如 `store_missing`）走 `degraded_envelope`（5 行仍齐、全 unavailable）。
- **阈值策略（store 级，`private_metadata['payment_risk_dashboard_policy']`）**：`Risk::DashboardPolicy` —— `window_days`（1..365）+ 每指标 `{ enabled, warning, critical }`。
  - `storable`（写）拒绝 `unknown_metric` / `warning_not_below_critical` / `out_of_range` / `invalid_type` 且**不落库**；`initialize`（读）**fail-safe**（坏载荷回落默认 + `reasons`，绝不让结账/看板 500）。
  - `configured?(key)` 要求 **warning 与 critical 双档都显式存在** —— 只配一档 = **未配置 = 不判定**（不是「通过」）。默认开启仅 `dispute_rate` + `review_queue_duration`。
- **判定**：`Risk::DashboardThreshold.classify(metrics:, policy:)` → 每指标 `ok / approaching / breached / unconfigured / unavailable`；**只对 `approaching` / `breached` 告警**（`unconfigured` 与 `unavailable` 是两种不同的「无可奉告」）。
- **留痕与幂等**：`Risk::DashboardAlert.call(store:, now:, window_days:, report:)` —— **档位变差才写**（同日重复 sweep 幂等；同日**绝不降档** `no_downgrade_same_day`）；审计 `payment_risk_dashboard_threshold`（before/after + metadata：metric/status/value/unit/两档阈值/direction），事件 `payments.risk_dashboard_threshold`（**无 PII**；`Events.enabled?` 守卫 + rescue —— 发不出去不影响巡检）。
- **巡检**：`Risk::DashboardAlertSweeperJob`（`risk_dashboard_alert_sweep`，每小时 `5 * * * *`，见 `backend/config/sidekiq_schedule.rb`）—— 逐店隔离（单店失败只计 `failed`）+ 指标 JSON 日志；`store_id:` 可单店重跑。
- **铁律**：**零写库**（除审计留痕）、**零 provider I/O**、**零资金副作用**；查询数固定（不随行数增长）；跨店隔离（全部按 `store` 收窄）；不改前台支付可用性（`Availability::Resolver` 不读该策略）。
- **回归**：`harness verify d3-risk-dashboard-rspec`。

## manual_review 人工裁决 —— 排障台的「通过并捕获 / 拒绝并释放」（D2, 2026-09-17；PRD-20260917-payments-d2）

业务方案 §78-D2 / §60.2-3 落地：`manual_review` 以前**只能 console 改状态**（自动恢复对它是禁区），现在有了**唯一的人工出口**——排障台两个动作，且证据链完整（谁、何时、为何、前后状态）。

- **服务（唯一入口，纯人工）**：`PallasTrade::Transactions::Review.call(transaction:, decision:, reason:, actor:, provider_reference:)`。
  - `decision='capture'`（通过并捕获）：要求存在**已授权未捕获**（`pending`）的 Payment → `Payment#capture!`（provider 真实捕获）→ `approve_after_review!`（新边 `manual_review → finalizing`）→ **既有** `Transactions::Finalize`（参与者订单完成 + 库存 commit）→ 交易 `completed`。
  - `decision='release'`（拒绝并释放）：**不捕获** → `Payment#void_transaction!` 撤销未捕获授权（**任一笔撤不掉 → 整条回滚**，不静默留枚可用授权）→ 逐参与者订单 `Orders::Cancel`（既有原语：库存释放 + 取消台账；`refund_payments: false` → **零退款**）→ `release_after_review!`（新边 `manual_review → canceled`）。
  - **不猜的拒绝**：无 pending 授权 → `no_pending_authorization`（capture 拒绝）；存在已捕获 Payment → `paid_payment_present`（release 拒绝，必须走 `Refunds::Request`）。两者都**不改状态**。
  - `reason` **必填**；只接受 `state == 'manual_review'`（其它状态 → `transaction_not_reviewable`；自动恢复仍走 `Transactions::Recover`）。
- **幂等键 = `(transaction, decision)` 的审计成功行**：重放返回 `already_applied: true`、零副作用（**幂等判定在状态守卫之前**，否则捕获后重放会误报不可复核）。
- **审计（成功与失败都写）**：`transaction_review_captured` / `transaction_review_released` / `transaction_review_failed`，带 `before/after` 状态、`decision`、`reason`、操作人、`provider_reference`；释放另记 `voided_payment_ids` / `canceled_order_numbers`。
- **取消原因枚举 vs 自由文本**：`OrderCancellation#reason` 是枚举（`customer/declined/fraud/inventory/staff/other/expired`）——人工裁决一律归 `staff`，操作人自由文本写 `note` + 审计（**不污染枚举语义**）。
- **状态机**：只**新增两条出向边**（`approve_after_review` / `release_after_review`），`reopen_review` 与自动恢复边**不动**；两者都在 bang 事件表内（非法迁移抛 `InvalidTransitionError`）。
- **后台**：`/admin/transactions/:id/approve_and_capture` 与 `/release_and_cancel`（member POST，与 `recover` 同权 → `:update` 授权），详情页复核卡（原因必填 + double confirm + 复核历史表；非 `manual_review` 只给说明**不给按钮**）。
- **铁律**：**人工专用** —— job / sweeper / subscriber **永不调用**（spec 断言调用点唯一）；不新建交易、不新建 PaymentSession、不碰 `PaymentSessions::Start`；历史 Payment / Refund / 账本行零改写。
- **回归**：`harness verify d2-manual-review-rspec`（含状态机 / 后台交易页 / Recover·Finalize 回归；110 例）。


- D8 (2026-09-15, PRD-20260915-payments-d8): Payment availability scope —— 入口级 `rule_set`
  （market/country/zone/currency 首版 4 维度）+ `Payments::Availability::{RuleSet,Context,Evaluator,Resolver}`
  + `Order#payment_methods` 三处投影接入 + `PaymentSessions::Start` 入口级同源门禁（422
  `payment_option_not_available`，不建会话）+ 后台「适用范围」编辑/摘要 + admin API `options[].rule_set` /
  `scope_summary`。零 migration（`private_metadata` additive）。

- DSP-P7-8 (2026-09-13, PRD-20260913-payments-dsp-p7-8): Dispute 危险操作与证据提交 —— provider 写契约
  （`submit_dispute_evidence` / `accept_dispute`，capability-gated）+ 证据目录（Stripe 16 文本 + 8 文件键）+
  `Disputes::SubmitEvidence` / `Disputes::AcceptDispute` 编排 + 不可变回执表 `pallastrade_dispute_evidence_submissions`
  （1 个 migration）+ 控制台危险操作卡（双重确认）。铁律：**零资金副作用**，状态仍由 webhook/收敛推进；
  Adyen/PayPal 适配延后至凭证齐备。

- DSP-P7-7 (2026-09-13, PRD-20260913-payments-dsp-p7-7): Dispute Admin Console——`/admin/disputes` 列表（注册表
  驱动 + Ransack 白名单 + `for_store` 隔离）与七卡详情（P7-1…P7-6 只读投影，异常降级不 500）；5 个动作全部叠在
  既有服务上（refresh / dry_run / snapshot / recover / mark_review），其中 `recover` 是唯一可写动作且仍然只修事实；
  新增 `Disputes::MarkManualReview`（`operator_review` + 审计，幂等只补不覆盖）。无 migration；Accept/Submit Evidence
  属 P7-8，本切片不提供路由/按钮。

- DSP-P7-1 (2026-09-11, PRD-20260911-payments-dsp-p7-1): Dispute durable 模型与 provider 事件入口——
  `pallastrade_disputes`/`PallasTrade::Dispute`（幂等 upsert + 阶段序状态机 + attention_reason）；
  `charge.dispute.*` 五事件订阅/映射/parse 分流；`HandleWebhookJob` 按族分派到
  `Disputes::HandleProviderEvent`（复用 P0 dedupe/replay）；无锚点不丢事件；零业务副作用。

- FIN-P4-8 (2026-09-06, PRD-20260906-payments-fin-p4-8): Repair/Legacy/Operations——`FinancialLedger::
  RepairTransaction`（Journal 幂等补记，委托 PostPayment/Refund/Allocation；绝不重 Payment/Refund）+
  `Reconciliations::ReconcileSweeperJob`（保守自动：journal-missing 自动 repair、mismatch/attention 仅
  warn）+ `RepairTransactionJob` + `reconciliations.rake`（list/reconcile/repair/backfill 三类 §50）+
  `docs/operations/financial-reconciliation-runbook.md`。无 migration；admin UI/timeline/audit 目录范围外。
  详见上文 §Repair / Legacy / Operations。

- FIN-P4-7 (2026-09-06, PRD-20260906-payments-fin-p4-7): Transaction Reconciliation——`Reconciliations::
  {ReconcileTransaction, TransactionResult, TransactionFinancialSummary}` 交易级只读聚合与核对（local 面权威 =
  immutable Journal by_transaction 按 entry_type 聚合；provider 面复用 P4-6 逐源；§38 核对矩阵 + 六态合成 +
  JOURNAL_POSTING_MISSING/short-paid 语义；SourceResult additive +provider_fee/provider_net）。零写零 mutation
  幂等；不落表（P4-8）；无 migration/API。详见上文 §Transaction Reconciliation。

- FIN-P4-6 (2026-09-06, PRD-20260906-payments-fin-p4-6): Source Reconciliation——`Reconciliations::{SourceResult,
  ReconcilePayment, ReconcileRefund}` 只读源级核对（local captured 判定 = CaptureEvidencePolicy；六态
  PENDING/MATCHED/MISMATCH/NEEDS_ATTENTION/NOT_APPLICABLE/UNSUPPORTED；provider 异常捕获不 raise）+ 
  `PaymentMethod#fetch_refund_details` base 契约 + Stripe `retrieve_refund`/`fetch_refund_details`
  （re_ → Refund，cents→元）+ `Gateway::Bogus` 确定性替身。零写/零 mutation/幂等可重跑；SourceResult 不落表
  （P4-7/8 持久化）；无 migration/API。详见上文 §Source Reconciliation。

- FIN-P4-5 (2026-09-06, PRD-20260906-payments-fin-p4-5): Stripe Provider Financial Facts——`fetch_financial_details` 只读契约（core base + Stripe cs_/pi_ 双模式：PI→Charge→BalanceTransaction→Refunds 归一，fee/net 从 BT、ch_/txn_/re_ refs 补齐 P4 §33；+retrieve_balance_transaction）+ `Gateway::Bogus` 确定性替身 + `FinancialFacts::ProviderFinancialDetails` VO + `provider_reconciliation_capability` 翻转（Stripe/Bogus→SUPPORTED）。fee/net=reconciliation fact 不进 Journal；快照不落表（P4-6）；无 migration/API。详见上文 §Stripe Provider Financial Facts。

- FIN-P4-4 (2026-09-06, PRD-20260906-payments-fin-p4-4): Allocation Integrity——FinancialFact 扩展
  `payment_split_id` + `ORDER_ALLOCATION`；`FinancialFacts::ResolveAllocation` + `FinancialLedger::PostAllocation`
  （显式稳定幂等 key）/`PostCombinationAllocations`/`AllocationIntegrity`（Σ active ORDER_ALLOCATION == Σ split.captured）；
  `PaymentCombinationSucceededSubscriber` 接线（payment_combination.succeeded）。ORDER_ALLOCATION = 归属投影非 cash
  （AC-4013）；无 migration（payment_split_id 列 P4-2 已建）。详见上文 §Allocation Integrity。

- FIN-P4-3 (2026-09-06, PRD-20260906-payments-fin-p4-3): Payment/Refund Posting 接线——`FinancialLedger::{PostPayment,PostRefund}` 编排（Resolve → 门禁 `Post.postable?` → 幂等 Post；不可 post → skipped success 不猜）+ `PaymentPaidSubscriber`(payment.paid after_commit)/`RefundCreatedSubscriber`(refund.created lifecycle after_commit) 注册 core engine.rb；posting 恒在资金事务提交后、幂等可重试、失败不逆转支付。无 migration/API；splits/ORDER_ALLOCATION 归 P4-4。详见上文 §Payment/Refund Posting。

- FIN-P4-2 (2026-09-06, PRD-20260905-payments-fin-p4-2): Immutable Financial Journal——新表
  `pallastrade_financial_ledger_entries` + `FinancialLedgerEntry`（append-only/ImmutableError/幂等 key/reversal
  自引用/state）+ `FinancialLedger::{Post,Reverse}` 原语（输入 = FIN-P4-1 FinancialFact，不判断 payment.state）。
  本包不接业务接线（P4-3）；详见上文 §Immutable Financial Journal。无 API/UI。

- FIN-P4-1 (2026-09-06, PRD-20260905-payments-fin-p4-1): Financial Fact Resolution 只读语义层——
  `PallasTrade::FinancialFact`（Value Object）+ `FinancialFacts::{InstrumentClassifier, CaptureEvidencePolicy,
  OwnershipResolver, ResolvePayment, ResolveRefund, RetryPaymentSafetyPolicy}`。Payment.state 不再直接等于现金事实：
  manual authorize(pending)→AUTHORIZED_ONLY、completed+capture_event 或组合 succeeded→CASH_CAPTURED、
  证据缺失→AMBIGUOUS、StoreCredit/Check→非 PSP fact；禁 PSP reference 推断 CommerceTransaction；
  FIN-P4-2 Journal 唯一 posting input contract（详见上文 §Financial Fact Resolution）。无 migration/API。

- TXN-P2-7 (2026-09-05, PRD-20260905-payments-txn-p2-7): Operational Hardening 后端切片——`CommerceTransaction.needs_attention(stuck_after:)`（recovery_required/manual_review 恒含 ＋ payment_confirmed/finalizing 超龄 stuck）+ `#trace`（时间戳/attempts/last_error/participants/sessions 摘要读模型）＋ rake `pallastrade:transactions:{list_needs_attention,recover[id]}`（manual recovery tooling，委托 Transactions::Recover）＋ `docs/operations/transaction-recovery-runbook.md`。
- TXN-P2-7 slice2 (2026-09-05, PRD-20260905-payments-txn-p2-7, REQ-20260905-txn-p2-7-admin-sweeper): Admin Transactions 资源页（Orders → Transactions：index store 作用域列表 + metrics 汇总卡 recovery_required/manual_review/stuck、show trace、recover 按钮→enqueue `RecoverJob`；controller 镜像 email_logs/contact_messages；PermissionRegistry `:transactions` read/update）＋ 保守自动 sweeper `Transactions::RecoverSweeperJob`（sidekiq-cron */5：仅 recovery_required 自动 enqueue RecoverJob；manual_review/stuck 只计数+warn 日志，人工介入，AC-2014/INV-04）+ `Store has_many :commerce_transactions` + host schedule 条目。
- TXN-P2 组合 txn 化 (2026-09-05, PRD-20260905-checkout-paymentcombination-txn-化): PaymentCombination 创建即建 durable CommerceTransaction（purpose=combined_payment + 每 unpaid 成员 TransactionOrder（primary=primary_order）+ session.transaction_id/txn.payment_combination 回填）；PSP 成功统一经 `Transactions::OnPaymentSuccess` → `Transactions::Finalize` 组合分支——入账提取为幂等 `PaymentCombinations::Settlement`（组合单 Payment(order_id=nil)+splits 回填+成员 payment_total+combination succeed），再逐成员 CombinationMemberComplete；资金入账但成员未完成 → txn `recovery_required`（INV-03，取代 SettleJob 于 txn 路径，Recover/Admin/sweeper 幂等收尾）。`PaymentCombinations::Complete`/`CombinationSettleJob` 保留为 legacy 非 txn 组合适配器（Strangler）。webhook/stripe/orders#complete 组合分支收敛 OnPaymentSuccess。

- TXN-P2-5 (2026-09-04, PRD-20260904-payments-txn-p2-5): Unified Finalization——`Transactions::Finalize`（canonical：payment_confirmed→begin_finalizing / recovery_required[已 paid]→retry_finalizing → 锁外逐参与者完成（委托 CombinationMemberComplete）→ complete!；失败→mark_recovery_required!+last_error，资金不回滚；已完成幂等短路）＋ `Transactions::OnPaymentSuccess`（Transaction Payment Handler 首版：组合→PaymentCombinations::Complete；带 commerce_transaction 会话→confirm_payment!+Finalize；无 txn legacy→Carts::Complete 行为不变，Strangler）。Webhook handle_success 单订单分支与 orders/payment_sessions#complete 接线；Recover PAID+incomplete 收口委托 Finalize。

- TXN-P2-4 (2026-09-04, PRD-20260904-payments-txn-p2-4): Recovery Engine——CommerceTransaction 状态机 recovery 出口（retry_payment/retry_finalizing/repair_completed，INV-02 保持 payment_confirmed→payment_pending 禁止）+ `Transactions::Recover`（锁内守卫 recovery_required/finalizing → attempt++ → PaymentFactResolver 权威判定 → UNPAID→retry_payment / AMBIGUOUS→manual_review / PAID→repair_completed 或锁外幂等 finalize 参与者（委托 CombinationMemberComplete：standard→Carts::Complete / legacy→Checkout::Complete）→ retry_finalizing+complete；失败写 last_error 保留 recovery_required，资金不回滚）+ `Transactions::RecoverJob`。先确认资金事实再行动（§26，绝不盲重试）；TXN-P2-5 将 finalize 收口为 Transactions::Finalize。

- TXN-P2-3 (2026-09-04, PRD-20260904-payments-txn-p2-3): Provider **只读**状态契约 `PaymentMethod#fetch_payment_status(payment_session:)` → 规范化 `{status:, amount_cents:, currency:, provider_reference:}`（基类 NotImplementedError；Stripe 实现复用 retrieve_checkout_session/retrieve_payment_intent，pi_/cs_ 双模式映射 paid/unpaid/processing/requires_capture/requires_action/canceled，零写库零状态变更；Bogus 确定性映射供测试）+ `Transactions::PaymentFactResolver#call(transaction:, provider_query:)` 判定 `paid/unpaid/ambiguous`（reasons/provider_results）。判定语义：本地 completed Payment（金额匹配）short-circuit PAID；session completed 但 Payment 缺失 → provider 权威确认；全部终态失败/无 attempt → unpaid；进行中/待捕获/部分入账/不可达 → ambiguous（不猜，交 manual_review）。P2-4 Recovery/P2-5 Finalize 消费；无 API 面。

- TXN-P2-2 (2026-09-04, PRD-20260904-api-txn-p2-2): PaymentSession 归属 durable CommerceTransaction（`transaction_id` 可空 FK + index，存量 NULL 不回溯）；`Transactions::Start` 复用 PaymentSessions::Start（透明 Refresh 后 expected 传 nil）；session = transaction 的支付 attempt（一 transaction 多 session 语义基础）。

- RISK-01 (2026-09-04): 组合成员完成 primitive 分流——新增 `Payments::CombinationMemberComplete`（standard 成员→`Carts::Complete`，legacy 成员→`Checkout::Complete`），`PaymentCombinations::Complete` 阶段 2 与 `CombinationSettleJob` 共用；修复账户 2+ 单合并收银台对 standard pending 成员"资金已入账、订单永不完成"缺陷（TXN-P2-0 §10 运行时验证）。

- P0 (2026-09-03, PRD-20260902-payments-p0-foundation-hardening): PaymentSession-Payment 正式 FK(payment_session_id)；Webhook Event Store/Dedup/Retry/Replay(pallastrade_payment_webhook_events)；Express 幂等复用 PaymentSessions::Start(REUSE_WINDOW/operation_key 含 amount)；Cart#express_payment 服务端金额权威；Gateway preferences AR-Encryption(ACTIVE_RECORD_ENCRYPTION_* + rake encrypt_preferences/verify)；AuditLog/Audit.record + ErrorCodes canonical 映射；Legacy=Compatibility Only(payment.legacy_flow.used)。**B5（2026-09-15）补充**：cart 域支付会话/支付的 legacy 身份（非 `cart_`）同时拿到 `Deprecation: true` / `Warning: 299` / `Link: rel="successor-version"` 三头，日志字段统一为 `{flow_type, entry_point, requested_cart_id, legacy_identity, action, deprecated, canonical_successor}`；`payment.legacy_flow.used` key **不变**。退役阀值：连绞 30 天 legacy 计数为 0 后可独立立项删除（§46）——服务语义本批零变更。。详见 docs/payment/。
- CHK-P1-3 (2026-09-03): PaymentSessions::Start 新增 quote 作用域 Payment Start Gate（过期自动 Refresh / 就绪拦截 checkout_not_ready；无 quote/legacy/completed 账户补付直通）；新会话 external_data 记录 price_version + quote_refreshed；幂等/reuse/operation_key/reconcile 不变。
- CHK-P1-5 (2026-09-04): PaymentSessions::Start 可选 expected_version/expected_price_version → 不匹配 409 `checkout_version_conflict`（含 latest{version,price_version,expires_at,amount_due,display_amount_due}）；幂等/reuse/operation_key 不变；409 前端消费留 P1-4B/4C。
