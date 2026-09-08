# REQ-20260908-rev-p6-8e-reverse-commerce-recover

> PRD: docs/prd/payments/PRD-20260908-payments-rev-p6-8e-reverse-commerce-recover-cross-domain.md
> Task: TASK-20260908131818-830193f9; Gate: GATE-2026-09-08T13-18-28（feature）
> 源: 豆包…/P6 §45/§39-42/§51 + RestockFact 注释（REV-P6-6 Recover 消费本事实）。用户指令「实施
> ReverseCommerce::Recover 跨域」。本包=Order 锚点跨域收敛（restock AMBIGUOUS 幂等自愈 + 复用 Refunds::Recover）；
> Journal/Reconcile 派发归 P4 sweeper，不重复；无自动调度（service+rake 手动）。

## 跨层搜索（节选）
Core：ReturnItem restock 唯一通道（partial unique，private restock_if_needed）+ RestockFact 五态（AMBIGUOUS=
accepted+eligible+无 movement，无收敛者=缺口）；order.customer_returns（经 return_authorizations）→ return_items；
Refunds::Recover 幂等（fresh no-op）；Refunds::RecoverSweeperJob 全局覆盖组合/无 order 退款。Admin/API/Platform
无涉。Skill: payments（REV-P6-5/6）、testing、prd、api-v3、customization（已读）。

## Skill 咨询证据表
| Skill | 结论 |
|---|---|
| pallastrade-payments | REV-P6-5 RestockFact/幂等键、REV-P6-6 Recover 语义已核实；restock AMBIGUOUS 无收敛者是缺口 |
| pallastrade-api-v3 | 无 API |
| pallastrade-customization | core gem 直接扩展（PALLAS-CUSTOM）；public 自愈入口需保守命名/守卫 |
| harness-prd | PRD+REQ 简版 |
| pallastrade-testing | model+service spec（真回补/守卫/异常 rescue） |

## 需求
1. `ReturnItem#restock_if_ambiguous!`（public 幂等）：accepted? && restock_eligible? && 无
   StockMovement(return_item_id:) → 复用 restock_if_needed（唯一通道+RecordNotUnique 跳过）回补；否则 no-op。
2. `ReverseCommerce::Recover.call(order:)`：restock 域逐 return item RestockFact.resolve；AMBIGUOUS→自愈 healed；
   RESTOCKED/NOT_REQUIRED/NOT_RESTOCKABLE/PENDING 计数；单条 rescue。refund 域：order.payments.refunds 逐条
   `Refunds::Recover.call(refund:)`（复用，幂等 no-op 安全）。聚合 Result；不 raise。
3. rake `pallastrade:reverse_commerce:{recover[order_id], list_ambiguous[store_id]}`。
4. runbook docs/operations/reverse-commerce-recover-runbook.md。
无 migration/API/UI/sidekiq。

## 验证
return_item_restock_recover_spec（AC-R68E-01/02）+ reverse_commerce/recover_spec（AC-R68E-03/04）+ rake 冒烟
（AC-R68E-05）→ 回归 refund/return/reconcile/8a-8d → 全量 ×2 + quick check + doc-impact。
