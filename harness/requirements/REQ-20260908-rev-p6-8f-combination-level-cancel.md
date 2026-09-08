# REQ-20260908-rev-p6-8f-combination-level-cancel.md

> 关联 PRD：`docs/prd/payments/PRD-20260908-payments-rev-p6-8f-combination-level-cancel-orchestration.md`
> Task：TASK-20260908145513-2c2bb186；Gate：GATE-2026-09-08T14-55-29
> 源需求：OrderCancellation 组合级取消编排（split-aware 取消退款 + CombinationCancel 编排器 + Admin API）

## 背景（缺口证据）
- PAID 组合成员资金不在本地 payment（组合 Payment `order_id=nil`），`Orders::Cancel#completed_refundable_payments`
  对其返回空 → 取消零退款（G1）。
- succeeded 组合无任何组合级取消入口；combo/txn `cancel` 仅 pending/processing（G2）。
- Admin API v3 无 combo 资源（G3）。REV-P6-4 FR-R64-106 明示组合级取消编排延后至本系列。

## FR / AC
见 PRD §2-5（FR-R68F-101..104；AC-R68F-01..09）。

## 6 层跨层搜索结果（Step 0 强制）
| 层 | 搜索词 | 结果 |
|---|---|---|
| backend/app | cancel/combination | 无 override/宿主（仅 ai_controller）→ 无已满足实现 |
| core | Orders::Cancel/PaymentCombination/PaymentSplit/Refunds::Request/Refund | 单订单 durable 取消（REV-P6-4）+ split 冻结退款底座（REV-P6-3）已具备；**无组合级取消编排 / 无 split-aware 取消退款**（缺口） |
| api | admin payment_combinations / cancel | admin 无 combo 资源；store 仅 create/show（客户无取消）→ 缺 G3 |
| admin | PaymentCombination/cancel | Rails Admin 无组合管理页（G6 另列）→ 无已满足 |
| storefront | cancel/combination | 无取消 UI（仅创建组合合并支付）→ 无已满足 |
| platform | paymentCombinations cancel | SDK 无取消方法 → 无已满足 |

## Skill 咨询结论表（R2 必读并填真实结论）
| Skill | 结论 |
|---|---|
| pallastrade-customization | 决策树：组合取消属「替换/扩展核心服务计算」→ 服务层新增 `Orders::CombinationCancel` 镜像既有 `Orders::Cancel`/`ManualSplit` 模式（service + DI 可选直接引用）；事件只用于副作用（每成员 order.canceled 已发布，无需新增订阅者）；不改 decorator/gem。**不需要** decoration/extension 层。 |
| pallastrade-payments | REV-P6-4 决策矩阵 + durable Refunds::Request(enqueue:false) + split 冻结上限 + update_order 唯一写点全部复用；REV-P6-4 边界注释明示组合级取消编排归本系列；8e Recover 边界注释同。组合成员退款语义（PaymentSplit 权威、金额=credit_allowed、不碰兄弟）即本包退款基础。 |
| pallastrade-prd | 一句话需求 → PRD 模板扩充 → 用户确认（实施指令=user-confirmed）→ gate + REQ → AC↔测试（`# PRD-… AC-R68F-xx`）→ 接口变更同步 admin.yaml + generated:check → 知识同步门。本包按 R8 全流程执行。 |

## 反模式检查（R5）
- AP-010：编排器/取消内不得事务内同步 `Refunds::Execute.call(`；一律 `Refunds::Request(enqueue:false)` +
  提交后统一 `ExecuteJob.perform_later`（镜像 Orders::Cancel 既有模式）。
- AP-005：current_store / accessible_by 作用域；AP-003 仅 spec 用 factory/直接建行。
- 不手改生成文件（admin.yaml 变更走 generated:check 同步 SDK）。

## 边界（记录不实施）
CommerceTransaction/PaymentCombination 状态机不加 PAID cancel 态；Rails Admin 组合可视化（G6 另开）；
OrderCancellation 状态机化与取消意图恢复；组合级取消事件（无订阅者）。
