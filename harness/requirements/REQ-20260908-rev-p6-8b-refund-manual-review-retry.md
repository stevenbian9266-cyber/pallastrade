# REQ-20260908-rev-p6-8b-refund-manual-review-retry

> PRD: docs/prd/payments/PRD-20260908-payments-rev-p6-8b-refund-manual-review-retry-人工裁决与确定性重试-危险操作.md
> Task: TASK-20260908092403-d808a6d7; Gate: GATE-2026-09-08T09-24-13（feature）
> 源: 豆包…/P6 §63（Manual Retry Query / Manual Review）+ §47 Recovery Matrix + §49（同 key 确定性解决）+
> §10（AMBIGUOUS/MANUAL_REVIEW）+ REV-INV-04。边界: 孤儿退款配对 / retry 全自动 / ReverseCommerce::Recover
> 跨域 → REV-P6-8c。

## 跨层搜索（节选）
- App: 无 host override → 无涉。
- Core: `Refund#retry_execution` 已预留（failed/ambiguous→processing，注释「人工裁决后回退执行」）；
  `Execute` claim 对 `processing` 以**同一 provider_idempotency_key** 重跑（Stripe 去重返回真实结果）= 确定性
  resolve 原语；`Recover` 对 ambiguous/failed/manual_review 只计数+warn 交人工；`Audit.record` 存在。
  **缺口**: manual_review→processing 迁移 + 人工服务 + 审计。
- Admin: `RefundsOpsController`（8a）可加 member action；模板 = `TransactionsController#recover`
  （member POST + 授权 + flash）；Show 页按钮区 8a 已有 page_actions。
- API/Storefront/Platform: 无涉（8a 已定不加 API）。
- Skill: pallastrade-payments（REV-P6-1~8a 节）、pallastrade-admin、pallastrade-api-v3、
  pallastrade-customization、harness-prd、pallastrade-testing（已读）。

## Skill 咨询证据表
| Skill | 结论（真实） |
|---|---|
| pallastrade-payments | Execute 同键重跑/Recover 语义/AP-010/状态机预留已核实（§339-470 节）；本包加人工触发入口，资金仍只走 ExecuteJob |
| pallastrade-admin | TransactionsController#recover 为 member-action 模板；RefundsOpsController/8a 页面可加 page_action 按钮（danger + turbo_confirm） |
| pallastrade-api-v3 | 不加 API（Rails Admin 直接 POST member） |
| pallastrade-customization | 操作层放 Admin gem 直接扩展（PALLAS-CUSTOM）；服务放 core refunds 域 |
| harness-prd | prd new（已建 payments 分类骨架，无查重命中）→ 模板扩充 → 用户确认 → gate |
| pallastrade-testing | service spec（enqueue 断言而非 stub call）+ admin 请求 spec（transactions_spec 模板） |

## 需求
1. `Refund#retry_execution` 扩展 `manual_review → processing`（failed/ambiguous 已有）。
2. 新 `Refunds::ManualRetry.call(refund:, actor:)`：with_lock；仅 failed/ambiguous/manual_review 且
   provider_idempotency_key 存在 → `retry_execution!` + attempt_count+1 → enqueue `Refunds::ExecuteJob(refund.id)`
   → `Audit.record(actor, 'refund_manual_retry', refund, after)`。其余态/key 缺失 → failure 零副作用。
   绝不同步 Execute（AP-010）。并发双点由 with_lock 状态守卫挡（processing 非 eligible）。
3. 新 `Refunds::MarkManualReview.call(refund:, actor:)`：仅 processing/ambiguous → `enter_manual_review!`
   (code:'OPERATOR_REVIEW') + Audit('refund_mark_review')；其余 failure。
4. Admin：`RefundsOpsController#retry` / `#mark_review`（POST member，authorize manage/update Refund，
   turbo_confirm 强确认 + flash）；Show 页按钮按 eligible+权限显隐；i18n 双语。
无 migration；无 API/Storefront/Platform；无新导航项。

## 验证
manual_retry_spec（AC-R68B-01~04）+ mark_manual_review_spec（AC-R68B-05）+ refunds_ops_actions 请求 spec
（AC-R68B-06/07）→ 全量 backend-rspec ×2 + quick check + nav:validate + doc-impact。对应 PRD AC-R68B-01~08。
