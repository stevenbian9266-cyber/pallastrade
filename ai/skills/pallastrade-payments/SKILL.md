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

## Gift cards

`PallasTrade::GiftCard` is built-in (5.x). Each gift card has a redemption code and a remaining balance. Customers can apply at checkout; partial redemption is supported.

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
- **Refunds::Execute**（`services/pallastrade/refunds/execute.rb`，v1 同步）：claim（payment 锁内重校验
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

## Where to read further

- **Payment source:** `bundle show pallastrade_core`/app/models/pallastrade/payment.rb — the state machine and processing methods.
- **Payment processing:** `PallasTrade::Payment::Processing` concern — `process!`, `authorize!`, `purchase!`, `confirm!`, `capture!`, `void_transaction!`, `cancel!` methods.
- **PaymentSession:** `PallasTrade::PaymentSession` — the 5.4+ redirect-flow wrapper.
- **Docs:** `node_modules/@pallastrade/docs/dist/developer/core-concepts/payments.md` (the how-to companion is `dist/developer/how-to/custom-payment-method.md`).
- **Stripe gem:** `https://github.com/stevenbian9266-cyber/pallastrade` — best reference for a real-world payment integration.

## Changelog (P0 Payment, 2026-09-03)

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

- P0 (2026-09-03, PRD-20260902-payments-p0-foundation-hardening): PaymentSession-Payment 正式 FK(payment_session_id)；Webhook Event Store/Dedup/Retry/Replay(pallastrade_payment_webhook_events)；Express 幂等复用 PaymentSessions::Start(REUSE_WINDOW/operation_key 含 amount)；Cart#express_payment 服务端金额权威；Gateway preferences AR-Encryption(ACTIVE_RECORD_ENCRYPTION_* + rake encrypt_preferences/verify)；AuditLog/Audit.record + ErrorCodes canonical 映射；Legacy=Compatibility Only(payment.legacy_flow.used)。详见 docs/payment/。
- CHK-P1-3 (2026-09-03): PaymentSessions::Start 新增 quote 作用域 Payment Start Gate（过期自动 Refresh / 就绪拦截 checkout_not_ready；无 quote/legacy/completed 账户补付直通）；新会话 external_data 记录 price_version + quote_refreshed；幂等/reuse/operation_key/reconcile 不变。
- CHK-P1-5 (2026-09-04): PaymentSessions::Start 可选 expected_version/expected_price_version → 不匹配 409 `checkout_version_conflict`（含 latest{version,price_version,expires_at,amount_due,display_amount_due}）；幂等/reuse/operation_key 不变；409 前端消费留 P1-4B/4C。
