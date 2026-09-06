# FIN-P4-4：Allocation Integrity —— PaymentSplit → ORDER_ALLOCATION 入账与 split/allocation 恒等式（P4 拆包第 4 包）

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-06 |
| 来源 | 用户任务：「继续第一条」——P4 V2 拆包第 4 包（Allocation Integrity）；前序 FIN-P4-1（Financial Fact Resolution）、FIN-P4-2（Immutable Financial Journal）、FIN-P4-3（Payment/Refund Posting）均已 done |
| 分类 | payments |
| 关联 Skill | `ai/skills/pallastrade-payments/SKILL.md`、`ai/skills/pallastrade-events-webhooks/SKILL.md`、`ai/skills/pallastrade-testing/SKILL.md` |
| 关联 REQ | REQ-20260906-fin-p4-4.md |
| 关联 PRD | 上游：`豆包梳理业务需求/P4 — Transaction Financial Ledger & PSP Reconciliation Foundation.md`（V2；§60 FIN-P4-4 + §21-24/§48/§66 AC-4013/4014/4015/4016）；前序：FIN-P4-1/2/3 PRD |
| 需求类型 | 新功能（FinancialFact 契约扩展 + allocation resolver/posting + combination.succeeded 订阅接线；**无 migration**——ledger `payment_split_id` 列 P4-2 已预留） |

> V2 顺序：FIN-P4-1 ✅ → FIN-P4-2 ✅ → FIN-P4-3 ✅ → **FIN-P4-4 Allocation Integrity（本包）** → FIN-P4-5+。
> 复用契约：FIN-P4-1 `FinancialFact`/Resolvers + FIN-P4-2 `FinancialLedger::{Post,Reverse}` + FIN-P4-3 PostPayment/PostRefund 编排与 subscriber 模式。

---

## 1. 背景与目标

- **一句话需求原文**：把组合支付 `PaymentSplit` 的订单归属作为不可变 `ORDER_ALLOCATION` 记入资金账本，并保证 `Σ ORDER_ALLOCATION = Σ PaymentSplit.captured_amount`（split/allocation sum invariant），不改变 OrderUpdater cash behavior。
- **背景**：
  - FIN-P4-1/2/3 已把 **cash 事实**（CASH_CAPTURED/STORE_CREDIT_APPLIED/OFFLINE_PAYMENT_RECORDED/REFUND_SUCCEEDED）接入不可变账本；`FinancialLedgerEntry` 表 P4-2 已预留 `payment_split_id` FK 与 `ORDER_ALLOCATION`（RESERVED 未激活），`fact_posting_key` 已支持 `payment_split_id` 溯源。
  - 但目前组合支付 Settlement 后 **splits 的订单归属没有 journal 投影**：P4 §23 组合不变量（Σ ORDER_ALLOCATION = Σ PaymentSplit.captured_amount）未闭环（P4 AC-4014/4015）；PaymentSplit 同时是 OrderUpdater cash aggregation source + allocation source of truth 的"双语义"（§21/P4 §66 FIN-INV-05）需要 journal 侧澄清：**ORDER_ALLOCATION = 资金归属投影（immutable），非额外 cash inflow（AC-4013）**。
  - P4 §48：trigger = "PaymentSplit settlement/update → Post/verify Allocation Journal"（不要用 Transaction completed 作统一 trigger）。
- **目标**：
  - 扩展 FIN-P4-1 契约：`FinancialFact` 增加 `payment_split_id` 属性 + `ORDER_ALLOCATION` fact type（不改变既有 5 type 语义）。
  - `FinancialFacts::ResolveAllocation`（split → ORDER_ALLOCATION fact：order_id = split.order、payment_split_id、amount = split.captured_amount、ownership = combination.commerce_transaction；只读零副作用）。
  - `FinancialLedger::Post` 激活 `ORDER_ALLOCATION` entry_type + create_entry 回填 `payment_split`。
  - `FinancialLedger::PostAllocation` 编排（镜像 P4-3 PostPayment/PostRefund；幂等 + skipped 语义）；`FinancialLedger::PostCombinationAllocations`（批量：组合内 splits）。
  - 接线：`payment_combination.succeeded`（after_transition → publish_event，既有）→ `PaymentCombinationSucceededSubscriber` → 为每个 captured>0 的 split PostAllocation（默认 async，幂等，失败不阻断资金流）。
  - 只读恒等式服务 `FinancialLedger::AllocationIntegrity`（Σ active ORDER_ALLOCATION vs Σ split.captured_amount per combination；供 spec + 未来 P4-7 reconciliation）。
  - **不改** OrderUpdater/PaymentSplit/Settlement/Carts/P0-P3 任何行为；ORDER_ALLOCATION 不参与任何 cash 聚合（类型隔离）。
- **成功指标**：AC-4P4-* 全绿；新增 spec + 全量 backend-rspec 0 failures；无 migration/API/UI。

## 2. 用户故事 / 场景

| # | 场景 | 类型 | 描述 |
|---|---|---|---|
| S1 | Combination settled exact-paid | 正常 | 组合 3 成员 → succeed → 每 split captured>0 → 各 1 条 ORDER_ALLOCATION（归各自 order + split） |
| S2 | 恒等式 | 正常 | Σ active ORDER_ALLOCATION == Σ split.captured_amount（AC-4014） |
| S3 | ORDER_ALLOCATION ≠ cash | 正常 | allocation entries 不增加 CASH_CAPTURED/gross 聚合（类型隔离，AC-4013） |
| S4 | Exact-paid combo | 正常 | allocation_total == captured_total == combination.amount（AC-4015） |
| S5 | Short payment | 边界 | captured share < amount_due → allocation = 实际 captured share，不报 ledger error（AC-4016） |
| S6 | 重复/重放 | 边界 | payment_combination.succeeded 重复触发 / job retry → 幂等同一条（显式稳定 idempotency key） |
| S7 | Reversal | 边界 | ORDER_ALLOCATION 被冲销 → active 集合恒等式仍成立（Σ active） |
| S8 | 不可 post | 异常 | split 无组合 / 组合无 txn（legacy）/ captured=0 → 不产生 entry（不猜） |
| S9 | Posting 失败 | 异常 | allocation posting 抛错 → 组合/订单/支付不受影响（subscriber rescue + 日志；幂等可重试） |

## 3. 功能需求（FR）

- FR-4P4-01：`FinancialFact` 扩展——`ATTRIBUTES` 增加 `payment_split_id`；`FACT_TYPES` 增加 `ORDER_ALLOCATION`（保持其余 5 type + NONE 不变）；helper `allocation?`（fact_type == ORDER_ALLOCATION）。**不改**既有常量/构造器语义（只读 VO，构造后 freeze）。
- FR-4P4-02：新增 `PallasTrade::FinancialFacts::ResolveAllocation`（只读 resolver）：`call(split:)` → ORDER_ALLOCATION fact。规则：
  - split.payment_combination 存在 且 `combination.commerce_transaction` 可解析（txn 化组合）→ CONFIRMED；`amount = split.captured_amount`、`currency = split.currency`、`order_id = split.order.prefixed_id`、`payment_split_id = split.prefixed_id`、`effective_at` = 确定性时刻（实施冻结：优先 combination.completed_at；缺省以显式稳定 idempotency key 兜底——见 FR-4P4-05）。
  - captured_amount 为 0 / 无组合 / 组合无 txn（legacy 非 txn 组合 Strangler）→ 表达为不可 post（status 语义对齐 P4-1：无可靠归属不猜）。
  - **只读**：不创建/更新/删除任何记录（含 split/combination/order），无 state machine、无 Journal 写。
- FR-4P4-03：`FinancialLedgerEntry`：`ORDER_ALLOCATION` 从 RESERVED 激活进 `ENTRY_TYPES`（validation inclusion 放行）；`RESERVED_ENTRY_TYPES` 保留 PSP_FEE/PSP_NET_SETTLEMENT。append-only/immutability/reversal 机制不变（payment_split_id 已在 IMMUTABLE_ATTRIBUTES）。
- FR-4P4-04：`FinancialLedger::Post`：create_entry 回填 `payment_split`（`resolve(PallasTrade::PaymentSplit, fact.payment_split_id)`）；`postable?` 随 ENTRY_TYPES 自动放行 ORDER_ALLOCATION（CONFIRMED + 激活 type + txn 可解析 + amount/currency 同既有门禁）。不改变既有 cash/refund posting 路径。
- FR-4P4-05：新增 `FinancialLedger::PostAllocation` 编排（镜像 PostPayment/PostRefund）：ResolveAllocation → `Post.postable?` → Post。幂等：**显式稳定 idempotency_key** `"fact:ORDER_ALLOCATION:#{txn.prefixed_id}:#{split.prefixed_id}"`（不依赖 effective_at 时间戳——replay/retry 换时刻不会产生重复 entry；Post 已支持显式 key 参数）。不可 post → `success({ entry: nil, skipped: true, reason })`（不猜、无部分记录 FIN-INV-09）。
- FR-4P4-06：新增 `FinancialLedger::PostCombinationAllocations`（组合批量编排）：遍历 `combination.payment_splits`（captured_amount>0）逐 split PostAllocation；逐条独立（一条失败不阻断其余——记录 + 继续）；返回结果聚合。幂等（内部逐条幂等）。
- FR-4P4-07：接线 `payment_combination.succeeded`（PaymentCombination after_transition publish_event，既有事件）→ `FinancialLedger::PaymentCombinationSucceededSubscriber`（`subscribes_to 'payment_combination.succeeded'`）→ 解析组合（payload `pcom_` prefixed 或 raw id 双模式）→ `PostCombinationAllocations`。subscriber 默认 async（SubscriberJob）；异常 rescue → Rails.logger（不阻断组合/资金流）。注册 core engine.rb subscribers.concat。
- FR-4P4-08：新增只读恒等式服务 `FinancialLedger::AllocationIntegrity.call(combination:)` → `{ allocation_total, split_captured_total, balanced? }`：`allocation_total = Σ active(posting) ORDER_ALLOCATION(entry_type) amount`（挂该组合 txn 或经 combination 过滤）；`split_captured_total = Σ split.captured_amount`；`balanced? = 二者相等`。**只读**（不写、不改任何状态）；供 spec 断言与 P4-7 reconciliation 复用。
- FR-4P4-09：不改既有行为——不碰 PaymentSplit 模型/OrderUpdater/Settlement/Carts::Complete/Transactions::Finalize/PaymentCombinations::Complete；ORDER_ALLOCATION 仅 Journal 投影，**不参与任何 cash/gross 聚合**（类型隔离；既有 cash scopes 按 entry_type 过滤天然隔离）。
- FR-4P4-10：范围外——无 migration（payment_split_id 列 P4-2 已建）；无 API/UI；不做 splitter/manual_split 等 legacy 非组合 split 的 backfill posting（无组合→无 txn→skip，P4-8 repair/backfill）；不做 Order-level refund allocation（P4 §29 REFUND_ALLOCATION_POLICY——transaction-level refund fact 已由 P4-3 入账，order-level refund split 归属留后续包）；不建 TransactionFinancialSummary（P4-7）。

## 4. 非功能需求（NFR）

- 可靠性：allocation posting 异步（SubscriberJob）+ **显式稳定幂等 key**；失败可重试不重复（P4 §42/§17）。
- 顺序/事务：`payment_combination.succeeded` 在 Settlement 写 splits captured 之后发布（Settlement：splits update_column → succeed! → publish）；subscriber async 在提交后执行 → 读到最终 captured（P4 §16：ledger 失败不逆转组合资金）。
- 只读边界：ResolveAllocation/PostAllocation/AllocationIntegrity 只读资金实体 + 写 Journal；对 PaymentSplit/Combination/Order 零写。
- 类型隔离：ORDER_ALLOCATION 与 cash facts 同表不同 entry_type——所有 cash 聚合按 entry_type 过滤即天然不含 allocation（AC-4013）。
- 性能：subscriber 单组合批量、无 N+1（splits includes order/combination）；batch 非本包关注。
- 兼容：无 schema/API 变更；P0-P4-3 行为不变；OrderUpdater cash behavior 不变（显式 spec 断言）。

## 5. 验收标准（AC，与测试一一映射）

> 对齐 P4 §66：AC-4013/4014/4015/4016 + §22/§23/§48 + FIN-INV-05/09。

- AC-4P4-01 ← FR-4P4-02/05/06/07 / P4 AC-4014：组合 Settlement（真实 succeed 路径）→ 每个 captured>0 的 split 恰好 1 条 `ORDER_ALLOCATION` entry（order_id + payment_split_id + amount=captured 正确）。
- AC-4P4-02 ← FR-4P4-08 / P4 AC-4014：恒等式——`AllocationIntegrity` 对 settled 组合 `balanced? == true`（Σ active ORDER_ALLOCATION == Σ split.captured_amount）。
- AC-4P4-03 ← FR-4P4-09 / P4 AC-4013：ORDER_ALLOCATION 不增加 gross/cash 聚合（cash-type 计数/金额查询不含 allocation entries）。
- AC-4P4-04 ← FR-4P4-08 / P4 AC-4015：exact-paid 组合——allocation_total == captured_total == combination.amount。
- AC-4P4-05 ← FR-4P4-05 / P4 AC-4016：short payment 组合——allocation 按实际 captured share（< amount_due），不报 ledger error、balanced 仍成立。
- AC-4P4-06 ← FR-4P4-05：重复 PostAllocation / 事件重放 → 幂等同一条（显式稳定 key 不因时刻变化重复）。
- AC-4P4-07 ← FR-4P4-05/06 + P4-2 Reverse：ORDER_ALLOCATION 参与标准冲销（append-only：reversal entry active 且 amount 相反、原 entry → reversed）；`AllocationIntegrity` 按 **active** 集合计——冲销后原 entry 不再计入；若未补记等价 allocation 则 `balanced? == false`（恒等式把"未完成冲销"暴露为不一致信号，不静默吞掉）；补记/修复归 P4-8 repair。
- AC-4P4-08 ← FR-4P4-02/05 / FIN-INV-09：不可 post 的 split（无组合 / 组合无 txn / captured=0）→ 不产生 entry（skip，不猜、无部分记录）。
- AC-4P4-09 ← FR-4P4-09：posting 前后 PaymentSplit/Combination/Order 状态与行数不变（零写）；OrderUpdater cash behavior 不变（payment_total/payment_state 不受 allocation posting 影响）。
- AC-4P4-10 ← FR-4P4-07：`payment_combination.succeeded` 事件触发后 subscriber 产生 entries（integration：发布事件 → 直接驱动 handler 或等 job）；无 txn legacy 组合 → 安全 no-op。
- AC-4P4-11 ← FR-4P4-10：P4-1/2/3 + P0-P3 既有 specs 零回归（financial_facts 56 + financial_ledger 22 + P4-3 posting/subscriber 28 + transactions/payments 等）。

## 6. 跨层搜索记录（6 层，gate 强制）

关键词：`ORDER_ALLOCATION / allocation / PaymentSplit / payment_split / payment_combination.succeeded / PostAllocation`。

| 层 | 路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | allocation/ledger/split | 无（app 层无 services/models 复制） | 否 |
| Core models | `pallastrade_core/app/models/` | PaymentSplit / FinancialLedgerEntry / PaymentCombination / FinancialFact | PaymentSplit（psplit_；authorized/captured/refunded_amount + payment 可空 + combination 可空）；FinancialLedgerEntry（payment_split_id FK + ORDER_ALLOCATION RESERVED + fact_posting_key 已支持 split）；PaymentCombination（`publishes_lifecycle_events` + `payment_combination.succeeded` after_transition 既有）；FinancialFact（无 payment_split_id/无 ORDER_ALLOCATION——P4-1 注释归 P4-4） | 部分：表结构/事件/契约预留就绪；缺 allocation fact type/resolver/posting |
| Core services | `pallastrade_core/app/services/` | financial_facts / financial_ledger / payments | FinancialFacts::{ResolvePayment,ResolveRefund}(P4-1)、FinancialLedger::{Post,Reverse,PostPayment,PostRefund}(P4-2/3)、PaymentCombinations::{Settlement,Complete} | 部分：缺 ResolveAllocation/PostAllocation/Integrity |
| Core subscribers | `pallastrade_core/app/subscribers/` | subscriber | PaymentSessionReservationSubscriber + P4-3 两个 ledger subscriber（模式参考；注册 core engine.rb） | 否 → 新增 combination succeeded subscriber |
| API | `pallastrade_api/app/` | allocation/ledger | 无 | 否（无 API） |
| Admin | `pallastrade_admin/app/` | allocation/ledger | 无 | 否（无 UI） |
| Storefront/Platform | 各层 | allocation/ledger/split | 无 | 否 |
| DB schema | `backend/db/schema.rb` | financial_ledger | `pallastrade_financial_ledger_entries.payment_split_id`（P4-2 已建 FK） | **无 migration 需求** |
| 写 splits 的既有路径（非本包改） | Settlement（splits captured update_column → succeed!）、Refund#update_order（combo 退款 refunded_amount）、orders/splitter.rb（P2 拆单，无组合） | — | 本包 trigger 只挂 `payment_combination.succeeded`；splitter legacy split 无组合/无 txn → skip（P4-8） | 不改 |

**结论**：ledger `payment_split_id` 列、`fact_posting_key` split 溯源、`payment_combination.succeeded` 事件、subscriber 注册点均已就绪（P4-2/3 产物）。缺口 = FinancialFact 契约扩展（payment_split_id + ORDER_ALLOCATION）+ ResolveAllocation + Post 激活与回填 + PostAllocation(s)/Integrity + combination succeeded subscriber。无重复能力。**无 migration**。

## 7. 技术影响

- **修改（core gem，既有 P4-1/2/3 文件——能力激活，非行为回退）**：
  - `app/models/pallastrade/financial_fact.rb`：ATTRIBUTES + `payment_split_id`；FACT_TYPES + `ORDER_ALLOCATION`；helper `allocation?`。
  - `app/models/pallastrade/financial_ledger_entry.rb`：ENTRY_TYPES + `ORDER_ALLOCATION`（RESERVED 留 PSP_FEE/PSP_NET_SETTLEMENT）。
  - `app/services/pallastrade/financial_ledger/post.rb`：create_entry 回填 `payment_split: resolve(PaymentSplit, fact.payment_split_id)`。
- **新建（core gem）**：
  - `app/services/pallastrade/financial_facts/resolve_allocation.rb`
  - `app/services/pallastrade/financial_ledger/post_allocation.rb`、`post_combination_allocations.rb`、`allocation_integrity.rb`
  - `app/subscribers/pallastrade/financial_ledger/payment_combination_succeeded_subscriber.rb`
- **修改注册**：`pallastrade_core/lib/pallastrade/core/engine.rb`（subscribers.concat +1）。
- **不修改**：PaymentSplit/OrderUpdater/Settlement/Complete/Carts::Complete/Transactions::Finalize/Refund；无 migration/schema；无 API/UI。
- **关键设计决策（实施冻结）**：
  - 幂等 key：显式 `"fact:ORDER_ALLOCATION:#{txn_id}:#{split_id}"`（不依赖 effective_at 时刻 → 重放/重试安全）。FR-4P4-05。
  - trigger：subscriber on `payment_combination.succeeded`（async）；Settlement 在锁内先写 splits captured 再 succeed!——subscriber job 提交后执行读到最终值。FR-4P4-07。
  - effective_at：确定性（combination.completed_at 或 fallback）——实施时按显式 key 策略下可安全用 posting 时刻（key 已稳定），但优先 completed_at 保持审计语义。
  - 组合无 txn（legacy Strangler）→ skip（不猜）；P4-8 负责 legacy backfill。
  - `AllocationIntegrity` 只读，`balanced?` 供测试与 P4-7；不做告警/阻断。

## 8. 测试计划

- 新增（backend/spec）：
  - `spec/services/pallastrade/financial_facts/resolve_allocation_spec.rb` —— AC-4P4-01/08
  - `spec/services/pallastrade/financial_ledger/post_allocation_spec.rb` —— AC-4P4-01/05/06/08/09
  - `spec/services/pallastrade/financial_ledger/post_combination_allocations_spec.rb` —— AC-4P4-01/06/08
  - `spec/services/pallastrade/financial_ledger/allocation_integrity_spec.rb` —— AC-4P4-02/03/04/07
  - `spec/jobs/pallastrade/financial_ledger/payment_combination_succeeded_subscriber_spec.rb` —— AC-4P4-10
- 真实路径要求：组合 settled 走真实 `Settlement`/`PaymentCombinations::Complete`（或 txn 化 Finalize 组合分支）succeed 路径（非手造 succeeded）；captured share 按 amount_due 比例（可造多成员订单验证 Σ）。
- 修改既有 spec：`financial_fact_spec`（新增 payment_split_id/ORDER_ALLOCATION 常量断言）、`financial_ledger_entry_spec`/`post_spec`（ORDER_ALLOCATION 激活后正反例——原 "refuses non-activated ORDER_ALLOCATION" 测试须改为激活后可 post 断言）、`financial_facts` spec 集合。
- 恒等式：exact-paid + short-payment + reversal 三态各断言 `AllocationIntegrity.balanced?`。
- 回归：financial_facts（56）+ financial_ledger（22）+ P4-3（28）+ transactions/payments + settlement/combination specs → 0 failures；全量 backend-rspec（coverage-gate 依据）。
- AC 映射：AC-4P4-01~11 → 上述 spec + 回归（spec 内 `AC-4P4-xx` 标注，同 P4-1/2/3；`prd verify` 仅支持纯数字 AC 不适用本系列命名）。

## 9. 文档同步清单（知识同步门）

- [ ] `ai/skills/pallastrade-payments/SKILL.md`：补 Allocation Integrity 章节（ORDER_ALLOCATION 语义 + ResolveAllocation/PostAllocation(s)/Integrity + combination.succeeded 接线；明确「allocation ≠ cash」）。
- [ ] `ai/skills/pallastrade-events-webhooks/SKILL.md`：如事件目录需登记 `payment_combination.succeeded` ledger 订阅（评估后定）。
- [ ] `harness/scenarios/scenarios.json`：新增 GS-053（allocation integrity 场景）。
- [ ] 本 PRD 状态 + `docs/prd/README.md` 索引。
- [ ] API/schema：不涉及。

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-06 | 0.1 | 初稿：FIN-P4-4 Allocation Integrity 拆包 PRD（P4 §60/§21-24/§48/§66 AC-4013-4016 + FIN-P4-1/2/3 复用；FinancialFact 契约扩展 + ResolveAllocation + Post 激活/回填 + PostAllocation(s)/Integrity + combination.succeeded subscriber；无 migration） | AI |
| 2026-09-06 | 0.2 | approved（用户「实施」确认）→ 实施完成：FinancialFact +payment_split_id/+ORDER_ALLOCATION；FinancialLedgerEntry 激活 ORDER_ALLOCATION；Post 回填 payment_split；ResolveAllocation/PostAllocation（显式稳定幂等 key）/PostCombinationAllocations/AllocationIntegrity（服务内 reload splits 防陈旧缓存）；PaymentCombinationSucceededSubscriber + engine 注册；新增 51 examples 0 failures；回归 financial_facts+ledger+subscribers 134、payments/transactions/combination/cart 102 全绿；AC-4P4-07 语义修正（冲销未补记 → balanced?=false 暴露不一致） | AI |
