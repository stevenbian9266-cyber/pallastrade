# Commerce Transaction — Recovery Operations Runbook（TXN-P2-7）

> P2（Commerce Transaction Orchestration & Recovery）运维手册。适用范围：
> durable `CommerceTransaction`（TXN-P2-1..5）的可见性与手工恢复。命令在宿主
> Rails 环境执行（本仓库 docker：`docker exec -it pallastrade-web-1 sh -c "cd /rails && ..."`）。

## 1. 关键概念速查

- 交易状态：`created → payment_pending → payment_confirmed → finalizing → completed`
  异常：`recovery_required`（资金已确认但订单未完成）、`manual_review`（资金事实无法确定，需人工）。
- 资金事实判定：`Transactions::PaymentFactResolver`（P2-3）——本地 completed
  Payment 或 provider 权威状态；`ambiguous` 绝不猜。
- 恢复执行：`Transactions::Recover`（P2-4）——**先确认资金事实再行动**；
  完成收口：`Transactions::Finalize` / `Transactions::OnPaymentSuccess`（P2-5）。

## 2. 可见性（stuck / needs-attention）

```bash
bundle exec rake pallastrade:transactions:list_needs_attention
```

输出 `count=` 及 TSV 行（prefixed_id / state / purpose / currency / amount / updated_at）。
包含：`recovery_required`、`manual_review`（任何时长）＋ `payment_confirmed`/`finalizing`
超 1h 未进展（stuck）。

代码语义：`PallasTrade::CommerceTransaction.needs_attention(stuck_after: 1.hour)`。

## 3. 详情 trace

```ruby
tx = PallasTrade::CommerceTransaction.find_by_prefix_id!('txn_xxx')
tx.trace
# => 时间戳/attempts/last_error/participants（total/completed/roles）/
#    payment_sessions（total/by_status）/snapshot_fingerprint
```

## 4. 手工恢复（manual recovery tooling）

```bash
bundle exec rake "pallastrade:transactions:recover[txn_xxx]"
```

- 成功：打印 `recovered <id>: action=... state=...`。
  action：`retry_payment`（UNPAID→payment_pending）/ `manual_review` /
  `repair_completed` / `finalized`。
- 失败：打印 last_error（如 `finalize_failed`/`commerce_transaction_not_recoverable`）并 exit 1。
- 幂等：重复执行安全（已完成交易会返回 not_recoverable；不会重复扣款/完成）。

## 5. 决策指引（Recover 分支语义）

| Resolver 判定 | Recover 动作 | 说明 |
|---|---|---|
| UNPAID | retry_payment → payment_pending | 无资金入账，可重启支付；不重复扣款 |
| PAID + 参与者订单已完成 | repair_completed → completed | 只修复状态 |
| PAID + 订单未完成 | finalized（Finalize） | 完成参与者（standard→Carts::Complete / legacy→Checkout::Complete） |
| AMBIGUOUS | manual_review | 不猜；人工核对 provider 后再恢复 |

## 6. 运维红线（INV）

- PSP authoritative success 不可逆（INV-02）：`payment_confirmed` 不得退回普通
  failure/pending；恢复只经上述状态出口。
- Recovery 不默认创建新 Payment（INV-04）；decline ≠ 交易失败（INV-05）。
- 重复 webhook/complete 幂等（INV-08）——不要手工重复触发 provider 收款。

## 7. 后续（未含于本切片）

- Admin transaction inspection UI / metrics / alerts / 自动 stuck sweeper：
  待 Admin resource 基建与可观测组件就绪后接入（P2 收尾项）。

## 8. Admin Transactions（slice2, 2026-09-05）

后台 **Orders → Transactions**（需 Orders 管理权限或 PermissionRegistry `transactions` read）：

- **列表** `/admin/transactions`：当前 store 的交易（分页/按 state 搜索），顶部 metrics 汇总卡
  （recovery_required / manual_review / stuck=payment_confirmed|finalizing 超 1h）。
- **详情** `/admin/transactions/txn_xxx`：trace 读模型（时间戳/attempts/last_error/参与者/会话）。
- **恢复**：仅 `recovery_required` / `finalizing` 显示 "Run recovery" 按钮 → enqueue
  `Transactions::RecoverJob`（异步；resolver 判定后分支）。`manual_review` 无按钮（人工，AC-2014）。

## 9. 自动 stuck sweeper（slice2, 2026-09-05）

sidekiq-cron `*/5 * * * *` 调度 `PallasTrade::Transactions::RecoverSweeperJob`（host
`config/sidekiq_schedule.rb` 条目 `transaction_recovery_sweeper`）：

- **自动**：`recovery_required` 交易 enqueue `RecoverJob`（幂等，resolver 判定后分支）。
- **不自动**：`manual_review` 与 stuck `payment_confirmed`/`finalizing`（>1h）——仅计数并
  `warn` 日志告警（metrics 最小集），走 Admin/rake 人工介入（AC-2014 / INV-04）。
- 重复调度安全：Recover 幂等（with_lock + 状态守卫 + attempts 计数）。

手动触发：`PallasTrade::Transactions::RecoverSweeperJob.perform_now` 或等下一个 cron。
