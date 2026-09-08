# ReverseCommerce::Recover Runbook（REV-P6-8e）

> 目的：Order 锚点的跨域逆向收敛——补上 REV-P6-5 后唯一无人收敛的缺口：return item 已 accepted 且可回补但
> StockMovement(+) 缺失（`RestockFact` = AMBIGUOUS）。同时复用 `Refunds::Recover` 收敛该订单可达退款。
> 「消费事实、不猜」（源 §45）：只对精确事实（accepted+eligible+无 movement）做幂等自愈；PENDING 留给上游验收。

## 语义
`ReverseCommerce::Recover.call(order:)` 返回 `{ order_id, restock:{...}, refunds:{...}, errors }`：

- **restock**：逐 return item `RestockFact.resolve`；`AMBIGUOUS` → `return_item.restock_if_ambiguous!`
  （幂等自愈：创建一条正向 `StockMovement(return_item_id:)`，partial unique 防重复）；
  `restocked / not_required / not_restockable / pending` 只计数。
- **refunds**：`order.payments.refunds` 逐条 `Refunds::Recover`（幂等；fresh/terminal no-op）。
  组合/无 order 退款由全局 `Refunds::RecoverSweeperJob`（*/5）覆盖。
- Journal/Reconcile 修复归 P4 `ReconcileSweeper`（本工具不重复派发）。

## 使用

```bash
# 单 order 收敛
cd /rails && bundle exec rake "pallastrade:reverse_commerce:recover[order_xxx]"
# 先看某店有多少 restock-AMBIGUOUS（未收敛）
cd /rails && bundle exec rake "pallastrade:reverse_commerce:list_ambiguous[<store_id>]"
```

## 解读
- `restock.healed>0`：已补回缺失的入库移动（exactly-once；重跑不会重复）。
- `restock.ambiguous>healed`：存在无法自愈的 AMBIGUOUS（restock 抛错/eligible 瞬时变化）→ 查日志/人工。
- `restock.pending>0`：尚未验收裁决，属正常，不动作。
- `refunds.ok/noop`：复用 Refunds::Recover 结果（requested-stale 重跑 / processing-stale→ambiguous / no-op）。

## 边界
- 不做自动调度（sidekiq）——restock 时序（acceptance 后何时可回补）需业务确认后再考虑定时化。
- 不自动取消订单、不改 Journal/Reconcile 派发、不猜状态。
