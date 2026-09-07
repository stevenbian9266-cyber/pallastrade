# PRD-20260907-payments-rev-p6-4-cancellation-orchestration-取消业务决策上收-unpaid-void-pai

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-07 |
| 来源 | 需求：REV-P6-4 Cancellation Orchestration（取消业务决策上收：UNPAID void / PAID durable refund + cancel + restock） |
| 分类 | payments（自动判定） |
| 关联 Skill | `pallastrade-payments`、`pallastrade-data-model`、`pallastrade-events-webhooks` |
| 关联 REQ | REQ-20260907-rev-p6-4-cancellation-orchestration.md（实施时回填） |
| 关联 PRD | PRD-…rev-p6-1（done）/ rev-p6-2（done）/ rev-p6-3（done，冻结与容量底座） |
| 需求类型 | 优化迭代（资金安全增量，feature gate，risk=critical） |

> 🔁 **查重回写**：`harness prd new` 自动查重通过（命中 1 关键词）。REV-P6-1（durable Refund + capacity + succeeded-only 投影）与 REV-P6-2（Refunds::Request / ExecuteJob async + gateway cancel durable 化）为本包底座；REV-P6-3（组合冻结 + split 上限）提供 PAID 组合成员的退款语义基础。
> ⚠️ **编号**：REV-P6 与内部拆单域 P5/P6/P7 为两套编号（源 `豆包…/P6 — Refund, Cancellation & Dispute Orchestration.md` §30-38/§59 + RV-R06/R07）。

---

## 1. 背景与目标

- **一句话需求原文**：REV-P6-4 Cancellation Orchestration —— 把「是否应该退款」的业务决策从 `Gateway.cancel`（隐式）上收到 **Cancellation Orchestrator**，统一 UNPAID → void/release/cancel（无退款）、PAID → durable refund request + cancel + restock。
- **背景（现状审计结论）**：
  - 当前唯一取消编排入口 `PallasTrade::Orders::Cancel`（DI `order_cancel_service`）：事务内写 durable `OrderCancellation`（reason/refund_payments/refund_amount/restock_items/notify_customer）→ `order.cancel!` → `Order#after_cancel` 无条件 `payments.completed.each(&:cancel!)`。
  - REV-P6-2 后各 gateway `cancel` 对 completed payment 已 durable 化（`Refunds::Request` 全 credit + 立即成功）——即 **PAID 订单一旦 cancel 必然隐式全额退款**，与 `OrderCancellation.refund_payments/refund_amount` 意图无关（这两个字段目前仅记录、不驱动行为）。这是「Gateway 决定业务是否退款」的错误 ownership（源 §30/§31、RISK-REV-04）。
  - 允许取消的面：标准流程 `pending/paid`（processing 后走售后/退款域）；legacy 仅 completed 未发货（shipment_state nil/ready/backorder/pending/canceled）。Stripe 失败/过期 webhook 直接 `order.cancel!`（UNPAID，无 completed payment → 无退款，行为正确）。
  - UNPAID 的 reservation release 已有且正确（`Orders::Cancel` 在取消时点判定 paid_or_in_flight? 后才 Release，INV-P3-4/FR-032-034）。
- **目标**：取消编排单点决策资金；PAID 退款由 orchestrator 按 durable intent 显式创建（尊重 `refund_payments`/`refund_amount`），provider I/O 仍全部走 `Refunds::ExecuteJob`（异步）；Order canceled 与 Refund processing 并存为合法状态（§35）。
- **成功指标**：任何取消路径（admin API v3 / admin legacy / stripe UNPAID webhook）不再存在「state 副作用自动建退款」；`refund_payments=false` 的 PAID cancel 不再产生 Refund；重复取消不产生第二笔 Refund；P0-P5 baseline + backend-rspec 全量绿。

## 2. 用户故事 / 场景

- 作为 **admin**，取消一笔已付款但未履约的标准订单，期望默认按原语义全额 durable 退款（requested → ExecuteJob 异步），而不是由状态机隐式决定。
- 作为 **admin**，取消已付款订单并选择「不退款」（例如仅误单取消、线下另退），期望订单 canceled 且 **不产生 Refund 行**、payment 保持 completed（§35 合法态）。
- 作为 **admin**，取消已付款订单并指定部分退款金额，期望 durable Refund(requested) 金额 = 指定值（≤ payment.credit_allowed）。
- 作为 **系统**，支付失败/过期（UNPAID，Stripe webhook）自动取消订单 → 无 Refund、无 Restock、reservation 正确 RELEASE（RV-R06）。
- 作为 **系统**，PAID 取消后重复触发（重试/重复点击）→ 不产生第二笔 Refund（RV-R07 no duplicate refund）。

## 3. 功能需求（FR）

- **FR-R64-101（决策上收）**：`Orders::Cancel`（= Cancellation Orchestrator，DI 入口不变）在订单事务内、`order.cancel!` **之前**，基于「取消时点 payment fact」做出退款决策：
  - UNPAID（无 completed payment / payment_total=0）→ 不建 Refund；后续 release/void 走现有路径（RV-R06）。
  - PAID（completed payment / combination captured）→ 默认创建 durable `Refund(requested)`（金额 = `refund_amount || payment.credit_allowed`，reason=order_canceled），经 `Refunds::Request`（绝不直接调 PSP；入队 ExecuteJob 在事务提交后）。
  - `refund_payments=false` 显式否决 → 不建 Refund（覆盖默认）。
- **FR-R64-102（移除 state 副作用退款）**：`Order#after_cancel` 删除 `payments.completed.each(&:cancel!)` 隐式退款分支；保留：void 未完成 payment（`void_transaction!`）、gift-card/store_credit 分支、`shipments.each(&:cancel!)`（restock REUSE，不动）、`update_with_updater!`、webhook/event。PAID 的 completed payment 在取消后保持 completed（退款由 FR-R64-101 的 requested Refund 承担）。
- **FR-R64-103（API 透传）**：Admin API v3 `PATCH /api/v3/admin/orders/:id/cancel` 与 legacy admin `PUT /admin/orders/:id/cancel` 支持可选 `reason/note/refund_payments/refund_amount/restock_items/notify_customer` 透传到 `Orders::Cancel`；`Order#canceled_by` 桥接新参数（向后兼容：不传 = 旧行为）。
- **FR-R64-104（幂等/防重）**：同订单重复取消（canceled 后再次触发）→ `order.cancel!` InvalidTransition 被服务捕获为 failure 且不产生第二笔 Refund；编排内 Refund 创建失败不导致订单半取消（事务整体回滚，抛 failure）。
- **FR-R64-105（durable evidence）**：`OrderCancellation` 行继续作为取消 intent/evidence owner（created_at=取消时点、含决策参数）；编排创建的 requested Refund 通过 `Refund.reason`（order_canceled）+ payment 关联可回溯；不新增 migration/state 字段（REV-P6-0 DB audit 前不做状态机扩展）。
- **FR-R64-106（组合边界）**：组合支付（PaymentCombination/split）成员订单的取消 + 冻结 split 退款已具备底座（REV-P6-3），完整组合取消编排（combination-level cancel event 路径核对）标注为本包**不做**，归 REV-P6-5/6-8 复核；本包保证不回归组合路径（baseline 绿）。

## 4. 非功能需求（NFR）

- 资金路径：取消事务内只做 durable 决策与落库；provider I/O 一律由 `Refunds::ExecuteJob`（REV-P6-2）异步执行，无同步 PSP。
- 向后兼容：所有既有调用（不传新参数）行为与现网等价（PAID 取消仍全额 durable 退款，只是来源从 state 副作用移到 orchestrator 显式创建）。
- 幂等/重放安全：重复取消、ExecuteJob 重试均不得产生第二笔 Refund / StockMovement。
- 无新 migration；无 Calculator 新增；不另起第二套 Restock（REUSE shipment.cancel）。

## 5. 验收标准（AC，与测试一一映射）

| AC | 源 | 验收条件 | 覆盖 FR |
|---|---|---|---|
| AC-R64-01 | RV-R06 | UNPAID cancel（标准 pending 无支付 / stripe 失败过期）→ order canceled、无 Refund 行、RESERVED → RELEASED | FR-R64-101/102 |
| AC-R64-02 | RV-R07 | PAID cancel（默认）→ durable Refund(requested, amount=payment.credit_allowed) + order canceled；completed payment 不再被 after_cancel 隐式 cancel；shipment cancel/restock 保留 | FR-R64-101/102 |
| AC-R64-03 | §35 | PAID cancel + `refund_payments=false` → 无 Refund 行、payment 保持 completed、order canceled（合法态） | FR-R64-101/103 |
| AC-R64-04 | §59 | PAID cancel + `refund_amount` 显式 < credit_allowed → requested Refund.amount = 指定值 | FR-R64-101 |
| AC-R64-05 | RV-R07 | 重复取消 → 不产生第二笔 Refund（canceled 再触发 failure 幂等） | FR-R64-104 |
| AC-R64-06 | — | API v3 + legacy cancel 透传参数生效；serializer/audit 可见（reason/refund 参数） | FR-R64-103/105 |
| AC-R64-07 | — | Stripe 失败/过期 webhook（UNPAID）`order.cancel!` 回归：仍无 Refund、无 reservation 误 Release 之外副作用 | FR-R64-102 |
| AC-R64-08 | AC-6030~6035 | P0-P5 baseline + backend-rspec 全量绿；组合支付回归绿 | 全部 |

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | cancel/OrderCancellation | 无宿主 override | 否——改框架层 |
| Core | `pallastrade_gems/pallastrade_core/app/` | Orders::Cancel / after_cancel / OrderCancellation / gateway cancel / reservation release | `services/pallastrade/orders/cancel.rb`（编排入口，UNPAID release 已有）、`models/.../order.rb`（after_cancel 隐式退款=要修点）、`models/.../order_cancellation.rb`、`models/.../payment/processing.rb`（cancel!/void）、`StockReservations::Release`、REV-P6-1/2 `Refund`/`Refunds::Request` | 部分——编排决策/隐式退款移除/参数生效需补 |
| API | `pallastrade_gems/pallastrade_api/app/` | cancel | `admin/orders_controller.rb#cancel`（canceled_by 无参数）、`fulfillments_controller.rb` | 部分——透传参数 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | cancel | `admin/orders_controller.rb#cancel`（canceled_by 无参数） | 部分——透传参数（或标注后续） |
| Storefront | `storefront/src/` | cancelOrder | 无客户侧取消入口 | 否（本包不改） |
| Platform | `platform/packages/` | order cancel | SDK 无 cancel 方法（仅 webhook 事件注释） | 否（本包不改） |

**结论**：`Orders::Cancel` 已是 durable-intent 唯一入口；本包把它升级为决策编排层 + 移除 `after_cancel` 的 gateway-owned 退款副作用 + API 透传决策参数。REV-P6-2 已保证资金异步；REV-P6-3 已保证 PAID 组合成员冻结退款语义。无重复能力需新建。Storefront/Platform 零改动。

## 7. 技术影响

- Core：`services/pallastrade/orders/cancel.rb`（决策矩阵 + 显式 `Refunds::Request`）、`models/pallastrade/order.rb`（`after_cancel` 移除 completed-payments 隐式 cancel）、`models/pallastrade/order_cancellation.rb`（读侧 helper/常量，如需）。
- API：`admin/orders_controllers` cancel 透传 + admin.yaml ×2（cancel 请求参数/说明）。
- Admin legacy：cancel action 透传（最小改动，可选本包）。
- 数据：无 migration。
- 回归面：所有调 `Orders::Cancel`/`canceled_by`/`order.cancel!` 的 spec（orders cancel、cancel_inventory、gateway cancel、reimbursement、P0-P5、stripe webhook 失败/过期）与组合支付回归。
- 文档：payments skill（REV-P6-4：Cancellation Orchestrator 语义 + 决策矩阵）、scenarios GS-062、admin.yaml ×2、PRD/REQ/README。

**风险**
- after_cancel 行为变更影响 legacy completed-unshipped cancel（原隐式全退 → orchestrator 显式默认全退，结果等价但创建时点/顺序变化）→ 用默认兼容 + 全量回归覆盖。
- 组合支付 primary/成员取消路径存在但完整组合编排本包不碰（边界明确，避免扩散）。
- 无资金语义倒推；回滚 = git revert（无 migration）。

## 8. 测试计划

**新增**
- `backend/spec/services/pallastrade/orders/cancellation_orchestration_spec.rb`：AC-R64-01~05（UNPAID 无退款 / PAID 默认 durable refund / refund_payments=false 无退款 / refund_amount 部分 / 重复取消幂等）。
- `backend/spec/requests/api/v3/admin/orders_controller_cancel_spec.rb`（或并入现有）：AC-R64-06 透传参数。
- `backend/spec/models/pallastrade/order_cancel_after_cancel_spec.rb`（或并入）：AC-R64-02/07 —— after_cancel 不再隐式退 completed payment；stripe UNPAID 回归。

**更新**
- `orders/cancel_inventory_spec.rb`、`orders cancel` 相关既有 spec、gateway cancel spec（completed 分支语义核对）、stripe 失败/过期 webhook spec、P0-P5 相关。
- 每 spec 头部标注 `# PRD-REV-P6-4 AC-R64-xx`。

## 9. 文档同步清单（知识同步门）

- [ ] API 文档：`backend/public/api-docs/admin.yaml` + `platform/docs/api-reference/admin.yaml`（cancel 参数/语义）
- [ ] Skill：`pallastrade-payments`（REV-P6-4：Cancellation Orchestrator + 决策矩阵 + after_cancel 语义）
- [ ] 场景库：`harness/scenarios/scenarios.json`（GS-062）
- [ ] 本 PRD 状态 + `docs/prd/README.md` 索引 + `harness doc-impact`

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-07 | 0.1 | 初稿（依据源 REV-P6 §30-38/§59/RV-R06/R07 + 2026-09-07 取消路径审计） | AI |
| 2026-09-07 | 0.2 | 实施：`Orders::Cancel`=Orchestrator（payment fact 决策 + 事务内 `Refunds::Request(enqueue:false)` + 提交后 ExecuteJob；refund_payments 三态；refund_amount 单笔限）；`after_cancel` 移除 PSP completed 隐式 cancel（store credit/void/restock 保留，fresh query）；API v3 cancel 透传 + `canceled_by` 桥接 + 服务 coalesce（reason/restock/notify）；`Refunds::Request` 加 enqueue 参数；新增 orchestration spec（6）与 orders_cancel request spec（3），回归组（cancel_inventory/refunds/组合/refunds controller）31 绿；admin.yaml×2 + payments skill REV-P6-4 + GS-063。 | AI |
| 2026-09-07 | 0.3 | 验证完成：commit `1149ff2`，gate 16/16 finished，提交前+提交后全量 backend-rspec 绿（EVD-…163204/…165357），recovery manual-only，doc-impact 通过，push dev 发布。 | AI |
