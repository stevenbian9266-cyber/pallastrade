# REQ-20260908-rev-p6-8i-recover-auto-scheduling.md

> 关联 PRD：`docs/prd/payments/PRD-20260908-payments-rev-p6-8i-recover-auto-scheduling.md`
> Task：TASK-20260908192732-ae0015f2；Gate：GATE-2026-09-08T19-27-33（约）
> 源需求：ReverseCommerce::Recover 自动调度化（用户三包授权 #3）

## 背景
8e Recover 手动（service/rake）；restock-AMBIGUOUS 无自动收敛者。Refunds::RecoverSweeperJob（6）与
Transactions::RecoverSweeperJob 为保守 sweeper 模板。

## FR/AC
见 PRD §2-5（FR-R68I-101..103；AC-R68I-01..06）。

## 6 层跨层搜索
| 层 | 结果 |
|---|---|
| backend/app | 无涉（job 在 core/host schedule） |
| core | 8e Recover/rake + ReturnItem.accepted/stock_movements/RestockFact；Refunds::RecoverSweeperJob 模板；**无 restock 自动收敛调度（缺口）** |
| api/admin/storefront/platform | 无涉 |

## Skill 咨询结论表
| Skill | 结论 |
|---|---|
| pallastrade-payments | 8e 语义 + Refunds::RecoverSweeperJob 保守哲学（enqueue 幂等、rescue 不 re-raise、capped、metrics+warn）为模板。 |
| pallastrade-events-webhooks | jobs/sidekiq-cron 注册位置：backend/config/sidekiq_schedule.rb（PALLAS_CART_SCHEDULE 常量 + initializer 装载）。 |
| pallastrade-prd | R8 流程照常。 |

## 反模式/约束
enqueue 幂等 RecoverJob（零副作用）；不事务内同步 Execute/Recover（AP-010 无关——只 enqueue）；rescue 不
re-raise（防 sidekiq 重试放大）；capped 防风暴；不手改生成文件。

## 边界
手动 rake/runbook 保留；ambiguous 之外人工/既有 sweeper；不做 refund 域额外调度。
