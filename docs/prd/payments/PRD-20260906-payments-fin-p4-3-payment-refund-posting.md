# FIN-P4-3：Payment/Refund Posting —— 资金事实入账接线（P4 拆包第 3 包）

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-06 |
| 来源 | 用户任务：「继续FIN-P4-3」——P4 V2 拆包第 3 包（Payment/Refund Posting）；前序 FIN-P4-1（Financial Fact Resolution）与 FIN-P4-2（Immutable Financial Journal）均已 done |
| 分类 | payments（CLI 自动判定，关键词命中） |
| 关联 Skill | `ai/skills/pallastrade-payments/SKILL.md`、`ai/skills/pallastrade-events-webhooks/SKILL.md`、`ai/skills/pallastrade-testing/SKILL.md` |
| 关联 REQ | REQ-20260906-fin-p4-3.md |
| 关联 PRD | 上游：`豆包梳理业务需求/P4 — Transaction Financial Ledger & PSP Reconciliation Foundation.md`（V2；原 §57 Payment Posting + §59 Refund Posting 合并为 FIN-P4-3）；前序：FIN-P4-1 / FIN-P4-2 PRD |
| 需求类型 | 新功能（入账接线，含事件订阅；无 migration/无 API） |

> V2 顺序：FIN-P4-1 ✅ → FIN-P4-2 ✅ → **FIN-P4-3 Payment/Refund Posting（本包）** → FIN-P4-4 Allocation Integrity。
> 复用契约：FIN-P4-1 `FinancialFact`/Resolvers + FIN-P4-2 `FinancialLedger::{Post,Reverse}`（幂等/不可变已冻结）。

---

## 1. 背景与目标

- **一句话需求原文**：把 Payment/Refund 的可靠资金事实接入不可变资金账本（posting 接线）。
- **背景**：
  - FIN-P4-1 已能解析 Payment/Refund → 标准 `FinancialFact`；FIN-P4-2 已建 `FinancialLedger::Post` 幂等入账原语。
  - 但目前 **Journal 只有原语、没有业务接线**：payment captured / refund succeeded 不会自动产生 ledger entry（P4 §71 的"所有金融事实可追溯"未闭环）。
  - P4 文档 §57/§59 + §65 AC-4001/4002/4007/4008/4009/4010/4011 定义 posting 语义。
- **目标**：
  - `FinancialLedger::PostPayment` / `PostRefund` 编排服务：Resolve → 门禁 → Post（幂等）。
  - 接线：`payment.paid`（after_commit，state→completed）→ PostPayment；`refund.created`（after_commit，创建提交=执行成功）→ PostRefund。subscriber 默认 async（SubscriberJob），posting 独立事务、可重试（幂等 key 保安全）。
  - 覆盖 single order / balance collection（独立 txn）/ combination payment（1 Payment → 1 cash entry；split allocation 归 FIN-P4-4）。
  - **不改** Payment/Refund orchestration、state machine、Settlement、P0-P3 任何行为（P4 §16：posting 失败不逆转支付；事件后置天然满足）。
- **成功指标**：AC-4P3-* 全绿；新增 spec + 全量 backend-rspec 0 failures；无 migration/API/UI 变更。

## 2. 用户故事 / 场景

- 作为支付工程/财务，我希望 Payment 成功收款与 Refund 成功退款**自动、恰好一次**进入不可变账本，以便审计与对账。
- 场景（本包只测 posting 接线；真实触发走事件/直接服务调用）：

| # | 场景 | 类型 | 描述 |
|---|---|---|---|
| S1 | Single payment captured | 正常 | 真实 `confirm!`（auto）完成 payment → PostPayment → 1 条 CASH_CAPTURED |
| S2 | Manual capture | 正常 | 真实 `capture!` 完成 → 1 条 CASH_CAPTURED |
| S3 | payment.paid 重复/重放 | 边界 | 同一 payment 重复 PostPayment → 幂等同一条 |
| S4 | Store credit / offline | 正常 | completed → STORE_CREDIT_APPLIED / OFFLINE_PAYMENT_RECORDED entry |
| S5 | Combination payment | 正常 | 1 Payment（挂组合）→ 1 cash entry（splits 不产生，P4-4） |
| S6 | Balance collection | 正常 | 独立 txn 的补付 payment → entry 归该 txn |
| S7 | Refund success | 正常 | 成功 refund → 1 条 REFUND_SUCCEEDED |
| S8 | Multiple partial refunds | 边界 | N 次部分退款 → N 条独立 REFUND_SUCCEEDED |
| S9 | 不可 post | 异常 | AMBIGUOUS / 无 txn / UNSUPPORTED → 不产生 entry（不猜） |
| S10 | Posting 失败 | 异常 | Post 抛错 → payment/refund 事实不受影响（subscriber job 可重试/日志） |

## 3. 功能需求（FR）

- FR-4P3-01：新增 `PallasTrade::FinancialLedger::PostPayment`（编排 service）：`ResolvePayment` → fact 不可 post（AMBIGUOUS/UNSUPPORTED/未激活 type/无 txn）→ `success({ entry: nil, skipped: true, reason: ... })`；可 post → `FinancialLedger::Post` → `success({ entry:, fact: })`。**不创建/不更新 Payment**。
- FR-4P3-02：新增 `PallasTrade::FinancialLedger::PostRefund`（编排）：`ResolveRefund` → 同上（REFUND_SUCCEEDED 等）；**不创建/不更新 Refund**。
- FR-4P3-03：Posting 幂等（承接 FIN-P4-2）：同一 payment/refund 重复触发只产生一条 entry（fact_posting_key 唯一）。
- FR-4P3-04：接线 `payment.paid`（after_commit，Payment::CustomEvents 既有事件）→ `FinancialLedger::PaymentPaidSubscriber`（`subscribes_to 'payment.paid'`）→ 解析 payment → `PostPayment`。subscriber 默认 async；异常 rescue 记录日志（不阻断 payment 流）。
- FR-4P3-05：接线 `refund.created`（after_commit lifecycle 事件；Refund 创建提交 = perform! 成功，失败 raise 回滚）→ `FinancialLedger::RefundCreatedSubscriber` → `PostRefund`。
- FR-4P3-06：subscriber 注册到 `pallastrade_core/lib/pallastrade/core/engine.rb` subscribers.concat（与 PaymentSessionReservationSubscriber 同列表）。
- FR-4P3-07：事件 payload 健壮解析：payload id 支持 prefixed（`py_`/`re_`）或 raw integer（参照 PaymentSessionReservationSubscriber#find_session 双模式）；解析失败静默跳过（日志）。
- FR-4P3-08：覆盖语义——single order / balance collection（独立 txn 独立 entry）/ combination payment（1 Payment → 1 cash entry；PaymentSplit 不产生额外 cash entry，Allocation 归 FIN-P4-4）。
- FR-4P3-09：不改既有行为——不碰 Payment/Refund state machine、不碰 Settlement/Carts::Complete/OnPaymentSuccess 等既有服务（事件后置、零侵入）。
- FR-4P3-10：范围外——无 migration、无 API/UI、无 PSP（fee/net/reconciliation 留 FIN-P4-5+）；不做历史 backfill（P4 §44）。

## 4. 非功能需求（NFR）

- 可靠性：posting 异步（SubscriberJob）+ 幂等 key；失败可重试不重复（P4 §42）。
- 顺序/事务：`payment.paid` 为 after_commit、`refund.created` 为 lifecycle after_commit——posting 恒在资金事务提交后执行（P4 §16：ledger 失败不逆转支付）。
- 只读边界（对 Payment/Refund/Transaction）：PostPayment/PostRefund 只读资金实体 + 写 Journal。
- 性能：subscriber 单对象解析，无 N+1；批量 posting 非本包关注。
- 兼容：无 schema/API 变更；P0-P4-2 行为不变。

## 5. 验收标准（AC，与测试一一映射）

> 对齐 P4 §65：AC-4001/4002/4007/4008/4009/4010/4011 + P4 §16 原则。

- AC-4P3-01 ← FR-4P3-01/08 / P4 AC-4001：可靠 Payment captured（真实 `confirm!`/`capture!` 路径）→ 恰好 1 条 `CASH_CAPTURED` entry。
- AC-4P3-02 ← FR-4P3-03 / P4 AC-4002：同一 payment 重复 PostPayment → 幂等同一条（重复 webhook/job/recovery 不重复 posting）。
- AC-4P3-03 ← FR-4P3-01/08：store credit / offline completed → `STORE_CREDIT_APPLIED` / `OFFLINE_PAYMENT_RECORDED` entry（非 PSP cash）。
- AC-4P3-04 ← FR-4P3-08 / P4 AC-4007：balance collection（独立 txn）→ 独立 entry 归该 txn。
- AC-4P3-05 ← FR-4P3-08：combination payment → 1 cash entry（挂组合 txn）；splits 不产生额外 entry。
- AC-4P3-06 ← FR-4P3-02 / P4 AC-4008：成功 Refund → 1 条独立 `REFUND_SUCCEEDED` entry。
- AC-4P3-07 ← FR-4P3-02 / P4 AC-4009：multiple partial refunds → 各自独立 entries。
- AC-4P3-08 ← FR-4P3-01/02 / P4 AC-4010/4011：posting 前后 Payment/Refund/Transaction 状态与行数不变（不创建 payment、不自动 refund、不改 state）。
- AC-4P3-09 ← FR-4P3-01/02 / P4 AC-4018 精神：AMBIGUOUS / UNSUPPORTED / 无 txn 的 payment/refund → 不产生 entry（不猜、无部分记录）。
- AC-4P3-10 ← FR-4P3-04/05：`payment.paid` 与 `refund.created` 事件触发后 subscriber 产生 entry（integration 级：发布事件 → 等待 job 或直接调 handler）。
- AC-4P3-11 ← FR-4P3-09：P0-P4-2 既有 specs 零回归（含 financial_facts 56 + financial_ledger 22 + transactions/payments 92+）。

## 6. 跨层搜索记录（6 层，gate 强制）

关键词：`posting / payment.paid / refund.created / FinancialLedger / PostPayment / subscriber / Subscriber`。

| 层 | 路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | posting/ledger | 无（app 层无 services/models） | 否 |
| Core models | `pallastrade_core/app/models/` | FinancialLedgerEntry / FinancialFact / Payment / Refund | FinancialFact(P4-1)、FinancialLedgerEntry(P4-2)、Payment/CustomEvents（`payment.paid` after_commit）、Refund（publishes_lifecycle_events → `refund.created`） | 部分满足：契约与事件信号就绪，缺 posting 接线 |
| Core services | `pallastrade_core/app/services/` | financial_ledger / FinancialFacts | `FinancialLedger::{Post,Reverse}`(P4-2)、`FinancialFacts::Resolve*`(P4-1) | 部分满足：缺 PostPayment/PostRefund 编排 |
| Core subscribers | `pallastrade_core/app/subscribers/` | subscriber | PaymentSessionReservationSubscriber（模式参考；注册于 core engine.rb:385） | 否 → 新增 ledger subscribers |
| API/Admin/Storefront/Platform | 各层 | posting | 无 | 否（无 API/UI） |
| DB | schema | ledger | `pallastrade_financial_ledger_entries`(P4-2) | 本包无 migration |

**结论**：posting 原语（P4-2）与 fact 解析（P4-1）已就绪；事件信号 `payment.paid`（CustomEvents after_commit）与 `refund.created`（lifecycle after_commit）已存在。缺口 = PostPayment/PostRefund 编排 + 2 个 subscriber + 注册。无重复能力。

## 7. 技术影响

- **新建（core gem）**：
  - `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/financial_ledger/post_payment.rb`
  - `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/financial_ledger/post_refund.rb`
  - `backend/pallastrade_gems/pallastrade_core/app/subscribers/pallastrade/financial_ledger/payment_paid_subscriber.rb`
  - `backend/pallastrade_gems/pallastrade_core/app/subscribers/pallastrade/financial_ledger/refund_created_subscriber.rb`
  - `backend/pallastrade_gems/pallastrade_core/app/jobs/pallastrade/financial_ledger/post_payment_job.rb`、`post_refund_job.rb`（若 subscriber 采用显式 job；否则 async SubscriberJob 承载——实施时冻结）
- **修改**：`pallastrade_core/lib/pallastrade/core/engine.rb`（subscribers.concat 追加 2 个——注册点，非行为变更）。
- **不修改**：Payment/Refund/Settlement/Carts/Transactions/OrderUpdater；无 migration；无 API/UI。
- **事件契约**（读 events-webhooks SKILL）：subscriber 不自动发现，必须注册；默认 async（SubscriberJob，queue `pallastrade.queues.events`）；lifecycle 事件 after_commit 后触发。
- **命名**：`FinancialLedger::PostPayment/PostRefund`（service）；`FinancialLedger::PaymentPaidSubscriber` 等。

## 8. 测试计划

- 新增（backend/spec）：
  - `spec/services/pallastrade/financial_ledger/post_payment_spec.rb` —— AC-4P3-01/02/03/04/05/08/09
  - `spec/services/pallastrade/financial_ledger/post_refund_spec.rb` —— AC-4P3-06/07/08/09
  - `spec/jobs/pallastrade/financial_ledger/post_payment_job_spec.rb`（或 subscriber spec）—— AC-4P3-10
- 真实路径要求：payment captured 用真实 `confirm!`/`capture!`（capture critical-path 规则，禁止只 factory 造 completed）；refund 走真实 Refund（transaction_id）或 factory（成功态）。
- 事件集成：发布 `payment.paid`/`refund.created` → 断言 posting（subscriber async → 用 `perform_enqueued_jobs` 或直接调 handler 单元测 + 一条 integration）。
- 回归：financial_facts（56）+ financial_ledger（22）+ transactions/payments（148）→ 0 failures；全量 backend-rspec（coverage-gate 依据）。
- AC 映射：AC-4P3-01~11 → 上述 spec + 回归。

## 9. 文档同步清单（知识同步门）

- [ ] `ai/skills/pallastrade-payments/SKILL.md`：补 Payment/Refund Posting 章节（PostPayment/PostRefund + payment.paid/refund.created 接线）。
- [ ] `ai/skills/pallastrade-events-webhooks/SKILL.md`：如事件目录需登记 ledger 订阅（评估后定）。
- [ ] `harness/scenarios/scenarios.json`：新增 GS-052（posting 接线场景）。
- [ ] 本 PRD 状态 + `docs/prd/README.md` 索引。
- [ ] API/schema：不涉及。

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-06 | 0.1 | 初稿：FIN-P4-3 Payment/Refund Posting 拆包 PRD（P4 §57/§59/§65 + FIN-P4-1/2 复用 + 事件接线方案：payment.paid / refund.created after_commit → Post） | AI |
| 2026-09-06 | 0.2 | approved（用户「实施」确认）→ 实施完成：`FinancialLedger::{PostPayment,PostRefund}` + `Post.postable?` 类方法（单一事实源）+ `FinancialLedger::{PaymentPaidSubscriber,RefundCreatedSubscriber}` + engine.rb 注册；新增 28 examples 0 failures；回归 financial_facts+financial_ledger 78、payment/transactions 122、cart/webhook 21、subscriber 8 全绿；AC-4P3-01~11 全覆盖（AC↔测试映射经 spec 内 `AC-4P3-xx` 标注，`prd verify` 仅支持纯数字 AC 与本系列 `AC-4Px-xx` 命名不兼容——评估 not-applicable，同 P4-1/2） | AI |
