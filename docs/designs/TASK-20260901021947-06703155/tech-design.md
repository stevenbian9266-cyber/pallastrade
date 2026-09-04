# 技术设计 — 正向下单与支付关键链路强化

> Task：`TASK-20260901021947-06703155`  
> Gate：`GATE-2026-09-01T02-20-03`  
> PRD：`PRD-20260830-checkout-下单链路规范化统一化-场景a-b统一下单页-场景c收银台弹窗-参考阿里国际站`

## 1. 目标与边界

本次把“创建订单、发起支付、支付确认、结果展示”设计为可恢复的正向 Saga：A/B/C 一次 Pay，D 只支付既有订单。Order 是交易真相，PaymentSession/PaymentCombination 是支付尝试载体，Cart 只保存结算前意图。

不新增 Order 状态，不把网关请求放入数据库事务，不重写拆单、组合记账、退款或 Stripe webhook 完成链路。

## 2. 目标调用链

```text
Browser / UnifiedCheckout
  └─ POST same-origin /api/checkout/start
       ├─ validate Origin + cart cookie/user context
       ├─ SDK PATCH cart（地址/物流/selected items）
       ├─ SDK POST cart submit（业务幂等）
       │    └─ Carts::Submit
       │         ├─ cart.with_lock
       │         ├─ active → authoritative recalc → Order + snapshot
       │         ├─ converted + source order → replay same Order
       │         └─ after commit → order.submitted side effects
       └─ SDK POST order payment_sessions
            └─ PaymentSessions::Start
                 ├─ order.with_lock + ownership/amount/state recheck
                 ├─ reuse matching active session
                 └─ provider create with stable idempotency key

Browser
  ├─ Stripe.confirmCardPayment(client_secret)
  ├─ API complete session（幂等）/ webhook（最终兜底）
  └─ /payment-result/{or_|pcom_}
```

## 3. Core 设计

### 3.1 `Carts::Submit`

- 将 active 状态校验移动到 `cart.with_lock` 内，避免检查与转换之间的竞态。
- converted Cart 若存在来源 Order，返回同一 Order 作为成功 replay；不存在来源时返回稳定业务错误。
- 保持服务端重新计算价格、库存、地址和物流校验。
- 事务完成后再发布 `order.submitted`；事件失败不得回滚已创建订单或阻止支付。
- 部分结算时，Order 只快照 selected items；未选项迁移到 successor active Cart。提交响应返回 `order` 与可选 `successor_cart`。

来源 Order 优先复用现有 `order.cart_id`/关联能力；若当前 schema 无可靠唯一约束，则先使用既有关联和锁，不为本需求引入新状态。并发 spec 必须证明同一 Cart 最终只有一个来源 Order。

### 3.2 `PaymentSessions::Start`

- 以领域服务统一订单支付会话的 create/reuse，不由 API controller 直接调用网关。
- 锁内复核 `current_store`、订单归属、`balance_due`、币种、支付方式可用性。
- active 定义采用模型现有 pending/processing 语义；成功、失败、取消、过期会话不复用。
- provider idempotency key 使用稳定的 `order + payment_method + operation generation` 派生值，保存/关联到本地会话；网关响应丢失后重试不会生成第二个 PaymentIntent。

## 4. API 与权限

- `POST /api/v3/store/carts/:id/submit` 保持 REST 边界，响应扩展可选 `successor_cart`；缓存型 `Idempotency-Key` 保留为请求重放优化。
- `POST /api/v3/store/orders/:id/payment_sessions` 委托 `PaymentSessions::Start`。
- Customer orders 列表改为当前店铺、当前用户的 submitted/completed 订单集合，不再以 `.complete` 排除待支付订单。
- 所有订单、会话、组合查询继续经 `current_store + current_user/token`；禁止 email 兜底匹配。
- 若公共响应 schema 变化，同步 OpenAPI、SDK 与 generated files。

## 5. Storefront 编排

- `UnifiedCheckout` 继续预渲染 Classic Stripe Elements 卡表单；预渲染不创建 Order/PaymentIntent。
- Pay Now 客户端调用同源 Route Handler。Route Handler 使用服务端 SDK，校验 Origin/CSRF，并返回 `{ order, payment_session, successor_cart? }`。
- 获得 client secret 后，页面在同一点击流程中确认支付。成功、失败、取消、无法判定均跳统一结果页。
- 若 Order 已创建但 session 启动失败，Route Handler 返回可恢复 `order_id`；浏览器进入该订单结果页，Retry 继续原订单。
- successor Cart 存在时更新 current cart cookie；Buy Now 的独立 Cart 不污染普通购物车。
- D 场景弹窗不调用 checkout-start/cart submit；支付结束导航到同一结果页。

## 6. 统一结果页

- 新路由 `/payment-result/[targetId]` 支持 `or_` 与 `pcom_`。
- 服务端查询确定 success/failed/canceled/pending；query string 只能携带非权威提示。
- failed/canceled 的 Retry 进入原订单支付流程或重新打开同一组合，不创建 Order。
- 旧 `/order-placed/[id]` 与 `/checkout/[or_id]` 保留兼容，重定向或复用统一展示。

## 7. 测试设计

- Core specs：重复/并发 submit、converted replay、successor Cart、事件提交后发布。
- Payment specs：活动会话复用、终态新建、稳定 provider key、complete/webhook 双通道幂等。
- API request specs：订单可见范围、越权 404、submit/session 响应。
- Storefront Vitest/RTL：A/B/C 一次 Pay、D 不 submit、successor cookie、四类结果态、Retry 原订单。
- E2E：Add Cart、Buy Now、selected Cart、account single/multi；覆盖成功、拒付/失败、取消、双击/重试。

## 8. 迁移与回滚

- 优先无 schema 变更；若唯一约束缺失导致无法证明并发正确性，必须单独提出 migration 设计并再次审查。
- 旧 checkout/order-placed 路由作为兼容回退面，先不删除。
- 人工恢复计划由 Harness 绑定 Task 创建并在完成前验证。

## 9. Go/No-Go 检查

- Go：业务正确性由持久化锁/关联保障，网关在事务外，D 不创建订单，结果态由服务端决定，回滚入口保留。
- No-Go：需要依赖 email 匹配、Rails.cache 保证唯一性、浏览器金额、事务内网关调用、或无法证明同 Cart 单 Order 时停止实施并重新设计。
