# PRD-20260908-payments-rev-p6-8c-reimbursement-async-chain-durable-requested-executejob

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-08 |
| 来源 | 需求：REV-P6-8c reimbursement legacy 退款链 async 拆链（durable requested + ExecuteJob + initiated 记账） |
| 分类 | payments（语义归属） |
| 关联 Skill | pallastrade-payments |
| 关联 REQ | REQ-20260908-rev-p6-8c-reimbursement-async-chain.md |
| 关联 PRD | REV-P6-1/2（create_refund 同步执行兼容边界）、P6-8a/8b（Ops/ManualRetry 消费） |
| 需求类型 | 优化迭代（资金链 async 收敛，feature gate） |

> 源：`豆包…/P6` §16（Provider I/O 禁事务内）/§46/§48/§57 + REV-P6-2 边界注记（「reimbursement 链仍 sync…
> 完整 async 编排归 REV-P6-8」）。**本包只做一件事**：legacy `Reimbursement#perform!` 退款链从「事务内同步
> `Refunds::Execute.call(raise_on_failure:)`」改为 **durable(requested) → enqueue ExecuteJob**（AP-010），
> 并把记账语义从 succeeded-only 提升为「initiated（covering）」，消除 async 化后 perform 判定/重复建单的两处
> 失真。边界（记录，不实施）：provider 孤儿退款配对、ReverseCommerce::Recover 跨域、OrderCancellation 组合
> 取消编排 → 后续独立包。

## 1. 背景与目标
`ReimbursementType::ReimbursementHelpers#create_refund`（OriginalPayment 售后退款）非 simulate 分支 =
`refund.save!` + `Refunds::Execute.call(refund:, raise_on_failure: true)` —— provider I/O 可能位于调用方 DB
事务内（源 §13/§16/REV-INV-03 违规残留，REV-P6-1/2 明示 v1 兼容边界）。且 `Reimbursement#perform!` 用
`paid_amount`（仅 succeeded）判 reimbursed/errored、重复 perform 靠「success 才更新 split/退款投影」去重 →
一旦 async，perform 永远见不到 succeeded → 判定/去重双重失真（REV-P6-2 根因注记）。目标：整链 async 收敛 +
initiated（covering）记账，AP-010 全绿、退款最终状态由 Refund Ops（8a/8b）呈现与人工收敛。
成功指标：reimbursement 退款不再同步 Execute；durable requested 覆盖即 reimbursed(initiated)；重复 perform
不重复建 requested；refund failed 不再把 Admin perform 卷入 raise（改为 Ops 可见 + ManualRetry）；全量绿。

## 2/3. FR
- FR-R68C-101：`create_refund`（reimbursement 链，非 simulate）`save!`（durable requested）后改为
  `Refunds::ExecuteJob.perform_later(refund.id)`；删除事务内同步 `Refunds::Execute.call`（AP-010）。simulate 不变。
- FR-R68C-102：`Reimbursement` 记账语义——新增 covering 口径 `refund_coverage_amount`（refunds state ∈
  requested/processing/ambiguous/succeeded 的 amount 合计；failed/canceled 不计）；`perform!` 用
  `total − (refund_coverage + credits)` 判定 `reimbursed!`/`errored!`（credits 为本地即时值）。`paid_amount`
  （succeeded-only）保留供资金事实展示/核算。
- FR-R68C-103：initiation 幂等（消除 async 后「重复建 requested」）——`create_refunds` 循环起点先扣
  `reimbursement` 已有 covering refund 合计（state ∈ covering），且逐 payment 上限已由
  `payment.credit_allowed`（含 requested 占用）兜底；拆单/组合 split 上限路径（child：无本地 payment）由
  `credit_limits[payment_id] = split.captured − split.refunded − 该 split covering refund 合计` 计算，保证
  任务未跑完时重复 perform 不重复建单。
- FR-R68C-104：`Reimbursement#perform!` 失败语义：容量不足无法覆盖 total → errored!+raise
  IncompleteReimbursementError（与旧一致）；provider 拒绝不再 raise（async 后 refund→failed 在 Ops 呈现，
  ManualRetry=8b 收敛）。Admin `ReimbursementsController#perform` 无代码变化（仍调 perform!；flash 语义随
  perform! 结果）。

## 4. NFR
资金安全：绝不同步 Execute（AP-010）；不自动重退（REV-INV-04）；durable-first（AC-6001）。审计/状态机其余
不动。无 migration；无 API/Storefront/Platform。

## 5. AC（与测试映射）
| AC | 条件 | FR |
|---|---|---|
| AC-R68C-01 | reimbursement 链 refund 创建 = durable requested + enqueue ExecuteJob；无同步 Execute（回归 AP-010 扫描） | 101 |
| AC-R68C-02 | perform!：covering（requested 等）覆盖 total → reimbursed；不足（容量/无支付）→ errored+raise | 102 |
| AC-R68C-03 | 重复 perform（含 ExecuteJob 未跑完）不重复建 requested（split 上限含 covering） | 103 |
| AC-R68C-04 | provider 拒绝不再使 Admin perform raise；refund 保持 failed 行（Ops 可见） | 104 |
| AC-R68C-05 | 既有 child/single 售后 spec 更新后绿 + 新增 async spec；全量 backend-rspec ×2 + quick check + doc-impact | 全部 |

## 6. 跨层搜索（节选）
App 无 override。Core：链路=Reimbursement#perform!→ReimbursementPerformer→ReimbursementType::
OriginalPayment.reimburse→ReimbursementHelpers#create_refund（save+Execute 同步）；`Refunds::Request`/
`ExecuteJob` 已收敛（REV-P6-2/4）；`Refund::CAPACITY_STATES`/`credit_allowed` 已含 requested（capacity 天然
防重复）；split 上限 `amount_within_frozen_split_limit` 用 captured−refunded（succeeded）→ 需 covering 修正。
Admin：ReimbursementsController#perform（调 perform!）；请求 spec 无。API/Storefront/Platform 无涉。
Skill：payments（REV-P6-1/2/8a/8b 节）、api-v3、customization、prd、testing（已读）。

## 7. 技术影响
Core：`models/pallastrade/reimbursement.rb`（covering helper + perform! 判定）、
`models/pallastrade/reimbursement_type/reimbursement_helpers.rb`（enqueue 替代同步 Execute + initiation
幂等/分拆 covering 上限）。specs：`reimbursement_type/original_payment_child_spec.rb` 更新（async 语义：
split.refunded_amount 由 ExecuteJob 更新 → 测试改为跑 job 或断言 requested+入队）+ 新增
`spec/models/pallastrade/reimbursement_async_spec.rb`。无 migration/API/UI。

## 8. 测试计划
- 新增 `reimbursement_async_spec.rb`（AC-R68C-01~04：durable requested+enqueue、perform reimbursed covering、
  容量不足 errored+raise、重复 perform 幂等）。
- 更新 `original_payment_child_spec.rb`：AC-001 后补 `ExecuteJob` 跑完（perform_enqueued_jobs）后断言
  split.refunded_amount；AC-003 断言 covering/errored 语义调整。
- 回归 refund/reconcile/orders cancel/refunds_ops + quick check + 全量 ×2 + doc-impact。

## 9. 文档同步清单
- [ ] payments skill（REV-P6-8c 节）；scenarios GS-070；PRD/REQ/README；doc-impact。
- [ ] 边界记录：孤儿配对/ReverseCommerce::Recover/组合取消 → 后续包。

## 10. 变更记录
| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-08 | 0.1 | 初稿（依据 §16/§46/§48/§57 + REV-P6-2 边界注记 + 链代码测绘） | AI |
| 2026-09-08 | 0.2 | 实施：create_refund async（save+ExecuteJob，删同步 Execute）+ Reimbursement covering/initiated 记账 + perform! 判定 + initiation 幂等（covering/split covering）；新 async+accounting spec + child spec 更新 7 例 + 回归 148 例全绿 + quick check（无 AP/nav OK） | AI |
| 2026-09-08 | 0.3 | 验证收尾：全量 backend-rspec ×2 绿（预提交 EVD-…114610 / 提交后 EVD-…120756）；commit `950573d`；Gate GATE-2026-09-08T11-16-24 FINISHED；knowledge + evidence verified + task finished；doc-impact 过；push dev 发布。 | AI |
