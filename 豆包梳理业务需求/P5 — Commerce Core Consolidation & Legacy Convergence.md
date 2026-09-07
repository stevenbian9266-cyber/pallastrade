# P5 — Commerce Core Consolidation & Legacy Convergence

> 建议工程编号：`CORE-P5`
>
> 前置：
>
> ```text
> P0 — Payment Execution Foundation
> P1 — Commercial Checkout Facts
> P2 — Commerce Transaction Runtime
> P3 — Inventory Consistency Integration
> P4 — Financial Fact & Reconciliation Foundation
> ```
>
> 核心定位：
>
> **停止继续扩展交易能力，对 P0-P4 形成的 Commerce Core 做一次正式收敛：统一 canonical flow、退休 legacy path、固化事实解析模式、强化数据库 invariant，并降低后续 Refund / Dispute / Fulfillment 扩展成本。**

---

## 1. 为什么 P4 后先做 P5 收敛

当前系统已经形成：

```text
Checkout
→ CommerceTransaction
→ Inventory Reserve
→ Payment Execution
→ Payment Fact
→ Order Finalization
→ Inventory Commit Fact
→ Financial Fact
→ Journal
→ Reconciliation
```

现在最大的风险已经不再是：

```text
缺能力
```

而是：

```text
同一能力存在多条历史路径

legacy adapter 长期不退

模型名字与职责逐渐错位

关键 invariant 只存在于 service 层

不同 Resolver 开始出现重复模式

provider / instrument abstraction 历史混杂
```

如果此时直接继续：

```text
Refund
Dispute
Chargeback
Supplier Settlement
```

这些历史复杂度会继续放大。

---

# 2. P5 的目标

P5 不新增商业能力。

只做六件事：

```text
1. Canonical Flow 收敛

2. Legacy Reachability 清理

3. Finalization Boundary 收敛

4. Fact Resolver Pattern 标准化

5. Payment / Financial abstraction 边界整理

6. Critical Invariants 从“约定”升级为可执行约束
```

---

# 3. P5 完成后的目标架构

```text
                         Order
                           │
                           ▼
                    Checkout Domain
                           │
                           ▼
                  CommerceTransaction
                    /      |       \
                   /       |        \
                  ▼        ▼         ▼
             Inventory   Payment   Financial
                Fact       Fact       Fact
                  \         |         /
                   \        |        /
                    └── Orchestration ──┘
                           │
                           ▼
                  Order Finalization
                           │
                           ▼
                       Completed
```

外层：

```text
Provider Events
      │
      ▼
Evidence Store
      │
      ▼
Fact Resolvers
      │
      ▼
Safe Action / Recovery / Reconciliation
```

---

# 4. 最终 Canonical Commerce Flow

P5 必须冻结一条唯一标准路径：

```text
Cart
↓
Submit
↓
Order
↓
CheckoutView / Readiness
↓
CheckoutSnapshot
↓
CommerceTransaction
↓
Inventory Reserve
↓
PaymentSession
↓
Provider
↓
Payment Fact
↓
Canonical Finalization
↓
Physical Inventory Consume
↓
Reservation Commit Fact
↓
CommerceTransaction Complete
↓
Financial Fact
↓
Journal / Reconciliation
```

以后所有新能力必须挂在这条链上。

禁止新增第二条：

```text
special checkout flow
special payment completion flow
special order complete flow
```

---

# 5. CORE-P5-0 — Architecture Convergence Audit

第一包仍建议只读。

目标不是重新审计 P0-P4，而是回答：

> **现在生产系统到底还有几条能完成一笔订单的路径？**

必须输出：

```text
CANONICAL_FLOW_MAP

LEGACY_FLOW_MAP

PRODUCTION_REACHABILITY_MATRIX

FINALIZATION_ENTRYPOINT_MATRIX

PAYMENT_COMPLETION_ENTRYPOINT_MATRIX

TRANSACTION_CREATION_ENTRYPOINT_MATRIX

INVENTORY_ENTRYPOINT_MATRIX

FINANCIAL_POSTING_ENTRYPOINT_MATRIX

PROVIDER_CAPABILITY_MATRIX

COMPATIBILITY_ADAPTER_MATRIX

FACT_RESOLVER_MATRIX

STATE_AND_FACT_OWNERSHIP_MATRIX

DB_INVARIANT_GAP_MATRIX

DEPRECATION_PLAN

P5_RISK_LIST

P5_IMPLEMENTATION_PLAN
```

无 migration。

无删除。

---

# 6. P5-0 最重要的审计问题

至少确认：

1. 当前到底有多少个 Order completion 入口？
2. `Carts::Complete` 还有哪些生产调用方？
3. `Checkout::Complete` 是否仍 reachable？
4. legacy Stripe completion job 是否仍 reachable？
5. PaymentCombination 是否完全进入 CommerceTransaction？
6. manual payment 是否绕过 Transaction？
7. legacy Check / StoreCredit 是否绕过 canonical financial facts？
8. AutoSplit / ManualSplit 是否存在独立 completion path？
9. Adyen / PayPal 哪些路径真实生产可达？
10. 是否仍存在 PaymentSession 之外直接调用 PSP 的路径？
11. Reservation 是否还有 transaction-unaware 新写入路径？
12. Journal 是否还有绕过 FinancialFactResolver 的 posting path？
13. Payment / Inventory / Financial Resolver 是否存在重复 fact rules？
14. 哪些 application invariant 已经稳定到适合 DB enforcement？
15. 哪些 compatibility adapter 已经可以删除？

---

# 7. CORE-P5-1 — Canonical Flow Contract

正式产出：

```text
Commerce Core Contract
```

定义唯一 ownership：

| Domain                | Authority                 |
| --------------------- | ------------------------- |
| Commercial facts      | Order / CheckoutSnapshot  |
| Transaction execution | CommerceTransaction       |
| Payment attempt       | PaymentSession            |
| Payment fact          | PaymentFactResolver       |
| Inventory reservation | StockReservation          |
| Physical inventory    | StockItem / StockMovement |
| Inventory fact        | InventoryFactResolver     |
| Financial fact        | FinancialFactResolver     |
| Financial history     | Financial Journal         |
| Provider consistency  | Reconciliation            |

任何模块不得跨 ownership 写入另一个领域的 authority。

---

# 8. CORE-P5-2 — Finalization Boundary Consolidation

这是 P5 最值得处理的历史债。

当前：

```text
Carts::Complete
```

已经实际承担：

```text
Order purchase finalization primitive
```

P5 目标不是立即删除它，而是建立明确边界：

```text
Transactions::Finalize
        ↓
OrderFinalizationPort
        ↓
Canonical Purchase Finalizer
        ↓
legacy adapter if required
```

候选：

```text
Orders::FinalizePurchase
```

或者项目 convention 下等价命名。

---

# 9. Finalization 原则

最终所有：

```text
single purchase
combined purchase
recovery
inventory recovery
```

统一调用：

```text
Canonical Finalizer
```

禁止：

```text
Controller 自己 complete order

Webhook 自己 finalize order

PaymentCombination 自己 complete member

ManualSplit 自己标 completed
```

---

# 10. 不要求立即删除 Carts::Complete

安全方式：

```text
Orders::FinalizePurchase
        ↓
Compatibility Adapter
        ↓
Carts::Complete
```

先把新调用方统一。

然后：

```text
0 production refs
+
runtime observation
+
baseline green
```

后再删除旧 primitive。

---

# 11. CORE-P5-3 — Fact Resolver Pattern Consolidation

当前已经形成：

```text
PaymentFactResolver

InventoryFactResolver

FinancialFactResolver
```

这是非常好的模式。

P5 要统一的是：

```text
接口风格
Result contract
evidence handling
ambiguity semantics
trace
```

不是合并成一个“大 Resolver”。

---

# 12. Resolver 统一 Contract

推荐统一概念：

```text
Result

status
reason_code
evidence
observed_at
source
```

核心规则：

```text
CONFIRMED
UNCONFIRMED
AMBIGUOUS
UNSUPPORTED
NOT_APPLICABLE
```

各领域可以保留自己的业务 fact：

```text
Payment:
PAID / UNPAID

Inventory:
RESERVED / COMMITTED / RELEASED / EXPIRED

Financial:
CASH_CAPTURED / CREDIT_APPLIED / ...
```

---

# 13. Resolver 必须遵守的共同原则

```text
Evidence First

No Guess

Read Before Side Effect

Provider Query Read-only

Ambiguous → Safe Stop

Recovery consumes Facts
```

禁止：

```text
state name
→ 直接猜现实世界事实
```

---

# 14. CORE-P5-4 — Payment Abstraction Cleanup

这是历史上比较明显的一块 abstraction debt。

当前：

```text
PaymentMethod
```

可能包含：

```text
Stripe
Adyen
PayPal

StoreCredit
Check
```

但它们不是同一种东西。

---

# 15. 目标概念拆分

不一定立刻改表，但 architecture contract 应明确：

```text
Payment Instrument
```

表示：

```text
Card / Wallet / StoreCredit / Check / Offline
```

和：

```text
Payment Provider / Gateway
```

表示：

```text
Stripe / Adyen / PayPal / Internal
```

不能继续逻辑上混为一层。

---

# 16. P5 不强制重写 PaymentMethod

第一阶段可以：

```text
FinancialInstrumentClassifier
+
Gateway capability
```

作为 compatibility layer。

只有审计证明：

```text
当前 PaymentMethod abstraction 已严重阻碍新功能
```

才批准 schema/model 重构。

---

# 17. Provider Capability Matrix

正式维护：

```text
Provider
│
├── create payment session
├── complete
├── capture
├── refund
├── webhook
├── fetch_payment_status
├── fetch_financial_details
└── reconciliation
```

例如：

```text
Stripe
→ FULL

Bogus
→ TEST

Adyen
→ LEGACY_PARTIAL

PayPal
→ LEGACY_PARTIAL
```

这样：

```text
Multi-PSP-ready
```

不再是模糊描述。

---

# 18. CORE-P5-5 — Legacy Path Retirement

所有 legacy 先分类：

```text
ACTIVE_CANONICAL

ACTIVE_COMPATIBILITY

OBSERVE_FOR_REMOVAL

DEPRECATED

DEAD
```

禁止看到：

```text
grep 0 refs
```

就直接删除。

还需要检查：

```text
external deep links

provider redirect

scheduled jobs

webhooks

admin/manual paths

historical callback URLs
```

---

# 19. 推荐优先退休对象

以审计结果为准，但优先关注：

```text
legacy checkout completion

legacy cart payment completion

legacy Stripe completion jobs

direct provider callbacks bypassing Transaction

manual completion shortcuts

old combined payment adapters

transaction-unaware inventory writes
```

---

# 20. Retirement Gate

每条 legacy 删除前必须：

```text
Code refs = 0

Route reachability = 0

Job schedule = 0

Webhook reachability = 0

Provider redirect dependency = 0

Production observation = clear

Regression green
```

---

# 21. CORE-P5-6 — Invariant Hardening

P0-P4 经过几轮运行后，很多 invariant 已经成熟。

P5 可以把部分：

```text
Application convention
```

升级成：

```text
DB / schema constraint
```

---

# 22. 候选 DB Invariants

例如：

### Transaction

```text
currency NOT NULL

amount >= 0
```

### TransactionOrder

```text
unique(transaction, order)

amount_snapshot >= 0
```

### PaymentSession

```text
transaction FK integrity

one payment per session
```

### Reservation

```text
only one active RESERVED
per relevant inventory identity
```

### Journal

```text
posting_key UNIQUE

reversal uniqueness

amount/currency immutable at application boundary
```

### PaymentSplit

```text
captured >= 0
refunded >= 0
```

---

# 23. 不要过度 DB 化

禁止用：

```text
复杂 trigger
```

把所有业务状态机塞进数据库。

只升级：

```text
稳定
简单
可以明确表达
高价值
```

的 invariant。

---

# 24. CORE-P5-7 — Trace / Audit Consolidation

现在有：

```text
CommerceTransaction trace
inventory trace
financial trace
webhook evidence
audit logs
```

P5 要把它们组织成统一：

```text
Commerce Trace
```

---

# 25. Commerce Trace

对于一个：

```text
txn_xxx
```

可以看到：

```text
Checkout Snapshot

Participants

Inventory Reservations

Payment Sessions

Payments

Provider Events

Payment Fact

Finalization attempts

Stock Movements

Inventory Fact

Financial Facts

Journal Entries

Refunds

Reconciliation

Recovery actions
```

---

# 26. Trace 不是新 Event Store

不新建：

```text
commerce_event_store
```

第一版仍然：

```text
read projection
```

聚合已有事实。

---

# 27. CORE-P5-8 — Operational Hardening

建立真正可运营的 Commerce Core。

至少：

```text
stuck transaction metrics

recovery required rate

inventory inconsistency rate

financial mismatch rate

manual review queue

legacy path usage counters

provider capability failures
```

---

# 28. Legacy Usage Metric 很重要

例如：

```text
legacy_carts_complete_calls_total

legacy_payment_completion_calls_total

legacy_provider_callback_calls_total
```

这样判断：

```text
真的没人用了
```

而不是：

```text
代码搜索看起来没人用了
```

---

# 29. P5 核心 Acceptance Criteria

## AC-5001

系统存在且文档化一条唯一 canonical purchase flow。

## AC-5002

所有新支付成功入口最终通过 CommerceTransaction orchestration。

## AC-5003

所有 transaction purchase finalization 通过统一 Finalization boundary。

## AC-5004

Webhook 不直接承担 Order business completion。

## AC-5005

PaymentSession.completed 不等于 CommerceTransaction.completed。

## AC-5006

Payment/Inventory/Financial Fact Resolver 均遵循 evidence-first / ambiguous-no-guess。

## AC-5007

Resolver 之间不复制彼此 domain authority。

## AC-5008

Payment instrument 与 provider capability 在 architecture contract 上明确分离。

## AC-5009

Stripe capability matrix 完整。

## AC-5010

Adyen/PayPal 未实现能力明确标为 partial/unsupported，不伪装 full support。

## AC-5011

每个 legacy path 有明确 lifecycle classification。

## AC-5012

DEAD path 删除前完成 runtime reachability gate。

## AC-5013

已稳定关键 invariant 有 DB enforcement 或明确保留 application-only 的理由。

## AC-5014

CommerceTransaction 可生成完整跨 checkout/payment/inventory/financial trace。

## AC-5015

Legacy path 使用可观测。

## AC-5016

P0 baseline 全绿。

## AC-5017

P1 baseline 全绿。

## AC-5018

P2 baseline 全绿。

## AC-5019

P3 baseline 全绿。

## AC-5020

P4 baseline 全绿。

---

# 30. P5 核心 Invariants

## CORE-INV-01

```text
一个商业事实
只能有一个 authoritative owner。
```

## CORE-INV-02

```text
Projection
不得反向成为 Authority。
```

## CORE-INV-03

```text
Recovery
必须基于 Fact，
不是基于猜测 state。
```

## CORE-INV-04

```text
所有资金副作用
必须位于明确 Payment execution boundary。
```

## CORE-INV-05

```text
Provider callback
不得直接成为业务状态 authority。
```

## CORE-INV-06

```text
Order Finalization
必须通过唯一 canonical boundary。
```

## CORE-INV-07

```text
Legacy Adapter
不得成为新功能依赖。
```

## CORE-INV-08

```text
Multi-PSP-ready
必须用 capability 描述，
不能等同 Multi-PSP-complete。
```

## CORE-INV-09

```text
不能证明无生产流量的 legacy path
不得仅因 grep=0 删除。
```

## CORE-INV-10

```text
P5 不新增新的 Commerce business capability。
```

---

# 31. 明确不做

P5 禁止扩展：

```text
❌ Refund orchestration

❌ Dispute

❌ Chargeback

❌ Return / RMA

❌ Supplier settlement

❌ Payout

❌ Accounting GL

❌ Revenue recognition

❌ Tax engine

❌ 新 PSP

❌ Payment Router

❌ Provider Registry 大重构

❌ Checkout redesign

❌ Inventory redesign

❌ CommerceTransaction rewrite

❌ 微服务拆分

❌ Kafka 化

❌ Event Sourcing 重构
```

---

# 32. 推荐实施顺序

```text
CORE-P5-0
Architecture Convergence Audit
        ↓
CORE-P5-1
Canonical Flow Contract
        ↓
CORE-P5-2
Finalization Boundary Consolidation
        ↓
CORE-P5-3
Fact Resolver Pattern Consolidation
        ↓
CORE-P5-4
Payment Abstraction / Provider Capability Cleanup
        ↓
CORE-P5-5
Legacy Path Retirement
        ↓
CORE-P5-6
Invariant Hardening
        ↓
CORE-P5-7
Commerce Trace Consolidation
        ↓
CORE-P5-8
Operational Hardening
```

---

# 33. Release Verification

P5 最重要的不是新业务 E2E，而是证明：

## RV-C01 — Canonical Purchase

```text
Checkout
→ Transaction
→ Reserve
→ Payment
→ Finalize
→ Financial Fact
```

只有一条 canonical execution path。

---

## RV-C02 — Recovery

```text
Payment success
→ local failure
→ Recovery
```

不能进入 legacy completion path。

---

## RV-C03 — Combination

```text
N Orders
→ CommerceTransaction
→ one canonical finalization boundary
```

---

## RV-C04 — Legacy Reachability

所有拟删除 legacy：

```text
route
job
webhook
external callback
runtime usage
```

均无生产依赖。

---

## RV-C05 — Invariant Violation

受控尝试：

```text
duplicate active reservation

duplicate journal posting

duplicate transaction participant
```

必须被 DB/application invariant 正确拒绝。

---

# 34. Definition of Done

P5 完成以后：

```text
P0-P4
```

不再只是几个阶段叠加，而成为一个正式：

# Commerce Core

它具备：

```text
Single Canonical Flow

Clear Domain Ownership

Fact-driven Recovery

Stable Provider Boundaries

Explicit Legacy Compatibility

Executable Invariants

Unified Trace

Operational Visibility
```

并且新功能开发可以基于稳定 extension points：

```text
Checkout

Transaction

Inventory

Payment

Financial

Finalization

Recovery

Reconciliation
```

而不是再次直接修改旧 Rails completion path。

---

# 35. P5 之后

P5 CLOSED 后，再进入真正的新业务阶段：

```text
P6 — Refund, Cancellation & Dispute Orchestration
```

届时可以基于：

```text
CommerceTransaction
FinancialFact
Journal
Inventory Fact
Canonical Finalization
```

设计：

```text
Partial Refund

Order-level Refund Allocation

Cancel-after-payment

Inventory Restock

Dispute

Chargeback

Financial reversal
```

而不会再次重写 P0-P4。

---

# 36. 当前下一步

现在只建议执行：

```text
CORE-P5-0 — Architecture Convergence Audit
```

先回答三个最关键的问题：

```text
1. 现在生产环境到底还有几条“订单完成”路径？

2. 哪些 legacy adapter 仍然真实 reachable？

3. P0-P4 哪些 application invariant 已经稳定到可以正式固化？
```

在这三个问题冻结之前，不批准大规模 legacy 删除或 Finalization 重构。
