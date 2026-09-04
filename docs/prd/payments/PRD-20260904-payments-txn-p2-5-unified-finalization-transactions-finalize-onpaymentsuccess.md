# PRD-20260904-payments-txn-p2-5-unified-finalization-transactions-finalize-onpaymentsuccess

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-04 |
| 来源 | P2 源文档 §21/§23-§25/§56（TXN-P2-5 Unified Finalization）+ AC-2015 + §62 可复用矩阵 |
| 分类 | payments（恢复/交易编排域） |
| 关联 Skill | pallastrade-payments / pallastrade-checkout / pallastrade-data-model |
| 关联 REQ | REQ-20260904-txn-p2-5.md |
| 关联 PRD | N/A（全新工作包） |
| 需求类型 | 新功能（P2 内部服务 + 完成入口 Strangler 接线） |

## 1. 背景与目标

- **一句话需求原文**：继续 P2 → TXN-P2-5 Unified Finalization：建立 `Transactions::Finalize` canonical application service，将 Carts::Complete / Checkout::Complete / 组合结算完成逐步收敛到统一 orchestration boundary（Strangler，不一次性删旧 service，§56）。
- **背景**：TXN-P2-1..4 已交付 durable transaction、Start/Resume、PaymentFactResolver、Recovery（Recover 内联 finalize）。现有完成入口（API complete / Webhook / 组合）各自决定"订单怎么完成"（§21 禁止），且不感知 transaction（P2-2 起 Start 建的 txn 未接完成路径）。P2-5 建立统一 finalization 边界并将主要完成入口接线（AC-2015：所有主要 completion 入口最终经过统一 transaction handler）。
- **目标**：
  1. `Transactions::Finalize`（canonical）：对已确认资金（payment_confirmed/finalizing/recovery_required[已由 Recover 判定 paid]）的 transaction 统一完成参与者订单 → completed；幂等/守卫；失败 → recovery_required + last_error（INV-03）。
  2. `Transactions::OnPaymentSuccess`（Transaction Payment Handler 首版，§21）：组合会话 → PaymentCombinations::Complete（保留）；有 commerce_transaction 的会话 → 本地资金落账后 `confirm_payment!` + `Finalize`；无 transaction（legacy）→ 原 Carts::Complete 行为。Webhook `handle_success` 单订单分支与 Store `orders/payment_sessions#complete` 控制器接线到它。
  3. `Transactions::Recover` 的 PAID+incomplete finalize 收口委托 `Finalize`（去重，单一 boundary）。
- **成功指标**：Finalize/OnPaymentSuccess spec 全绿；Recover 既有 AC-412/417 语义不回归；p0-payment-rspec（webhook/API complete/组合）回归全绿；新增文件 rubocop 0。

## 2. 用户故事 / 场景

- 场景 A（事务支付成功-API）：前端 complete → session 完成 → 有 txn 的会话 → confirm_payment + Finalize → 参与者订单 + transaction completed（AC-2015）。
- 场景 B（Webhook 异步成功）：handle_success 单订单 + txn → 同一 handler 收口；legacy 订单行为不变。
- 场景 C（组合）：session 挂 PaymentCombination → 走既有 PaymentCombinations::Complete（adapter，不回归）。
- 场景 D（Recovery 收敛）：Recover PAID+incomplete → Finalize 完成（不再各写一套 finalize 循环）。
- 场景 E（失败）：finalize 参与者失败 → transaction recovery_required（资金不回滚，交 Recover/人工）。
- 场景 F（幂等）：重复 Finalize / 重复 webhook → 一次 completion（INV-08）。

## 3. 功能需求（FR）与验收标准（AC）

### FR-501：Transactions::Finalize（canonical）
`call(transaction:)`：
1. 守卫：nil → failure；`with_lock` reload；已 completed → success（幂等短路，action `:completed`）。
2. 前置状态：payment_confirmed → `begin_finalizing!`；finalizing → 继续；recovery_required → `retry_finalizing!`（供 Recover 已判定 paid 后调用；本服务不 resolve，调用方保证资金事实）；其他（created/payment_pending/canceled/manual_review）→ failure `commerce_transaction_not_finalizable`。
3. 锁外逐参与者 finalize（复用 `Payments::CombinationMemberComplete`：standard→Carts::Complete / legacy→Checkout::Complete；INV-08 幂等），成功者 TransactionOrder.completion_status='completed'；单参与者异常不中断其余。
4. 收口锁：有失败 → 写 last_error（code finalize_failed）→（若已 finalizing）`mark_recovery_required!` → failure `finalize_failed`；全成功 → `complete!` → success `{action: :finalized}`。
- AC-501（FR-501）：payment_confirmed → 参与者完成 + transaction completed。
- AC-502（FR-501）：已 completed 重复调用 → success 幂等短路（不重复 finalize）。
- AC-503（FR-501）：created/payment_pending → failure 不改状态。
- AC-504（FR-501）：参与者失败 → recovery_required + last_error finalize_failed。
- AC-505（FR-501）：recovery_required（已 paid）→ retry_finalizing 完成 → completed（Recover 委托语义）。

### FR-502：Transactions::OnPaymentSuccess（Transaction Payment Handler）
`call(payment_session:)`：
1. nil/combo：session.payment_combination → `PaymentCombinations::Complete.call(payment_session:)`（保留，适配器）。
2. `transaction = session.commerce_transaction`：
   - 无 transaction → legacy：`carts_complete_service.call(cart: order) unless order.completed?`（行为与现 webhook/controller 一致）→ success `{mode: :legacy_completed}`。
   - 有 transaction → `with_lock` reload：payment_pending → `confirm_payment!`（本地已验资 success 后调用，AC-2009）；随后 `Finalize.call(transaction:)`；Finalize 已做幂等/守卫。recovery_required/manual_review/completed → 不动（交 Recover/已完成）；返回 Finalize 结果（`{mode: :finalized}`）。
- AC-511（FR-502）：带 txn 的会话成功 → confirm_payment + Finalize → transaction completed。
- AC-512（FR-502）：无 txn 会话 → legacy Carts::Complete 行为不变。
- AC-513（FR-502）：重复调用（session 已 completed / txn 已 completed）→ 幂等。

### FR-503：完成入口接线（Strangler 首版）
- `Payments::HandleWebhook#handle_success` 单订单分支：本地 payment/session 落账后，替代直调 `carts_complete_service` → `Transactions::OnPaymentSuccess.call(payment_session:)`（组合分支保持在前）。
- Store `orders/payment_sessions#complete` 控制器（非组合、active 完成路径）：替代 `carts_complete_service unless completed` → `OnPaymentSuccess`。
- `Recover` PAID+incomplete：委托 `Finalize`（移除自身 finalize 循环）。
- **不**改 CombinationSettleJob（组合 adapter 语义保留；组合 txn 化随未来 combined strategy）；无 API 面新增。
- AC-521（FR-503）：webhook 单订单带 txn → 走 Finalize（order+txn completed）。
- AC-522（FR-503）：无 txn legacy webhook/controller 回归不变（p0-payment-rspec 全绿）。
- AC-523（FR-503）：Recover 委托 Finalize，AC-412/417 语义保持。

### FR-504：范围边界
- 不删旧 service（Strangler）；不改 quote/pricing；不新增迁移/API/SDK；不处理 stuck sweeper/UI。
- INV-02/03/08 保持；attempt 计数仅 Recover（Finalize 失败写 last_error，不再计 attempt，避免双计）。

## 4. 跨层搜索记录（Step 0）

| 层 | 结论 |
|---|---|
| App | 无（backend/app 无完成入口 txn 感知） |
| core | 完成入口现状：Payments::HandleWebhook#handle_success（组合→PaymentCombinations::Complete；单订单→carts_complete_service）；Recover 内联 finalize（TXN-P2-4）；CombinationMemberComplete（RISK-01 分流原语）与 CombinationSettleJob（组合 adapter）；Carts::Complete/Checkout::Complete canonical/compatibility —— 无 Finalize/OnPaymentSuccess |
| api | orders/payment_sessions#complete 控制器：组合→PaymentCombinations::Complete；active 完成→carts_complete_service unless completed（接线点） |
| admin | 无 |
| storefront | 无（后端内部） |
| platform | 无 |

## 5. 技术影响与设计要点

- core services 新建：`transactions/finalize.rb`、`transactions/on_payment_success.rb`；`recover.rb` 收敛（委托 Finalize，保留 resolve/guard/attempt/retry/repair）。
- core service 改：`payments/handle_webhook.rb`（单订单完成 → OnPaymentSuccess）。
- api controller 改：`store/orders/payment_sessions_controller.rb#complete`（→ OnPaymentSuccess）。
- 复用 `Payments::CombinationMemberComplete`（订单级分流原语）为 finalize 的 per-participant 执行器；`PaymentCombinations::Complete` 保持组合入口。
- 反模式：无回调副作用（finalize 委托服务）；无跨 store；无内联样式/裸 fetch。

## 6. 测试计划

- 新增 `spec/services/pallastrade/transactions/finalize_spec.rb`（AC-501..505）。
- 新增 `spec/services/pallastrade/transactions/on_payment_success_spec.rb`（AC-511..513；legacy + txn 两模式）。
- 既有 `recover_spec.rb`（AC-412/417 收敛语义不回归）。
- 回归：p0-payment-rspec 注册 verifier（webhook/API complete/组合/Carts::Complete 全套）。
- 每条 spec 头标注 `# PRD-20260904-payments-txn-p2-5 AC-xxx`。

## 7. 文档同步清单

- [ ] `ai/skills/pallastrade-payments/SKILL.md` changelog（Transactions::Finalize + OnPaymentSuccess 接线）
- [ ] `ai/skills/pallastrade-checkout/SKILL.md` changelog（订单完成收敛，视需要）
- [ ] `docs/prd/README.md` 索引 + 本 PRD 状态
- [ ] store.yaml/SDK/api-v3：N/A（无 API 面新增；controller 行为兼容）
- [ ] RESEARCH-20260904-txn-p2-0 审计附录（可选）

## 8. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-04 | 0.1 | 定稿 approved（用户"实施"预授权后呈现） | AI |
| 2026-09-04 | 0.2 | 实施完成：Transactions::Finalize + OnPaymentSuccess + Webhook/controller 接线 + Recover 委托收口；specs 18+15 examples 0 failures；新增文件 rubocop 0 | AI |
