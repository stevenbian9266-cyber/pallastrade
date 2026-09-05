# REQ-20260905-paymentcombination-txn — PaymentCombination txn 化

- 关联 PRD：docs/prd/checkout/PRD-20260905-checkout-paymentcombination-txn-化-组合交易收敛到-transactions-finalize-recov.md（approved）
- 任务：TASK-20260905050410-0f492f00
- Gate：GATE-2026-09-05T05-04-20
- 类型：feature / risk critical（组合资金面）
- 用户决策（2026-09-05）：全收敛 Finalize / 每成员 TransactionOrder / OnPaymentSuccess 收敛

## Skill 表
| Skill | 结论 |
|---|---|
| pallastrade-payments | 组合契约（1 combo→1 session(primary)+1 Payment+per-order splits）；Complete 阶段1入账+阶段2成员；SettleJob 补偿；RISK-01 CombinationMemberComplete 分流；Finalize/OnPaymentSuccess/Recover（P2-4/5）语义 |
| pallastrade-events-webhooks | webhook 组合完成路径需收敛到 OnPaymentSuccess（session 有 txn 时） |
| pallastrade-data-model | CommerceTransaction(combined_payment purpose + belongs_to payment_combination) / TransactionOrder(primary/participant, order 唯一) / PaymentSession(可同时挂 combination+transaction) 均就绪，无需迁移 |

## 实施清单
1. payment_combination.rb：`has_one :commerce_transaction`（inverse_of）
2. 提取 `PaymentCombinations::Settlement`（入账幂等 primitive：payment 完成+splits+订单 payment_total+combination succeed，已 succeeded 短路）；`Complete` 改为薄适配器（Settlement + 成员 + SettleJob，供 legacy 无 txn 组合）
3. `Transactions::Finalize` 组合分支（txn.payment_combination 存在 → Settlement + 逐成员 CombinationMemberComplete + complete/recovery_required）
4. `Transactions::OnPaymentSuccess` 组合分支：txn 存在→confirm_payment!+Finalize；txn 不存在→Complete 适配器（legacy）
5. `PaymentCombinations::Create`：建组合后同步建 txn（combined_payment）+ per-unpaid TransactionOrder + session.transaction_id/txn.payment_combination 回填 + start_payment
6. webhook 组合完成点收敛（读后改：session 有 txn → OnPaymentSuccess）
7. specs：create/finalize 组合/on_payment_success/recover 组合/legacy 回归/complete 适配器

## 验证
- docker rspec 定向（create/finalize/on_payment_success/recover/handle_webhook_combination/combination complete/settle job）；p0-payment-rspec + chk-p1-5 注册 verifier
- rubocop 0；doc-impact 绿；recovery plan（critical）

## 收尾
prep（user-confirmed 以三项决策授权）→ 实施 → specs → evidence → coverage-gate → commit → 重跑 verifier → finish → push。
