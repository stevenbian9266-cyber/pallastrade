# FIN-P4-8：Repair / Legacy / Operations —— Journal repair + Reconciliation ops + Legacy 处置（P4 拆包第 8 包 / 收官）

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-06 |
| 来源 | 用户「实施 FIN-P4-8」→ P4 V2 拆包第 8 包（收官）；前序 FIN-P4-1~7 均 done |
| 分类 | payments |
| 关联 Skill | `ai/skills/pallastrade-payments/SKILL.md`、`ai/skills/pallastrade-testing/SKILL.md`、`ai/skills/pallastrade-deployment/SKILL.md`（job 调度） |
| 关联 REQ | REQ-20260906-fin-p4-8.md（实施时回填） |
| 关联 PRD | 上游：`豆包梳理业务需求/P4 — ...md`（V2；§64 FIN-P4-8 + §44/§46/§49-53/§66 AC-4025/§67 INV-08/09/12）；前序 FIN-P4-1~7 |
| 需求类型 | 新功能（core 只读/幂等 ops 原语 + job + rake + runbook；**无 migration/schema/API**——legacy 处置沿用既有 journal/UNSUPPORTED 语义） |

> V2 顺序：FIN-P4-1 ✅ → … → FIN-P4-7 ✅ → **FIN-P4-8 Repair / Legacy / Operations（本包，收官）**。
> 复用：FIN-P4-2/3/4 posting 原语（Post/PostPayment/PostRefund/PostAllocation 幂等 = repair 引擎）+ FIN-P4-6/7 reconciliation（SourceResult/TransactionResult/ReconcilePayment/Refund/Transaction）+ `CommerceTransaction.needs_attention` + RecoverSweeperJob 保守自动先例。

---

## 1. 背景与目标

- **一句话需求原文**：实现 P4 收官 ops 层（§64）——Journal repair（§49）/ Reconciliation retry（§44）/ Sweeper（自动可见性）/ Manual reconcile / Controlled backfill（§50 三类）/ Legacy unsupported 处置（§41/§50 legacy_unverified）/ Metrics-Runbook（§53）。
- **背景**：FIN-P4-1~7 已落地解析→Journal→Posting→Allocation→Provider facts→Source/Transaction reconciliation（全部 transient、只读、幂等）。缺**运维闭环**：Journal 缺失时谁补（repair）、reconciliation 谁周期性重跑（sweeper/retry）、历史缺 journal 如何受控回填（backfill 三类）、人工如何介入（manual/rake/runbook）、legacy 无法证明数据如何处置（不猜）。
- **目标**：core 新增**只读/幂等、绝不重新 Payment/Refund/倒退 state** 的 ops 原语：`RepairTransaction`（journal 幂等补记，§49）、reconciliation retry/manual/backfill 的 rake + 分类逻辑、保守 `ReconcileSweeperJob`（sidekiq-cron 周期重跑 + 结构化 metrics 日志，参考 RecoverSweeperJob）；backfill 三类语义（§50 PROVABLE/PARTIALLY_PROVABLE/UNPROVABLE——UNPROVABLE 绝不猜）；`docs/operations/financial-reconciliation-runbook.md`。
- **成功指标**：AC-4P8-* 全绿；新增 spec + 全量 backend-rspec 0 failures；无 migration/schema/API。

## 2. 用户故事 / 场景

| # | 场景 | 类型 | 描述 |
|---|---|---|---|
| S1 | Journal 缺失 repair | 修复 | captured payment / succeeded refund / settled combination 缺 journal entry → `RepairTransaction` 幂等补记（不重 Payment/Refund） |
| S2 | Repair 幂等 | 边界 | 重复 repair → 不重复 entry（Post idempotency key 兜底） |
| S3 | Reconciliation retry | 运维 | 手动重跑单个 txn 的 ReconcileTransaction（只读、幂等） |
| S4 | Sweeper 自动可见性 | 运维 | 周期对 completed/payment_confirmed/finalizing txn 重跑 reconcile，输出结构化 metrics（matched/mismatch/needs_attention/…），journal-missing 自动 enqueue repair（幂等安全）；provider 冲突/needs_attention 只计数告警不自动动资金（§44/§46） |
| S5 | Backfill PROVABLE | 修复 | captured payment + provider reference + 证据 + currency → 可安全补 journal |
| S6 | Backfill PARTIALLY_PROVABLE | 边界 | 缺 provider settlement 信息 → 只补本地 journal，reconcile 如实 PENDING/UNSUPPORTED |
| S7 | Backfill UNPROVABLE / legacy | 异常 | 无法证明 captured/ownership/currency → 不猜（保留 legacy，不写半套事实） |
| S8 | Manual / runbook | 运维 | rake `pallastrade:reconciliations:{repair,reconcile,list_needs_attention,backfill}` + runbook 操作手册 |
| S9 | 只读/幂等边界 | 边界 | 全链路绝不自动 charge/refund、绝不倒退 transaction state、绝不新 Payment/Refund（INV-08/09/12） |

## 3. 功能需求（FR）

- FR-4P8-01：新增 `PallasTrade::FinancialLedger::RepairTransaction.call(transaction:)`（journal repair 原语，§49）：
  - **范围**：transaction 可达的 captured payments / succeeded refunds（transaction_id present）/ settled combination splits，缺对应 active Journal entry（CASH_CAPTURED/REFUND_SUCCEEDED/ORDER_ALLOCATION）时**幂等补记**——委托既有 `PostPayment`/`PostRefund`/`PostAllocation`（复用 FIN-P4-2 idempotency key / FIN-P4-3/4 编排；内部再走 Fact Resolve→门禁→Post）。
  - **绝不**：重新 Payment / 重新 Refund / 修改任何 state machine / 自动 charge（§44/§49/INV-08/09）。
  - 缺失判定与 FIN-P4-7 一致（journal missing 检测语义复用：captured payment 无 CASH_CAPTURED entry 等）。
  - 输出 `success({ repaired: [entry...], already_present: [source...], skipped: [{source, reason}] })`；全幂等可重跑。
- FR-4P8-02：`rake pallastrade:reconciliations:*` 运维工具（core gem `lib/tasks/reconciliations.rake`，镜像 `transactions.rake`）：
  - `list_needs_attention`：transaction 状态级 needs_attention（复用 `CommerceTransaction.needs_attention`）概述。
  - `repair[txn_xxx]`：调用 `RepairTransaction`（manual repair tooling）。
  - `reconcile[txn_xxx]`：调用 `ReconcileTransaction` 打印 status/reasons/summary（manual retry）。
  - `backfill[store_id?]`：受控回填（见 FR-4P8-04）。
- FR-4P8-03：新增 `PallasTrade::Reconciliations::ReconcileSweeperJob`（sidekiq-cron 周期，`PallasTrade::BaseJob` 子类）——**保守自动**（参考 RecoverSweeperJob 设计决策）：
  - 扫描 store 的 completed / payment_confirmed / finalizing（有 reconciliation 价值）transaction：
    - 逐个 `ReconcileTransaction`（只读、幂等）→ 收集 status 分布；
    - **journal-missing（JOURNAL_POSTING_MISSING）→ enqueue `RepairTransactionJob`（幂等补记，自动安全，§44「repair missing Journal projection」允许）**；
    - mismatch / needs_attention / provider 冲突 → **不自动动资金**，仅计数 + warn 日志（人工/runbook 介入，§44/§46）；
  - 输出结构化 `{ event: 'reconciliations.sweeper', ... counts, threshold }` metrics 日志；重复调度安全（幂等）。
  - 注册 sidekiq-cron schedule（host `config/sidekiq_schedule.rb` 追加；按 RecoverSweeperJob 先例）。
- FR-4P8-04：**受控 backfill 三类语义**（§50/AC-4025），rake `backfill` 内部按三类路由：
  - PROVABLE（payment/refund/split + provider reference + capture evidence + currency 可证明）→ `RepairTransaction` 幂等补 journal；
  - PARTIALLY_PROVABLE（缺 provider settlement 信息）→ 只补本地 Journal；reconcile 状态如实 PENDING/UNSUPPORTED（不猜 settled）；
  - UNPROVABLE（无法证明 captured/ownership/currency）→ **不写 journal、不猜**，报告 legacy 计数并跳过（保留 legacy，`legacy_unverified` 概念记录于 runbook/输出，不落半套事实）。
  - 输出每类处理计数 + skipped reasons。
- FR-4P8-05：范围外（不实施，记入 PRD 供后续）——Admin Financial View UI 面板（§51 完整 UI/字段卡）、Financial Timeline 展示（§52）、`finance.*` audit 事件目录全量（§53 建议集）；本包聚焦 core ops 原语 + 日志/runbook（sweeper 已输出 metrics 日志；admin/UI/audit 目录留 P4 之后 UI/ops 演进）。无 migration/schema/API。

## 4. 非功能需求（NFR）

- 只读/幂等：Repair/Sweeper/Backfill 全部幂等可重跑；绝不自动 charge/refund/倒退 state（§44/INV-08/09）。
- 保守自动（Sweeper）：只对「明确可安全补记的 journal missing」自动；mismatch/needs_attention/provider 冲突一律人工（§46 严重冲突 manual_review 不自动倒退）。
- 失败语义：repair/reconcile 失败逐源记录 skipped（不 raise 中断整批；runbook 可重跑）。
- 兼容：无 schema/API；P0~P4-7 行为不变；Journal/Payment/Refund/Transaction state machine 全不动。
- 确定性：Bogus provider 替身确定性；Stripe stub 测试（沿 P4-5~7 模式）。
- 调度：sidekiq-cron 注册沿用 RecoverSweeperJob 先例；无调度环境测试直接驱动 job。

## 5. 验收标准（AC，与测试一一映射）

> 对齐 P4 §64/§44/§46/§49-50/§66 AC-4025/§67 INV-08/09/12。

- AC-4P8-01 ← FR-4P8-01 / §49：captured payment 缺 CASH_CAPTURED entry → `RepairTransaction` 幂等补记一条；**不新建 Payment、不改 payment state、不 charge**。
- AC-4P8-02 ← FR-4P8-01：succeeded refund（transaction_id）缺 REFUND_SUCCEEDED entry → 补记；settled combination split 缺 ORDER_ALLOCATION → 补记（复用 PostAllocation）。
- AC-4P8-03 ← FR-4P8-01：重复 repair / 已存在 entry → 幂等不重复（entry count 不变）；不可证明源 → skipped 不猜。
- AC-4P8-04 ← FR-4P8-02/03：`reconcile[txn]` rake 输出 status/reasons（手动 retry）；`repair[txn]` 输出补记计数。
- AC-4P8-05 ← FR-4P8-03：Sweeper 对 journal-missing txn 自动 enqueue repair（幂等安全）；对 mismatch/needs_attention 仅计数 + warn 日志、**不自动动资金**（§44/§46）。
- AC-4P8-06 ← FR-4P8-03：Sweeper 结构化 metrics 日志含 status 分布与 store 维度；重复运行无重复副作用。
- AC-4P8-07 ← FR-4P8-04 / §50：PROVABLE → 补 journal；PARTIALLY_PROVABLE → 只补本地 + reconcile PENDING/UNSUPPORTED 如实；UNPROVABLE → 不写 journal 不猜（legacy 保留，AC-4025）。
- AC-4P8-08 ← FR-4P8-01~04 / INV-08/09/12：全链路只读/幂等边界——零自动 charge/refund/倒退 transaction state、零新 Payment/Refund 创建（repair 唯一写 = Journal entry）。
- AC-4P8-09 ← FR-4P8-02：rake task 存在且用法输出正确（`list_needs_attention`/`repair`/`reconcile`/`backfill`）。
- AC-4P8-10 ← FR-4P8-05：范围外确认——无 migration/schema/API；admin UI/timeline/audit 目录不在本包。
- AC-4P8-11 ← FR-4P8-01~04：回归零破坏——P4-1~7 + P0-P3 + stripe gem specs 全绿。

## 6. 跨层搜索记录（6 层，gate 强制）

关键词：`repair / journal repair / reconcile retry / sweeper / backfill / legacy_unverified / manual reconcile / runbook`。

| 层 | 路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | repair/sweeper/backfill | 无 | 否 |
| Core | `pallastrade_core/app/` | repair/reconcile | `FinancialLedger::{Post,PostPayment,PostRefund,PostAllocation,AllocationIntegrity}`（幂等 posting 引擎）；`Reconciliations::{ReconcileTransaction,SourceResult,...}`（P4-6/7）；`Transactions::{RecoverSweeperJob,RecoverJob}`（保守自动先例）；`CommerceTransaction.needs_attention`；`Audit.record` | 部分：posting/reconcile/保守 sweeper 先例就绪；缺 RepairTransaction 原语 + ReconcileSweeperJob + backfill rake |
| API gem | `pallastrade_api/app/` | repair/reconcile | 无 | 否（本包无 API） |
| Admin gem | `pallastrade_admin/app/` | transactions | `TransactionsController`（recover/index/show + trace）；views show.html.erb（inventory panel 先例） | 否（本包不做 admin UI，P4-8 范围外） |
| DB schema | schema | repair 表 | 无（修复走既有 immutable journal；legacy 不落半套事实） | 本包无 migration |
| Storefront | `storefront/src/` | repair/reconcile | 无 | 否 |
| Platform | `platform/packages/` | repair/reconcile | 无 | 否 |

**结论**：Posting 幂等原语 + reconciliation 只读服务 + RecoverSweeperJob 保守自动先例 + rake/manual tooling 先例（transactions.rake）全部就绪；缺口 = `FinancialLedger::RepairTransaction`、`Reconciliations::ReconcileSweeperJob`（+RepairTransactionJob）、`reconciliations.rake`（repair/reconcile/backfill 三类）、runbook。无重复能力、无 migration。

## 7. 技术影响

- **修改（core gem）**：
  - `lib/pallastrade/core/engine.rb`（如需要）：无新增 subscriber（repair 是 ops 手动/调度触发，非事件订阅）。
- **新建（core gem）**：
  - `app/services/pallastrade/financial_ledger/repair_transaction.rb`
  - `app/jobs/pallastrade/reconciliations/reconcile_sweeper_job.rb`
  - `app/jobs/pallastrade/reconciliations/repair_transaction_job.rb`
  - `lib/tasks/reconciliations.rake`
- **修改（host backend，如适用）**：`config/sidekiq_schedule.rb` 追加 ReconcileSweeperJob 调度（沿 RecoverSweeper 先例；若 schedule 表只含 cart job 则评估是否 host 或 engine 注册）。
- **新建（docs）**：`docs/operations/financial-reconciliation-runbook.md`（manual/repair/backfill/sweeper 操作手册）。
- **不修改**：Payment/Refund/Transaction state machine、Journal/Post/Reverse、P4-6/7 reconcile 服务、fetch_* 契约；无 migration/schema；无 API/UI。
- **关键设计决策（实施冻结）**：repair 唯一写 = Journal（经既有幂等 Post 原语），绝不新 Payment/Refund；journal missing 自动 repair 是安全的（幂等 + §44 允许），mismatch/needs_attention 不自动（§46 人工）；backfill UNPROVABLE 不写不猜（AC-4025）；sweeper 幂等可重跑（重复调度安全）；legacy 概念记录于 runbook/输出不落半套事实。

## 8. 测试计划

- 新增（backend/spec）：
  - `spec/services/pallastrade/financial_ledger/repair_transaction_spec.rb` —— AC-4P8-01/02/03/08（bogus captured + refund + combination fixture；幂等）
  - `spec/jobs/pallastrade/reconciliations/reconcile_sweeper_job_spec.rb` —— AC-4P8-05/06/08（journal missing → enqueue repair；mismatch → 仅日志；store 维度 metrics）
  - `spec/jobs/pallastrade/reconciliations/repair_transaction_job_spec.rb` —— AC-4P8-01/03（job 驱动 RepairTransaction）
  - `spec/lib/tasks/reconciliations_rake_spec.rb`（如项目有 rake spec 先例；否则经 task 调用 smoke）—— AC-4P8-04/09
- 真实路径：bogus captured payment（completed+event+session）无 journal → repair 补 CASH_CAPTURED；refund transaction_id 有 → 补 REFUND_SUCCEEDED；组合 settled splits 缺 ORDER_ALLOCATION → 补；重复跑幂等；backfill 三类 fixture（PROVABLE/缺 provider/PARTIALLY/UNPROVABLE）。
- 回归：P4-1~7 specs（financial_facts/financial_ledger/reconciliations/payments/transactions/jobs）+ stripe gem specs + P0-P3 → 0 failures；全量 backend-rspec（coverage-gate）。
- AC 映射：AC-4P8-01~11 → 上述 spec + 回归（spec 内 `AC-4P8-xx` 标注）。

## 9. 文档同步清单（知识同步门）

- [ ] `ai/skills/pallastrade-payments/SKILL.md`：补 Repair/Legacy/Operations 章节（RepairTransaction + ReconcileSweeperJob + backfill 三类 + 保守自动语义）。
- [ ] `ai/skills/pallastrade-deployment/SKILL.md`（如涉 sidekiq-cron 调度注册说明）。
- [ ] `harness/scenarios/scenarios.json`：新增 GS-057（repair/ops 场景）。
- [ ] `docs/operations/financial-reconciliation-runbook.md`（新 runbook）。
- [ ] 本 PRD 状态 + `docs/prd/README.md` 索引。
- [ ] API/schema：不涉及。

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-06 | 0.1 | 初稿：FIN-P4-8 Repair/Legacy/Operations 收官 PRD（P4 §64/§44/§46/§49-50/AC-4025/INV-08/09/12 + P4-2~7 幂等 posting/reconcile/保守 sweeper 复用；RepairTransaction + ReconcileSweeperJob + backfill 三类 rake + runbook；无 migration，admin UI/timeline/audit 目录范围外） | AI |
| 2026-09-06 | 0.2 | 实施完成：RepairTransaction/RepairTransactionJob/ReconcileSweeperJob + reconciliations.rake（backfill 三类）+ financial-reconciliation-runbook；新 16 specs + 回归 279 0 failures（全量 EVD-20260906052900-3fa1a181c2）；skills §Repair/Legacy/Operations + scenarios GS-057 同步 | AI |
