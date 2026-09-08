# REQ-20260908-rev-p6-6-refund-reverse-recovery

> PRD: docs/prd/payments/PRD-20260908-payments-rev-p6-6-refund-reverse-recovery-recover-recoverjob-recovers.md
> Task: TASK-20260908032357-d77e4164; Gate: GATE-2026-09-08T03-24-07（feature，critical）
> 源: 豆包…/P6 §45/§46/§61。边界: ReverseCommerce::Recover 跨域收敛 + reimbursement async 拆链后置 REV-P6-7/8。

## 跨层搜索（节选）
Core 已有 Transactions::RecoverSweeperJob（保守范式）、Refunds::Execute（幂等 claim + attempt_count + provider idempotency key）、Refund 状态机（retry_execution 预留）；无重复 Recover。API/Admin/Storefront/Platform 无涉及。Skill: pallastrade-payments（已读）。

## 需求
1. `Refunds::Recover`：with_lock + 状态守卫；requested stale（>1h）& attempts<5 → 幂等 Execute 重跑；processing stale（>6h）→ record_ambiguous!(RECOVERY_TIMEOUT)（REV-INV-04 不自动重退）；其余（ambiguous/failed/manual_review/fresh/capped）不动。
2. `Refunds::RecoverJob`：per-refund，rescue 不 re-raise。
3. `Refunds::RecoverSweeperJob`：全局/单店保守扫描 + structured metrics + warn（capped/ambiguous/manual 人工接管）。
4. host sidekiq_schedule.rb 注册 refund_recovery_sweeper（*/5，1h/6h）。
无 migration。

## 验证
recover_spec 5 + sweeper_spec 2（7 绿）→ 全量 backend-rspec ×2 + P0-P5 + doc-impact。
