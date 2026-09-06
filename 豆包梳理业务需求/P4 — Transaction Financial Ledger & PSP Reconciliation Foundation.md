# P4 — Transaction Financial Journal & PSP Reconciliation Foundation V2

> 工程编号：`FIN-P4`
>
> 前置：
>
> ```text
> P0 — Payment Foundation
> P1 — Order-centric Checkout
> P2 — Commerce Transaction Orchestration & Recovery
> P3 — Inventory Transaction Integration & Reservation Lifecycle
> ```
>
> 核心定位：
>
> **在不重写 Payment / Refund / CommerceTransaction 的前提下，建立“Financial Fact Resolution → Immutable Financial Journal → PSP Reconciliation”的交易级资金事实体系。**

---

# 1. P4 核心问题重新定义

P0-P3 已经可以回答：

```text
这是什么交易？
应该收多少钱？
实际支付是否成功？
库存是否正确锁定/消费？
订单是否正确完成？
异常是否能够恢复？
```

P4 要回答：

```text
这笔 Transaction 实际发生了哪些资金事实？

收了几笔？
每笔属于什么资金类型？
实际 capture 多少？
是否使用 Store Credit / Offline Payment？
退款多少？
多订单之间如何分配？
PSP 侧记录是否一致？
PSP fee / net 是多少？
本地与 PSP 不一致在哪里？
```

---

# 2. P4 不直接从 Payment 状态发 Ledger

禁止：

```text
Payment.completed?
↓
直接 PAYMENT_CAPTURED
```

因为项目实际存在：

```text
Stripe auto capture

Stripe manual capture

StoreCredit

Check / offline payment

PaymentCombination

short payment / retry payment
```

这些虽然都可能形成 Payment，但金融语义不同。

目标变为：

```text
Payment / Refund / Split / CaptureEvent
                ↓
       FinancialFactResolver
                ↓
     Confirmed Financial Fact
                ↓
      Immutable Journal Entry
```

---

# 3. 四层金融事实

## 3.1 Commercial Fact

来源：

```text
CommerceTransaction
Transaction Snapshot
TransactionOrder
```

表示：

> 这一商业交易应该支付多少。

---

## 3.2 Payment Execution Fact

来源：

```text
PaymentSession
Payment
PaymentCaptureEvent
```

表示：

> 支付执行到了什么阶段。

例如：

```text
AUTHORIZED
CAPTURED
PENDING
FAILED
```

---

## 3.3 Financial Journal Fact

表示：

> 已经能够确定的资金/价值变动。

例如：

```text
CASH_CAPTURED
STORE_CREDIT_APPLIED
OFFLINE_PAYMENT_RECORDED
REFUND_SUCCEEDED
ORDER_ALLOCATION
```

---

## 3.4 Provider Settlement Fact

来源：

```text
Stripe PaymentIntent
Stripe Charge
Stripe BalanceTransaction
Stripe Refund
```

表示：

```text
provider gross
provider refunds
provider fee
provider net
settlement state
```

这一层用于：

```text
Reconciliation
```

不直接等同 Journal。

---

# 4. 新增 FinancialFactResolver

P4 最先应该建立的不是 Ledger Model，而是：

```text
FinancialFactResolver
```

职责：

> 根据 Payment / Capture Event / Payment Method / Provider / Refund 等真实证据，确定“发生了什么金融事实”。

---

# 5. Payment Financial Fact

候选输出：

```text
AUTHORIZED_ONLY

CASH_CAPTURED

STORE_CREDIT_APPLIED

OFFLINE_PAYMENT_RECORDED

UNPAID

AMBIGUOUS
```

并携带：

```text
amount
currency

payment_id

commerce_transaction_id

provider
provider_reference

evidence

effective_at
```

---

# 6. 为什么需要 AUTHORIZED_ONLY

当前 manual capture 场景允许：

```text
Payment = pending
Order 已完成/继续业务流
PaymentIntent = requires_capture
```

所以：

```text
AUTHORIZED
≠
CAPTURED
```

P4 必须保留这一事实差异。

但：

```text
AUTHORIZED_ONLY
```

第一版不一定需要写入 Cash Journal。

它可以只是：

```text
FinancialFactResolver Result
```

直到真正 Capture 成功。

---

# 7. Cash / Non-cash Payment 必须分类

Stripe 捕获：

```text
CASH_CAPTURED
```

Store Credit：

```text
STORE_CREDIT_APPLIED
```

Check / Offline Payment：

```text
OFFLINE_PAYMENT_RECORDED
```

不能全部写：

```text
PAYMENT_CAPTURED
```

否则：

```text
100 USD Store Credit
```

会被误解为：

```text
PSP 收了 100 USD cash
```

---

# 8. Capture Evidence Matrix

FIN-P4-0 必须冻结：

```text
CAPTURE_EVIDENCE_MATRIX
```

每个支付路径明确：

```text
什么证据表示 AUTHORIZED

什么证据表示 CAPTURED

是否有 PaymentCaptureEvent

哪个 provider reference 可证明

是否支持 PSP reconciliation
```

至少覆盖：

```text
Stripe auto capture

Stripe manual capture

PaymentCombination

Store Credit

Check / Offline

Bogus

Adyen legacy

PayPal legacy
```

---

# 9. 不强制“一 Transaction = 一 Successful Payment”

当前架构应正式支持：

```text
CommerceTransaction
        │
        └── Successful Financial Payment Facts × N
```

例如：

```text
Transaction amount = 100

Payment #1 captured = 40
Payment #2 captured = 60
```

Journal：

```text
CASH_CAPTURED +40
CASH_CAPTURED +60
```

最终：

```text
gross_collected = 100
```

---

# 10. Balance Collection

仍保持 P2 语义：

```text
Initial Purchase
=
Transaction A

Balance Collection
=
Transaction B
```

所以：

```text
Order
├── txn_purchase
│      └── +80
│
└── txn_balance_collection
       └── +20
```

P4 不把它们重新合并成一个 Transaction。

Order Financial View 可以聚合多个 Transaction。

---

# 11. Immutable Financial Journal

P4 正式建立：

```text
FinancialJournalEntry
```

它不是完整会计总账。

定义：

> **已经确认的交易级资金/价值事实的 append-only record。**

---

# 12. 第一版 Entry Type 收敛

建议首版只做：

```text
CASH_CAPTURED

STORE_CREDIT_APPLIED

OFFLINE_PAYMENT_RECORDED

REFUND_SUCCEEDED

ORDER_ALLOCATION

CORRECTION

REVERSAL
```

暂时不要把：

```text
PSP_FEE
PSP_NET_SETTLEMENT
```

作为 Journal Entry。

它们第一版进入：

```text
ProviderFinancialSnapshot
/
Reconciliation
```

原因是：

> PSP fee/net 属于 provider settlement 事实，而不是当前已经冻结定义的 customer transaction cash movement。

未来需要会计 Ledger 时再决定如何 posting。

---

# 13. Journal Entry 候选模型

```text
financial_journal_entries

id

commerce_transaction_id nullable
order_id nullable

source_type
source_id

payment_id nullable
refund_id nullable
payment_split_id nullable

entry_type

amount
currency

instrument_class

provider nullable
provider_reference nullable

posting_key

effective_at

reversal_of_id nullable

metadata

created_at
```

---

# 14. commerce_transaction_id 可以 Nullable

新 transaction-first 路径：

```text
commerce_transaction_id REQUIRED
```

但历史：

```text
Admin manual payment

legacy Payment

StoreCredit legacy

无 PaymentSession 的历史记录
```

可能无法可靠关联 Transaction。

因此：

```text
commerce_transaction_id nullable
```

允许 legacy evidence 存在。

禁止为了 P4：

```text
猜 Transaction ownership
```

---

# 15. Journal 必须 Immutable

禁止：

```text
entry.amount = new_amount
```

修正采用：

```text
REVERSAL
+
new entry
```

或者：

```text
CORRECTION
```

追加。

---

# 16. Posting Identity

Posting 的真正 identity 不能简单写：

```text
payment:{payment_id}
```

因为未来可能出现：

```text
partial capture
multiple financial events
```

目标：

```text
[source_type, source_id, financial_fact_type, fact_identity]
```

优先使用：

```text
PaymentCaptureEvent id

Refund id/provider refund reference

PaymentSplit id + allocation version/fact

Provider financial reference
```

最终由 FIN-P4-0 的：

```text
LEDGER_ENTRY_IDENTITY
```

冻结。

---

# 17. Posting 幂等

必须保证：

```text
Webhook replay

Controller retry

Job retry

Recovery retry

Manual replay
```

不会产生：

```text
duplicate Journal Entry
```

DB 必须有唯一约束支持。

不能只靠 Ruby：

```text
find_or_create
```

---

# 18. Payment Posting Pipeline

目标：

```text
Payment / Capture Event
↓
FinancialFactResolver
↓
CAPTURED / CREDIT_APPLIED / OFFLINE_RECORDED
↓
FinancialJournal::Post
↓
Journal Entry
```

---

# 19. Journal Posting 不属于 Payment Hot-path Critical Success

如果：

```text
Stripe 已成功
Payment Fact 已确认
Order 已完成
```

但：

```text
Journal insert temporarily failed
```

禁止：

```text
Payment → failed

CommerceTransaction → payment_pending

重新 charge
```

而是：

```text
FinancialPostingPending
```

通过独立 Job/Repair 补 Journal。

---

# 20. 不新增 CommerceTransaction finance 状态

CommerceTransaction 继续：

```text
created
payment_pending
payment_confirmed
finalizing
completed
recovery_required
manual_review
```

禁止添加：

```text
ledger_pending
ledger_failed
reconciled
```

金融状态独立存在。

---

# 21. PaymentSplit 的正式定位

当前 PaymentSplit：

```text
一方面 = Order allocation

另一方面 = OrderUpdater cash aggregation source
```

P4 不立即改变现有：

```text
OrderUpdater
```

行为。

定义：

```text
PaymentSplit
=
allocation source of truth
```

Financial Journal：

```text
ORDER_ALLOCATION
```

是：

```text
immutable financial projection
```

---

# 22. 防止 PaymentSplit 双账

禁止：

```text
PaymentSplit captured amount
+
ORDER_ALLOCATION
```

被同时当成：

```text
两笔 cash inflow
```

定义：

```text
CASH_CAPTURED
=
资金流入

ORDER_ALLOCATION
=
这笔资金如何归属不同 Order
```

Allocation 不增加：

```text
gross_collected
```

---

# 23. Combination Financial Invariant

组合：

```text
CommerceTransaction amount
=
Σ successful captured financial facts

PaymentCombination amount
=
Σ PaymentSplit.captured_amount

Σ ORDER_ALLOCATION
=
Σ PaymentSplit.captured_amount
```

正常完整付款情况下：

```text
CommerceTransaction.amount
=
captured_total
=
split_total
=
allocation_total
```

---

# 24. 不要假设永远 exact-paid

因为系统真实存在：

```text
short payment
retry payment
balance_due
```

因此 Financial Summary 必须分别记录：

```text
commercial_amount

captured_total

allocated_total

refunded_total
```

而不是只：

```text
paid = true
```

---

# 25. TransactionFinancialSummary

新增只读 projection/service：

```text
TransactionFinancialSummary
```

输出：

```text
commercial_amount

cash_captured

store_credit_applied

offline_payment_recorded

gross_value_received

refund_total

net_customer_value

allocation_total

unallocated_amount

provider_fee

provider_net

currency

reconciliation_status
```

首版不必落表。

---

# 26. Refund 先做 Financial Fact，不重写 Refund Domain

当前：

```text
Refund belongs_to Payment

Refund.transaction_id = PSP refund reference

无独立 state machine
```

P4 不重写。

成功锚点：

```text
Refund#perform! successful
```

然后：

```text
RefundFinancialFactResolver
↓
REFUND_SUCCEEDED
↓
Journal
```

---

# 27. Refund Journal

例如：

```text
Cash Capture +100

Refund #1 -20

Refund #2 -10
```

Summary：

```text
cash_captured = 100

refund_total = 30

net_customer_cash = 70
```

保留每一次 Refund 独立事实。

---

# 28. Refund CommerceTransaction Ownership

第一优先级：

```text
Refund
→ Payment
→ PaymentSession
→ CommerceTransaction
```

组合：

```text
Refund
→ Payment
→ PaymentCombination
→ CommerceTransaction
```

如果只能推导 Order：

```text
commerce_transaction_id nullable
order_id = known
```

禁止通过脆弱关联猜一个 Transaction。

---

# 29. Refund Allocation

组合退款当前会影响目标：

```text
PaymentSplit.refunded_amount
```

因此 P4-0 必须冻结：

```text
REFUND_ALLOCATION_POLICY
```

至少区分：

```text
Transaction-level Refund Fact

Order-level Refund Allocation
```

不要直接把：

```text
Refund amount
```

重复算到多个 Order。

---

# 30. Provider Financial Contract

P2 保留：

```text
fetch_payment_status
```

P4 新增：

```text
fetch_financial_details
```

只读。

职责不同。

---

# 31. Stripe Financial Details V1

Stripe 第一版读取：

```text
PaymentIntent

latest Charge

BalanceTransaction

Refunds
```

标准输出：

```text
provider_payment_reference

provider_charge_reference

provider_balance_transaction_reference

gross_amount
gross_currency

refund_total

fee_amount
fee_currency

net_amount
net_currency

settlement_status

observed_at
```

---

# 32. Provider Reference 必须规范化

当前：

```text
Payment.response_code
=
Payment.transaction_id alias
=
pi_

Refund.transaction_id
=
re_

PaymentSession.external_id
=
cs_ / pi_

private_metadata.stripe_charge_id
=
ch_（仅部分路径）
```

P4 不能继续使用模糊：

```text
transaction_id
```

新模型统一使用：

```text
commerce_transaction_id

provider_payment_reference

provider_charge_reference

provider_refund_reference

provider_balance_transaction_reference
```

---

# 33. Stripe Charge Reference 必须全路径补齐

目前：

```text
stripe_charge_id
```

不是所有 Stripe payment 路径都有。

P4 Stripe reconciliation 前必须补齐：

```text
PI
→ latest_charge
```

解析能力。

不要求全部冗余落 Payment 表。

可以在：

```text
ProviderFinancialSnapshot
```

中标准化保存。

---

# 34. ProviderFinancialSnapshot

建议 P4 新增一个 reconciliation evidence 概念：

```text
ProviderFinancialSnapshot
```

可作为：

```text
FinancialReconciliation
```

内部 JSON snapshot，而不一定第一版独立表。

记录：

```text
provider
references

gross
refund
fee
net

settlement state

observed_at
raw evidence reference
```

---

# 35. 为什么 fee/net 不直接进 Journal

因为当前没有冻结：

```text
PSP fee
```

应该属于：

```text
transaction expense

payment processing expense

settlement adjustment
```

中的哪一种会计语义。

所以 P4 第一版：

```text
fee/net
=
Reconciliation Fact
```

不是：

```text
Journal Cash Entry
```

避免提前发明半套会计系统。

---

# 36. Reconciliation 必须两层

这是新版 P4 的重要调整。

## 第一层：Source Reconciliation

针对：

```text
Payment
Refund
```

分别核对 PSP。

例如：

```text
Payment #1 Local
↔
Stripe PI/Charge
```

---

## 第二层：Transaction Financial Reconciliation

针对整个：

```text
CommerceTransaction
```

核对：

```text
Commercial Amount

Captured Total

Refund Total

Allocation Total

Provider Totals
```

这样才能支持：

```text
1 Transaction
→ N Successful Payments
```

而不会被单个 reconciliation record 淹没问题。

---

# 37. Source Reconciliation

Payment：

```text
local captured amount
↔
provider gross
```

检查：

```text
amount

currency

provider reference

capture state
```

Refund：

```text
local Refund
↔
provider Refund
```

检查：

```text
amount
currency
reference
```

---

# 38. Transaction Reconciliation

聚合：

```text
Commercial amount

Σ captured value

Σ refunds

Σ allocations
```

检查：

```text
captured vs commercial

allocation vs captured

refund vs captured

provider gross vs local captured

provider refund vs local refund
```

---

# 39. Reconciliation 状态

建议：

```text
PENDING

MATCHED

MISMATCH

NEEDS_ATTENTION

NOT_APPLICABLE

UNSUPPORTED
```

---

# 40. NOT_APPLICABLE

例如：

```text
Store Credit
Check / Offline
```

没有 PSP。

不能返回：

```text
PROVIDER_PAYMENT_MISSING
```

应该：

```text
NOT_APPLICABLE
```

---

# 41. UNSUPPORTED

当前：

```text
Adyen
PayPal
```

仍 reachable，但没有完整：

```text
fetch_payment_status
/
fetch_financial_details
```

P4 Stripe-first 第一版：

```text
Stripe → full reconciliation

Adyen / PayPal legacy
→ UNSUPPORTED / manual evidence
```

不能错误标：

```text
MISMATCH
```

---

# 42. Reconciliation Reason Codes

建议：

```text
AMOUNT_MISMATCH

CURRENCY_MISMATCH

LOCAL_PAYMENT_MISSING

PROVIDER_PAYMENT_MISSING

DUPLICATE_EFFECTIVE_PAYMENT

REFUND_MISMATCH

ALLOCATION_MISMATCH

COMMERCIAL_AMOUNT_MISMATCH

SETTLEMENT_PENDING

PROVIDER_UNAVAILABLE

PROVIDER_CONTRACT_UNSUPPORTED

UNLINKED_LEGACY_PAYMENT

AMBIGUOUS_CAPTURE

UNKNOWN
```

---

# 43. Settlement Pending

Stripe：

```text
Payment succeeded
```

不保证：

```text
fee/net
```

立即稳定可获取。

因此：

```text
SETTLEMENT_PENDING
```

是合法中间结果。

不能直接报警：

```text
MISMATCH
```

---

# 44. Financial Reconciliation 不修改 Payment

禁止：

```text
Mismatch
→ update Payment amount
```

更禁止：

```text
Mismatch
→ Charge again
```

允许：

```text
repair missing Journal projection

refresh provider snapshot

repair missing provider reference projection

re-run reconciliation
```

---

# 45. Reconciliation 与 P2 Recovery 分离

P2：

```text
Transaction execution recovery
```

P4：

```text
Financial evidence reconciliation
```

例如：

```text
Transaction completed
Order completed
Inventory committed
```

但：

```text
Financial Journal missing
```

此时：

```text
CommerceTransaction
```

仍然：

```text
completed
```

P4 自己修：

```text
Journal / Reconciliation
```

---

# 46. 严重金融冲突

如果：

```text
CommerceTransaction completed
```

但 Provider authoritative evidence 明确：

```text
Payment NOT captured
```

则：

```text
NEEDS_ATTENTION
```

并升级：

```text
manual_review
```

是否影响 CommerceTransaction state 必须人工/策略判断。

禁止自动倒退到：

```text
payment_pending
```

---

# 47. Recovery Retry 双扣窗口

审计已经暴露一个必须专项冻结的问题：

```text
local = UNPAID
provider 实际可能已入账
↓
retry_payment
↓
可能创建新的支付 attempt
```

FIN-P4-0 必须输出：

```text
RETRY_PAYMENT_FINANCIAL_SAFETY_POLICY
```

至少规定：

> 任何存在可确认 provider session/reference 的 UNPAID retry，在产生新 charge 前必须完成 authoritative provider verification。

这属于 P2/P4 边界安全强化，不是 Ledger 本身。

---

# 48. Posting Trigger

第一版：

```text
Payment financial fact becomes confirmed
→ Post Payment Journal

Refund financial fact becomes confirmed
→ Post Refund Journal

PaymentSplit settlement/update
→ Post/verify Allocation Journal
```

不要用：

```text
Transaction completed
```

作为统一 posting trigger。

---

# 49. Journal Posting Recovery

新增：

```text
FinancialJournal::Post

FinancialJournal::Repair
```

或项目 convention 下等价服务。

目标：

```text
missing Journal
+
source financial fact still exists
↓
idempotent repost
```

不能：

```text
重新 Payment
重新 Refund
```

---

# 50. Historical Backfill

正式分三类：

## PROVABLE

有：

```text
Payment
provider reference
capture evidence
currency
```

可以 backfill。

## PARTIALLY_PROVABLE

缺部分：

```text
provider settlement info
```

只写本地 Journal，Reconciliation PENDING/UNSUPPORTED。

## UNPROVABLE

无法证明：

```text
captured fact
transaction ownership
currency
```

禁止猜测。

保留：

```text
legacy_unverified
```

---

# 51. Admin Financial View

扩现有 Transaction Admin：

```text
Commercial Amount

Cash Captured

Store Credit Applied

Offline Payment

Gross Value Received

Refund Total

Net Customer Value

Allocation Total

Unallocated Amount

Provider Gross

Provider Fee

Provider Net

Reconciliation Status
```

---

# 52. Financial Timeline

例如：

```text
txn.created

stripe.cash_captured +60

stripe.cash_captured +40

order_a.allocated 60
order_b.allocated 40

refund.succeeded -20

stripe.settlement
gross 100
fee 3
net 97

reconciliation.matched
```

---

# 53. Audit

新增：

```text
finance.fact_resolved

finance.fact_ambiguous

finance.journal_posted

finance.journal_post_failed

finance.journal_repaired

finance.reconciliation_started

finance.reconciliation_pending

finance.reconciliation_matched

finance.reconciliation_mismatch

finance.reconciliation_needs_attention
```

继续复用：

```text
audit_logs
request_id
commerce_transaction_id
```

---

# 54. FIN-P4-0 — Financial Semantic Freeze

当前分析已经完成绝大多数 Repo Audit。

所以新版 P4-0 不再做大范围重复搜索。

重点冻结以下未决语义。

---

# 55. P4-0 必须冻结 10 项策略

```text
FINANCIAL_INSTRUMENT_CLASSIFICATION

CAPTURE_EVIDENCE_POLICY

FINANCIAL_FACT_AUTHORITY

SUCCESSFUL_PAYMENT_CARDINALITY

JOURNAL_ENTRY_IDENTITY

JOURNAL_IMMUTABILITY_POLICY

REFUND_OWNERSHIP_POLICY

ALLOCATION_POLICY

PROVIDER_FINANCIAL_FACT_POLICY

RECONCILIATION_POLICY
```

额外输出：

```text
RETRY_PAYMENT_FINANCIAL_SAFETY_POLICY
```

---

# 56. P4-0 重点冻结的问题

### A. Capture

每个 Payment Method：

```text
什么时候只是 Authorization？

什么时候才算 Capture？
```

---

### B. Multiple Successful Payment

冻结：

```text
1 Transaction
可存在 N captured financial facts
```

以及：

```text
short payment
retry payment
```

如何计算。

---

### C. Refund Ownership

明确：

```text
Refund
→ Payment
→ CommerceTransaction / Order
```

的可靠推导规则。

---

### D. Allocation

建立：

```text
Σ split captured
=
Σ allocation journal
```

并明确 exact-paid / short-paid 行为。

---

### E. Retry Safety

确认：

```text
UNPAID
```

什么时候允许：

```text
new PaymentSession
```

---

# 57. FIN-P4-1 — Financial Fact Resolution

先实现：

```text
FinancialFactResolver
```

以及：

```text
payment financial classification

refund financial classification

capture evidence matrix implementation
```

暂不建完整 Reconciliation。

---

# 58. FIN-P4-2 — Immutable Financial Journal

实现：

```text
FinancialJournalEntry

posting identity

append-only

correction/reversal

FinancialSummary
```

---

# 59. FIN-P4-3 — Payment / Refund Posting

接：

```text
Payment Facts
Refund Facts
```

到 Journal。

覆盖：

```text
Stripe auto

Stripe manual capture

Combination

StoreCredit

Check/offline

balance_collection

Refund
```

---

# 60. FIN-P4-4 — Allocation Integrity

接入：

```text
PaymentSplit
```

生成：

```text
ORDER_ALLOCATION
```

并增加：

```text
split/allocation sum invariant
```

不改变现有 OrderUpdater cash behavior。

---

# 61. FIN-P4-5 — Stripe Provider Financial Facts

实现：

```text
fetch_financial_details
```

以及：

```text
PI
Charge
BalanceTransaction
Refund
```

normalized snapshot。

---

# 62. FIN-P4-6 — Source Reconciliation

实现：

```text
Payment ↔ PSP

Refund ↔ PSP
```

独立 source-level reconciliation。

---

# 63. FIN-P4-7 — Transaction Reconciliation

聚合：

```text
CommerceTransaction
+
Journal
+
Allocation
+
Provider Source Reconciliations
```

产生：

```text
Transaction Financial Reconciliation
```

---

# 64. FIN-P4-8 — Repair / Legacy / Operations

实现：

```text
Journal repair

Reconciliation retry

Sweeper

Manual reconcile

Controlled backfill

Legacy unsupported state

Admin financial panel

Metrics / Runbook
```

---

# 65. 推荐实施顺序

```text
FIN-P4-0
Financial Semantic Freeze
        ↓
FIN-P4-1
Financial Fact Resolution
        ↓
FIN-P4-2
Immutable Financial Journal
        ↓
FIN-P4-3
Payment / Refund Posting
        ↓
FIN-P4-4
Allocation Integrity
        ↓
FIN-P4-5
Stripe Provider Financial Facts
        ↓
FIN-P4-6
Source Reconciliation
        ↓
FIN-P4-7
Transaction Reconciliation
        ↓
FIN-P4-8
Repair / Legacy / Operations
```

---

# 66. 核心 Acceptance Criteria

## AC-4001

Payment 状态不能绕过 FinancialFactResolver 直接产生错误现金事实。

## AC-4002

Stripe manual authorization 不得写 CASH_CAPTURED。

## AC-4003

Stripe capture 成功产生且只产生一个对应 captured financial fact。

## AC-4004

StoreCredit / offline payment 不得伪装成 PSP cash capture。

## AC-4005

一个 CommerceTransaction 支持多个 successful payment facts。

## AC-4006

Journal posting 重复调用幂等。

## AC-4007

Journal Entry immutable。

## AC-4008

Correction 使用 append/reversal。

## AC-4009

Journal failure 不逆转 Payment Fact。

## AC-4010

Journal failure不创建新 Payment。

## AC-4011

Multiple partial refunds 各自保留独立 Journal Fact。

## AC-4012

Refund ownership 无法可靠解析时不得猜 Transaction。

## AC-4013

ORDER_ALLOCATION 不增加 gross_collected。

## AC-4014

Combination：

```text
Σ PaymentSplit
=
Σ ORDER_ALLOCATION
```

## AC-4015

正常 exact-paid combination：

```text
captured_total
=
allocation_total
=
commercial_amount
```

## AC-4016

Short payment 可以明确表现：

```text
captured_total < commercial_amount
```

而不是 ledger error。

## AC-4017

Stripe provider financial query 为只读。

## AC-4018

Source Reconciliation 支持 Payment amount/currency/reference 核对。

## AC-4019

Refund 可与 provider refund 核对。

## AC-4020

Settlement pending 不误报 mismatch。

## AC-4021

StoreCredit/offline provider reconciliation = NOT_APPLICABLE。

## AC-4022

Legacy unsupported provider 不误报 mismatch。

## AC-4023

Mismatch 不自动 charge/refund。

## AC-4024

Reconciliation 重复执行幂等。

## AC-4025

历史无法证明的数据不强制 backfill。

## AC-4026

P0 baseline 全绿。

## AC-4027

P1 baseline 全绿。

## AC-4028

P2 baseline 全绿。

## AC-4029

P3 baseline 全绿。

---

# 67. 核心 Invariants

## FIN-INV-01

```text
Commercial Fact
≠
Payment Execution Fact
≠
Financial Journal Fact
≠
Provider Settlement Fact
```

## FIN-INV-02

```text
Payment.completed
不能在所有 Payment Method 上
直接解释为 PSP CASH_CAPTURED。
```

## FIN-INV-03

```text
Authorization
≠
Capture
```

## FIN-INV-04

```text
1 CommerceTransaction
可对应 N Financial Payment Facts。
```

## FIN-INV-05

```text
PaymentSplit
=
Allocation Fact

不是额外 Cash Inflow。
```

## FIN-INV-06

```text
Journal append-only。
```

## FIN-INV-07

```text
Financial Fact Resolver
必须先于 Journal Posting。
```

## FIN-INV-08

```text
Journal missing
不得触发新的 Payment。
```

## FIN-INV-09

```text
Reconciliation mismatch
不得自动产生资金副作用。
```

## FIN-INV-10

```text
Provider fee/net
第一版属于 Settlement/Reconciliation Fact，
不是强制 Journal Posting。
```

## FIN-INV-11

```text
Transaction completed
≠
Financial reconciliation matched。
```

## FIN-INV-12

```text
无法证明的历史金融事实
不得猜测。
```

---

# 68. 明确不做

```text
❌ General Ledger

❌ Double-entry Accounting

❌ Chart of Accounts

❌ ERP

❌ 财务报表平台

❌ Revenue Recognition

❌ Tax Accounting

❌ Supplier Settlement

❌ Payout Accounting

❌ Treasury / FX

❌ Refund workflow 重写

❌ Dispute / Chargeback orchestration

❌ Payment state machine 重写

❌ CommerceTransaction 重写

❌ 自动 mismatch charge

❌ 自动 mismatch refund

❌ 全历史强制 Ledger backfill

❌ 一次迁移所有 Adyen/PayPal reconciliation

❌ MQ / 微服务强依赖
```

---

# 69. 最高风险排序

### RISK-FIN-01 — Capture semantics

最高。

必须先解决：

```text
Payment state
≠
统一 cash meaning
```

---

### RISK-FIN-02 — Retry Payment double-charge window

P2 Recovery 的：

```text
UNPAID → retry_payment
```

在 provider 状态存在延迟/不确定时必须加强安全门。

---

### RISK-FIN-03 — Multiple Successful Payments

Journal/Data Model 必须支持 N payment facts。

---

### RISK-FIN-04 — PaymentSplit dual semantics

不能让：

```text
Split + Allocation Journal
```

产生双计。

---

### RISK-FIN-05 — Refund ownership

组合 Refund 到 CommerceTransaction/Order 的归属链需要冻结。

---

### RISK-FIN-06 — Stripe provider refs

Charge / BalanceTransaction 目前不完整。

---

### RISK-FIN-07 — Legacy providers

Adyen/PayPal full financial reconciliation 第一版不能伪装已支持。

---

# 70. Release Verification

## RV-F01 — Stripe Auto Capture

```text
Transaction
→ Payment
→ FinancialFact=CASH_CAPTURED
→ Journal
→ Stripe reconciliation
→ MATCHED
```

---

## RV-F02 — Stripe Manual Capture

```text
Authorize
→ NO CASH_CAPTURED Journal

Capture
→ CASH_CAPTURED Journal
→ MATCHED
```

这是 P4 最关键验证之一。

---

## RV-F03 — Multi-payment / Short Payment

```text
Transaction amount 100

Payment A 40
Payment B 60
```

验证：

```text
2 captured entries
gross = 100
```

---

## RV-F04 — Combination

```text
Payment 100

Split A 60
Split B 40
```

验证：

```text
cash = 100
allocation = 100
无双计
```

---

## RV-F05 — Partial Refund

```text
Capture +100

Refund -30

net = 70
```

并与 Stripe Refund 对账。

---

## RV-F06 — Reconciliation Mismatch

受控制造：

```text
local projection mismatch
```

要求：

```text
MISMATCH / NEEDS_ATTENTION
```

且：

```text
no charge
no refund
```

---

## RV-F07 — Retry / Replay

重复：

```text
Webhook
Posting
Reconciliation
Repair
```

不得：

```text
duplicate Journal
duplicate Payment
duplicate Refund
```

---

# 71. Definition of Done

P4 完成后系统应形成：

```text
CommerceTransaction
        ↓
Payment / Refund / Allocation
        ↓
FinancialFactResolver
        ↓
Immutable Financial Journal
        ↓
TransactionFinancialSummary
        ↓
Provider Financial Facts
        ↓
Source Reconciliation
        ↓
Transaction Reconciliation
```

系统可以准确回答：

```text
商业上应该收多少

实际 PSP cash capture 多少

Store Credit 使用多少

Offline Payment 记录多少

发生了几笔成功支付

退款多少

每个 Order 分配多少

是否 short paid / overpaid

Stripe gross 是否一致

Stripe refund 是否一致

Stripe fee/net 是多少

本地和 PSP 哪里不一致

是否需要人工处理
```

---

# 72. 当前下一步

当前建议只执行：

```text
FIN-P4-0 — Financial Semantic Freeze
```

但不需要重新做一轮完整 Repo Audit。

现有分析已经证明大部分事实。

只需重点冻结：

```text
1. CAPTURE_EVIDENCE_MATRIX

2. FINANCIAL_INSTRUMENT_CLASSIFICATION

3. SUCCESSFUL_PAYMENT_CARDINALITY

4. REFUND_OWNERSHIP_POLICY

5. ALLOCATION_POLICY

6. JOURNAL_ENTRY_IDENTITY

7. RETRY_PAYMENT_FINANCIAL_SAFETY_POLICY

8. STRIPE_PROVIDER_REFERENCE_POLICY
```

这些冻结后，再批准：

```text
FIN-P4-1 — Financial Fact Resolution
```

**不要直接从 FIN-P4-0 跳到建 `financial_ledger_entries` 表。**
