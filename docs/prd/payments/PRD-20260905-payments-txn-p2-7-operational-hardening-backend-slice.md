# PRD-20260904-payments-txn-p2-7-operational-hardening-backend-slice

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-05 |
| 来源 | P2 源文档 §58（TXN-P2-7 Operational Hardening）——本轮后端切片；Admin UI/metrics/alerts 为后续（前置：Admin resource 基建/可观测） |
| 分类 | payments（交易运维域） |
| 关联 REQ | REQ-20260905-txn-p2-7.md |
| 需求类型 | 新功能（后端运维强化：读模型/scope/rake/ops runbook；无 API 面） |

## 1. 背景与目标

- **一句话需求原文**：继续 P2 → TXN-P2-7 Operational Hardening 后端切片。
- **背景**：TXN-P2-2..5 已交付 transaction 全生命周期；运维需要：交易 trace（时间戳/尝试/错误聚合）、stuck/needs-attention 可见性（payment_confirmed/finalizing 超龄 + recovery_required/manual_review）、manual recovery tooling（不依赖 Admin UI）、ops runbook。Admin transaction inspection UI、metrics/alerts 需 Admin resource 基建/可观测组件，独立后续。
- **目标**：
  1. `CommerceTransaction.needs_attention` scope + `trace` 读模型（§58 transaction trace / stuck visibility）。
  2. rake `pallastrade:transactions:{list_needs_attention,recover[id]}`（manual recovery tooling，ops 直用）。
  3. `docs/operations/transaction-recovery-runbook.md`（inspection/recover 操作手册）。
- **成功指标**：scope/trace spec 绿；rake 可执行；新增文件 rubocop 0；回归绿。

## 2. 场景

- 运维 A：列出全部需关注交易（recovery_required/manual_review 或 payment_confirmed/finalizing 超 1h）。
- 运维 B：对单笔交易执行 manual recover（rake），输出 action/终态；失败给出 last_error。
- 运维 C：详情 trace 聚合（启动/确认/finalize/完成/恢复时间戳、attempts、last_error、参与者与会话数、快照指纹）。

## 3. FR/AC

### FR-701：needs_attention scope（stuck visibility）
- 语义：state ∈ recovery_required/manual_review（任何时长）∪ state ∈ payment_confirmed/finalizing 且 updated_at 早于阈值（默认 1h，参数 stuck_after）。
- AC-701：recovery_required/manual_review 恒被包含。
- AC-702：payment_confirmed 超龄（updated_at < now-1h）被包含；新鲜（<阈值）不包含。
- AC-703：completed/payment_pending/canceled/created 不含；参数 stuck_after 生效。

### FR-702：trace 读模型
- `transaction.trace` → Hash：state/purpose/amount/currency/snapshot_fingerprint + started_at/payment_confirmed_at/finalizing_at/completed_at/recovery_required_at/manual_review_at/canceled_at + recovery_attempts/last_error_{class,code,message} + participants（role/count/已完成数）+ sessions（count/状态分布）。
- 只读、零副作用。
- AC-711：trace 含时间戳/attempts/error/participant/session 摘要（关键键存在且值正确）。

### FR-703：manual recovery rake（tooling）
- `rake pallastrade:transactions:list_needs_attention`（stdout count + tsv 行）。
- `rake pallastrade:transactions:recover[txn_xxx]` → `Transactions::Recover.call`；成功打印 action+终态；失败打印 error（exit 1）。
- AC-721：recover[id] 对 recovery_required 交易执行并输出终态（rake 内调用 Recover 语义同 P2-4 spec）。

### FR-704：范围边界
- Admin UI/metrics/alerts/自动 sweeper：延后（REQ 记录）；不新增迁移/API/SDK；无状态机改动。

## 4. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-05 | 0.1 | 定稿 approved（用户选 A 推进 P2-7 后端切片） | AI |
| 2026-09-05 | 0.2 | 实施完成：needs_attention scope + trace + rake list/recover + ops runbook；模型 spec 9 examples 0 failures；rake 注册验证；新增文件 rubocop 0 | AI |
