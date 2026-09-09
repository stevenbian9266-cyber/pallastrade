# REQ-20260909-rev-p6-8j-ordercancellation-state-machine.md

> 关联 PRD：`docs/prd/payments/PRD-20260909-payments-rev-p6-8j-ordercancellation-state-machine.md`
> Task：TASK-20260909013338-65c98ad4；Gate：GATE-2026-09-09T01-33-51
> 源需求：OrderCancellation 状态机化 + 取消意图恢复（durable intent lifecycle）

## 背景
§34 建议 OC 加状态机（是否加 state 由 REV-P6-0 DB audit 决定）。audit：OC 无 state、唯一写入=Orders::Cancel
（同事务原子）；加 state 安全。成功取消→applied；恢复=审计 rake 检测「意图已 applied 但资金未落地」。

## FR/AC
见 PRD §2-5（FR-R68J-101..104；AC-R68J-01..05）。

## 6 层跨层搜索 + REV-P6-0 audit
| 层 | 结果 |
|---|---|
| backend/app | 无 override |
| core | OrderCancellation（无状态）；Orders::Cancel 唯一写入（L57）；Refund/Refunds::Request durable；无 OC 生命周期（缺口） |
| api | 无涉 |
| admin | 无 OC 展示（8g 组合页不含 OC）→ 不涉 |
| storefront/platform | 无涉 |

## Skill 咨询结论表
| Skill | 结论 |
|---|---|
| pallastrade-payments | §34/35：OC durable intent；Order=canceled + Refund=processing 合法并存；Recover 收尾。状态机事件映射到 Orders::Cancel 同事务。 |
| pallastrade-admin | 本包无 admin UI（audit 走 rake）；状态呈现留给后续与 8g/8a 合并。 |
| pallastrade-prd | R8 流程照常；feature。 |

## 反模式/约束
不改资金成功/失败行为（失败仍整体回滚）；状态机迁移不加约束破坏存量；ransack 白名单；rake 只读；
migration 幂等。

## 边界
completed/processing 态、失败路径持久 recovery_required 意图（改动资金失败语义）、Admin UI → 后续。
