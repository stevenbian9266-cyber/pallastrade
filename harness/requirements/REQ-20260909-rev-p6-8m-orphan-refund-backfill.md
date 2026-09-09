# REQ-20260909-rev-p6-8m-orphan-refund-backfill.md

> 关联 PRD：`docs/prd/payments/PRD-20260909-payments-孤儿退款补记-backfill-refunds-backfillproviderrefund-rake-dry-run-.md`
> Task：TASK-20260909063544-ba160044；Gate：待开
> 源需求：孤儿退款补记 backfill（8d/8h 边界落地；RISK-REV-01 收口）——补记即终态 succeeded + Journal，绝不二次 PSP

## 背景
8d/8h 孤儿只读配对/金额后本地无 durable Refund 行 → Journal/对账缺半边。8m = Refunds::BackfillProviderRefund
（复用 apply_success! 幂等 + refund.succeeded → PostRefund Journal 自动闭合）+ RefundReason.orphan_backfill_reason
+ rake dry-run/apply 人工门。零 PSP mutation；幂等 noop；target 不可证明不猜。

## FR/AC
见 PRD §3/§5（FR-R68M-101..103；AC-R68M-01..06）。

## 6 层跨层搜索
| 层 | 结果 |
|---|---|
| backend/app | 无 |
| core | OrphanPairing（8d/8h 金额）；Refund apply_success!（幂等/succeeded+journal）；RefundReason find_or_create 惯例 |
| api | 孤儿只读端点（8l）存在；无写入口（backfill 走 rake） |
| admin | 无 |
| storefront/platform | 无 |

## Skill 咨询结论表
| Skill | 结论 |
|---|---|
| pallastrade-payments | ApplySuccess 幂等/Journal 闭环；8d/8h 孤儿金额语义；reason find_or_create 惯例 |
| pallastrade-security | 危险资金操作（写资金记录）→ Audit + dry-run 门 + 人工确认 |
| pallastrade-prd | 新 PRD（查重通过未命中）；feature |

## 反模式/约束
绝不调 PSP/ExecuteJob（补记=记录 provider 已发生资金，非发起退款）；幂等（同 payment+transaction_id noop）；
target_order/split 不可证明不猜（AC-6029）；Audit 敏感操作；rake dry-run 默认 --apply 显式；无 migration。

## 边界
孤儿 target 不可证明（组合 order nil）→ 仅 fact/journal 落；自动调度不做（人工门）；孤儿对外 API 已由 8l。
