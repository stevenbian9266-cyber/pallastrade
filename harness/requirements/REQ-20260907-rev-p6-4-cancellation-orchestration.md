# REQ-20260907-rev-p6-4-cancellation-orchestration — Cancellation Orchestration

> 关联 PRD：`docs/prd/payments/PRD-20260907-payments-rev-p6-4-cancellation-orchestration-取消业务决策上收-unpaid-void-pai.md`（approved）
> 源规格：`豆包梳理业务需求/P6 — Refund, Cancellation & Dispute Orchestration.md`（REV-P6 §30-38/§59/RV-R06/R07）
> Task：`TASK-20260907154853-ba96412a`；Gate：`GATE-2026-09-07T15-49-07`（feature，risk=critical）
> 分支：dev @ 599850d（REV-P6-1/2/3 已合入）

---

## Step 0：跨层搜索（六层，gate 强制）

| 层 | 路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | cancel / OrderCancellation | 无宿主 override | 否——改框架层 |
| Core | `pallastrade_gems/pallastrade_core/app/` | Orders::Cancel / after_cancel / gateway cancel / release | `services/.../orders/cancel.rb`（编排入口+UNPAID release）、`models/.../order.rb`（after_cancel 隐式退款=改点）、`order_cancellation.rb`、`payment/processing.rb`、`Refunds::Request`(REV-P6-2) | 部分——决策矩阵/隐式退款移除/参数生效需补 |
| API | `pallastrade_gems/pallastrade_api/app/` | cancel | `admin/orders_controller.rb#cancel`（无参数） | 部分——透传 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | cancel | `admin/orders_controller.rb#cancel` | 部分——透传（最小） |
| Storefront | `storefront/src/` | cancel | 无客户侧取消 | 否 |
| Platform | `platform/packages/` | cancel | SDK 无 cancel | 否 |

### 搜索结论

`Orders::Cancel` 是唯一 durable intent 入口（admin v3/legacy 都经它）；`after_cancel` 隐式 completed-payment cancel（REV-P6-2 后=durable 全退）为要修点；Stripe UNPAID 失败/过期 webhook 直接 `order.cancel!`（无退款，回归保护）。本包：Cancel 升级决策编排 + after_cancel 显式化 + API 透传参数。无重复能力。

## Step 1：Skill 文件咨询

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `pallastrade-customization` | ✅ 已读（REV-P6-1~3） | 行为用服务/事件；自持 gem 内改 |
| `pallastrade-payments` | ✅ 已读 | REV-P6-1/2/3 章节；本包将追加 REV-P6-4 |
| `harness-prd` | ✅ 已读 | PRD 流程 |

---

## 需求标题

REV-P6-4：Cancellation Orchestration —— 把「是否退款」决策从 Gateway/state 副作用上收到 `Orders::Cancel`（=Orchestrator）；PAID 默认显式 durable refund、`refund_payments=false` 不退款；API 透传决策参数。

## 任务类型

优化迭代（feature gate，risk=critical）

## 需求描述

1. `Orders::Cancel`：取消时点 payment fact 决策 → PAID（默认/`refund_payments`）在 `order.cancel!` 前经 `Refunds::Request` 建 durable `Refund(requested)`（金额 = `refund_amount || payment.credit_allowed`）；UNPAID 无退款；`refund_payments=false` 显式否决；provider I/O 只走 ExecuteJob。
2. `Order#after_cancel`：删除 `payments.completed.each(&:cancel!)` 隐式退款；保留 void 未完成/store_credit 分支 + `shipments.each(&:cancel!)`（restock）+ updater/webhook/event。
3. Admin API v3 + legacy cancel：可选 `reason/note/refund_payments/refund_amount/restock_items/notify_customer` 透传；`canceled_by` 桥接（向后兼容）。
4. 幂等：重复取消不产生第二笔 Refund；Refund 创建失败整体回滚。
5. 组合路径/OrderCancellation 状态机扩展不做（边界），baseline 回归保护。

## 影响范围

- Core：`services/pallastrade/orders/cancel.rb`、`models/pallastrade/order.rb`（after_cancel）、`order_cancellation.rb`（读侧/决策默认）。
- API：`admin/orders_controller.rb` cancel 透传 + admin.yaml ×2。
- Admin legacy：cancel 透传（最小）。
- 测试：orchestration spec + controller 透传 spec + after_cancel/UNPAID 回归 spec + 既有 cancel/gateway/stripe webhook/组合 spec 适配。
- 文档：payments skill（REV-P6-4）、scenarios GS-062、admin.yaml ×2、PRD/REQ/README。

## 技术方案（初步）

- `Orders::Cancel` 内：`release_allowed`（已有 paid_or_in_flight? 判定）之前新增 `refund_decision`：
  ```ruby
  def call(order:, ..., reason:, refund_payments:, refund_amount:, ...)
    # refund 决策在事务内、cancel! 前
    order.transaction do
      order.cancellations.create!(...)
      build_refund_if_decided(order, refund_payments, refund_amount, reason) # PAID 默认 true
      order.cancel!  # after_cancel 不再退 completed
    end
  end
  ```
  组合/多 payment：默认对每笔 completed payment 建 refund（credit_allowed）？——先限定单 payment 默认 credit_allowed、多 payment 每笔 completed 一笔（与旧 after_cancel each 语义一致），`refund_amount` 仅在单 payment 场景可用（多 payment 时 amount 平分/校验，取严格；具体实施按 spec 核对）。
- after_cancel 删除 completed cancel 分支后，需确认 update_with_updater! 对 canceled+completed payment 的 payment_state 输出（回归观察）。

## 风险点

- after_cancel 行为变更（legacy completed-unshipped cancel 原隐式全退 → orchestrator 默认全退，等价但时点不同）——默认兼容 + 全量回归。
- 多 payment/组合的 amount 语义边界（本包按每 completed payment 一笔默认全额；复杂 amount 平分不引入）。
- 回滚：git revert；无 migration/数据迁移。

## 决策节点（用户已确认 2026-09-07「实施」）

1. PAID 默认仍全额 durable 退款（显式化，兼容）；2. `refund_payments=false` 真正生效；3. after_cancel 移除隐式退款 + API 透传；4. 组合编排/OrderCancellation 状态机不做（边界）。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| Core | `orders/cancel.rb`/`order.rb` | orchestration/after_cancel/UNPAID 回归 spec | | ⬜ |
| API | controller | 透传 request spec | | ⬜ |
| 全量 | — | backend-rspec verifier + P0-P5 + doc-impact | | ⬜ |

### 验证结论

（实施后回填）
