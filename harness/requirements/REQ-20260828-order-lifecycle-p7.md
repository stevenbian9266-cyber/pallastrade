# REQ-20260828-order-lifecycle-p7 — 逆向链路售后父子单化（flag 灰度）

> 对应 PRD：`docs/prd/checkout/PRD-20260828-checkout-p7-逆向链路售后父子单化-flag-灰度.md`
> Task：`TASK-20260828141537-72f726ec` ｜ Gate：`GATE-2026-08-28T14-16-02`（Risk: critical）

---

## Step 0：跨层搜索（已执行，详见 PRD §6）

**结论**：售后底链（RA→CR→Reimb→Refund）完整可复用；父子场景需修复 3 个 Core 单订单假设：
1. `OriginalPayment.reimburse` 用 `order.payments.completed`（拆单/组合支付子订单无本地 payment → 无法退款）
2. `Refund#update_order` 用 `payment.order`（组合支付 payment.order 为 nil → 报错）
3. `Refund` `delegate :order, :currency, to: :payment` + `editable?`（组合支付 nil）

另需父订单批量售后服务 + Admin 入口。**不新建售后框架**。

## Step 1：Skill 文件咨询

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读（本会话 P6） | 决策树：Settings → Config → Events → Dependencies → Admin/Ransack → Generators → Decorators → Extensions。P7 用 Config flag（第 2 档）+ Admin 直接改 gem 视图 + Core 模型/服务修复。 |
| `ai/skills/pallastrade-payments/SKILL.md` | ✅ 已读 | Refund 链：`Payment(completed) → Refund`，`create!` after_create 自动执行网关退款 + 写 transaction_id；售后链 `RA → CR → Reimbursement → Refund / StoreCredit`；PaymentSplit `credit_allowed = captured_amount - refunded_amount`（P1）。 |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读（本会话 P6） | 阶段 0-1：prd new → 6 层搜索 → 模板扩充 → 用户"实施"确认。 |

**按需 Skill（本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-checkout` | ✅ | ✅ 已读（P5/P6 会话 + 本会话 grep） | 订单状态机 `complete` 后 admin 仍可调整（refunds/return authorizations 走专用 controller）；订单完成链路 P2-P6 段已同步。 |
| `pallastrade-admin` | ✅ | ✅ 已读（本会话 P6） | Admin = ERB engine；订单详情 `_header` dropdown 扩展；`_parent_child_tree` partial 挂订单页。 |
| `pallastrade-events-webhooks` | ✅ | ⬜（沿用既有） | 售后事件（order.returned 等）父子场景沿用现有发布机制，P7 不改事件。 |

---

## 需求标题

子订单可通过现有售后链（RA→CR→Reimb→Refund）退款（资金在组合/共享 payment，退款更新 `PaymentSplit.refunded_amount`）；Admin 可对父订单批量发起子订单售后。flag 灰度。

## 任务类型

新功能（flag 默认关闭）

## 需求描述

1. **P7a Core 修复**（子订单退款链路）：
   - `OriginalPayment.reimburse`：`order.payments.completed` 为空时从 `order.payment_splits` 取关联 payment 退款
   - `Refund#update_order`：`payment.order` nil（组合）→ 更新对应子订单 `PaymentSplit.refunded_amount` + 子订单 updater
   - `Refund` `order`/`currency`/`editable?`：组合支付时从 reimbursement→customer_return 推导
2. **P7b 父订单批量售后**：`PallasTrade::Returns::ParentOrderReturns` 服务（展开 children → 每子订单建 RA + return_items）；Admin 父订单详情批量售后入口 + 创建页
3. **flag**：`store.preferred_returns_parent_order_handling` / `Config[:returns_parent_order_handling]`，默认 false

## 验收标准

- AC-001~003 → `backend/spec/models/pallastrade/reimbursement_type/original_payment_child_spec.rb`
- AC-004 → `backend/spec/services/pallastrade/returns/parent_order_returns_spec.rb`
- AC-005 → `backend/spec/requests/admin/parent_order_returns_spec.rb`
- AC-006 → 现有售后 spec 回归

详见 PRD §5。

## 实施要点

- **pallastrade_core**：`reimbursement_type/original_payment.rb`（split 取 payment）；`refund.rb`（update_order split 分支 + delegate/editable? fallback）；新增 `services/pallastrade/returns/parent_order_returns.rb`；`store.rb`/`configuration.rb`/`initializers/pallastrade.rb` flag
- **pallastrade_admin**：`orders_controller.rb`（+parent_order_returns 入口/创建）+ `views/.../orders/parent_order_returns.html.erb` + `_header.html.erb` 入口 + locales
- **无新迁移**；**无新 API 端点**（P7 为 Core 修复 + Admin UI）

## 测试计划

- 新增 `original_payment_child_spec.rb`、`parent_order_returns_spec.rb`（service + request）
- 回归现有售后 spec

## 文档同步

- Skill：checkout（子订单售后 + 父订单批量）、payments（split.refunded_amount 退款）、admin（批量售后入口）、events-webhooks（如涉事件）
- 升级方案 P7 段标记完成；PRD §9/§10；docs/prd/README.md 索引
