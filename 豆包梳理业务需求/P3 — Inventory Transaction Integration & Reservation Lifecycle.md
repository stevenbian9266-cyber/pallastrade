# P3 — Inventory Transaction Integration & Reservation Lifecycle V2

> 工程编号：`INV-P3`
>
> 前置阶段：
>
> ```text
> P0 — Payment Foundation
> P1 — Order-centric Checkout
> P2 — Commerce Transaction Orchestration & Recovery
> ```
>
> 核心定位：
>
> **保留现有库存权威与 StockMovement 扣减体系，把 StockReservation 从“临时软占位记录”升级成 CommerceTransaction 下可追踪、可恢复的库存承诺生命周期。**

---

# 1. P3 最终要解决的问题

当前已经具备：

```text
StockItem.count_on_hand
StockMovement
StockReservation
StockReservations::Reserve
StockReservations::Release
StockReservations::Extend
Reservation TTL
悲观锁
backorder/preorder bypass
```

但缺少：

```text
Transaction ownership

RESERVED
COMMITTED
RELEASED
EXPIRED

transaction-first Reserve

reservation demand snapshot

取消释放

显式 expiration lifecycle

inventory recovery

transaction / payment / reservation TTL 对齐
```

P3 不重新实现库存，而是完成：

```text
SOFT RESERVATION
        ↓
TRANSACTION OWNERSHIP
        ↓
EXPLICIT LIFECYCLE
        ↓
PAYMENT / FINALIZATION COORDINATION
        ↓
RECOVERY
```

---

# 2. 当前库存权威正式冻结

## 2.1 物理库存权威

继续使用：

```text
StockItem.count_on_hand
+
StockMovement
```

P3 不新增：

```text
allocated_count
transaction_stock
第二套 physical quantity
```

---

## 2.2 Available-to-sell

继续：

```text
available_to_sell
=
count_on_hand
-
active RESERVED quantity
```

由现有：

```text
Stock::Quantifier
```

负责。

P3 只修改：

> 什么 Reservation 算 active。

目标：

```text
state = RESERVED
AND expires_at > now
```

才计入 reserved quantity。

---

# 3. Reservation 与 Physical Inventory 必须分层

正式定义：

```text
Reservation Fact
≠
Physical Inventory Fact
```

Reservation 表达：

> 某笔 Transaction 暂时获得多少库存销售资格。

Physical Inventory 表达：

> 仓库当前真实 count_on_hand。

因此：

```text
Reserve
```

不得修改：

```text
count_on_hand
```

真正物理库存减少仍通过：

```text
Order Finalization
→ Shipment
→ InventoryUnit
→ StockMovement
```

执行。

---

# 4. P3 最重要的设计修正：Commit 不负责再次扣库存

禁止：

```text
Payment Success
→ InventoryCommit
→ StockMovement decrement
→ Order.finalize!
→ 再次 StockMovement decrement
```

这是双扣库存风险。

P3 中的：

```text
COMMITTED
```

定义为：

> **该 Reservation 对应的销售库存已经通过现有 canonical fulfillment/finalization pipeline 成功消费，Reservation 从“可释放占位”转成“历史交易承诺证据”。**

所以 Commit 是：

```text
事实确认
```

不是新的：

```text
库存扣减算法
```

---

# 5. 新的正常主链

目标链路：

```text
CheckoutSnapshot
        ↓
CommerceTransaction
        ↓
Freeze Inventory Demand
        ↓
Reserve Inventory
        ↓
RESERVED
        ↓
PaymentSession
        ↓
PSP
        ↓
PaymentFact = PAID
        ↓
Inventory Commit Coordination
        ↓
Existing Order Finalization
        ↓
StockMovement physical decrement
        ↓
Reservation → COMMITTED
        ↓
Transaction → COMPLETED
```

---

# 6. Commit Coordination

新增概念：

```text
InventoryCommitCoordinator
```

可以采用其他符合项目 convention 的命名。

职责：

```text
1. Verify required reservations are RESERVED
2. Invoke / cooperate with canonical order finalization
3. Confirm physical inventory consumption succeeded
4. Mark matching reservations COMMITTED
```

它不能：

```text
自己创建第二套 stock decrement
```

---

# 7. COMMITTED 的成立条件

Reservation 不能仅因为：

```text
Payment = PAID
```

就变成：

```text
COMMITTED
```

至少需要确认：

```text
Payment Fact = PAID
+
Canonical inventory consumption succeeded
```

第一版可通过：

```text
successful finalization
+
existing inventory-unit / stock-movement semantics
```

作为 commit confirmation。

未来 InventoryFactResolver 可以提供更严格检查。

---

# 8. 为什么不能“先标 COMMITTED 再 Finalize”

如果这样：

```text
Payment PAID
↓
Reservation COMMITTED
↓
Finalize raises
```

可能得到：

```text
Reservation = COMMITTED
StockMovement 尚未发生
```

语义错误。

因此正确顺序：

```text
RESERVED
↓
finalization / physical consumption
↓
COMMITTED
```

或者在同一个受控 orchestration 中完成。

---

# 9. Reservation Lifecycle

正式冻结：

```text
RESERVED
COMMITTED
RELEASED
EXPIRED
```

允许转换：

```text
RESERVED → COMMITTED
RESERVED → RELEASED
RESERVED → EXPIRED
```

正常情况下禁止：

```text
COMMITTED → RELEASED
COMMITTED → EXPIRED

RELEASED → COMMITTED

EXPIRED → COMMITTED
```

重新预留应产生新的 reservation execution/evidence，而不是直接伪造旧状态。

具体是否复用原 row，由 P3-1 数据模型决定。

---

# 10. RESERVED

表示：

```text
库存仍未物理消费
但已从 available-to-sell 中占位
```

必须有：

```text
stock_item
line_item
order
transaction
quantity
reserved_at
expires_at
```

---

# 11. COMMITTED

表示：

```text
交易已经获得 authoritative PAID fact
且对应物理库存消费已经成功
```

Reservation 不再计入：

```text
active reserved quantity
```

因为库存已经从：

```text
count_on_hand
```

真实扣除。

---

# 12. RELEASED

表示：

```text
交易在库存消费前主动放弃 reservation
```

例如：

```text
Transaction canceled

Checkout abandoned and transaction terminated

Payment confirmed UNPAID
+
明确取消
```

必须保存：

```text
released_at
release_reason
```

---

# 13. EXPIRED

表示：

```text
Reservation TTL 到期
且尚未 COMMITTED / RELEASED
```

必须保存：

```text
expired_at
```

不能继续硬删除。

---

# 14. 不再硬删除 Reservation

目标：

```text
StockReservations::Release
```

从：

```text
DELETE
```

升级为：

```text
RESERVED → RELEASED
```

Expire：

```text
RESERVED → EXPIRED
```

Commit：

```text
RESERVED → COMMITTED
```

---

# 15. 历史数据与表增长

软状态意味着 Reservation 表会增长。

因此 P3-1 必须同时设计：

```text
active scope

partial indexes

retention/archive policy（只记录，不要求本期实现）
```

常用查询重点：

```text
stock_item_id
state
expires_at
transaction_id
order_id
line_item_id
```

---

# 16. Reservation 唯一约束需要重构

当前：

```text
UNIQUE(stock_item_id, line_item_id)
```

适合硬删除模型。

改为保留历史行后会阻止：

```text
EXPIRED 后重新 Reserve
```

推荐：

```text
UNIQUE(stock_item_id, line_item_id)
WHERE state = 'reserved'
```

或仓库 convention 下的等价 active-reservation uniqueness。

目标 invariant：

> 同一个 stock_item + line_item 同时最多一个 active Reservation。

历史：

```text
COMMITTED
RELEASED
EXPIRED
```

可以共存。

---

# 17. Reservation Ownership

推荐直接扩展现有：

```text
StockReservation
```

新增：

```text
commerce_transaction_id / transaction_id
```

可空 FK。

不要新建：

```text
TransactionInventoryReservation
```

除非 P3-0 最终发现现有表无法满足 cardinality。

---

# 18. Ownership Cardinality

目标：

```text
CommerceTransaction
        │
        └── StockReservation × N
```

同时 Reservation 继续关联：

```text
Order
LineItem
StockItem
```

因为库存 demand 仍来自具体 Order item。

---

# 19. Legacy Compatibility

历史 / legacy Reservation：

```text
transaction_id = NULL
```

允许继续存在。

新：

```text
transaction-first
```

路径必须写：

```text
transaction_id
```

不要求回填历史数据。

---

# 20. Transaction Snapshot 需要升级到 V2

当前 P2 transaction snapshot 偏金额证据。

P3 需要：

```text
inventory demand evidence
```

因此禁止修改历史 snapshot。

新增：

```text
snapshot_schema_version = 2
```

新 Transaction Snapshot 应包含：

```text
participants[]
  order_id
  amount
  currency

  items[]
    line_item_id
    variant_id / sku
    quantity
    stock_requirement
```

---

# 21. Snapshot Demand 与 Inventory Authority

正式区分：

```text
Transaction Snapshot
=
Demand Evidence
```

例如：

```text
SKU-A × 2
SKU-B × 1
```

但：

```text
Inventory Domain
=
Availability Authority
```

Snapshot 不能说：

```text
库存一定还有 2
```

---

# 22. 历史 P2 Transaction

P3 上线前已有 Transaction：

```text
snapshot_schema_version = 1
```

不强制重写。

如需要 Resume/Recover：

```text
transaction_orders
→ orders
→ line_items
```

作为 compatibility demand resolver。

不得修改已经冻结的 transaction snapshot。

---

# 23. Transaction Start 新流程

新 canonical flow：

```text
Transactions::Start
        ↓
Resolve latest Checkout
        ↓
Quote consent
        ↓
Freeze Transaction Snapshot V2
        ↓
InventoryRequirement
        ↓
InventoryReservationPort.reserve
        ↓
all required items RESERVED
        ↓
PaymentSessions::Start
```

---

# 24. Reserve 必须发生在 PaymentSession 前

新的 transaction-first 路径冻结：

```text
Reserve Before Payment
```

因此：

```text
Reserve failure
```

必须保证：

```text
PaymentSession not created
Payment not created
PSP side effect not created
```

---

# 25. stock_reservation_strategy 重新定位

当前：

```text
order
payment
```

双策略继续作为：

```text
LEGACY COMPATIBILITY
```

存在。

新：

```text
CommerceTransaction
```

路径不再依赖该策略决定是否 Reserve。

统一：

```text
Transaction Start
→ Reserve
```

目标是逐渐把：

```text
stock_reservation_strategy
```

降级为 legacy compatibility flag。

本 P3 不要求立即删除。

---

# 26. InventoryRequirement Policy

需要判断：

```text
REQUIRED
NOT_REQUIRED
```

无需新表。

典型：

```text
normal physical SKU → REQUIRED

backorderable → NOT_REQUIRED

preorder → NOT_REQUIRED / existing policy

digital → NOT_REQUIRED

non-stock-managed → NOT_REQUIRED
```

优先复用现有 `build_targets` / stock policy。

禁止重新复制商品库存规则。

---

# 27. Reserve Idempotency

必须保证：

```text
reserve(transaction)
reserve(transaction)
reserve(transaction)
```

不会：

```text
quantity × 3
```

业务 identity：

```text
transaction_id
+
line_item_id
+
stock_item_id
```

---

# 28. Reserve Concurrency

两个 Transaction 竞争最后一个库存：

```text
Txn A
Txn B
```

必须：

```text
only one RESERVED
```

继续复用现有：

```text
StockItem pessimistic locking
```

不实现第二套锁。

---

# 29. Combination Reservation

组合交易：

```text
Transaction
├── Order A
└── Order B
```

必须：

```text
所有 REQUIRED inventory reserve 成功
```

之后才能：

```text
PaymentSessions::Start
```

---

# 30. Combination 首版不要求 DB 单事务原子 Reserve

现有 Reserve 是 per Order primitive。

首版推荐：

```text
Reserve A
Reserve B
Reserve C
```

若 B/C 失败：

```text
release all reservations
created by this Start attempt
```

形成：

```text
business-level all-or-nothing
```

而不是立即重写为大型跨订单 DB transaction。

以后有必要再优化。

---

# 31. Compensation 必须只释放本次创建的 Reservation

禁止：

```text
Reserve B failure
↓
Release(order A)
```

然后误删/释放：

```text
之前已经合法存在的 reservation
```

因此 P3-2 必须能识别：

```text
created_this_attempt
reused_existing
```

补偿只作用于：

```text
created_this_attempt
```

---

# 32. Payment Success 流程

P3 后：

```text
PaymentFactResolver = PAID
        ↓
Transactions::Finalize
        ↓
Inventory pre-finalization guard
        ↓
Existing physical inventory finalization
        ↓
Reservation → COMMITTED
        ↓
Transaction completed
```

---

# 33. Inventory Pre-finalization Guard

在真正 finalize 之前必须确认：

```text
required reservation exists
state = RESERVED
not expired
belongs to transaction
quantity matches transaction demand
```

如果不成立：

```text
do not silently finalize
```

根据资金事实进入：

```text
Recovery / Manual Review
```

---

# 34. Payment PAID + Reservation EXPIRED

这是高风险场景。

不能：

```text
Payment already PAID
↓
return insufficient_stock
↓
让用户再付
```

应该：

```text
Transaction
→ recovery_required
```

Recovery 尝试：

```text
re-reserve / reconcile inventory
```

如果无法安全满足：

```text
manual_review
```

P3 不自动退款。

---

# 35. Finalization Failure

如果：

```text
Payment = PAID
Reservation = RESERVED
Order finalize fails
```

则：

```text
Transaction = recovery_required
Reservation remains RESERVED
```

不得：

```text
Release
```

因为资金已经成功。

Recovery：

```text
PaymentFact = PAID
InventoryFact = RESERVED
↓
retry canonical finalize
↓
physical decrement
↓
Reservation COMMITTED
```

---

# 36. Partial Physical Consumption

如果 existing finalization 可能出现：

```text
部分 StockMovement 成功
随后异常
```

P3-0 / P3-3 必须确认数据库 transaction boundary。

如果无法保证 atomic：

必须让：

```text
InventoryFactResolver
```

能够识别：

```text
PARTIALLY_COMMITTED / AMBIGUOUS
```

不允许盲目重复扣减。

---

# 37. InventoryFactResolver

新增：

```text
InventoryFactResolver
```

核心输出建议：

```text
NOT_REQUIRED
UNRESERVED
RESERVED
COMMITTED
RELEASED
EXPIRED
AMBIGUOUS
```

如果组合参与者混合状态，可以返回：

```text
PARTIAL
```

或统一：

```text
AMBIGUOUS
```

首版保持简单。

---

# 38. COMMITTED Fact 判定

不能只看：

```text
reservation.state
```

建议至少检查：

```text
Reservation.state = COMMITTED

+
Order/finalization inventory facts consistent
```

若：

```text
reservation COMMITTED
但 physical inventory evidence 不一致
```

返回：

```text
AMBIGUOUS
```

---

# 39. Recovery 决策矩阵

| Payment Fact | Inventory Fact | Order      | 动作                                     |
| ------------ | -------------- | ---------- | -------------------------------------- |
| UNPAID       | RESERVED       | incomplete | 允许继续支付                                 |
| UNPAID       | EXPIRED        | incomplete | Re-reserve 后才可支付                       |
| UNPAID       | RESERVED       | canceled   | Release                                |
| PAID         | RESERVED       | incomplete | Retry Finalize → Commit                |
| PAID         | COMMITTED      | incomplete | Retry business finalization            |
| PAID         | COMMITTED      | complete   | Repair Transaction                     |
| PAID         | EXPIRED        | incomplete | Recovery / stock reconcile             |
| PAID         | RELEASED       | incomplete | Critical inconsistency → manual_review |
| PAID         | AMBIGUOUS      | 任意         | manual_review                          |
| AMBIGUOUS    | 任意             | 任意         | Payment recovery first                 |

---

# 40. Release Policy

只有：

```text
Reservation = RESERVED
```

可以正常 Release。

并且对于已经有 PaymentSession 的 Transaction，Release 前必须：

```text
PaymentFactResolver
```

确认：

```text
UNPAID
```

---

# 41. 禁止 PAID Transaction 普通 Release

核心 invariant：

```text
PAID
+
RESERVED
```

不能走：

```text
Release
```

只能：

```text
Finalize / Recover / Manual Review
```

---

# 42. Order Cancellation

当前取消路径没有可靠释放 active Reservation。

P3 必须补：

```text
pre-payment cancellation
↓
PaymentFact = UNPAID
↓
Reservation RESERVED
↓
RELEASED
```

---

# 43. Post-sale Cancel / Restock 不归 Reservation Release

如果：

```text
Reservation = COMMITTED
```

之后订单进入：

```text
cancel / refund / return / restock
```

这是：

```text
售后库存
```

不是：

```text
Reservation Release
```

P3 不要重新打开 COMMITTED reservation。

---

# 44. ExpireJob

现有 ExpireJob 从：

```text
delete expired rows
```

改为：

```text
RESERVED + expires_at <= now
→ EXPIRED
```

并正式加入 scheduler。

---

# 45. TTL 策略修正

审计建议中出现：

```text
reservation_ttl ≤ payment_execution_window
```

这个方向需要修正。

正确 invariant 应为：

```text
reservation_validity
>=
active payment execution window
```

或者：

```text
active PaymentSession
→ automatically Extend reservation
```

否则会出现：

```text
3DS still active
Reservation already expired
```

---

# 46. 推荐 TTL 关系

定义：

```text
reservation_ttl

payment_session_validity

transaction_payment_window
```

必须保证：

```text
Reservation 不会在合法活跃 PaymentSession 仍可成功时
提前失效而无人处理
```

第一版可以：

```text
PaymentSession active
→ Extend reservation
```

复用现有：

```text
StockReservations::Extend
```

---

# 47. Resume Payment Gate

每次：

```text
Transactions::Resume
```

或创建新 PaymentSession 前必须检查：

```text
InventoryFact
```

如果：

```text
RESERVED
→ continue

EXPIRED
→ re-reserve

RELEASED
→ inventory_changed

COMMITTED
→ payment normally forbidden / transaction already paid

AMBIGUOUS
→ block
```

---

# 48. Re-reserve

Re-reserve 必须重新检查：

```text
current inventory authority
```

不能因为原来曾经 reserve 成功就直接恢复。

如果库存不够：

```text
INVENTORY_CHANGED
```

---

# 49. Storefront Error Contract

建议正式增加：

```text
INSUFFICIENT_STOCK

INVENTORY_CHANGED

RESERVATION_EXPIRED

INVENTORY_RECOVERY_REQUIRED
```

但保持职责：

```text
Server decides
Frontend renders
```

Frontend 不自己推导库存状态。

---

# 50. Admin / Ops

扩展现有 Transaction Admin。

展示：

```text
Inventory Fact

Reservation IDs

Stock Item

Line Item

Quantity

Reservation State

Reserved At

Expires At

Committed At

Released At

Expired At

Release Reason

Inventory Recovery Status
```

---

# 51. Audit Events

复用现有 Audit：

```text
inventory.reserve_started
inventory.reserved
inventory.reserve_failed

inventory.extended

inventory.commit_started
inventory.committed
inventory.commit_failed

inventory.release_started
inventory.released
inventory.release_failed

inventory.expired

inventory.recovery_started
inventory.recovery_completed
inventory.manual_review
```

---

# 52. Trace

P3 完整 trace：

```text
Order
↓
CheckoutSnapshot
↓
CommerceTransaction
↓
Transaction Snapshot V2
↓
StockReservation
↓
PaymentSession
↓
Payment
↓
PSP
↓
Order Finalization
↓
StockMovement
↓
Reservation COMMITTED
↓
Transaction Completed
```

---

# 53. P3-0 — Formal Semantic Freeze

当前审计已经完成大部分事实取证。

所以 P3-0 不需要重新进行大范围探索。

主要任务：

> 把当前审计结论正式冻结成 Implementation Contract。

必须冻结：

```text
INVENTORY_AUTHORITY

RESERVATION_IDENTITY

RESERVATION_LIFECYCLE

RESERVATION_TIMING

RESERVATION_TTL_POLICY

INVENTORY_RECOVERY_POLICY

COMMIT_SEMANTICS
```

相比上一版增加：

```text
COMMIT_SEMANTICS
```

这是本次审计后最重要的新增决策。

---

# 54. INV-P3-1 — Reservation Lifecycle Foundation

实现：

```text
state

transaction_id nullable

reserved_at
committed_at
released_at
expired_at

release_reason

lock_version / concurrency convention
```

修改：

```text
active reservation scope

Quantifier

unique indexes

Expire semantics
```

不接 Transaction Start。

---

# 55. INV-P3-1 关键 Gate

必须证明：

```text
旧 Reserve behavior 不回归

active RESERVED 仍正确降低 ATS

COMMITTED 不重复降低 ATS

RELEASED 不降低 ATS

EXPIRED 不降低 ATS

历史 transaction_id NULL 可正常运行
```

---

# 56. INV-P3-2 — Transaction Snapshot V2 + Reserve Integration

实现：

```text
Transaction Snapshot schema v2

inventory_demand[]

InventoryRequirement

InventoryReservationPort

StockReservationAdapter
```

然后：

```text
Transactions::Start
→ Reserve
→ PaymentSessions::Start
```

---

# 57. INV-P3-2 Combination Gate

实现：

```text
all participants reserve
or
compensate reservations created in this attempt
```

只有全体成功：

```text
PaymentSession allowed
```

---

# 58. INV-P3-3 — Finalization / Commit Coordination

这是 P3 风险最高的包。

不要：

```text
改写 StockMovement
```

建立：

```text
InventoryCommitCoordinator
```

将：

```text
payment confirmed
+
reservation guard
+
existing Carts::Complete/finalization
+
reservation COMMITTED confirmation
```

组合起来。

---

# 59. INV-P3-3 对 Carts::Complete 的改造原则

当前：

```text
finalize
→ Release(delete reservation)
```

目标：

### Transaction-aware path

```text
finalize
→ Reservation COMMITTED
```

### Legacy no-transaction path

短期允许：

```text
原行为 compatibility
```

但应明确标记：

```text
LEGACY INVENTORY ADAPTER
```

不要一次性破坏旧路径。

---

# 60. INV-P3-4 — Release / Expiration / TTL

实现：

```text
Cancel → Release

ExpireJob → EXPIRED

scheduler

PaymentSession active → Extend

Resume → Reservation Gate

Re-reserve
```

---

# 61. INV-P3-5 — Inventory Recovery

扩展 P2：

```text
Transactions::Recover
```

新流程：

```text
PaymentFactResolver
↓
InventoryFactResolver
↓
Recovery Plan
```

支持：

```text
PAID + RESERVED
PAID + COMMITTED
UNPAID + RESERVED
UNPAID + EXPIRED
PAID + EXPIRED
PAID + RELEASED
AMBIGUOUS
```

---

# 62. INV-P3-6 — Combination + Legacy Convergence

专门处理：

```text
PaymentCombination

Transaction N Orders

legacy reservation strategy

legacy Carts::Complete inventory branches
```

避免把组合兼容逻辑散进 P3-2/P3-3。

---

# 63. INV-P3-7 — Storefront / Operations

实现：

```text
inventory error UI

Transaction Admin inventory panel

audit events

structured metrics

recovery tooling

runbook
```

---

# 64. 推荐实施顺序

```text
INV-P3-0
Semantic Freeze
        ↓
INV-P3-1
Reservation Lifecycle Foundation
        ↓
INV-P3-2
Snapshot V2 + Reserve Before Payment
        ↓
INV-P3-3
Physical Finalization + Commit Confirmation
        ↓
INV-P3-4
Release / Expire / TTL
        ↓
INV-P3-5
Inventory Recovery
        ↓
INV-P3-6
Combination / Legacy Convergence
        ↓
INV-P3-7
Storefront / Operations
```

---

# 65. Acceptance Criteria

## AC-3001

新 transaction-first purchase 在创建 PaymentSession 前完成 required inventory Reserve。

## AC-3002

Reserve 失败不得产生 PaymentSession / PSP side effect。

## AC-3003

Reserve 重试幂等。

## AC-3004

并发争抢最后一个库存只能一个 Transaction 成功 Reserve。

## AC-3005

backorder / preorder / digital 等正确判定 NOT_REQUIRED。

## AC-3006

Reservation 可通过 transaction/order/line_item/stock_item 完整 trace。

## AC-3007

Transaction Snapshot V2 包含 immutable inventory demand evidence。

## AC-3008

Snapshot 不成为库存 availability authority。

## AC-3009

Payment confirmed 后仍通过现有 finalization / StockMovement 完成物理库存消费。

## AC-3010

P3 不产生第二套 physical stock decrement。

## AC-3011

物理库存消费成功后 Reservation 转 COMMITTED。

## AC-3012

COMMITTED Reservation 不再降低 ATS。

## AC-3013

Payment confirmed + Finalization failure：

```text
Transaction = recovery_required
Reservation remains RESERVED unless consumption has actually succeeded
```

## AC-3014

Recovery 可以安全完成：

```text
PAID + RESERVED
→ Finalize
→ COMMITTED
→ Transaction completed
```

## AC-3015

重复 Recovery 不重复扣库存。

## AC-3016

UNPAID + canceled 可将 RESERVED → RELEASED。

## AC-3017

PAID Transaction 禁止普通 Release。

## AC-3018

TTL 到期将 RESERVED → EXPIRED，不硬删除。

## AC-3019

EXPIRED Reservation 不降低 ATS。

## AC-3020

合法 active payment execution 不允许因为 TTL 策略静默失去库存保证。

## AC-3021

Reservation expired 后，新支付动作前必须重新 Reserve。

## AC-3022

组合 Transaction 全部 required items Reserve 成功后才能支付。

## AC-3023

组合部分 Reserve 失败只补偿本 Start attempt 新建的 Reservation。

## AC-3024

Transaction-aware canonical path 不再把完成后的 Reservation 硬删除。

## AC-3025

Order cancel 正确释放仍处于 RESERVED 的 Reservation。

## AC-3026

P0 Payment baseline 全绿。

## AC-3027

P1 Checkout baseline 全绿。

## AC-3028

P2 Transaction baseline 全绿。

---

# 66. P3 核心 Invariants

## INV-I01

```text
StockItem.count_on_hand + StockMovement
是唯一 physical inventory authority。
```

## INV-I02

```text
StockReservation
只是 allocation/reservation fact。
```

## INV-I03

```text
Reserve 不修改 physical count_on_hand。
```

## INV-I04

```text
P3 Commit 不建立第二套库存扣减。
```

## INV-I05

```text
COMMITTED
必须建立在 physical inventory consumption 已成功的事实之上。
```

## INV-I06

```text
Reserve 必须幂等。
```

## INV-I07

```text
Finalization / inventory consumption 必须幂等。
```

## INV-I08

```text
PAID + inventory incomplete
=
RECOVERY_REQUIRED
```

## INV-I09

```text
PAID Transaction
不得普通 Release reservation。
```

## INV-I10

```text
只有 RESERVED 且未过期 reservation
降低 available-to-sell。
```

## INV-I11

```text
合法 payment execution window
不得长于未被续期的 reservation validity。
```

## INV-I12

```text
Snapshot = inventory demand evidence

Inventory Domain = availability authority
```

## INV-I13

```text
Combination 必须 business-level all-reserved
才能产生支付副作用。
```

## INV-I14

```text
Fulfillment split
不自动形成新的 inventory transaction。
```

---

# 67. P3 明确不做

```text
❌ 重写 StockItem

❌ 重写 StockMovement

❌ 第二套 physical quantity

❌ Inventory Ledger 全面重构

❌ 多仓智能分配

❌ ERP / WMS

❌ ATP forecasting

❌ Safety Stock optimization

❌ Procurement planning

❌ Return / RMA / Restock 重构

❌ Refund orchestration

❌ Checkout 重写

❌ CommerceTransaction 重写

❌ Payment Router

❌ 分布式 2PC

❌ 强制 MQ

❌ 微服务拆分
```

---

# 68. 可复用矩阵

```text
StockItem
→ REUSE AS AUTHORITY

StockMovement
→ REUSE AS PHYSICAL CONSUMPTION

Stock::Quantifier
→ EXTEND ACTIVE RESERVATION FILTER

StockReservation
→ EXTEND LIFECYCLE / TRANSACTION OWNERSHIP

StockReservations::Reserve
→ WRAP / EXTEND

StockReservations::Release
→ CHANGE DELETE TO RELEASED SEMANTICS

StockReservations::Extend
→ REUSE

ExpireJob
→ CHANGE DELETE TO EXPIRED + SCHEDULE

CommerceTransaction
→ REUSE

Transaction Snapshot
→ VERSION TO V2

Transactions::Start
→ EXTEND RESERVE STAGE

Transactions::Finalize
→ EXTEND INVENTORY COMMIT COORDINATION

Transactions::Recover
→ EXTEND INVENTORY FACT / RECOVERY

PaymentFactResolver
→ REUSE

Carts::Complete
→ KEEP PHYSICAL FINALIZATION PRIMITIVE

AuditLog / Transaction Admin
→ EXTEND
```

---

# 69. P3 风险排序

### RISK-P3-01 — Finalization / Commit coordination

最高。

因为现有物理扣库存隐藏在：

```text
Order finalize
→ Shipment
→ InventoryUnit
→ StockMovement
```

错误插入 commit 很容易双扣或提前 commit。

---

### RISK-P3-02 — Hard-delete → stateful history

需要修改：

```text
active scope
Quantifier
unique index
cleanup behavior
```

否则可能出现：

```text
历史 reservation 继续占 ATS
```

---

### RISK-P3-03 — 3DS / Payment window vs TTL

Reservation 提前过期而 PSP 仍能成功是重大竞态。

---

### RISK-P3-04 — Combination partial reservation

需要可靠 compensation。

---

### RISK-P3-05 — Legacy `stock_reservation_strategy`

新 transaction-first 语义不能被 legacy flag 反向控制。

---

### RISK-P3-06 — Cancellation

当前 cancel 与 reservation 生命周期脱节，需要补齐。

---

# 70. Release Verification

P3 完成后至少：

## RV-I01 — Normal

```text
Transaction
→ Reserve
→ Payment
→ Finalize/StockMovement
→ Reservation COMMITTED
→ Transaction completed
```

检查：

```text
ATS 正确
count_on_hand 正确
无双扣
```

---

## RV-I02 — Last Unit Race

```text
Stock = 1

Txn A + Txn B
→ concurrent reserve
```

只能一个成功。

---

## RV-I03 — Paid Finalization Recovery

```text
RESERVED
→ Payment PAID
→ controlled finalization failure
→ recovery_required
→ Recover
→ StockMovement once
→ COMMITTED
→ completed
```

重点：

```text
不得重复扣库存
不得重复支付
```

---

## RV-I04 — Combination

```text
N Orders
→ all reserve
→ Payment
→ all physical consumption
→ all reservations committed
```

并测试：

```text
partial reserve failure compensation
```

---

## RV-I05 — TTL / 3DS

验证：

```text
active PaymentSession
+
long authentication
```

Reservation 不会无感过期导致：

```text
PSP succeeded
+
inventory guarantee disappeared
```

---

# 71. Definition of Done

P3 完成以后：

```text
Checkout
↓
CommerceTransaction
↓
Snapshot V2
↓
Reserve
↓
RESERVED
↓
Payment
↓
PAID
↓
Canonical Finalization
↓
StockMovement
↓
COMMITTED
↓
Transaction Completed
```

失败：

```text
Payment PAID
+
Inventory / Finalization incomplete
↓
RECOVERY_REQUIRED
↓
PaymentFactResolver
+
InventoryFactResolver
↓
Safe Retry
↓
COMMITTED
↓
COMPLETED
```

---

# 72. 当前下一步

当前建议只正式完成：

```text
INV-P3-0 — Semantic Freeze
```

这次不需要重新做一轮宽泛 Repo Audit。

现有审计已经给出了大部分事实。

P3-0 主要冻结：

```text
INVENTORY_AUTHORITY
RESERVATION_IDENTITY
RESERVATION_LIFECYCLE
RESERVATION_TIMING
RESERVATION_TTL_POLICY
INVENTORY_RECOVERY_POLICY
COMMIT_SEMANTICS
```

尤其最终确认：

> **COMMITTED = 现有 canonical StockMovement 物理消费成功后的 Reservation 历史事实；不是新的库存扣减动作。**

这项冻结后，才批准：

```text
INV-P3-1
```

的 migration 与生命周期实现。
