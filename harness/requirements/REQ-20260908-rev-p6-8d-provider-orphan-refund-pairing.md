# REQ-20260908-rev-p6-8d-provider-orphan-refund-pairing

> PRD: docs/prd/payments/PRD-20260908-payments-rev-p6-8d-provider-orphan-refund-pairing.md
> Task: TASK-20260908122048-6f194e4f; Gate: GATE-2026-09-08T12-21-01（feature）
> 源: 豆包…/P6 §62 REV-P6-7 边界「provider 孤儿退款配对」+ FIN-P4-5 `provider_refund_references`（已取回未消费）。
> 用户选定「1. Provider 孤儿退款配对」并指令实施（多选回答）。

## 跨层搜索（节选）
Core：ProviderFinancialDetails.provider_refund_references（Stripe 已填充 re_[]；Bogus=本地派生 `re_bogus_<id>`）；
ReconcilePayment 范式（StoreCredit/Check→NOT_APPLICABLE、无 fetch_financial_details→UNSUPPORTED、session 锚点
（payment_session || payment_combination.payment_sessions.first）、provider 异常捕获不 raise）；本地 `payment.refunds`
transaction_id（=provider refund id）。无既有孤儿检测。API/Admin/Storefront/Platform 无涉。
Skill：payments（REV-P6-7/FIN-P4-5/6）、reconcile、testing、prd、api-v3、customization（已读）。

## Skill 咨询证据表
| Skill | 结论 |
|---|---|
| pallastrade-payments | FIN-P4-5/6 + REV-P6-7 边界已核实；孤儿配对数据面=provider_refund_references |
| pallastrade-api-v3 | 无 API（rake+service 消费） |
| pallastrade-customization | core gem 直接扩展（PALLAS-CUSTOM） |
| harness-prd | PRD+REQ 简版（本文件） |
| pallastrade-testing | service spec（stub fetch_financial_details）+ rake 冒烟 |

## 需求
1. `Refunds::OrphanPairingResult`（VO freeze）：status/reasons/provider_refund_references[]/matched[]/orphans[]/
   local_unmatched[]/observed_at。
2. `Refunds::OrphanPairing.call(payment:)`：not_applicable（StoreCredit/Check）/unsupported（无实现）/unavailable
   （无 session 或 provider 异常）/配对（provider ids ∩ 本地 transaction_id → matched；provider-only→orphans
   ORPHAN_REFUND；本地有引用缺 provider→local_unmatched LOCAL_REFUND_NOT_ON_PROVIDER；任一异常→needs_attention）。
3. rake `pallastrade:refunds:orphans[store_id]`：扫 completed PSP 支付→TSV+汇总，异常不中断。
4. runbook docs/operations/refund-orphan-pairing-runbook.md。
无 migration/API/UI。

## 验证
orphan_pairing_spec（AC-R68D-01~04）+ rake 冒烟（AC-R68D-05）→ 回归 refund/reconcile/8a/8b/8c → 全量 ×2 +
quick check + doc-impact。
