# REQ-20260908-rev-p6-8g-combination-visibility.md

> 关联 PRD：`docs/prd/payments/PRD-20260908-payments-rev-p6-8g-combination-visibility-rails-admin.md`
> Task：TASK-20260908171203-15614323；Gate：GATE-2026-09-08T17-12-12
> 源需求：Rails Admin 组合可视化 + 退款聚合展示（G6；用户三包多选授权）

## 背景（缺口）
Rails Admin 无 PaymentCombination controller/nav/tables/i18n（调研确认零痕迹）；Ops 无法查看组合资金
split 已退/未退。8a Refund Ops（RefundsOpsController + tables + nav + helper + i18n）为模板基建。

## FR/AC
见 PRD §2-5（FR-R68G-101..104；AC-R68G-01..06）。

## 6 层跨层搜索
| 层 | 结果 |
|---|---|
| backend/app | 无 override → 无已满足 |
| core | PaymentCombination/PaymentSplit 模型 + Refund.for_store（via_combination）已备；无展示需求实现 |
| api | admin 仅 cancel member（8f）；无只读端点（本包不做） |
| admin | **无组合面（缺口）**；8a/Transactions 基建齐全 |
| storefront/platform | 无涉 |

## Skill 咨询结论表
| Skill | 结论 |
|---|---|
| pallastrade-admin | Rails Admin 只读资源页模板：ResourceController+TableConcern、tables register、nav add、helper 注册、routes、i18n —— 全按 8a RefundsOps/Transactions 骨架复制。 |
| pallastrade-payments | 组合资金语义（split captured/refunded/credit_allowed、组合 Payment refunds、CommerceTransaction 关联）为展示数据源；8a 状态徽章/字段复用。 |
| pallastrade-prd | 一句话需求流程；本包按 R8 全流程执行（实施指令 + 多选授权 = user-confirmed）。 |

## 反模式
只读页无资金副作用；不加写动作；custom partial 内走 helper（需 BaseController 注册）；N+1 用 ar_lazy_preload；
不手改生成文件（无生成文件变更）。

## 边界
组合写动作（new/edit/delete 不做）；Admin API 组合只读端点 → 8h 评估；触发取消/退款走 8f Admin API。
