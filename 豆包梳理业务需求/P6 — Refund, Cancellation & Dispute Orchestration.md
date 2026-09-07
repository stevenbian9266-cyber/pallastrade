# P6 — Reverse Commerce Orchestration & Recovery

> 工程编号：`REV-P6`
>
> 前置：
>
> ```text
> P0 — Payment Execution Foundation
> P1 — Commercial Checkout Facts
> P2 — Commerce Transaction Runtime
> P3 — Inventory Consistency Integration
> P4 — Financial Fact / Journal / Reconciliation
> P5 — Commerce Core Consolidation & Legacy Convergence
> ```
>
> 核心定位：
>
> **在不重写现有 Return / Reimbursement / Inventory / Payment 基础设施的前提下，把 Merchant-initiated Reverse Commerce 正式纳入 Commerce Core：将 Refund 从“事务内同步副作用”升级为 durable、幂等、可恢复的资金执行生命周期，并统一 Cancellation、Partial/Combination Refund、Restock 与 Financial Recovery。**
>
> P6 闭环范围：
>
> ```text
> Refund
> + Cancellation
> + Return / Restock
> + Reverse Recovery
> + Financial Journal / Reconciliation
> ```
>
> `Dispute / Chargeback` 明确顺延后续独立阶段。

---

# 1. P6 的真实起点

P0-P5 已形成稳定正向主链：

```text
Checkout
↓
CommerceTransaction
↓
Inventory Reserve
↓
Payment Execution
↓
Payment Fact
↓
Canonical Finalization
↓
StockMovement(-)
↓
Inventory COMMITTED
↓
Financial Fact
↓
Journal
↓
Reconciliation
```

现在缺失的是一条同样可靠的逆向链：

```text
Completed Commerce
↓
Cancellation / Return / Refund Intent
↓
Durable Reverse Execution
├── Refund
├── Order Adjustment
├── Restock
└── Financial Posting
↓
Reverse Recovery
↓
Reconciliation
```

---

# 2. P6 首要问题不是 Return UI，而是 Refund 安全性

现有 Refund 语义存在根本缺陷：

```text
Refund.create
↓
after_create :perform!
↓
DB transaction 内调用 PSP
↓
PSP refund succeeded
↓
后续本地更新失败
↓
整个 DB transaction rollback
↓
Refund row 消失
```

最终可能形成：

```text
PSP:
钱已经退了

Local:
没有 Refund
没有 provider reference
没有 Journal
没有 Recovery owner
```

这是 P6 第一优先级必须消灭的事故模型。

---

# 3. P6 最重要的语义拆分

现有：

```text
Refund
=
Refund Request
+
Refund Execution
+
Refund Success Fact
```

目标：

```text
Refund
=
Durable Refund Execution Context

FinancialFact
=
Refund Financial Fact

FinancialJournalEntry
=
Immutable Financial History
```

因此：

```text
Refund Request
≠
Provider Refund Execution
≠
Refund Financial Fact
≠
Order Adjustment
≠
Inventory Restock
```

---

# 4. 不新增 ReverseTransaction

P6 第一版明确：

```text
NO ReverseTransaction table
```

原因：

当前已经有足够的 durable participants：

```text
OrderCancellation
Reimbursement
CustomerReturn
ReturnItem
Refund
Payment
PaymentSplit
StockMovement
FinancialJournalEntry
CommerceTransaction
```

再创建：

```text
ReverseTransaction
```

极易变成：

```text
第二套 CommerceTransaction
+
第二套 Reimbursement
+
第二套 Refund ownership
```

P6 使用：

```text
ReverseCommerce Application Layer
```

编排已有领域对象。

---

# 5. Original CommerceTransaction 不回退

这是 P6 必须冻结的核心原则。

正常：

```text
CommerceTransaction = completed
↓
以后发生退款
```

禁止：

```text
completed
→ refund_pending
→ refunded
```

污染 P2 状态机。

原始 CommerceTransaction 表达：

> 原始商业交易当时是否完成。

Refund 是后来发生的新逆向事实。

因此：

```text
Original Transaction remains COMPLETED
```

Reverse 状态由：

```text
Refund
OrderCancellation
Return / Reimbursement
Financial Reconciliation
```

分别表达。

---

# 6. Reverse Commerce Ownership

正式冻结：

| 事实                            | Authority                       |
| ----------------------------- | ------------------------------- |
| 原支付是否成功                       | `PaymentFactResolver`           |
| Refund 执行上下文                  | `Refund`                        |
| Refund 金融事实                   | `FinancialFacts::ResolveRefund` |
| Refund immutable history      | `FinancialJournalEntry`         |
| Combination refund allocation | `PaymentSplit`                  |
| Cancellation intent           | `OrderCancellation`             |
| Return item business status   | `ReturnItem / CustomerReturn`   |
| Physical restock              | `StockMovement(+)`              |
| Inventory quantity            | `StockItem.count_on_hand`       |
| Financial consistency         | P4 Reconciliation               |

---

# 7. PaymentFact 与 FinancialFact Authority 裁决

P6 不允许再发展第三套资金事实。

正式定义：

```text
Transactions::PaymentFactResolver
```

只回答：

```text
原始 Payment 是否 authoritative PAID / UNPAID / AMBIGUOUS？
```

用于：

```text
能不能 Refund？
能不能 Cancel without refund？
能不能产生新的资金副作用？
```

而：

```text
FinancialFacts::ResolvePayment
FinancialFacts::ResolveRefund
```

回答：

```text
具体发生了什么金融事实
amount
currency
instrument
provider reference
```

用于：

```text
Journal
Reconciliation
Financial Summary
```

二者职责不同，不互相复制。

---

# 8. Refund 模型语义重构

不新建 RefundRequest 表。

升级现有：

```text
PallasTrade::Refund
```

从：

```text
successful-refund-only row
```

变成：

> **Durable Refund Execution Aggregate**

---

# 9. Refund Lifecycle

建议最小状态：

```text
requested
   ↓
processing
   ├────────→ succeeded
   ├────────→ failed
   └────────→ ambiguous
                    │
          ┌─────────┼─────────┐
          ▼         ▼         ▼
     processing  succeeded  failed
                    │
                    └────→ manual_review
```

可选：

```text
requested → canceled
```

仅允许 PSP side effect 尚未开始时撤销请求。

---

# 10. Refund 状态语义

## REQUESTED

```text
本地退款意图已 durable
尚未调用 PSP
```

## PROCESSING

```text
准备/正在执行 provider refund
```

## SUCCEEDED

```text
provider refund 已权威确认成功
本地 success projection 已完成
```

## FAILED

```text
provider 明确拒绝/失败
可以释放 refund capacity
```

## AMBIGUOUS

```text
不知道 PSP 是否已经退款
```

此状态：

```text
不得创建第二笔替代 Refund
不得释放 refund capacity
```

## MANUAL_REVIEW

```text
无法通过当前 provider contract 自动确定真实资金结果
```

---

# 11. Refund 表候选增强

最终字段由 REV-P6-0 DB proposal 冻结，但建议至少支持：

```text
refunds

state

commerce_transaction_id nullable
target_order_id nullable
payment_split_id nullable

provider_idempotency_key
provider_refund_reference
# 现有 transaction_id 可兼容保留，
# 新代码不继续使用模糊命名

requested_at
processing_at
succeeded_at
failed_at
ambiguous_at

last_error_code
last_error_message

attempt_count
lock_version

metadata
```

历史成功 Refund：

```text
backfill state = succeeded
```

不得猜无法确定的新 ownership。

---

# 12. Refund 创建必须先于 PSP 副作用

新 canonical flow：

```text
Refunds::Request
↓
lock Payment
↓
validate refundable capacity
↓
CREATE Refund(state=requested)
↓
COMMIT DATABASE
↓
enqueue ExecuteRefundJob
↓
RETURN
```

只有 Refund row durable 成功后：

```text
才允许调用 PSP
```

因此不再存在：

```text
PSP refund
但 local 完全没有 owner
```

的正常路径。

---

# 13. Provider I/O 禁止位于 DB Transaction / Lock 内

延续 P0/P2 已验证原则：

```text
DB lock
→ claim operation / reserve capacity
→ commit

Provider I/O

DB transaction
→ apply provider result
```

禁止：

```text
payment.with_lock do
  gateway.credit(...)
end
```

长期占锁。

---

# 14. Refund Capacity Reservation

把 provider I/O 移出 lock 后，必须解决新的并发问题：

```text
Refund A 请求 60
Refund B 请求 60

Payment 可退 100
```

不能让两个请求都通过。

因此 Payment refundable capacity 必须计算：

```text
captured amount
-
successful refunds
-
active refund reservations
```

其中 active refund：

```text
requested
processing
ambiguous
```

都占用 Refund Capacity。

---

# 15. Refund Capacity Invariant

正式冻结：

```text
Σ SUCCEEDED refunds
+
Σ REQUESTED/PROCESSING/AMBIGUOUS refunds
≤
Payment refundable amount
```

FAILED / canceled：

```text
不占用 capacity
```

数据库不能完全表达时：

```text
Payment pessimistic lock
+
application invariant
```

作为 canonical guard。

---

# 16. Refund Execution

目标服务：

```text
Refunds::Execute
```

逻辑：

```text
Refund REQUESTED
↓
claim → PROCESSING
↓
commit
↓
PSP refund(idempotency_key)
↓
Resolve Provider Outcome
     │
     ├─ success
     │     ↓
     │  ApplySuccess
     │
     ├─ definite failure
     │     ↓
     │  FAILED
     │
     └─ unknown / timeout
           ↓
        AMBIGUOUS
```

---

# 17. Refund Provider Idempotency

每个 Refund 使用稳定：

```text
provider_idempotency_key
```

例如：

```text
refund:{refund_prefixed_id}:execute
```

同一个 Refund：

```text
Job retry
timeout retry
Recovery retry
```

必须始终使用相同 provider idempotency key。

禁止：

```text
attempt-1 → key A
attempt-2 → key B
```

对 ambiguous outcome 重新发起新的真实退款。

---

# 18. Provider Metadata

Provider 支持时附带：

```text
refund_id
commerce_transaction_id
payment_id
target_order_id
operation_key
```

用于：

```text
orphan detection
reconciliation
manual incident investigation
```

---

# 19. ApplySuccess 必须独立幂等

Provider 返回成功后：

```text
Refunds::ApplySuccess
```

完成：

```text
Refund → succeeded
provider reference persist
PaymentSplit.refunded_amount update
Order payment projection update
timestamps
audit
```

全部在一个**本地 DB transaction**中完成。

---

# 20. 为什么 ApplySuccess 必须独立

考虑：

```text
PSP succeeded
↓
ApplySuccess DB exception
```

Refund row 仍然存在：

```text
processing / ambiguous
```

Recovery 可以：

```text
Provider confirms SUCCEEDED
↓
retry ApplySuccess
```

不需要：

```text
再退款一次
```

这就是 P6 相比当前 Refund 实现最大的安全提升。

---

# 21. Refund Fact

P6 不新增第二个 RefundFact authority。

继续复用：

```text
FinancialFacts::ResolveRefund
```

并升级其能力：

```text
REQUESTED      → pending
PROCESSING     → pending
SUCCEEDED      → REFUND_SUCCEEDED
FAILED         → failed
AMBIGUOUS      → ambiguous
```

---

# 22. Journal 语义

正常 business Refund：

```text
Payment:
CASH_CAPTURED +100

Refund:
REFUND_SUCCEEDED -30
```

最终：

```text
Net Customer Cash = 70
```

---

# 23. FinancialLedger::Reverse 不用于正常 Refund

正式冻结：

```text
Refund != Ledger Reversal
```

禁止：

```text
Payment +100
↓ normal refund
Reverse(original payment entry)
```

因为这会破坏：

```text
partial refunds
multiple refunds
historical payment fact
```

正常 Refund 永远追加：

```text
REFUND_SUCCEEDED
```

`FinancialLedger::Reverse` 仅用于：

> **Journal 本身记录错误时的 accounting/evidence correction。**

不是业务退款工具。

---

# 24. Refund Ownership

新 Refund 创建时冻结：

```text
Payment
CommerceTransaction if provable
target Order
PaymentSplit if combination
```

推荐优先路径：

```text
Payment
→ PaymentSession
→ CommerceTransaction
```

其次：

```text
Payment
→ PaymentCombination
→ CommerceTransaction
```

组合退款：

```text
Payment
→ target PaymentSplit
→ target Order
```

---

# 25. 不再依赖运行时脆弱推导

当前组合退款可通过：

```text
Reimbursement
→ ReturnItem
→ InventoryUnit
→ Order
```

推导 target order。

P6 新 Refund 在 REQUESTED 时应尽量冻结：

```text
target_order_id
payment_split_id
```

后续 Execute / Recover 不重新猜 ownership。

legacy Refund 可以继续 fallback 推导。

---

# 26. Partial Refund

Multiple partial refund 保持：

```text
Refund #1
Refund #2
Refund #3
```

每笔：

```text
独立 Refund row
独立 PSP identity
独立 Financial Fact
独立 Journal Entry
```

禁止只维护：

```text
total_refunded
```

作为唯一事实。

---

# 27. Combination Refund

例如：

```text
Combined Payment = 100

Order A Split = 60
Order B Split = 40
```

退款：

```text
Order A Refund = 20
```

必须形成：

```text
Payment refund        -20
Order A refunded      +20 allocation effect
Order B                unchanged
```

并满足：

```text
split.refunded_amount
≤
split.captured_amount
```

---

# 28. Refund Allocation Authority

继续保留：

```text
PaymentSplit
```

作为组合 Order-level refund allocation authority。

Financial Journal：

```text
REFUND_SUCCEEDED
```

表示资金事实。

禁止：

```text
PaymentSplit.refunded_amount
```

再被当作第二笔资金流。

---

# 29. Tax / Shipping / Promotion Refund

P6 不另造 Calculator。

REV-P6-0 / P6-3 正式审计：

```text
DefaultRefundAmount
ReimbursementTaxCalculator
legacy reimbursement calculation
```

然后冻结：

```text
REFUND_AMOUNT_AUTHORITY
REFUND_TAX_ALLOCATION_POLICY
REFUND_SHIPPING_ALLOCATION_POLICY
REFUND_PROMOTION_ALLOCATION_POLICY
```

有成熟 primitive：

```text
REUSE
```

没有：

```text
不得在 Controller / UI 临时计算
```

---

# 30. Cancellation 重新定义

当前不健康语义：

```text
Gateway.cancel
↓
if payment.completed?
↓
隐式 create Refund
```

这是错误的 ownership。

Provider Gateway 不应该决定：

> “业务上是不是应该退款”。

---

# 31. 新 Cancellation Boundary

统一：

```text
OrderCancellation
↓
Cancellation Orchestrator
```

负责：

```text
Payment Fact
Inventory Fact
Order State
Refund Policy
Restock Requirement
```

Gateway 只执行：

```text
void authorization
refund request
```

等 provider primitive。

---

# 32. Pre-payment Cancellation

```text
PaymentFact = UNPAID
Inventory = RESERVED
↓
Cancel
↓
void authorization if needed
↓
Reservation RELEASED
↓
Order canceled
↓
NO Refund
↓
NO Restock
```

因为：

```text
physical inventory 从未消费
```

---

# 33. Paid Cancellation

如果：

```text
PaymentFact = PAID
```

业务取消：

```text
OrderCancellation durable intent
↓
determine refund requirement
↓
create durable Refund REQUESTED
↓
apply Order cancellation
↓
Restock if physical inventory had been consumed
↓
execute Refund asynchronously
↓
Refund Fact
↓
Journal / Reconciliation
```

Refund 与 Restock 分别恢复。

---

# 34. Cancellation Intent 必须 Durable

`OrderCancellation` 继续作为取消业务 intent owner。

建议增加/明确：

```text
requested
processing
applied
recovery_required
completed
manual_review
```

是否需要新增 state 字段由 REV-P6-0 DB audit 决定。

但禁止：

```text
controller 里临时 cancel + refund
```

而没有 durable cancellation evidence。

---

# 35. Cancellation 与 Refund 独立

允许：

```text
Order = canceled
Refund = processing
```

这不是非法状态。

同样允许短期：

```text
Order = canceled
Restock = complete
Refund = ambiguous
```

系统必须通过 Reverse Recovery 收尾。

---

# 36. Restock Authority

继续严格继承 P3：

```text
StockItem.count_on_hand
+
StockMovement
=
physical inventory authority
```

---

# 37. COMMITTED Reservation 永远不 Release

支付并物理消费后：

```text
StockReservation = COMMITTED
```

之后发生：

```text
Cancel / Return
```

禁止：

```text
COMMITTED → RELEASED
```

恢复库存。

必须：

```text
StockMovement(+)
```

---

# 38. Cancellation Restock

订单取消时已存在：

```text
Shipment cancel
→ manifest_restock
→ StockMovement(+)
```

P6 原则：

```text
REUSE
```

不建立第二套 Restock algorithm。

重点补：

```text
idempotency
fact resolution
recovery
```

---

# 39. Return Restock

当前 ReturnItem 在 receive 阶段可能直接：

```text
receive
→ should_restock?
→ restock
```

P6 目标语义更明确：

```text
Return Received
↓
Inspection / Acceptance
↓
Restock Decision
     │
     ├─ RESELLABLE
     │      ↓
     │   StockMovement(+)
     │
     └─ NOT_RESELLABLE
            ↓
         no restock
```

---

# 40. Refund 与 Restock 永远分离

例如：

```text
Refund succeeded
Return item damaged
```

合法：

```text
钱退了
库存不增加
```

又例如：

```text
Return received
Inventory restocked
Refund pending
```

也合法。

因此：

```text
Refund Fact
≠
Restock Fact
```

---

# 41. Restock Fact Resolver

新增或形成等价：

```text
RestockFactResolver
```

输出：

```text
NOT_REQUIRED
PENDING
RESTOCKED
NOT_RESTOCKABLE
AMBIGUOUS
```

evidence 来自：

```text
ReturnItem
InventoryUnit
Shipment
StockMovement
```

不是 Refund state。

---

# 42. Restock Idempotency

P6 必须审计：

```text
Return receive retry
Cancellation retry
Recovery retry
```

是否可能生成第二次：

```text
StockMovement(+)
```

若现有 InventoryUnit transaction boundary 已可证明 exactly-once：

```text
REUSE
```

否则必须增加 stable restock operation identity。

核心 invariant：

```text
one logical restock
→ at most one physical positive movement
```

---

# 43. Reimbursement 定位

保留现有：

```text
Reimbursement
```

作为：

> 售后业务金额/退款分配上下文。

但它不是：

```text
PSP Refund Execution
```

实际资金副作用必须走：

```text
Refunds::Request
→ Refunds::Execute
```

---

# 44. CustomerReturn 定位

继续表示：

```text
商品退回业务流程
```

不升级为：

```text
ReverseTransaction
```

---

# 45. Reverse Recovery

新增统一 application layer：

```text
ReverseCommerce::Recover
```

它不自己猜状态，而消费：

```text
PaymentFact
Refund Financial Fact
Restock Fact
Order / Cancellation Fact
Journal / Reconciliation
```

---

# 46. Refund Recovery

推荐：

```text
Refunds::Recover
Refunds::RecoverJob
Refunds::RecoverSweeperJob
```

主要处理：

```text
processing too long
ambiguous
provider success/local incomplete
local success/journal incomplete
```

---

# 47. Refund Recovery Matrix

| Local Refund  | Provider Fact           | Action                   |
| ------------- | ----------------------- | ------------------------ |
| REQUESTED     | none                    | Execute                  |
| PROCESSING    | pending                 | wait/retry query         |
| PROCESSING    | SUCCEEDED               | ApplySuccess             |
| PROCESSING    | FAILED                  | mark FAILED              |
| PROCESSING    | unknown                 | AMBIGUOUS                |
| AMBIGUOUS     | SUCCEEDED               | ApplySuccess             |
| AMBIGUOUS     | FAILED                  | mark FAILED              |
| AMBIGUOUS     | unavailable             | retry/manual_review      |
| SUCCEEDED     | journal missing         | repair Journal           |
| SUCCEEDED     | reconciliation mismatch | P4 Reconciliation        |
| FAILED        | none                    | release refund capacity  |
| MANUAL_REVIEW | any                     | no automatic side effect |

---

# 48. Provider Success + Local Failure

P6 最重要恢复链：

```text
PSP Refund SUCCEEDED
↓
local ApplySuccess failed
↓
Refund remains PROCESSING / AMBIGUOUS
↓
Recover
↓
fetch provider refund
↓
SUCCEEDED
↓
ApplySuccess
↓
PostRefund
↓
Reconcile
```

全过程：

```text
NO second refund
```

---

# 49. Timeout / Unknown Outcome

例如：

```text
POST refund
↓
network timeout
```

禁止：

```text
立即创建 Refund #2
```

正确：

```text
Refund #1 → AMBIGUOUS
↓
same operation key
↓
provider status query / same idempotent execution
↓
resolve
```

---

# 50. Provider Capability

Stripe：

```text
refund execution
provider idempotency
fetch_refund_details
reconciliation
```

作为第一版完整实现。

Adyen / PayPal：

```text
legacy partial capability
```

无法确认 ambiguous refund 时：

```text
manual_review
```

禁止：

```text
猜 FAILED
→ 再退一次
```

---

# 51. Reverse Financial Recovery

P4 已有：

```text
PostRefund
ReconcileRefund
ReconcileSweeper
Journal repair
```

P6 复用。

边界：

```text
P6
负责 Refund execution 是否真实完成

P4
负责资金事实是否正确记录、是否与 PSP 一致
```

---

# 52. Reverse Recovery 不改变 Original Payment

即使 Refund：

```text
SUCCEEDED
```

原始：

```text
Payment = completed
```

仍然保留。

因为真实历史是：

```text
曾经成功收款
后来成功退款
```

而不是：

```text
原支付从未发生
```

---

# 53. Reverse Recovery 不倒退 CommerceTransaction

同样：

```text
CommerceTransaction = completed
```

继续保持。

Refund/Return/Cancellation：

```text
作为后发生事实存在
```

---

# 54. REV-P6-0 — Formal Semantic Freeze

当前分析已经完成大部分 Repo Audit。

P6-0 不需要再做重复大范围搜索。

正式冻结：

```text
REFUND_EXECUTION_AUTHORITY

REFUND_REQUEST_LIFECYCLE

REFUND_FACT_AUTHORITY

REFUND_CAPACITY_POLICY

REFUND_IDEMPOTENCY_POLICY

REFUND_OWNERSHIP_POLICY

REFUND_ALLOCATION_POLICY

CANCELLATION_ORCHESTRATION_POLICY

RESTOCK_AUTHORITY

RESTOCK_TIMING_POLICY

RESTOCK_IDEMPOTENCY_POLICY

REVERSE_RECOVERY_POLICY

PROVIDER_REFUND_CAPABILITY_POLICY
```

---

# 55. P6-0 必须额外冻结

### A. Refund success

什么 evidence 才能：

```text
Refund → SUCCEEDED
```

---

### B. Failed vs Ambiguous

必须区别：

```text
Provider definite failure
```

和：

```text
不知道 Provider 是否成功
```

---

### C. Active Refund Capacity

确认：

```text
requested / processing / ambiguous
```

必须占用 refundable capacity。

---

### D. Existing Refund migration

历史 Refund 是否都可安全：

```text
state=succeeded
```

不可证明的例外如何处理。

---

### E. Combination Target

新组合 Refund 是否要求：

```text
payment_split_id
target_order_id
```

创建时冻结。

---

### F. Return Inspection

当前 `receive → restock` 是否迁移为：

```text
receive → inspect → restock
```

以及 legacy compatibility。

---

# 56. REV-P6-1 — Durable Refund Lifecycle Foundation

实施：

```text
Refund state

Refund ownership

provider idempotency key

timestamps/errors

refund capacity scopes

historical backfill
```

并删除：

```text
after_create :perform!
```

这种“create 即 provider side effect”模式。

本包暂不正式发起新 PSP refund。

---

# 57. REV-P6-2 — Refund Execution Orchestration

实现：

```text
Refunds::Request

Refunds::Execute

Refunds::ApplySuccess
```

接入 provider：

```text
stable idempotency

PSP I/O outside DB tx

FAILED vs AMBIGUOUS
```

---

# 58. REV-P6-3 — Partial / Combination Refund Allocation

实现：

```text
Payment lock + capacity

target PaymentSplit

Order allocation

tax/shipping/promotion allocation freeze

multiple partial refund concurrency
```

---

# 59. REV-P6-4 — Cancellation Orchestration

把业务决策从：

```text
Gateway.cancel
```

上收为：

```text
Cancellation Orchestrator
```

统一：

```text
UNPAID → void/release/cancel

PAID → durable refund request + cancel/restock
```

逐步废弃：

```text
Gateway 自动根据 payment.completed?
决定创建 Refund
```

的旧语义。

---

# 60. REV-P6-5 — Return Inspection & Restock

正式收敛：

```text
CustomerReturn

ReturnItem

InventoryUnit

Shipment cancel

StockMovement(+)
```

确保：

```text
Inspection
→ Restock decision
→ exactly-once StockMovement
```

---

# 61. REV-P6-6 — Reverse Recovery

实现：

```text
Refunds::Recover

Refund Recover Job

Refund Sweeper

Restock Fact

ReverseCommerce::Recover
```

重点关闭：

```text
PSP succeeded + local missing/incomplete
```

事故。

---

# 62. REV-P6-7 — Financial Convergence

确认：

```text
Refund SUCCEEDED
↓
FinancialFact
↓
REFUND_SUCCEEDED Journal
↓
Source Reconciliation
↓
Transaction Financial Reconciliation
```

补：

```text
missing posting repair
ambiguous refund financial state
provider mismatch
```

不重新实现 P4。

---

# 63. REV-P6-8 — Admin / Ops / Legacy Convergence

Admin 至少展示：

```text
Refund State

Original Payment

CommerceTransaction

Target Order / Split

Amount / Currency

Provider Refund Reference

Provider Idempotency Key

Requested / Processing / Succeeded timestamps

Refund Fact

Journal Entry

Reconciliation Status

Restock Status

Recovery Status

Last Error
```

以及：

```text
Manual Retry Query
Manual Review
```

危险资金操作仍按现有权限/确认机制控制。

---

# 64. Dispute / Chargeback 不属于 P6 DoD

当前项目：

```text
0 model
0 webhook handler
0 service
0 orchestration
```

而 Dispute 是：

```text
provider/customer initiated involuntary money reversal
```

它与：

```text
Merchant requested Refund
```

本质不同。

因此正式顺延：

# P7 — Dispute & Chargeback Orchestration

P6 只确保现有：

```text
FinancialFact
Journal
Reconciliation
Provider Event Evidence
```

未来可以承载 Dispute extension。

---

# 65. 推荐实施顺序

```text
REV-P6-0
Formal Semantic Freeze
        ↓
REV-P6-1
Durable Refund Lifecycle
        ↓
REV-P6-2
Refund Execution Orchestration
        ↓
REV-P6-3
Partial / Combination Allocation
        ↓
REV-P6-4
Cancellation Orchestration
        ↓
REV-P6-5
Return Inspection / Restock
        ↓
REV-P6-6
Reverse Recovery
        ↓
REV-P6-7
Financial Convergence
        ↓
REV-P6-8
Admin / Ops / Legacy Convergence
```

---

# 66. 核心 Acceptance Criteria

## AC-6001

任何 PSP Refund 副作用发生前，本地必须已有 durable Refund row。

## AC-6002

Refund 创建失败时不得调用 PSP。

## AC-6003

PSP 调用不位于长 DB transaction / Payment lock 中。

## AC-6004

同一 Refund 所有 retry 使用相同 provider idempotency key。

## AC-6005

Provider timeout 后 Refund = AMBIGUOUS，不自动新建第二笔 Refund。

## AC-6006

PSP success + local ApplySuccess failure 可 Recovery，且不重复退款。

## AC-6007

REQUESTED/PROCESSING/AMBIGUOUS Refund 均占用 refundable capacity。

## AC-6008

并发 partial refund 总额不能超过 Payment refundable amount。

## AC-6009

FAILED Refund 释放 refund capacity。

## AC-6010

一个 Payment 支持 multiple successful partial Refund。

## AC-6011

组合 Refund 只影响目标 PaymentSplit / Order。

## AC-6012

Combination sibling Order 不因目标订单退款被修改。

## AC-6013

普通 Refund 产生 REFUND_SUCCEEDED Journal Entry，不 Reverse 原始 Payment entry。

## AC-6014

重复 Journal/Recovery 不重复 REFUND_SUCCEEDED posting。

## AC-6015

Payment success 不因 Refund failure 被改写。

## AC-6016

Original CommerceTransaction completed 不因 Refund 被倒退。

## AC-6017

UNPAID cancel 不产生 Refund。

## AC-6018

UNPAID + RESERVED cancel 正确 RELEASE Reservation。

## AC-6019

PAID cancellation 由 domain orchestrator 决定 Refund，不由 Gateway 隐式决定。

## AC-6020

COMMITTED Reservation 在 cancel/return 后仍保持 COMMITTED。

## AC-6021

已消费库存恢复只能通过 StockMovement(+)。

## AC-6022

Refund success 不自动意味着 Restock success。

## AC-6023

ReturnItem 非 resellable 不增加 physical inventory。

## AC-6024

一个 logical restock 最多产生一次 physical StockMovement(+)。

## AC-6025

Restock succeeded + Refund pending 可独立 Recovery。

## AC-6026

Refund succeeded + Restock incomplete 可独立 Recovery，不再次退款。

## AC-6027

Stripe Refund 可执行 provider reconciliation。

## AC-6028

Unsupported provider ambiguous outcome 不猜，进入 manual_review。

## AC-6029

历史 Refund migration 不伪造无法证明的 ownership。

## AC-6030

P0 baseline 全绿。

## AC-6031

P1 baseline 全绿。

## AC-6032

P2 baseline 全绿。

## AC-6033

P3 baseline 全绿。

## AC-6034

P4 baseline 全绿。

## AC-6035

P5 canonical flow baseline 全绿。

---

# 67. P6 核心 Invariants

## REV-INV-01

```text
Refund Request
≠
Refund Execution
≠
Refund Financial Fact
```

## REV-INV-02

```text
PSP side effect
必须有 durable local owner 在先。
```

## REV-INV-03

```text
Provider I/O
不得位于长期 DB lock/transaction。
```

## REV-INV-04

```text
Ambiguous Refund
不得自动重复退款。
```

## REV-INV-05

```text
Refund idempotency
必须跨 Job/HTTP/Recovery retry 稳定。
```

## REV-INV-06

```text
Inflight Refund
必须占用 refundable capacity。
```

## REV-INV-07

```text
Refund Fact
≠
Original Payment Fact。
```

## REV-INV-08

```text
Normal Refund
不是 Journal correction/reversal。
```

## REV-INV-09

```text
Refund
≠
Cancellation。
```

## REV-INV-10

```text
Refund
≠
Restock。
```

## REV-INV-11

```text
Reservation Release
≠
Physical Restock。
```

## REV-INV-12

```text
COMMITTED Reservation
是历史终态。
```

## REV-INV-13

```text
Physical Restock
只能通过 StockMovement(+)。
```

## REV-INV-14

```text
Original CommerceTransaction
不会因为售后逆向被重新打开。
```

## REV-INV-15

```text
Gateway
不拥有是否应该退款的业务决策权。
```

## REV-INV-16

```text
无法确定 Provider Refund Fact
→ AMBIGUOUS / MANUAL_REVIEW
而不是猜。
```

---

# 68. 明确不做

P6 禁止扩张为：

```text
❌ ReverseTransaction 新聚合

❌ 第二套 CommerceTransaction

❌ Inventory engine rewrite

❌ Refund 通过 Reservation Release 恢复库存

❌ Refund workflow 与 Return 强绑定

❌ 强制“退款一定退货”

❌ 强制“退货一定退款”

❌ Exchange orchestration 大重构

❌ Warranty

❌ Customer service ticketing

❌ CRM after-sale platform

❌ Warehouse Return Management 全套

❌ Supplier claims

❌ Accounting GL

❌ Provider payout

❌ 自动重新 Refund ambiguous outcome

❌ Dispute / Chargeback 实现

❌ 新 PSP

❌ MQ / 微服务强依赖
```

---

# 69. 最高风险

### RISK-REV-01 — Orphan PSP Refund

最高风险。

必须在 P6-1/P6-2 最先关闭。

---

### RISK-REV-02 — Concurrent Partial Refund

provider I/O 外移后，如果没有 refund capacity reservation，会重新引入 double refund。

必须和 durable Refund lifecycle 一起实施。

---

### RISK-REV-03 — Ambiguous Provider Outcome

timeout：

```text
不等于 FAILED
```

错误处理会直接造成双退款。

---

### RISK-REV-04 — Gateway-owned Cancellation

如果继续：

```text
Gateway.cancel
→ decide refund
```

会形成第二套 reverse orchestration。

---

### RISK-REV-05 — Combination Ownership

如果新 Refund 继续每次从 Reimbursement 深层链动态猜 Order，将降低 Recovery 可靠性。

---

### RISK-REV-06 — Return Restock Timing

receive 即 restock 与 inspection/acceptance 语义需要正式冻结，否则损坏商品可能错误回到 ATS。

---

### RISK-REV-07 — Legacy Provider

Stripe 可完成自动 Recovery；Adyen/PayPal 可能只能 manual review。

不能伪装能力对称。

---

# 70. Release Verification

## RV-R01 — Normal Stripe Refund

```text
Payment +100
↓
Refund Request 30
↓
Refund row REQUESTED
↓
provider refund
↓
SUCCEEDED
↓
Journal -30
↓
Reconciliation MATCHED
```

---

## RV-R02 — Provider Success / Local Failure

强制：

```text
Stripe refund succeeds
↓
ApplySuccess raises
```

必须：

```text
durable Refund remains
↓
Recover
↓
provider confirms success
↓
ApplySuccess
↓
NO second Stripe refund
```

这是 P6 最关键 RV。

---

## RV-R03 — Ambiguous Timeout

```text
Refund call timeout after provider may have succeeded
```

必须：

```text
AMBIGUOUS
↓
provider verification
↓
resolve same Refund
```

不得创建 Refund #2。

---

## RV-R04 — Concurrent Partial Refund

```text
Payment refundable = 100

Refund A = 60
Refund B = 60
```

并发：

```text
only one / valid combination may reserve capacity
```

绝不能 provider refund 总额 >100。

---

## RV-R05 — Combination Child Refund

```text
Payment = 100
Split A = 60
Split B = 40

Refund A = 20
```

验证：

```text
A refunded = 20
B unchanged
Journal net correct
Reconciliation correct
```

---

## RV-R06 — Pre-payment Cancel

```text
UNPAID
RESERVED
↓
Cancel
↓
Reservation RELEASED
NO Refund
NO Restock
```

---

## RV-R07 — Paid Cancellation

```text
PAID
Inventory consumed
↓
Cancellation
↓
StockMovement(+)
↓
Refund
↓
Journal
↓
Reconciliation
```

重复 Recovery：

```text
no duplicate StockMovement
no duplicate Refund
```

---

## RV-R08 — Return Inspection

```text
Return received
↓
resellable inspection
↓
StockMovement(+)
```

以及：

```text
damaged
→ no restock
```

---

## RV-R09 — Financial Repair

```text
Refund succeeded
Journal missing
```

P4 Repair 补 Journal：

```text
without second Refund
```

---

## RV-R10 — Legacy Provider Ambiguity

Provider 无 refund fact query：

```text
AMBIGUOUS
→ manual_review
```

不能自动重退。

---

# 71. Definition of Done

P6 完成后，PallasTrade 具备完整 Merchant-initiated Reverse Commerce 闭环：

## 正向

```text
Checkout
→ Transaction
→ Reserve
→ Pay
→ Finalize
→ Stock Consume
→ Journal
→ Reconcile
```

## 退款

```text
Refund Intent
→ Durable Refund
→ Provider Execution
→ Refund Fact
→ Local Apply
→ Journal
→ Reconciliation
```

## 取消

```text
Cancellation Intent
→ Payment Fact
→ Cancel
├─ UNPAID → Release
└─ PAID → Refund
→ Restock if consumed
→ Recovery
```

## 退货

```text
Return
→ Receive
→ Inspect
→ Restock Decision
→ StockMovement(+)
→ Reimbursement / Refund
→ Financial Reconciliation
```

## 故障

```text
Provider succeeded
+
Local incomplete
↓
Reverse Recovery
↓
Resolve Facts
↓
Repair local state
↓
NO duplicate money side effect
```

---

# 72. P6 最终架构全景

```text
                    Original CommerceTransaction
                              │
                        remains COMPLETED
                              │
         ┌────────────────────┼─────────────────────┐
         │                    │                     │
         ▼                    ▼                     ▼
 OrderCancellation       CustomerReturn       Refund-only
         │                    │                     │
         │              Reimbursement                │
         │                    │                     │
         └────────────────────┼─────────────────────┘
                              ▼
                     Durable Refund Request
                              │
                              ▼
                       Refund Execution
                              │
                      PSP / Payment Method
                              │
                              ▼
                     Refund Financial Fact
                              │
                   ┌──────────┴───────────┐
                   ▼                      ▼
             Local Projection       Financial Journal
                   │                      │
                   ▼                      ▼
            PaymentSplit/Order       Reconciliation
                   
Return / Cancellation
         │
         ▼
Restock Decision
         │
         ▼
StockMovement(+)
         │
         ▼
Restock Fact

All incomplete combinations
         │
         ▼
ReverseCommerce::Recover
```

---

# 73. P6 后续阶段

P6 CLOSED 后再进入：

# P7 — Dispute & Chargeback Orchestration

因为届时已经具备：

```text
Provider Event Evidence
Payment Fact
Financial Fact
Journal
Reconciliation
Reverse Recovery pattern
```

Dispute 可以作为：

```text
Provider-initiated involuntary financial reversal
```

独立建模，而不会污染 merchant Refund。

---

# 74. 当前下一步

只执行：

```text
REV-P6-0 — Formal Semantic Freeze
```

但现有分析已经完成绝大部分 broad audit。

无需重复扫描全仓。

只需正式冻结四个最关键决策：

```text
1. Refund = durable execution aggregate
   FinancialFact = refund fact

2. provider side effect only after durable Refund row

3. requested / processing / ambiguous
   all reserve refundable capacity

4. normal Refund uses REFUND_SUCCEEDED journal,
   not FinancialLedger::Reverse
```

这四项冻结后，立即批准：

```text
REV-P6-1 — Durable Refund Lifecycle Foundation
```

优先关闭 **orphan PSP refund** 风险。
