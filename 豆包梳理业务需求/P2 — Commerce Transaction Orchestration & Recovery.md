# P2 — Commerce Transaction Orchestration & Recovery

> 建议工程编号：`TXN-P2`
>
> 核心定位：
>
> **在 P1 Checkout 与 P0 Payment 之间建立 durable Commerce Transaction 编排层，使支付成功后的业务完成、异常恢复、多订单参与和未来库存事务拥有统一的生命周期。**

---

# 1. P2 阶段目标

P2 不再解决：

```text
怎么买
多少钱
是否 Ready
如何调用 Stripe
```

这些已经分别由：

```text
P1 Checkout
+
P0 Payment
```

解决。

P2 重点解决：

```text
一次商业交易如何被可靠执行

支付成功以后谁负责推进订单

本地完成失败以后如何恢复

一个 Transaction 可以关联哪些 Order

多个 PaymentSession 如何属于同一交易

组合支付 / 父子单 / 补付如何进入统一交易语义

库存如何最终接入交易生命周期
```

---

# 2. 当前基础

## P1 Checkout

```text
Cart
↓
Submit
↓
Order
↓
CheckoutView
↓
checkout_version
price_version
expiration / refresh
readiness
CheckoutSnapshot
fingerprint
↓
Payment Start Gate
```

---

## P0 Payment

```text
PaymentSessions::Start
↓
active session reuse
operation_key
provider idempotency
↓
PSP
↓
PaymentSession
↓
Payment
↓
Webhook Event Store
Retry / Replay
↓
Carts::Complete
```

---

# 3. 当前最关键缺口

当前 canonical 路径存在：

```text
PSP succeeded
↓
PaymentSession completed
↓
Payment completed
↓
Carts::Complete raises
↓
Order still pending
```

之后再次调用 complete：

```text
session.completed?
→ short circuit
→ 不再驱动 Carts::Complete
```

结果：

```text
钱已经成功
订单没有完成
没有 Recovery
```

因此 P2 第一原则：

> **资金成功和业务完成必须成为两个可独立确认、可恢复的事实。**

---

# 4. P2 目标架构

```text
                 Checkout Domain
                       │
                       ▼
               CheckoutSnapshot
                       │
                       ▼
              CommerceTransaction
            ┌──────────┼──────────┐
            │          │          │
            ▼          ▼          ▼
     TransactionOrder Payment   Inventory
          × N         Sessions Reservation
                         │
                         ▼
                        PSP
                         │
                         ▼
                Payment Fact Resolver
                         │
               ┌─────────┴─────────┐
               │                   │
            UNPAID               PAID
               │                   │
               ▼                   ▼
       PAYMENT_PENDING        FINALIZATION
                                   │
                         ┌─────────┴─────────┐
                         │                   │
                      success             failure
                         │                   │
                         ▼                   ▼
                    COMPLETED        RECOVERY_REQUIRED
                                             │
                                             ▼
                                          Recovery
```

---

# 5. P2 核心领域定义

正式引入：

```text
CommerceTransaction
```

它表示：

> **一次由用户确认的商业交易执行上下文。**

它不是：

```text
Order
CheckoutSession
Payment
PaymentAttempt
PaymentCombination
```

它负责：

```text
交易输入绑定
交易幂等
交易参与者
支付执行关联
支付事实确认
订单完成编排
异常恢复
审计
```

---

# 6. Transaction 与 Order 的关系

不要设计：

```text
OrderTransaction
  belongs_to :order
```

作为唯一结构。

因为已经存在：

```text
组合支付
父子单
账户补付
未来多订单结算
```

因此目标关系应为：

```text
CommerceTransaction
       │
       └── TransactionOrder × N
```

候选：

```text
transactions

transaction_orders
```

其中：

```text
TransactionOrder
- transaction_id
- order_id
- role
- amount_snapshot
- completion_status
```

---

# 7. Transaction Cardinality

## 普通订单

```text
Transaction #1
└── Order A
```

---

## 同一订单换卡重试

```text
Transaction #1
├── PaymentSession #1 declined
├── PaymentSession #2 failed
└── PaymentSession #3 succeeded
```

仍然是：

```text
1 Transaction
```

不是三个 Transaction。

---

## 组合支付

```text
Transaction #1
├── Order A
├── Order B
├── Order C
└── PaymentSession #1
```

---

## 账户补付

建议定义为：

```text
Order A
├── Transaction #1 initial purchase
└── Transaction #2 balance collection
```

即：

```text
Order : Transaction = N:M / 1:N semantic
```

而不是永久 1:1。

---

# 8. PaymentSession 关系

P0 的多 attempt 模型继续保留。

正式语义：

```text
CommerceTransaction
        │
        └── PaymentSession × N
```

不要增加：

```text
PaymentAttempt
```

PaymentSession 本身已经承担支付 attempt/session 语义。

候选新增：

```text
payment_sessions.transaction_id
```

可空，用于兼容 legacy / 历史数据。

---

# 9. CheckoutSnapshot 两层语义

## P1 Snapshot

继续：

```text
OrderCheckout::Snapshot
```

是实时：

```text
DTO / Value Object
```

不需要为了 P1 改成持久化模型。

---

## P2 Transaction Snapshot

Transaction 启动时必须冻结：

```text
transaction_snapshot
checkout_version
price_version
snapshot_fingerprint
amount
currency
```

建议：

```text
transaction_snapshot JSONB
```

它属于：

> immutable transaction evidence

用途：

```text
Audit
Recovery
Reconciliation
Dispute investigation
Trace
```

它不是新的 pricing source。

任何重新报价仍回到：

```text
OrderCheckout
```

---

# 10. Transaction Snapshot 必须记录什么

至少：

```text
transaction_id

order participants

checkout_version
price_version
fingerprint

items

addresses

shipping

discounts

tax

amount
currency

generated_at
```

对于组合交易：

```text
participant_orders[]
```

必须明确各自：

```text
order_id
allocated_amount
currency
```

---

# 11. Quote Expiration 策略升级

当前 P1：

```text
expired
→ Refresh
→ Recalculate
→ continue
```

P2 不应简单照搬。

推荐：

```text
StartTransaction
↓
expired?
↓ yes
Refresh
↓
compare commercial facts
```

如果：

```text
amount unchanged
currency unchanged
shipping semantics unchanged
promotion unchanged
tax unchanged
```

则：

```text
transparent refresh
→ continue
```

如果商业事实变化：

```text
amount changed
shipping changed
promotion changed
tax changed
```

返回：

```text
409 QUOTE_CHANGED
```

携带：

```text
latest_checkout_version
latest_price_version
latest_fingerprint
latest_amount
latest_currency
```

要求用户重新确认。

---

# 12. Quote Consent Invariant

核心原则：

```text
Server 可以自动刷新报价

Server 不可以替用户静默同意新的商业条件
```

因此：

```text
expired
≠
always reject
```

也：

```text
expired
≠
always silently continue
```

真正 Gate 是：

```text
commercial facts changed?
```

---

# 13. PaymentSessions::Start 保留

P2 不替换：

```text
PaymentSessions::Start
```

它继续负责：

```text
session reuse
operation_key
attempt-N
provider idempotency
amount/currency verification
provider execution
```

调用关系变为：

```text
StartTransaction
↓
Transaction policy checks
↓
PaymentSessions::Start
↓
Payment defensive checks
↓
PSP
```

形成双层防御：

```text
Transaction Gate
+
Payment Gate
```

---

# 14. StartTransaction

候选 Application Service：

```text
Transactions::Start
```

输入：

```text
order / participant orders

expected_checkout_version
expected_price_version
expected_fingerprint

payment_method
```

流程：

```text
Resolve participants
↓
Load CheckoutSnapshot
↓
Validate Readiness
↓
Refresh if needed
↓
Validate user quote consent
↓
Find/Create active Transaction
↓
Persist immutable transaction snapshot
↓
PaymentSessions::Start
↓
attach PaymentSession
↓
return Transaction + payment execution
```

---

# 15. Transaction Start Idempotency

Transaction 必须拥有自己的业务幂等。

例如由：

```text
participant orders
commercial intent
checkout version
price version
fingerprint
transaction purpose
```

决定 active transaction identity。

以下场景：

```text
double click
HTTP timeout
frontend retry
concurrent requests
```

只能得到：

```text
same active CommerceTransaction
```

资金层再由 P0：

```text
PaymentSessions::Start
```

提供第二层幂等。

---

# 16. Transaction Purpose

建议一开始就预留：

```text
purpose
```

例如：

```text
purchase
balance_collection
combined_payment
```

不要过早添加过多类型。

但至少区分：

```text
INITIAL_PURCHASE
BALANCE_COLLECTION
```

因为它们生命周期不同。

---

# 17. Transaction 状态机

建议保持极简：

```text
created
    ↓
payment_pending
    ↓
payment_confirmed
    ↓
finalizing
    ↓
completed
```

正常取消：

```text
created
payment_pending
↓
canceled
```

异常：

```text
payment_confirmed
finalizing
↓
recovery_required
```

必要时：

```text
recovery_required
↓
manual_review
```

---

# 18. 不要增加这些 Transaction 状态

禁止：

```text
payment_failed
checkout_failed
provider_failed
shipping_failed
tax_failed
inventory_failed
```

这些属于其他 Domain。

例如卡被拒：

```text
PaymentSession = failed
Transaction = payment_pending
```

用户仍可换支付方式继续。

---

# 19. Payment Fact Resolver

P2 新增一个非常重要的能力：

```text
PaymentFactResolver
```

职责：

> 判断这次 Transaction 当前真实资金事实是什么。

输入：

```text
Transaction
PaymentSessions
Payments
Webhook Events
Provider References
```

输出：

```text
UNPAID
PAID
AMBIGUOUS
```

---

# 20. Provider Status Query Contract

P0 现有：

```text
verify_payment_intent_matches!
```

主要用于：

```text
amount/currency verification
```

P2 建议新增 Provider Contract：

```text
fetch_payment_status
```

或：

```text
retrieve_payment_result
```

Stripe 第一版实现：

```text
PaymentIntent retrieve
→ authoritative status
→ amount
→ currency
→ provider reference
```

未来其他 PSP 实现同样 contract。

---

# 21. Payment Success Handoff

现在：

```text
API
Webhook
Redirect
Combination Settle
...
```

存在多个完成入口。

P2 不再允许各入口自己决定：

```text
Order 怎么完成
```

目标：

```text
Provider/API/Webhook/Redirect
            │
            ▼
Transaction Payment Handler
            │
            ▼
PaymentFactResolver
            │
            ▼
payment_confirmed
```

---

# 22. 完成入口数量

不要继续只按：

```text
API
Webhook
Redirect
```

三个入口设计。

P2-0 必须覆盖当前所有真实入口：

```text
Order complete API

Cart complete API

Webhook

Redirect / confirm

CompleteOrderFromSessionJob

CombinationSettleJob

Balance payment

Combination payment

legacy provider adapters
```

但最终都应走：

```text
Transaction Handler
```

---

# 23. Unified Finalization

建立新的 canonical Application Service：

```text
Transactions::Finalize
```

或：

```text
Orders::FinalizePaidOrder
```

职责：

```text
payment fact confirmed?
↓
finalize participant orders
↓
mark participant result
↓
complete transaction
```

---

# 24. Carts::Complete 的定位

P2 不删除现有：

```text
Carts::Complete
```

第一阶段：

```text
Transactions::Finalize
↓
Carts::Complete
```

它作为：

```text
finalization primitive / adapter
```

使用。

长期：

```text
Carts::Complete
```

不再承担顶层交易编排职责。

---

# 25. Legacy Checkout::Complete

当前组合成员仍可能使用：

```text
legacy Checkout::Complete
```

P2 不允许它长期继续作为第二个 canonical completion primitive。

第一阶段允许：

```text
Transactions::Finalize
        │
        ├── standard → Carts::Complete
        └── legacy compatibility → Checkout::Complete
```

但明确标记：

```text
COMPATIBILITY ADAPTER
```

目标最终收敛：

```text
Orders::FinalizePaidOrder
```

---

# 26. Recovery 是 P2 第一等能力

新增：

```text
Transactions::Recover
```

Recovery 不能：

```text
rescue
→ retry Carts::Complete blindly
```

必须先确认资金事实。

---

# 27. Recovery 流程

```text
Load Transaction
↓
Load Participant Orders
↓
Load PaymentSessions
↓
Load Payments
↓
Load Webhook Events
↓
必要时 Query PSP
↓
PaymentFactResolver
```

然后：

```text
UNPAID
→ payment_pending

PAID + Order incomplete
→ retry finalization

PAID + Order complete
→ repair transaction → completed

AMBIGUOUS
→ manual_review
```

---

# 28. Money-state Invariant

必须正式写入 P2：

```text
PSP authoritative success
不得变回普通 failure
```

因此：

```text
payment_confirmed
→ finalizing
→ completed
```

或者：

```text
payment_confirmed
→ recovery_required
```

禁止：

```text
payment_confirmed
→ payment_pending
```

更禁止：

```text
payment_confirmed
→ create new payment automatically
```

---

# 29. Recovery Idempotency

以下调用：

```text
recover
recover
recover
```

最终必须保持：

```text
1 Transaction
1 authoritative money result
1 Order completion per participant
```

Recovery 需要：

```text
transaction lock
state guard
attempt count
last_error
audit
```

---

# 30. Recovery Trigger

第一版支持：

```text
Immediate failure mark
↓
recovery_required
↓
Recovery Job
```

以及：

```text
Manual Recover
```

后续增加：

```text
Stuck Transaction Sweeper
```

用于：

```text
payment_confirmed too long
finalizing too long
recovery_required too long
```

---

# 31. Payment Start Policy

Transaction 以下状态：

```text
payment_confirmed
finalizing
recovery_required
completed
manual_review
```

必须禁止创建新的 PaymentSession。

只有：

```text
created
payment_pending
```

允许：

```text
start/reuse payment session
```

---

# 32. PaymentCombination 的目标定位

现有：

```text
PaymentCombination
PaymentSplit
CombinationSettleJob
```

继续保留。

但正式定位：

```text
PaymentCombination
=
combined-payment feature / adapter
```

不是：

```text
CommerceTransaction Core
```

长期：

```text
CommerceTransaction
        ↓
Combined Payment Strategy
        ↓
PaymentCombination
```

---

# 33. CombinationSettleJob 的复用

保留它已经验证的原则：

```text
资金事实先确认

成员订单完成失败
不回滚资金

后续补偿
```

但 Generic Recovery 不直接依赖：

```text
CombinationSettleJob
```

而应抽象成统一：

```text
Transactions::Recover
```

Combination 可以逐步接入。

---

# 34. 父子单语义

P2-0 必须重新确认商业意义，而不是照现有实现复制。

默认建议：

```text
Fulfillment Split
≠
Payment Transaction Split
```

即：

```text
一个 Checkout
一个金额
一次付款
```

即使后续被拆成：

```text
Child Order A
Child Order B
Child Order C
```

也默认：

```text
1 CommerceTransaction
```

除非产品明确要求：

```text
each child separately payable
```

---

# 35. TransactionOrder Role

候选：

```text
primary
participant
fulfillment_child
balance_target
```

不要第一版做得过于复杂。

P2-0 冻结实际需要的最小集合。

---

# 36. Inventory：现有能力必须复用

现有：

```text
StockReservation
StockReservations::Reserve
StockReservations::Release
```

继续保留。

P2 不重新实现库存锁。

---

# 37. Inventory Transaction Port

新增统一语义：

```text
InventoryReservationPort

reserve(transaction_snapshot)

commit(transaction)

release(transaction)

status(transaction)
```

现有：

```text
StockReservations::Reserve
StockReservations::Release
```

成为 Adapter。

---

# 38. Inventory 必须审计 commit 语义

P2/P3 必须确认当前：

```text
Reserve
Release
```

究竟表示：

```text
锁库存
释放库存
```

还是：

```text
支付成功后消费 reservation
```

如果当前缺：

```text
commit / consume
```

则 P3 应负责补齐：

```text
RESERVED
COMMITTED
RELEASED
EXPIRED
```

完整生命周期。

---

# 39. P3 重新定位

旧：

```text
P3 = 实现 Inventory Reservation
```

已经不准确。

建议改为：

# P3 — Inventory Transaction Integration

核心：

```text
CommerceTransaction
↓
Reserve
↓
Payment
↓
Commit
```

异常：

```text
Payment before success failure
→ Release

Payment success + inventory commit failure
→ Recovery Required
```

---

# 40. Audit / Trace

P0：

```text
order
→ payment_session
→ payment
→ PSP
→ webhook
```

P1：

```text
order
→ checkout_version
→ price_version
→ fingerprint
```

P2：

```text
transaction
→ participant orders
→ transaction snapshot
→ checkout_version
→ price_version
→ fingerprint
→ payment sessions
→ payment
→ provider reference
→ webhook event
→ finalization
→ recovery
```

---

# 41. Transaction Audit Events

至少：

```text
transaction.created

transaction.payment_started

transaction.payment_confirmed

transaction.finalization_started

transaction.completed

transaction.recovery_required

transaction.recovery_started

transaction.recovery_completed

transaction.manual_review

transaction.canceled
```

复用 P0：

```text
audit_logs
request_id
```

不重新创建 Audit Engine。

---

# 42. Frontend 目标

现状：

```text
UnifiedCheckout
→ PaymentSessions.create

OrderPaymentContent
→ PaymentSessions.create
```

P2 最终：

```text
Frontend
↓
Start / Resume Transaction
↓
Backend Transaction Coordinator
↓
PaymentSession
↓
Provider UI
```

---

# 43. Transaction API

候选：

```http
POST /orders/{order_id}/transactions
```

或根据 P2-0 cardinality 选择更合理路径。

返回：

```json
{
  "transaction_id": "txn_xxx",
  "state": "payment_pending",
  "payment_execution": {},
  "checkout": {}
}
```

组合交易则不能强绑定单一 order 路由，因此最终路径应在 P2-0 后冻结。

---

# 44. Resume Transaction

建议支持：

```http
GET /transactions/{id}
```

返回：

```text
state
participants
payment state summary
recovery status
completion state
```

Frontend 不再自己拼：

```text
Order
+
PaymentSession
+
Payment
```

推断交易状态。

---

# 45. P2 Entry Gate

在 P2 Coding 前确认：

```text
P0 baseline green

P1 baseline green

P0/P1 migrations settled

P0/P1 PRD status closed or formally accepted

working tree / branch state可审计
```

审计报告指出当前 P0/P1 工作仍存在未提交/未正式收口情况，这属于实施治理 Gate，而不是 P2 架构本身。

---

# 46. TXN-P2-0 — Transaction Semantic Audit

第一阶段仍然纯只读。

但这次不是单纯：

```text
当前代码怎么做
```

而是输出：

```text
CURRENT_STATE
+
TARGET_SEMANTICS
```

---

# 47. P2-0 必须冻结四个核心决策

```text
TRANSACTION_IDENTITY

TRANSACTION_CARDINALITY

TRANSACTION_SNAPSHOT_POLICY

TRANSACTION_FINALIZATION_POLICY
```

---

# 48. P2-0 必查场景

至少：

```text
普通 Order

digital Order

多 PaymentSession attempts

parent/child orders

automatic split

PaymentCombination

PaymentSplit

balance collection

legacy provider completion

inventory strategy order/payment

Carts::Complete

Checkout::Complete

CombinationSettleJob
```

---

# 49. P2-0 关键问题

必须回答：

1. 普通订单 Transaction 边界是什么？
2. 一个 Transaction 是否允许多个 Order？
3. 一个 Order 是否允许多个 Transaction？
4. 父子单是不是资金边界？
5. PaymentCombination 与 Transaction 如何映射？
6. Balance collection 是否是独立 Transaction？
7. Snapshot 冻结在哪个时刻？
8. Transaction Start 后 Checkout Refresh 是否允许继续？
9. 已付款订单最终由哪个 canonical Finalizer 完成？
10. Inventory reservation 与 Transaction 的生命周期怎样对齐？

---

# 50. P2-0 输出

必须输出：

```text
TRANSACTION_SCOPE_MATRIX

TRANSACTION_CARDINALITY_DECISION

TRANSACTION_PARTICIPANT_MODEL

TRANSACTION_SNAPSHOT_POLICY

QUOTE_CONSENT_POLICY

PAYMENT_SESSION_RELATIONSHIP

PAYMENT_FACT_RESOLUTION_POLICY

FINALIZATION_PRIMITIVE_MATRIX

INVENTORY_TRANSACTION_MATRIX

LEGACY_ADAPTER_MATRIX

DB_MODEL_PROPOSAL

API_PROPOSAL

RISK_LIST

IMPLEMENTATION_PLAN
```

完成后停止。

未经评审：

```text
禁止 migration
禁止创建 transactions 表
```

---

# 51. TXN-P2-1 — Transaction Core

P2-0 通过后实现：

```text
CommerceTransaction

TransactionOrder

Transaction state machine

immutable snapshot evidence

locks

audit
```

暂不改变支付入口。

---

# 52. 候选 Transaction 字段

仅候选，需 P2-0 决策：

```text
id

state
purpose

checkout_version
price_version
snapshot_fingerprint

snapshot_data

amount
currency

started_at
payment_confirmed_at
finalizing_at
completed_at
recovery_required_at

recovery_attempts

last_error_code
last_error_class
last_error_message

created_at
updated_at
```

---

# 53. TXN-P2-2 — Start / Resume Transaction

实现：

```text
Transactions::Start

Transactions::Resume
```

包括：

```text
business idempotency

snapshot freeze

quote consent

PaymentSessions::Start integration

multiple PaymentSession attempts
```

---

# 54. TXN-P2-3 — Payment Fact Resolver

实现：

```text
PaymentFactResolver

provider read-only status contract
```

先 Stripe。

目标：

```text
local DB inconsistent
↓
仍然能确定真实资金事实
```

---

# 55. TXN-P2-4 — Recovery Engine

实现：

```text
recovery_required

Recover service

Recovery Job

Manual recovery

authoritative state resolution

retry finalization

audit
```

这是 P2 的关键里程碑。

---

# 56. TXN-P2-5 — Unified Finalization

建立：

```text
Transactions::Finalize
```

将：

```text
Carts::Complete
Checkout::Complete
Combination settlement completion
```

逐步收敛到统一 orchestration boundary。

注意：

```text
P2-5 ≠ 一次性删掉所有旧 service
```

采用 Strangler。

---

# 57. TXN-P2-6 — Storefront / API Migration

迁移：

```text
UnifiedCheckout

OrderPaymentContent

/api/checkout/start

SDK
```

从：

```text
payment-session-first
```

变成：

```text
transaction-first
```

Provider UI 保持独立。

---

# 58. TXN-P2-7 — Operational Hardening

实现：

```text
transaction trace

transaction metrics

recovery metrics

admin transaction inspection

stuck transaction visibility

manual recovery tooling

alerts

docs
```

---

# 59. P2 Acceptance Criteria

## AC-2001

READY 且用户确认最新商业条件的 Checkout 可启动 Transaction。

## AC-2002

同一商业意图重复调用只产生一个 active Transaction。

## AC-2003

Transaction 可关联一个或多个 Order participant。

## AC-2004

同一 Order 可在业务需要时拥有多个 Transaction，例如 balance collection。

## AC-2005

Transaction 在启动时冻结：

```text
checkout_version
price_version
fingerprint
transaction snapshot
amount
currency
```

## AC-2006

PaymentSession 属于 Transaction payment attempts；不新增 PaymentAttempt。

## AC-2007

相同 Transaction 的重复支付请求仍受 P0 幂等保护。

## AC-2008

卡拒绝只导致 PaymentSession failed，Transaction 保持 payment_pending。

## AC-2009

PSP authoritative success 将 Transaction 推进到 payment_confirmed。

## AC-2010

payment_confirmed 后禁止创建新的普通支付 attempt。

## AC-2011

PSP 成功 + Order 未完成必须进入：

```text
recovery_required
```

而不是普通 failed。

## AC-2012

Recovery 能安全完成：

```text
paid + incomplete order
```

## AC-2013

重复 Recovery 幂等。

## AC-2014

PSP 状态无法确定时进入 manual_review，不猜测。

## AC-2015

所有主要 completion 入口最终经过统一 Transaction handler。

## AC-2016

P0 Payment baseline 全绿。

## AC-2017

P1 Checkout baseline 全绿。

## AC-2018

PaymentCombination 保持功能可用，但不成为 Transaction Core。

## AC-2019

现有 StockReservation 功能不被破坏。

## AC-2020

未新增：

```text
PaymentAttempt
CheckoutSession
Payment Router
ProviderRegistry
```

---

# 60. P2 核心 Invariants

## INV-01

```text
一个 Transaction
不得产生两个有效资金结果。
```

---

## INV-02

```text
PSP authoritative success
是不可逆资金事实。
```

---

## INV-03

```text
PSP success
+
local incomplete
=
RECOVERY_REQUIRED
```

---

## INV-04

```text
Recovery 不得默认创建新 Payment。
```

---

## INV-05

```text
Payment decline
≠
Transaction failure
```

---

## INV-06

```text
Checkout stale
只能阻止新的未确认商业副作用

不能逆转已经发生的资金事实。
```

---

## INV-07

```text
用户未确认的商业价格变化
不得被静默带入 Transaction。
```

---

## INV-08

```text
Order finalization 必须幂等。
```

---

## INV-09

```text
Checkout Snapshot
是交易输入证据

不是新的价格计算源。
```

---

## INV-10

```text
Transaction
是 orchestration aggregate

不是 Payment aggregate。
```

---

# 61. P2 不实现

严格禁止 Scope Creep：

```text
❌ 新 CheckoutSession

❌ PaymentAttempt

❌ 重写 PaymentSession

❌ 重写 Stripe payment execution

❌ Multi-PSP Router

❌ ProviderRegistry

❌ Adyen transaction migration

❌ Ledger

❌ Refund orchestration

❌ Dispute

❌ Full reconciliation platform

❌ 2PC

❌ 分布式事务框架

❌ 强制引入 MQ

❌ 微服务拆分

❌ 重写完整库存系统
```

---

# 62. P2 可复用能力矩阵

```text
PaymentSessions::Start
→ REUSE_AS_IS

Webhook Event Store
→ REUSE_AS_IS

Carts::Complete
→ WRAP / FINALIZATION PRIMITIVE

Checkout::Complete
→ COMPATIBILITY ADAPTER

OrderCheckout::Snapshot
→ REUSE AS DYNAMIC SNAPSHOT

Checkout Version / Price Version
→ REUSE_AS_IS

PaymentCombination
→ KEEP AS FEATURE / ADAPTER

CombinationSettleJob
→ REUSE RECOVERY PATTERN

StockReservations::Reserve/Release
→ REUSE LOW-LEVEL PRIMITIVE

AuditLog / RequestId
→ EXTEND transaction dimension
```

---

# 63. P2 需要改造的现有能力

```text
Payment completion
→ transaction-aware

session.completed? short circuit
→ 不得阻断 paid-order recovery

multiple completion paths
→ converge through transaction handler

legacy Checkout::Complete
→ adapter

Carts::Complete
→ canonical finalization primitive / adapter

StockReservation
→ transaction lifecycle semantics

Payment provider
→ add authoritative status query
```

---

# 64. Definition of Done

P2 完成后：

```text
Checkout READY
↓
Start CommerceTransaction
↓
Freeze Transaction Snapshot
↓
Payment Pending
↓
PaymentSession(s)
↓
PSP
↓
Payment Fact Resolution
↓
Payment Confirmed
↓
Finalization
```

正常：

```text
→ Completed
```

异常：

```text
→ Recovery Required
→ Recover
→ Completed
```

而不是：

```text
Payment succeeded
↓
local crash
↓
user pays again
```

---

# 65. P2 最终产物

输出：

```text
TXN_P2_COMPLETION_REPORT
```

至少包括：

```text
Transaction Domain Model

Transaction Cardinality

Transaction Snapshot Contract

Quote Consent Policy

Payment Attempt Relationship

Payment Fact Resolver

Provider Status Contract

Finalization Architecture

Recovery Architecture

Combination Adapter

Parent/Child Transaction Semantics

Balance Collection Semantics

Inventory Integration Boundary

API Contract

Storefront Migration

Audit / Trace

Migration Plan

Regression Matrix

Rollback Plan

Remaining Legacy Adapters

P3 Inventory Transaction Readiness
```

---

# 66. 下一阶段

P2 完成后进入：

# P3 — Inventory Transaction Integration

目标：

```text
CommerceTransaction
↓
Reserve Inventory
↓
Payment
↓
Commit Inventory
↓
Finalize
```

并将当前库存能力真正升级为：

```text
RESERVED
COMMITTED
RELEASED
EXPIRED
```

Transaction Recovery 同时负责：

```text
payment success
+
inventory/finalization exception
```

的恢复。

---

# 67. 本轮推荐执行指令

**当前只执行 TXN-P2-0。**

禁止 Coding。

禁止 migration。

禁止创建 Transaction Model。

必须先完成：

```text
TRANSACTION_SCOPE_MATRIX

TRANSACTION_CARDINALITY_DECISION

TRANSACTION_PARTICIPANT_MODEL

TRANSACTION_SNAPSHOT_POLICY

QUOTE_CONSENT_POLICY

PAYMENT_SESSION_RELATIONSHIP

PAYMENT_FACT_RESOLUTION_POLICY

FINALIZATION_PRIMITIVE_MATRIX

INVENTORY_TRANSACTION_MATRIX

LEGACY_ADAPTER_MATRIX

DB_MODEL_PROPOSAL

API_PROPOSAL

RISK_LIST

IMPLEMENTATION_PLAN
```

然后停止，等待架构评审。
