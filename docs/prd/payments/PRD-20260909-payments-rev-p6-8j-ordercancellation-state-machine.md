# PRD-20260909-payments-rev-p6-8j-ordercancellation-state-machine-recovery

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-09 |
| 来源 | 需求：REV-P6-8j OrderCancellation 状态机化 + 取消意图恢复（durable intent lifecycle；用户指令实施此前暂缓的第 4 项） |
| 分类 | payments |
| 关联 Skill | pallastrade-payments / pallastrade-admin |
| 关联 REQ | REQ-20260909-rev-p6-8j-ordercancellation-state-machine.md |
| 关联 PRD | REV-P6-4（Orders::Cancel 决策矩阵/REV-P6-0 DB audit 前置）；8e/8i（Reverse Commerce 恢复）；8g（Ops 可见性） |
| 需求类型 | 优化迭代（审计/恢复语义，feature gate） |

> 源：REV-P6 §34（Cancellation Intent 必须 Durable——建议 OrderCancellation 增加
> requested/processing/applied/recovery_required/completed/manual_review；是否加 state 由 REV-P6-0 DB audit
> 决定）+ §35（Order=canceled 与 Refund=processing 合法并存，系统经 Reverse Recovery 收尾）。**本包执行
> REV-P6-0 式 DB audit（见 §6）并按审计结果实施**：给 OrderCancellation 加 `state` 生命周期 + 取消意图
> 恢复审计工具。**不改变资金/取消成功路径行为**（失败仍整体回滚、不留半取消——REV-P6-4 不变式保持）。

## 1. 背景与目标
审计结论：OrderCancellation 为无状态普通行（仅 Orders::Cancel 一处写入，事务内与 cancel! 同原子）；取消意图
已 durable（OC 行 + durable Refund(requested) 同一事务），但无显式生命周期 → Ops 无法按状态分诊；已 applied
的取消若下游 refunds 缺失（如 8f 前的 legacy/异常）无检测入口。目标：
1. **状态机化**：`state ∈ requested/applied/failed/recovery_required/manual_review`；成功取消 → applied；
   迁移回填存量 applied；predicates/scopes/事件守卫。
2. **取消意图恢复审计**：rake 列出 attention（applied 且 refund_payments=true 但 order 无任何 durable 退款行
   ——资金意图未落地；或 state ∈ recovery_required/manual_review），供人工 re-drive（修复后重跑 Orders::Cancel
   幂等）。
成功指标：新取消 OC.state=applied 且存量回填一致；既有取消/退款行为与 spec 全绿（零回归）；rake 审计可用；全量绿。

## 2/3. FR
- FR-R68J-101（DB audit + migration）：`state` string 列（default 'requested'，index），存量行回填
  'applied'（历史 OC 均为已应用取消）。
- FR-R68J-102（状态机）：`OrderCancellation::STATES` + state_machine（initial requested）：
  requested→applied(`apply`)、[requested/applied/recovery_required/manual_review]→failed(`fail`)、
  applied→recovery_required(`flag_recovery_required`)、applied/recovery_required→manual_review
  (`flag_manual_review`)、[recovery_required/manual_review/failed]→applied(`reapply`，人工裁决后重新标记)。
  scopes/predicates + ransack 白名单（state）。
- FR-R68J-103（Orders::Cancel 接线）：捕获 create! 返回值；事务内 order.cancel! 成功后 `apply` →
  state='applied'（与取消同原子）；失败/回滚不变（无行）。
- FR-R68J-104（恢复审计 rake）：`pallastrade:orders:cancellations:list_attention[store_id]`——逐 applied OC
  （refund_payments=true & order canceled）：订单可退源（本地 PSP payments refunds ∪ 组合 splits refunds）
  无任何 durable 退款行 → `ATTENTION_NO_DURABLE_REFUND` 行；state ∈ recovery_required/manual_review →
  独立列出。TSV + summary。只读。
- 边界（记录不实施）：`completed/processing` 态暂不加（apply 即 terminal=applied；refund 行终态由 Refund
  state 各自表达——避免重复聚合）；失败路径语义不变（不留 recovery_required 意图行，保持既有「不留半取消」）；
  Admin UI 展示（后续与 8g/8a Ops 合并）。

## 4. NFR
零资金行为变更（成功路径仅 +state 审计写入；失败回滚语义不变）；migration 幂等回填；rake 只读；
ransack 白名单按模型惯例。

## 5. AC
| AC | 条件 | FR |
|---|---|---|
| AC-R68J-01 | 迁移后 schema 有 pallastrade_order_cancellations.state（default requested + index）；存量行回填 applied | 101 |
| AC-R68J-02 | Orders::Cancel 成功（含 UNPAID/PAID/refund_payments=false/refund_amount）→ OC.state='applied'；状态机谓词/scopes/非法迁移守卫生效 | 102/103 |
| AC-R68J-03 | 既有取消回归全绿：失败回滚不留行（无 state 泄漏）；8f split-aware、8e 域不回归 | 103 |
| AC-R68J-04 | rake list_attention：refund_payments=true 且无可退源 durable refund 行的 applied OC 列出 ATTENTION_NO_DURABLE_REFUND；recovery_required/manual_review 行列出 | 104 |
| AC-R68J-05 | 全量 backend-rspec ×2 + quick check + doc-impact | — |

## 6. REV-P6-0 DB audit 结果（节选，只读证据）
- `pallastrade_order_cancellations` 列：order_id/canceled_by*/reason/note/restock_items/refund_payments/
  refund_amount/notify_customer/metadata/timestamps——**无 state**（schema.rb）。
- 写入方：仅 `Orders::Cancel#call` L57 `order.cancellations.create!(...)`（事务内）；读方：cancellation
  specs、after_cancel 无、admin 无（8g 页未含 OC）。
- Orders::Cancel 流程：OC 行 + update_columns(canceled_at/canceler) + build durable refunds + cancel! → 同事务；
  提交后 ExecuteJob；refund 建单失败 → ActiveRecord::Rollback（不留半取消）。
- 结论：加 state 无并发/历史冲突（存量单写入方已完成取消）；回填 applied 安全。

## 7. 技术影响
core：db/migrate（+state 列/回填/index）、models/order_cancellation.rb（状态机）、services/orders/cancel.rb
（+apply）；lib/tasks/orders_cancellations.rake（新，audit rake）。specs：model 状态机 + cancel state + rake
冒烟。无 v3/UI。

## 8. 测试计划
model spec（迁移守卫/谓词/事件从态）；Orders::Cancel spec 增 state 断言（各分支 success→applied）；rake
list_attention 用 runner/直接方法测试可选；回归 cancellation_orchestration/8f split/8e。全量 ×2 + quick。

## 9. 文档同步清单
- [x] payments skill（8j 节）✅（本提交）；scenarios GS-077 ✅（本提交）；PRD/REQ/README ✅；runbook：审计 rake 记录于 payments skill（无独立 runbook 改动，恢复仍走 8e/8i runbook 入口）✅；doc-impact ✅。
- [ ] 边界：completed/processing 态、Admin UI、失败持久 recovery 意图 → 后续。

## 10. 变更记录
| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-09 | 0.1 | 初稿（REV-P6-0 audit + §34 落地；保守：不改资金成功/失败行为） | AI |
| 2026-09-09 | 1.0 | 实施完成：migration(20260909000000)+状态机+Orders::Cancel apply 接线+审计 rake+specs；spec 9 绿/回归 30 绿/全量×2 绿/quick 干净；需求 commit c729ce2；GS-077 | AI |
