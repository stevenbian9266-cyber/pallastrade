# REQ-20260908-rev-p6-8c-reimbursement-async-chain

> PRD: docs/prd/payments/PRD-20260908-payments-rev-p6-8c-reimbursement-async-chain-durable-requested-executejob.md
> Task: TASK-20260908111613-bb52baf8; Gate: GATE-2026-09-08T11-16-24（feature）
> 源: 豆包…/P6 §16/§46/§48/§57 + REV-P6-2 边界注记。本包=legacy reimbursement 退款链 async 收敛（单包，不做
> 孤儿配对/跨域 Recover/组合取消——后续包）。用户指令「实施 REV-P6-8c」= 明确确认。

## 跨层搜索（节选）
App 无 override。Core 链：Reimbursement#perform! → ReimbursementPerformer → OriginalPayment.reimburse →
ReimbursementHelpers#create_refund = save! + `Refunds::Execute.call(raise_on_failure:true)`（事务内同步，违规残留）。
`Refunds::Request`/`ExecuteJob`（REV-P6-2/4）与 `Refund::CAPACITY_STATES`（capacity 含 requested）已就绪；
split 上限 `amount_within_frozen_split_limit` 以 succeeded 口径 → 需 covering 修正防重复建单。
Admin/API/Storefront/Platform 无涉。Skill: payments（REV-P6-1/2/8a/8b 节）、api-v3、customization、prd、
testing（已读）。

## Skill 咨询证据表
| Skill | 结论 |
|---|---|
| pallastrade-payments | REV-P6-2 边界注记确认本链归属 8；Request/ExecuteJob/covering capacity 语义已核实 |
| pallastrade-api-v3 | 无 API 变更 |
| pallastrade-customization | 资金链改 core gem 直接（PALLAS-CUSTOM）；不用 decorator |
| harness-prd | prd new + REQ 简版（本文件） |
| pallastrade-testing | 更新 original_payment_child_spec + 新增 async spec（perform_enqueued_jobs） |

## 需求
1. `create_refund`（非 simulate）：save!（durable requested）→ enqueue `Refunds::ExecuteJob`（删同步 Execute，
   AP-010）。
2. `Reimbursement` covering 记账：`refund_coverage_amount`（refunds state∈requested/processing/ambiguous/
   succeeded 合计）；`perform!` 用 total − (coverage + credits) 判定 reimbursed/errored（≤容差）；paid_amount
   （succeeded）保留展示。
3. initiation 幂等：create_refunds 先扣已有 covering 合计；split 上限 = captured − refunded − 该 split
   covering 合计。
4. provider 拒绝不再 raise 到 perform（async 后 failed 行 Ops 呈现）；容量不足 → errored+raise（不变）。
无 migration/API/UI。

## 验证
reimbursement_async_spec（AC-R68C-01~04）+ 更新 original_payment_child_spec → 回归 refund/reconcile/
orders-cancel/refunds-ops + quick check + 全量 backend-rspec ×2 + doc-impact。
