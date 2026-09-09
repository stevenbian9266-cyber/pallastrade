# REQ-20260909-rev-p6-8l-admin-api-v3-readonly.md

> 关联 PRD：`docs/prd/payments/PRD-20260909-payments-admin-api-v3-只读端点-payment_combinations-index-show-refunds-sh.md`
> Task：TASK-20260909052623-817e6af6；Gate：待开
> 源需求：Admin API v3 只读端点（payment_combinations index/show + refunds show + 孤儿配对扫描）+ yaml/api-reference 同步（8g/8h 边界落地；SDK：无 admin-sdk 包不新建）

## 背景
8a/8g/8h 的只读信息仅在 Rails Admin HTML；v3 admin 仅 refunds index/create（无 show）+ 组合 cancel。
本包新增 4 个只读端点（组合列表/详情、退款详情、支付孤儿配对）+ admin_payment_combination_serializer +
admin.yaml/api-reference 同步 + generated:check。SDK 现实：platform 仅 store SDK（generate-zod 只服务
store），无 admin TS 客户端 → 记录边界不新建。

## FR/AC
见 PRD §3/§5（FR-R68L-101..105；AC-R68L-01..06）。

## 6 层跨层搜索
| 层 | 结果 |
|---|---|
| backend/app | 无 override |
| core | PaymentCombination/PaymentSplit/Refund 数据面 + OrphanPairing（8d/8h 只读）+ CommerceTransaction |
| api | admin orders/refunds index+create（无 show）；payment_combinations cancel；serializer 注册表 admin_refund/admin_payment（无 admin_payment_combination）→ 缺口 |
| admin | 8a/8g/8h Rails Admin 只读页（数据面/降级语义参考） |
| storefront/platform | sdk 仅 store；无 admin-sdk |

## Skill 咨询结论表
| Skill | 结论 |
|---|---|
| pallastrade-api-v3 | v3 惯例：store 作用域/prefixed id/{data}/expand/fields；ResourceController/BaseController 模式；serializer dependencies 注册 |
| pallastrade-payments | 8a/8d/8g/8h 数据面与孤儿只读语义（能力/锚点判定、金额降级） |
| pallastrade-customization | 决策树：纯 API 展示=api 层直接加端点（非 decorator/subscriber） |

## 反模式/约束
零写/零 provider mutation（孤儿端点只读不变式，8d）；store 作用域（AP-005 无 store scope 禁止）；
prefixed ids 无整型 PK（AGENTS §4）；AP-002（本包后端无关，但未来消费方用 typed client——SDK 边界已记录）；
ransack 白名单；N+1 避免。

## 边界
新建 admin TS SDK/typed client（无此包，独立工程）；孤儿全店扫描列表端点（rake 保留）；组合/退款写动作
（既有 create/cancel）；store SDK 不涉。
