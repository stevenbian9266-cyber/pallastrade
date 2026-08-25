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

## Payment groups (5.6+) — combined payment across orders

> PALLAS-CUSTOM: PRD-20260823-checkout-多订单拆分与合并支付.

`PallasTrade::PaymentGroup` (`pg_`) bundles multiple unpaid orders into **one** payment:
one Stripe PaymentIntent covers every member order, and a single successful
webhook completes them all. This powers "合并支付" (combined payment) and
checkout-time/admin order splitting.

```
Order A (unpaid) ─┐
Order B (unpaid) ─┼─ PaymentGroup ── PaymentSession (one PI) ── webhook ── all orders complete
Order C (unpaid) ─┘
```

Key facts:

- **Membership** is validated server-side (`PallasTrade::PaymentGroups::Create`):
  same store, same user, same currency; no canceled / already-paid orders.
- **Idempotent reuse (2026-08-24)**: if a selected order is already in an
  *active* payment group (`status` pending/processing and not expired), `Create`
  no longer fails — it reuses the **most recently created** active group and
  merges the selected orders (including ones spread across other groups or not
  yet grouped) into it, recomputing the group `amount`. Groups that become empty
  after the merge are `canceled`. Use `PaymentGroup#active?` for the check.
- **Amount** is always server-computed (`payment_group.total_minus_store_credits`
  = sum of member orders' `total_minus_store_credits`); clients only send order ids.
- **Completion** (`PallasTrade::PaymentGroups::Complete` / Stripe
  `PallasTradeStripe::CompletePaymentGroup`) is idempotent — each member order
  gets its own `Payment` record sharing the group's `response_code`, and only
  unpaid orders are touched; duplicate webhooks and job retries are safe.
- **Non-active session/group tolerance (2026-08-24)**: gateways and jobs must
  never call the non-bang state-machine transition on a session that already
  left `pending/processing` (e.g. a stale retry against an already-`failed`
  session). StateMachines writes *errors* (not exceptions) for invalid
  transitions, so calling `payment_session.complete` unconditionally surfaces a
  bare `Status cannot transition via "complete"` 422 to the client. Always guard
  with `if session.can_complete?` / `if group.can_complete?` before transitioning.
  Storefront renders non-active groups (`failed`/`expired`/`canceled`) as an
  end-state page with no payment form (see `CombinedPaymentContent`).
- **State machine**: `pending → processing → completed`, plus `failed` /
  `canceled` / `expired`; events `payment_group.processing/completed/failed/canceled/expired`.
- **Store API**: `POST/GET /api/v3/store/payment_groups`, nested
  `payment_sessions` (create/show/update/complete). Requires a logged-in customer (JWT).
- **Split provenance + 父子单（PRD-20260824）**: `orders.split_from_id` 记录拆出来源；
  父子单结构用 **`Order#parent_id` 自引用**（未拆单时父=子，用户规则 2）。
  `PallasTrade::Orders::Splitter` 拆分能力（FR-022~039）：
  - **策略** `groups:` 手分组 / `by:` 自动分组（`:warehouse` 按仓 / `:store` 按店铺 /
    `:custom` 钩子 `Config[:auto_split_orders_custom]`）；`allow_paid: true` 支持支付后拆单
    （`PallasTrade::Orders::Splitting::AfterPayment` 在支付组完成后评估，配置
    `Config[:auto_split_orders]` 或店铺级 `preferred_auto_split_orders`）。
  - **跨店手动拆单（FR-027~029）**: group 可为 Hash
    `{"line_item_ids"=>[], "store_id"=>"st_x", "stock_location_id"=>"loc_y"}`；
    目标店无商品 → `SplitterError` → failure `{code: :split_error}`。
  - **资金/税费/运费/促销分摊**: 拆单时子订单继承已付状态（真实 `Payment` 记录）；
    订单级促销 adjustment 复制到子订单（`compute_amount` 基于子订单金额自动按比例分摊，
    需先 `update_columns(item_total:)` 预写列避免 `includes(:adjustable)` 旧列值 bug）；
    shipment 运费按行项目金额比例分摊（父/子订单同步调减，总额守恒）。
  - **子订单可售可发**: inventory_units 跟随行项目转移；复制源订单 shipment
    （stock_location + shipping method），子订单可独立触发发货与售后。
  - **售后父子单（FR-033~036）**: `PallasTrade::Returns::FromParent` 父单售后批量创建
    RA（`[父]+children` 展开，幂等）；Admin API
    `POST /api/v3/admin/orders/:id/return_authorizations(/bulk_from_parent)`。
  - **取消联动（FR-041）**: `PallasTrade::Orders::Cancel(cascade: true)` 父取消联动全部子订单。

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
