# CHK-P1-3 — Server Readiness / CheckoutSnapshot / Payment Start Gate

> 日期：2026-09-03 ｜ PRD：`PRD-20260903-checkout-chk-p1-1...`（§12 CHK-P1-3）
> Task：`TASK-20260903141927-b2e41335`；Gate：`GATE-2026-09-03T14-19-49`
> 范围（用户确认，vscode_askQuestions 2026-09-03）：Readiness + Snapshot + Payment Start Gate（Start 内部）+ PaymentSession 记录 price_version（external_data，无 migration）；过期自动 Refresh；409 CHECKOUT_VERSION_CONFLICT 留后续。

## 1. 新增服务（core `order_checkout/`）

| 服务 | 行为 |
|---|---|
| `OrderCheckout::Readiness` | 只读聚合（**不复制校验规则**）：`email`(contact)、`requires_ship_address?/ship_address`(shipping_address，digital 免)、`shipments selected rate`(delivery_rate，无 shipments 免)、`amount_due > 0`(balance) → `Result{ ready, missing_requirements }` |
| `OrderCheckout::Snapshot` | 只读确定性 transaction projection：`CheckoutSnapshot` 冻结值对象（order_id/number/state/currency/checkout_version/price_version/checkout_expires_at + 权威金额列 to_s）+ `fingerprint`（SHA256([order_id,checkout_version,price_version,currency,amount_due])[0,16]）。不落库。 |

## 2. Payment Start Gate（`PaymentSessions::Start` 内部，quote 作用域）

- **激活条件** `gate_active?`：`standard_flow? && !completed? && checkout_expires_at.present?`（已有 quote）。
- **过期** → 自动 `OrderCheckout::Refresh`（Recalculate + 续期）→ 以新权威金额继续；`quote_refreshed: true` 入 session external_data（客户端可感知金额/版本变化）。
- **就绪拦截**：Readiness 缺 `contact/shipping_address/delivery_rate` → `failure({code:'checkout_not_ready', message:, missing_requirements:})`，不建会话。
- **直通**：无 quote 标准流订单 / legacy cart / completed 账户补付 → 行为与 P1-2 前完全一致（P0 回归不破坏）。
- **新会话记录**：锁内权威 `price_version` merge 入 `external_data`（无 migration）；`quote_refreshed` 仅真刷新时写入。
- 幂等契约不变：operation_key/reuse（mode+amount+窗口）/二次锁 reconcile 均未改。

## 3. API / View

- CheckoutView 暴露 `ready` / `missing_requirements`（委托 Readiness，零副作用）；`CheckoutSerializer` 输出 `ready`(boolean) + `missing_requirements`(Array<string>)。
- `error_handler#render_service_error` 结构化分支把 `{code:,message:}` 之外的键（如 `missing_requirements`）透传 `details`（既有 details 字段，零破坏）。
- `orders/payment_sessions_controller#create` 改传 `result.error`（ResultError 本体）——String/AR errors 渲染与之前一致；Hash 结构化错误（checkout_not_ready）渲染 code+details。

## 4. 测试结果

- 新增：readiness_spec 8、snapshot_spec 6、start_spec P1-3 gate 4 例；view/serializer 各 +2。
- 全套（chk-p1-3-rspec 文件集）绿：readiness+snapshot+versioning+view+mutation+start+serializer+checkout_controller+order_payment_sessions+cart_payment_sessions+carts。
- RuboCop 0；payment controllers 回归 23/23 绿。

## 5. DEFERRED

- **409 CHECKOUT_VERSION_CONFLICT**（客户端带期望 version/price_version 比对 → 409 + 最新 CheckoutView）→ 后续包。
- Storefront 消费 ready/missing_requirements/quote_refreshed（Pay 按钮禁用/刷新提示）→ P1-4。
- CheckoutSnapshot 由 P1-4/409 流消费（本轮为服务 + spec 基座）。
