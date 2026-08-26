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

## Where to read further

- **Payment source:** `bundle show pallastrade_core`/app/models/pallastrade/payment.rb — the state machine and processing methods.
- **Payment processing:** `PallasTrade::Payment::Processing` concern — `process!`, `authorize!`, `purchase!`, `confirm!`, `capture!`, `void_transaction!`, `cancel!` methods.
- **PaymentSession:** `PallasTrade::PaymentSession` — the 5.4+ redirect-flow wrapper.
- **Docs:** `node_modules/@pallastrade/docs/dist/developer/core-concepts/payments.md` (the how-to companion is `dist/developer/how-to/custom-payment-method.md`).
- **Stripe gem:** `https://github.com/stevenbian9266-cyber/pallastrade` — best reference for a real-world payment integration.
