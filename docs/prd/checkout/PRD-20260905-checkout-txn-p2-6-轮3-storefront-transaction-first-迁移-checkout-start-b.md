# PRD-20260905-checkout-txn-p2-6-轮3-storefront-transaction-first-迁移-checkout-start-b

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-05 |
| 来源 | 需求：TXN-P2-6 轮3 storefront transaction-first 迁移（checkout/start BFF + order-payment action） |
| 分类 | checkout（自动判定） |
| 关联 Skill | pallastrade-storefront / pallastrade-payments / pallastrade-api-v3 |
| 关联 REQ | REQ-20260905-txn-p2-6-storefront-transaction-first.md |
| 关联 PRD | PRD-20260905-other-txn-p2-6-sdk-consumption.md（轮2，同 TXN-P2-6 包） |
| 需求类型 | 优化迭代（storefront 迁移，后端 API 契约已在轮1/轮2 落地） |

> 上游：`豆包梳理业务需求/P2 — Commerce Transaction Orchestration & Recovery.md` §42 Frontend 目标 / §57 TXN-P2-6 Storefront/API Migration。后端 TXN-P2-1..5、7、收口（serializer）、契约快照（轮1）、SDK 消费（轮2）均已完成并推 dev（HEAD bf2e296）。

## 1. 背景与目标

- **一句话需求原文**：TXN-P2-6 轮3 storefront transaction-first 迁移（checkout/start BFF + order-payment action）
- **背景**：P2 目标前端流向为 `Frontend → Start/Resume Transaction → Backend Transaction Coordinator → PaymentSession → Provider UI`。当前 storefront 仍是 **payment-session-first**：订单支付入口直接调用 `orders.paymentSessions.create`（BFF `POST /api/checkout/start` 与 `lib/data/order-payment.ts#createOrderPaymentSession`）。后端已提供 durable CommerceTransaction 启动入口 `POST /orders/:id/transactions`（Transactions::Start：quote 同意/幂等/快照冻结/委托 PaymentSessions::Start 并绑定 `transaction_id`），SDK 已在轮2 暴露 `orders.transactions.create` + `transactions.get`。
- **目标**：订单域支付入口改为 **transaction-first**——前端触发支付时先 Start durable CommerceTransaction，PaymentSession 变为该 transaction 的支付 attempt（AC-2006）；Provider UI（Stripe 自绘卡字段 / 会话跳转）保持独立不变。
- **成功指标**：P1 Checkout baseline（chk-p1-4-storefront / storefront vitest）全绿；标准流程 Stripe 卡支付路径仍走 `PaymentIntent → confirmCardPayment → complete`；409 业务码（quote 变更/未就绪）映射不回归。

## 2. 用户故事 / 场景

- 作为顾客（标准流程订单支付），我在统一下单页点 Pay Now：Cart update → submit → **Start CommerceTransaction（冻结快照 + 绑定 payment execution）** → Stripe 卡确认 / 会话跳转，行为与 P1 一致但资金路径有 durable 事务。
- 作为顾客（or_ 订单纯支付页），重试/换卡支付时同一商业意图只产生一个 active Transaction（后端幂等，AC-2002）；卡拒绝仅使 session failed、transaction 保持 payment_pending（INV-05）。
- 作为门店运营：quote 在用户确认后变化 → 409（quote_changed/checkout_version_conflict）→ 前端提示"报价已更新"+ 刷新 view，绝不静默带入新价格（INV-07 / AC-2001）。
- 边界：非会话支付方式（Check/COD/银行转账）不创建 transaction/session（保持现有直通完成页逻辑）；组合支付（PaymentCombination）不属本包（P2-6 后 combined strategy，RISK-01 Strangler 保持）。

## 3. FR / AC

| # | FR | AC（可测试） |
|---|---|---|
| FR-1 | BFF `POST /api/checkout/start` 在 `method.session_required` 分支改用 `orders.transactions.create`，把 `payment_execution` 作为会话返回给前端 | AC-1: 请求命中 `orders.transactions.create(orderId, { payment_method_id, external_data:{mode} }, checkoutOptions)` 恰好一次；响应含 `{ order, transaction:{id,state}, session:{id, external_data:{client_secret}} }`；无 `successor_cart` 泄漏 |
| FR-2 | BFF 响应携带 transaction 身份（id/state）供后续 resume/重试使用；PATCH complete 继续走 `orders.paymentSessions.complete`（session 仍为支付 attempt 对象，AC-2006/2007） | AC-2: 成功流 `session.id` = transaction 的 `payment_execution.id`；PATCH complete 仍调用 `paymentSessions.complete(order_id, session_id)` |
| FR-3 | 会话启动失败（含 409）保持 502/422 语义：返回 `order_id` 让前端可跳 payment-result 重试 | AC-3: transaction create reject → 502 `{order_id}`；未提交（400/403）不变 |
| FR-4 | `lib/data/order-payment.ts#createOrderPaymentSession`（OrderPaymentContent 的 server action）内部改为 transaction-first：`orders.transactions.create`（透传 external_data/mode）→ 返回 `payment_execution` 作为 session | AC-4: Stripe 卡流 `mode:'payment_intent'` 时 `payment_execution.external_data.client_secret` 可被 `extractSessionClientSecret` 消费并 `confirmCardPayment` |
| FR-5 | 409 业务码前端映射：`quote_changed` 与既有 `checkout_version_conflict` 同样 → toast「报价已更新」+ `refreshView()`，不自动支付（INV-07） | AC-5: OrderPaymentContent 收到 `code:'quote_changed'` → 重取 view、不 complete/不跳转（与 checkout_version_conflict 测试同型） |
| FR-6 | 非会话支付方式 / 已 paid 短路等既有行为不变 | AC-6: 无 `session_required` 方法 → 不调 transactions.create；`state=paid/completed` 仍直接跳完成页 |

## 4. 跨层搜索结果（R4/Step 0，6 层独立）

| 层 | 搜索路径 | 结果 |
|---|---|---|
| backend/app | backend/app/** | 无 host 交易/支付启动代码（P2 后端全部在 gems）；无重复实现 |
| Core | pallastrade_core | `Transactions::Start`（quote 同意/幂等/快照/委托 PaymentSessions::Start + attach session.transaction_id）已在（TXN-P2-2） |
| API | pallastrade_api | `store/orders/transactions_controller.rb#create`（POST /orders/:id/transactions → Start）＋ `store/transactions_controller.rb#show`（GET /transactions/:id，require_authentication!，customer scope）；`orders/payment_sessions_controller#complete` 已接 OnPaymentSuccess/事务完成 |
| Admin | pallastrade_admin | 无交易相关（P2-7 Admin 延后） |
| Storefront | storefront/src | session-first 调用点仅 2：`app/api/checkout/start/route.ts#POST`（order 域 BFF）、`lib/data/order-payment.ts#createOrderPaymentSession`（order 域 server action）；`lib/data/payment.ts` 为 cart 域 legacy（express/legacy 页面，不改）；组件经 fetch/action，不直连 SDK |
| Platform | platform/packages | SDK 轮2 已含 `orders.transactions.create`（store-client ~L712）+ 顶层 `transactions.get`（L376）+ `OrderTransactionStart/TransactionResume/CreateOrderTransactionParams` types（已提交 bf2e296） |

结论：后端契约 + SDK 消费已就绪，本包只改 storefront 两处入口 + 组件错误码映射 + 测试。

## 5. 技术方案

1. `route.ts#POST`：`PaymentSession` 局部类型改为 payment execution 结构（`NonNullable<OrderTransactionStart['payment_execution']>`）；session 创建改为 `orders.transactions.create`；响应体增加 `transaction: { id, state }`，`session` = `payment_execution`。PATCH 不动。
2. `route.test.ts`：mock 改为 `orders.transactions.create`（返回 OrderTransactionStart 形状含 payment_execution）；断言 create 参数/响应含 transaction 与 session；失败用例 502 不变。
3. `order-payment.ts#createOrderPaymentSession`：内部走 `orders.transactions.create`；成功返回 `{ success:true, session: payment_execution, transaction:{id,state} }`（返回类型放宽，消费端按需取 session.id/external_data）；`completeOrderPaymentSession*` 保持 `paymentSessions.complete`。
4. `OrderPaymentContent.tsx#handleSessionCreateError`：`quote_changed` 并入既有分支 → quoteUpdated toast + refreshView；其余 code 走通用错误。
5. 测试：route.test.ts 更新 + OrderPaymentContent.test.tsx 增补 quote_changed 用例；跑 storefront vitest。

## 6. 测试计划

- 更新：`storefront/src/app/api/checkout/start/__tests__/route.test.ts`
- 增补：`storefront/src/components/checkout/__tests__/OrderPaymentContent.test.tsx`（quote_changed → 刷新不支付）
- 回归：storefront vitest（checkout 相关）；`harness e2e storefront`（时间允许）

## 7. 文档同步清单（doc-impact / §7）

- `ai/skills/pallastrade-storefront/SKILL.md`：§Checkout/CHK 变更记录新增 TXN-P2-6 轮3 条目（storefront 代码变更→skill 同步）
- `ai/skills/pallastrade-payments/SKILL.md`：changelog 增补（若 storefront 语义值得记录）
- `docs/prd/README.md`：本 PRD 索引行
- storefront API 无 OpenAPI 影响（BFF 内部路由，非 Store API surface）

## 8. 变更记录
- 2026-09-05 轮3：创建（checkout/start BFF + order-payment action transaction-first；用户「继续」确认）。
