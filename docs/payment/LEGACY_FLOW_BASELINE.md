# LEGACY_FLOW_BASELINE（P0-7 / FR-072）

> 目的：盘点 Legacy（Cart 域）支付的真实代码入口与现状，为「是否/如何迁移」提供依据，
> 而非凭感觉删除。**不删除 Legacy**；只明确 Compatibility Only + 用量可统计。

## 1. Canonical vs Legacy 边界

| 流 | 域 | 声明 | 后端入口 |
|---|---|---|---|
| Canonical Standard | Order 域（submit 后 `or_` Order） | 唯一新增支付能力去向 | `POST /api/v3/store/orders/:id/payment_sessions` → `PaymentSessions::Start` |
| Legacy（Compatibility Only） | Cart 域（Order state=cart / Express） | 存量兼容；**禁新增支付 Feature** | `POST /api/v3/store/carts/:cart_id/payment_sessions` → `PaymentSessions::Start`（P0-3 起复用，幂等已拉齐） |

## 2. Legacy 入口清单（真实代码路径）

| # | 场景 | Storefront 入口 | 后端落点 | 备注 |
|---|---|---|---|---|
| L1 | **Express Checkout**（Apple/Google Pay） | `ExpressCheckoutButton.tsx` → `express-checkout-flow.ts` server actions | cart 域 `paymentSessions.create` + `complete` + `carts.complete` | P0-3 幂等 + P0-4 金额权威已覆盖 |
| L2 | **Legacy 一页式兜底**（旧购物车/灰度未切） | `CheckoutPageContent.tsx` + `PaymentSection.tsx`（`createCheckoutPaymentSession`/`confirmPaymentAndCompleteCart`） | 同上 cart 域 | 进页建 `cs_` 会话 → confirm → complete |
| L3 | **离站 redirect 返回** | `confirm-payment` / `payment-result` 页 | cart 域 `paymentSessions.complete`（redirect_result / session_result） | 统一走 cart 域 complete |
| L4 | 组合支付（P5）legacy 分支 | PaymentCheckoutModal | `carts.paymentSessions.complete`（`payment_combination` 分支） | 与 Order 域并存 |

> 新 Cart 实体（`PallasTrade::Cart`，`cart_` 前缀）走 submit → Order 域，**不是** Legacy。

## 3. Usage Metric（FR-071）

- 位置：`Carts::PaymentSessionsController#create`（所有 legacy 会话创建共用咽喉）。
- key：`payment.legacy_flow.used`
- 字段：`flow_type` / `entry_point` / `payment_method_id` / `order_id`（cart legacy order）
- 查询示例（JSON 结构化日志）：
  ```text
  count by message=payment.legacy_flow.used, entry_point=<express_checkout|legacy_one_page|unknown>
  ```
- 覆盖说明：Express 与一页式都会经此 create 计一次；redirect 返回的 complete 未单独计（由会话归属可回查）。

## 4. 开放项

- entry_point 为后端启发式（external_data：return_url → one_page；stripe_payment_method_id → express）；服务端无法区分时归 `unknown`。若需精确归因，可在 SDK 层透传 `flow_type` 参数（后续）。
- redirect/complete 层面的调用量若需单独指标，可在 `Carts::PaymentSessionsController#complete` 追加同类 log（本期未加，避免噪音）。

## 5. 决策依据（后续迁移时）

1. 用 metric 统计周期内 L1/L2/L3 流量占比 → 决定 Legacy 退役顺序（预计 Express 优先迁 Order 域，需 submit+Start 语义改造）。
2. 迁移任一场景前，以本文档入口清单 + P0-0 基线测试为回归锚点。
