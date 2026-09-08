# PRD-20260908-payments-rev-p6-6-refund-reverse-recovery

| 元数据 | 值 |
|---|---|
| 状态 | verifying |
| 创建日期 | 2026-09-08 |
| 来源 | 需求：REV-P6-6 Refund Reverse Recovery（Recover + RecoverJob + RecoverSweeper） |
| 分类 | payments |
| 关联 Skill | pallastrade-payments |
| 关联 REQ | REQ-20260908-rev-p6-6-refund-reverse-recovery.md |
| 关联 PRD | REV-P6-1~5（done，底座） |
| 需求类型 | 优化迭代（资金安全，feature gate） |

> 源：`豆包…/P6` §45/§46/§61。范围边界：本包 = **Refund 恢复引擎**（requested 从未执行/processing 超时/ambiguous 不自动重退）；`ReverseCommerce::Recover`（Restock/journal 跨域收敛）+ reimbursement async 拆链后置 REV-P6-7/8。

## 1. 背景与目标
REV-P6-1 已交付 durable Refund（requested/processing/ambiguous + attempt_count + provider_idempotency_key），但无自动收敛：requested 可能因 Job 丢失永不执行；processing 可能卡死；ambiguous/manual 仅人工。目标：保守自动 sweeper（镜像 `Transactions::RecoverSweeperJob`）周期性收敛，不猜、不重复 PSP。
成功指标：requested stale → bounded 幂等重执行；processing stale → 收敛 ambiguous（REV-INV-04 不自动重退）；ambiguous/manual/failed 仅计数+warn；P0-P5 + 全量绿。

## 2. 场景
- requested 超阈值（1h）未执行且 attempts<5 → 重跑幂等 Execute（稳定 idempotency key，不重复退款）。
- processing 超阈值（6h）无终态 → mark_ambiguous（超时；重试/人工裁决=REV-P6-8 同 key）。
- requested attempts 达上限 / ambiguous / manual_review / failed / fresh → 不动，仅计数+warn。
- 周期调度 */5（sidekiq-cron）；enqueue RecoverJob 幂等。

## 3. FR
- FR-R66-101 `Refunds::Recover`：with_lock+状态守卫；requested stale & attempts<MAX → `Execute.call`（幂等重跑）；processing stale → `record_ambiguous!(RECOVERY_TIMEOUT)`；其余不动。
- FR-R66-102 `Refunds::RecoverJob`：per-refund 委托 Recover；rescue 不 re-raise（sweeper 重扫）。
- FR-R66-103 `Refunds::RecoverSweeperJob`：全局/单店保守扫描（requested stale enqueue、capped 停、processing stale enqueue、ambiguous/manual/failed 计数+warn）；结构化 metrics。
- FR-R66-104 调度：host `sidekiq_schedule.rb` 注册 `refund_recovery_sweeper`（*/5，1h/6h）。

## 4. NFR
无 migration；只读/幂等 enqueue；attempts 封顶（MAX_AUTO_RETRY_ATTEMPTS=5）；不猜（存量/ambiguous 不自动重退）。

## 5. AC
| AC | 条件 | FR |
|---|---|---|
| AC-R66-01 | requested stale & <MAX → Execute 重跑至 succeeded（attempt=1） | 101 |
| AC-R66-02 | requested fresh / capped(≥5) → 不动 | 101 |
| AC-R66-03 | processing stale → ambiguous + RECOVERY_TIMEOUT | 101 |
| AC-R66-04 | ambiguous/failed/manual_review → 不动 | 101 |
| AC-R66-05 | sweeper enqueue 集正确（stale+processing；capped/fresh 不 enqueue）；ambiguous 等仅 warn | 103 |
| AC-R66-06 | P0-P5 + backend-rspec 全量绿 | 全部 |

## 6. 跨层搜索（节选）
Core 已有 `Transactions::RecoverSweeperJob`/`Refunds::Execute`/Refund 状态机（retry_execution 预留）；无重复 Recover。API/Admin/Storefront/Platform 无涉及。

## 7. 技术影响
Core `services/pallastrade/refunds/recover.rb` + `jobs/pallastrade/refunds/{recover_job,recover_sweeper_job}.rb`；host `backend/config/sidekiq_schedule.rb`；specs（recover 5 + sweeper 2）。

## 8. 测试计划
`spec/services/pallastrade/refunds/recover_spec.rb`、`spec/jobs/pallastrade/refunds/recover_sweeper_job_spec.rb`（7 例全绿）；回归 refunds/orders/returns 组 + 全量。

## 9. 文档同步
- [x] PRD/REQ/README/skill（REV-P6-6）/scenarios GS-065/sidekiq_schedule
- [ ] 全量验证 + doc-impact

## 10. 变更记录
| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-08 | 0.1 | 初稿 | AI |
| 2026-09-08 | 0.2 | 实施：三件套 + 调度 + specs 7 绿 | AI |
