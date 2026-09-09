# REQ-20260909-rev-p6-8k-combination-cancel-event.md

> 关联 PRD：`docs/prd/payments/PRD-20260908-payments-rev-p6-8f-combination-level-cancel-orchestration.md` §11（8f 边界落地）
> Task：TASK-20260909032549-ef07c9b7；Gate：待开
> 源需求：组合级取消编排事件 `payment_combination.cancel_orchestrated` + 审计/metrics 订阅者（8f 边界「组合级 payment_combination.* 取消事件订阅者暂缺」落地）

## 背景
8f `Orders::CombinationCancel` 逐成员复用 `Orders::Cancel`（每成员各自 `order.canceled`），组合层无聚合事件
→ 组合级取消联动无钩子。命名决策：状态机 `cancel` 事件（pre-payment，pending/processing→canceled）已占用
`payment_combination.canceled`（零消费者）——语义不同（succeeded 编排不改组合状态），故 8k 用独立事件名
`payment_combination.cancel_orchestrated`。

## FR/AC
见 PRD §11（FR-R68K-101..103；AC-R68K-01..05）。

## 6 层跨层搜索
| 层 | 结果 |
|---|---|
| backend/app | 无涉 |
| core | CombinationCancel（无事件发布，缺口）；PaymentCombination publish_event 惯例（succeeded 先例）；engine.rb 订阅者注册点 L391；Audit.record / OperationalMetrics.count 可用 |
| api | 无涉 |
| admin | 无涉 |
| storefront/platform | 无涉 |

## Skill 咨询结论表
| Skill | 结论 |
|---|---|
| pallastrade-events-webhooks | 订阅者惯例：`subscribes_to` + `handle(event)`（勿覆写 call）；默认 async SubscriberJob；注册非自动发现；payload 双模 id（prefixed/raw） |
| pallastrade-payments | 8f/8a 上下文：Audit.record 敏感资金操作；编排审计与逐成员 order.canceled 的关系 |
| pallastrade-prd | 查重命中 8f PRD（44%）→ 回写更新原 PRD（不新建）；优化迭代 |

## 反模式/约束
订阅者 rescue 不 raise（不阻断事件流）；不覆写 Subscriber#call；事件仅在 canceled>0 时发布（幂等防噪）；
状态机 `payment_combination.canceled`（pre-payment）语义与注册不变；不涉资金/状态机变更。

## 边界
状态机 canceled 事件加消费者/加 payload、webhook 出站、组合全取消后自动转 canceled/closed → 后续（PRD §11.2 边界）。
