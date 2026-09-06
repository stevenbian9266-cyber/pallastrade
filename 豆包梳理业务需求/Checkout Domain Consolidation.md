这版新的 P1 已经按你当前项目真实现状重构：**基于 P0 已完成的支付加固，不再引入独立 CheckoutSession，而是围绕现有 Order 做 Checkout Consolidation。**

你当前 canonical 已经是 `Cart submit → Order → Order-domain Checkout → PaymentSession → Carts::Complete`，标准 Checkout 页面和权威金额也都已经围绕 Order 运转，因此 P1 应补的是 version、readiness、snapshot、server-driven view 和前端收敛，而不是复制一套 Checkout 数据。 

# P1 — Order-centric Checkout Consolidation

> 建议工程内部编号使用 `CHK-P1`，避免与现有“订单流程标准电商改造 P1”串号。

---

# 1. 阶段定位

P0 已完成 Payment Foundation Hardening。

P1 不再建设支付基础，而是围绕现有 Order checkout 建立统一的 Checkout Application Layer。

目标架构：

```text
Cart
↓
Submit
↓
Order
↓
Order Checkout Application Layer
├── CheckoutView
├── Version / Price Version
├── Invalidation
├── Expiration
├── Readiness
└── CheckoutSnapshot
        ↓
    Future OTS
```

支付继续：

```text
Order
↓
PaymentSession
↓
Gateway
↓
Stripe
↓
Payment
↓
Carts::Complete
```

---

# 2. P0 作为 P1 的既有基础

P1 必须直接复用以下 P0 成果：

```text
PaymentSession ↔ Payment 正式关联

Webhook Event Store
Webhook Dedup / Retry / Replay

Express Payment Idempotency

Express Server-authoritative Amount

Secret Protection

Payment Trace / Audit

Standard Flow = Canonical

Legacy Flow = Compatibility Only
```

P1 禁止重新实现上述能力。

---

# 3. P1 核心目标

P1 只重点解决 7 件事：

1. 明确 Order Checkout 数据所有权。
2. 建立统一 Checkout Application Layer。
3. 建立 Server-driven `CheckoutView`。
4. 建立 checkout version / price version。
5. 集中地址、物流、优惠、税、金额的失效和重算规则。
6. 建立 Server-side Checkout Readiness。
7. 建立供未来 OTS 消费的 `CheckoutSnapshot`。

附加目标：

```text
统一 Storefront Checkout 状态

Express 向 Canonical Order Checkout 收敛

治理遗留 Order::Checkout state machine
```

---

# 4. Scope Lock

## P1 实现

* Order Checkout Application Layer
* CheckoutView
* Checkout Version
* Price Version
* Expiration / Refresh
* Invalidation Rules
* Readiness Evaluator
* CheckoutSnapshot
* Internal Snapshot Contract
* Storefront Checkout 收敛
* Express / Legacy Checkout 收敛
* 遗留 `Order::Checkout` usage audit / governance

## P1 不实现

```text
❌ 独立 CheckoutSession 聚合
❌ Checkout 8 张快照表
❌ 新 Pricing Engine
❌ OTS
❌ Saga
❌ Inventory Reserve / Commit / Release
❌ PaymentAttempt
❌ Payment Router
❌ ProviderRegistry
❌ Adyen 新接入
❌ PaymentSession 重写
❌ Stripe Gateway 重写
❌ Payment 状态机重写
❌ Refund / Dispute / Ledger
❌ Money DB migration
❌ 删除 Legacy Flow
```

---

# 5. 数据所有权

正式定义：

```text
Cart
=
购物编辑态

Order
=
Canonical Checkout 商业事实载体

PaymentSession
=
一次支付执行上下文

Payment
=
资金结果

WebhookEvent
=
PSP 事件事实
```

因此：

```text
商品
地址
Shipping
Promotion
Tax
Price
Currency
```

的 canonical checkout 事实继续由：

```text
Order + Existing Associated Models
```

承载。

不得为了 P1 再复制一套同义数据。

---

# 6. Order Checkout Application Layer

新增逻辑层，不一定新增领域实体。

建议职责：

```text
OrderCheckout::View

OrderCheckout::UpdateContact

OrderCheckout::UpdateAddress

OrderCheckout::SelectShipping

OrderCheckout::ApplyPromotion

OrderCheckout::RemovePromotion

OrderCheckout::Refresh

OrderCheckout::Readiness

OrderCheckout::Snapshot
```

实际命名遵守仓库既有风格。

Controller / BFF 不直接编排：

```text
Address
Shipping
Promotion
Tax
Price
Readiness
```

统一交由 Application Layer 处理。

---

# 7. CheckoutView

`CheckoutView` 是 Storefront 唯一主要 Checkout DTO。

目标结构：

```text
order_id

status

version
price_version

items

contact

shipping_address
billing_address

shipping_options
selected_shipping

discounts
taxes

price

ready
missing_requirements

expires_at
```

其中：

```text
price.total
price.currency
```

是 Server authoritative。

Frontend 不重新计算。

---

# 8. Checkout Mutation 模型

当前目标不是：

```text
PATCH address

Frontend:
GET shipping
GET promotion
GET tax
GET order
重新算 total
```

而是：

```text
PATCH address
↓
OrderCheckout Application Service
↓
Update Address
↓
Invalidate dependencies
↓
Recalculate affected data
↓
Evaluate Readiness
↓
Return CheckoutView
```

所有主要 mutation 都返回最新 CheckoutView。

---

# 9. Checkout Version

P1 建立 checkout concurrency contract。

优先检查现有：

```text
lock_version
updated_at
现有 optimistic locking
```

能否复用。

如果不足，再增加 checkout version。

影响 checkout 编辑状态的变化：

```text
contact
address
shipping
promotion
items
```

应产生新 version。

用于阻止：

```text
多标签页覆盖

stale frontend mutation

并发 checkout update
```

错误：

```text
CHECKOUT_VERSION_CONFLICT
```

---

# 10. Price Version

影响真实交易金额的数据变化：

```text
items

quantity

address

shipping method

promotion

tax

currency
```

必须导致新的：

```text
price_version
```

目标：

> 能明确知道某次支付究竟基于哪个价格版本。

长期链路：

```text
Order
↓
price_version
↓
PaymentSession
↓
Payment
```

P1 至少要建立这个 contract。

是否立即把 `price_version` 写入 PaymentSession，需要基于真实代码影响评估；不得为此重写 PaymentSession。

---

# 11. Invalidation Rules

P1 建立集中 dependency graph。

至少：

```text
Items changed
↓
Shipping stale
Promotion re-evaluate
Tax stale
Price stale
Readiness stale
```

```text
Address changed
↓
Shipping stale
Tax stale
Price stale
Readiness stale
```

```text
Shipping selected
↓
Tax may change
Price stale
Readiness stale
```

```text
Promotion changed
↓
Adjustment recalc
Tax may change
Price stale
Readiness stale
```

禁止这些规则继续散落在：

```text
Controller
Storefront component
BFF
Provider code
```

---

# 12. Pricing

P1 不重新实现价格公式。

继续复用现有：

```text
Order
LineItems
Adjustments
Shipping
Tax
OrderUpdater
```

建立的真实结算能力。

如需要统一入口，只增加 facade，例如：

```text
OrderCheckout::Recalculate
```

职责：

```text
调用现有 domain pricing

输出统一 PriceSummary
```

不重新维护第二套算法。

---

# 13. PriceSummary

统一输出：

```text
subtotal

item_discount

order_discount

shipping

shipping_discount

tax

total

currency
```

真实字段可根据当前 Order 数据模型调整。

必须保持：

```text
Server total
=
唯一 authoritative total
```

---

# 14. Shipping

继续复用现有：

```text
fulfillment
shipping rate
delivery method
shipment
```

能力。

P1 重点建设：

```text
统一 quote/select contract

address/item change invalidation

CheckoutView presentation
```

选择 Shipping 后，CheckoutView 至少能表达：

```text
method
service level
amount
currency
ETA
```

不额外造一套 Checkout Shipping 表，除非现有模型无法表达必要事实。

---

# 15. Promotion

继续复用现有：

```text
Promotion
Adjustment
DiscountCode
```

P1 不重写 Promotion Engine。

Checkout Application Layer 负责：

```text
apply
remove
re-evaluate
present
```

并保证 Promotion 改变后：

```text
price_version
```

正确更新。

---

# 16. Tax

继续复用现有 Tax 能力。

P1 负责：

```text
何时 stale

何时重新计算

如何进入 CheckoutView

如何进入 CheckoutSnapshot
```

地址、Shipping、Promotion 改变时必须按真实业务规则重新验证 Tax。

---

# 17. Checkout Expiration

需要建立报价有效性概念。

优先评估现有 Order / Cart 是否已经具备可利用的时间语义。

最终需要表达：

```text
expires_at
```

但是：

```text
Order expired
```

不能等价于：

```text
Order canceled
```

Expiration 表示：

> 当前 Checkout 商业条件需要重新验证。

---

# 18. Refresh

Checkout 过期或 stale 后：

```text
Refresh
↓
Revalidate Items
↓
Revalidate Shipping
↓
Revalidate Promotion
↓
Recalculate Tax
↓
Recalculate Price
↓
new version
↓
new price_version
↓
Evaluate Readiness
```

不得直接继续使用旧价格支付。

---

# 19. Readiness Evaluator

新增统一 Server-side readiness。

概念：

```text
OrderCheckout::Readiness
```

至少验证：

```text
order checkout-able

items valid

contact complete

shipping address valid

shipping available

shipping selected

promotion valid/current

tax current

price current

currency valid

not expired
```

返回：

```json
{
  "ready": false,
  "missing_requirements": [
    "SHIPPING_ADDRESS",
    "SHIPPING_METHOD"
  ]
}
```

Frontend：

```text
ready=false
→ 不允许进入最终支付提交
```

不能由前端自己推导 READY。

---

# 20. CheckoutSnapshot

这是 P1 最核心的后端交付。

`CheckoutSnapshot` 不要求是一张数据库表。

优先实现为：

```text
Server-generated immutable DTO / value object
```

由当前 Order 投影。

建议包含：

```text
order_id

checkout_version
price_version

customer / guest
contact

items

shipping_address
billing_address

shipping_method

discounts
taxes

price

currency

expires_at
generated_at
```

---

# 21. Snapshot 生成条件

只有：

```text
READY
+
not expired
+
price current
+
shipping current
+
tax current
```

的 Order 才允许生成 transaction-grade Snapshot。

否则返回：

```text
CHECKOUT_NOT_READY

CHECKOUT_EXPIRED

CHECKOUT_PRICE_STALE

SHIPPING_STALE

TAX_STALE
```

---

# 22. Internal Snapshot Contract

为未来 OTS 提供：

```text
GetCheckoutSnapshot(order_id)
```

或者等价 internal endpoint：

```http
GET /internal/orders/{id}/checkout_snapshot
```

具体形式遵循当前项目内部调用方式。

P2 的目标应该是：

```text
只给 order_id
```

即可得到完整、可信的交易输入。

由于当前 canonical 已经在 submit 时生成 Order，所以这里不再要求 `checkout_session_id`。

---

# 23. 与 PaymentSession 的边界

明确：

```text
Order Checkout
负责：

买什么
送哪里
什么 Shipping
多少优惠
多少税
多少钱
是否 READY
```

```text
PaymentSession
负责：

使用哪个 PaymentMethod
这一次支付 attempt/session
operation_key
provider session
PSP execution state
```

交接：

```text
Order READY
↓
authoritative amount_due
currency
price_version
↓
PaymentSessions::Start
```

P1 不允许 PaymentSession 反向成为 Checkout 数据源。

---

# 24. No Money-State Regression

继承 P0 原则：

```text
支付开始前：
stale checkout
→ 可以阻止支付

PSP 已成功后：
checkout 后续变 stale
→ 不得让用户再次支付
```

未来异常由：

```text
Recovery / OTS
```

处理。

不得因为 P1 version/expiration 改造造成重复扣款路径。

---

# 25. Trace 扩展

P0 已经建立：

```text
order
→ payment_session
→ payment
→ PSP
→ webhook
```

P1 扩展成：

```text
order
→ checkout_version
→ price_version
→ payment_session
→ payment
→ PSP
→ webhook
```

要求发生资金问题时能够回答：

> 该 Payment 是基于哪个 Checkout / Price Version 创建的？

---

# 26. Frontend Consolidation

Storefront 最终：

```text
CheckoutPage
        │
        ▼
   CheckoutView
```

页面结构：

```text
ContactSection

AddressSection

ShippingSection

PromotionSection

BillingSection

OrderSummary

PaymentSection
```

所有 section mutation：

```text
user input
↓
server mutation
↓
new CheckoutView
↓
frontend render
```

减少本地业务派生状态。

---

# 27. PaymentSection

保持独立：

```text
CheckoutPage
↓
PaymentSection
```

CheckoutPage 不直接依赖 Stripe SDK。

PaymentSection 内部当前真实组件必须在 P1-0 分成：

```text
ACTIVE

LEGACY

STUB

UNUSED
```

至少核查：

```text
Card Elements
PaymentElement
ExpressCheckoutElement
PayPal components
Adyen components
```

P1 不因为“文件存在”就认为 Provider 已正式启用。

---

# 28. Express Consolidation

P0 已解决：

```text
Express Idempotency

Express Server Amount
```

P1 不重复做。

P1 的目标是：

```text
Express
↓
Canonical Order Checkout View / Order facts
↓
PaymentSession
```

逐步减少：

```text
Cart-domain compatibility checkout
```

但不直接删除。

迁移决策使用 P0 已有：

```text
LEGACY_FLOW_BASELINE

usage metric
```

作为依据。

---

# 29. Legacy Order::Checkout State Machine

P1-0 必须专项审计现有：

```text
Order::Checkout

checkout_flow

checkout_steps

step

requirement

registry
```

并将引用分类：

```text
ACTIVE_PRODUCTION

PAYMENT_PROVIDER_DEPENDENCY

ADMIN_DEPENDENCY

COMPATIBILITY

DEAD_CODE
```

输出：

```text
KEEP

WRAP

DEPRECATE

REMOVE_LATER
```

P1 不允许未经审计直接删除这套 Legacy state machine。

---

# 30. Existing PRD 查重

P1-0 必须搜索：

```text
docs/prd/checkout

order flow PRD

standard ecommerce PRD

legacy checkout PRD
```

建立：

```text
P1_PRD_OVERLAP_MATRIX
```

对于已有需求：

```text
MERGE

SUPERSEDE

REFERENCE

KEEP_SEPARATE
```

禁止创建第三条重复 PRD 链。

---

# 31. 工作包

## CHK-P1-0 — Checkout Current-State Audit

纯只读。

输出：

```text
CURRENT_CHECKOUT_ARCHITECTURE

CHECKOUT_DATA_OWNERSHIP

CANONICAL_FLOW

LEGACY_FLOW

CURRENT_PRICE_FLOW

CURRENT_ADDRESS_FLOW

CURRENT_SHIPPING_FLOW

CURRENT_PROMOTION_FLOW

CURRENT_TAX_FLOW

PAYMENT_HANDOFF_FLOW

FRONTEND_CHECKOUT_ARCHITECTURE

PAYMENT_COMPONENT_USAGE_MATRIX

LEGACY_ORDER_CHECKOUT_STATE_MACHINE_USAGE

P1_PRD_OVERLAP_MATRIX

P1_REUSE_MATRIX

P1_CHANGE_PLAN

P1_RISK_LIST
```

---

## CHK-P1-1 — Order Checkout Application Layer

实现：

```text
统一 mutation services

CheckoutView

统一 Server orchestration
```

先不引入 version/expiration 大改。

---

## CHK-P1-2 — Version / Invalidation / Expiration

实现：

```text
checkout version

price version

dependency invalidation

stale detection

expiration

refresh
```

---

## CHK-P1-3 — Readiness + Snapshot

实现：

```text
ReadinessEvaluator

CheckoutSnapshotBuilder

Internal Snapshot Contract
```

这是 P1 后端最重要里程碑。

---

## CHK-P1-4 — Unified Storefront

实现：

```text
single CheckoutView

section mutations

server readiness

server price

PaymentSection boundary
```

---

## CHK-P1-5 — Express / Legacy Consolidation

逐步把：

```text
Cart compatibility checkout
```

向：

```text
Canonical Order Checkout
```

迁移。

基于真实 usage 决定范围。

---

## CHK-P1-6 — Legacy Checkout Governance

如果 P1-0 确认安全：

```text
deprecate / isolate
Order::Checkout legacy state machine
```

如果风险过高：

移入后续专项，不阻塞 P1 Snapshot 完成。

---

# 32. 验收标准

## AC-100

Canonical Order checkout 数据所有权有正式文档和代码边界。

## AC-110

Storefront 能从 Server 获取统一 CheckoutView。

## AC-120

修改地址会正确触发相关 Shipping / Tax / Price invalidation。

## AC-130

Shipping 变化由 Server 重新计算最终金额。

## AC-140

Promotion 变化正确触发 price recalculation / price version。

## AC-150

Frontend 不重新计算 authoritative total。

## AC-160

Stale checkout mutation 可被版本机制拒绝。

## AC-170

Expired / stale Checkout 无法直接进入新的支付创建。

## AC-180

Checkout Readiness 完全由 Server 判定。

## AC-190

READY Order 可生成完整 CheckoutSnapshot。

## AC-191

NOT READY Order 不得获得 transaction-grade Snapshot。

## AC-192

Snapshot 明确包含 checkout / price version。

## AC-200

给定 `order_id` 可以获取未来 OTS 所需的完整可信输入。

## AC-210

CheckoutPage 不直接调用 PSP SDK。

## AC-220

Express 使用 Canonical Server-side Checkout facts。

## AC-230

P0 Payment regression baseline 全绿。

## AC-240

现有 Order Flow regression baseline 全绿。

## AC-250

未创建重复 CheckoutSession / Pricing Engine / Checkout 数据副本。

---

# 33. 必须回归的支付行为

P1 每个涉及 checkout/payment handoff 的 PR 都必须验证：

```text
PaymentSessions::Start

operation_key

active session reuse

PaymentSession ↔ Payment FK

Webhook Dedup / Retry

Carts::Complete

verify_payment_intent_matches!

Express idempotency

Server-authoritative payment amount
```

P1 不允许降低 P0 的可靠性。

---

# 34. Definition of Done

P1 完成：

```text
Cart
↓
Submit
↓
Order
↓
Order Checkout Application Layer
↓
CheckoutView
↓
Server Readiness
↓
CheckoutSnapshot
```

并具备：

```text
统一数据所有权

统一 Storefront View

统一 mutation orchestration

Version

Price Version

Invalidation

Expiration

Refresh

Server Readiness

CheckoutSnapshot

Express canonical consolidation
```

同时明确确认：

```text
没有 CheckoutSession 新聚合

没有复制 Order 数据模型

没有新 Pricing Engine

没有 PaymentAttempt

没有 Router

没有 OTS

没有破坏 P0 Payment Foundation
```

---

# 35. P1 最终产物

输出：

`CHECKOUT_P1_COMPLETION_REPORT`

包含：

```text
Architecture Before / After

Checkout Data Ownership

Canonical / Legacy Flow

Application Layer

CheckoutView

Version Strategy

Price Version Strategy

Invalidation Graph

Expiration / Refresh

Readiness Rules

CheckoutSnapshot Contract

Payment Handoff Contract

Frontend Consolidation

Express Migration

Legacy Order::Checkout Governance

Database Changes

API Changes

Regression Matrix

Rollback Strategy

Remaining Technical Debt

OTS Readiness
```

---

# 36. P1 → OTS 的最终交接

P1 完成后，未来 OTS 不再从 Storefront 接收可信：

```text
items
amount
shipping
tax
discount
currency
```

只接收：

```text
order_id
```

然后服务端读取：

```text
CheckoutSnapshot
```

获得：

```text
买什么

数量

地址

Shipping

Discount

Tax

Amount

Currency

Checkout Version

Price Version

Expiration / Validity
```
