# REQ-20260905-txn-p2-6-storefront-transaction-first — TXN-P2-6 轮3 storefront 迁移

- 关联 PRD：docs/prd/checkout/PRD-20260905-checkout-txn-p2-6-轮3-storefront-transaction-first-迁移-checkout-start-b.md（approved，用户「继续」确认）
- 任务：TASK-20260905031630-e6314687
- Gate：GATE-2026-09-05T03-17-03
- 类型：feature / risk critical（资金链路 storefront 迁移）

## 目标
订单域支付入口从 payment-session-first 迁到 transaction-first（P2 §42/§57）：
Start CommerceTransaction → PaymentSession(attempt) → Provider UI 独立；PATCH complete 仍 paymentSessions.complete。

## Skill 表（真读结论）
| Skill | 结论 |
|---|---|
| pallastrade-customization | storefront 消费只经 SDK canonical client（AP-002）+ server action/route handler；本包为宿主 storefront 应用代码，无框架 customization 需求（非 gem 改造） |
| pallastrade-storefront（domain） | 「Don't hand-write fetch；用 @pallastrade/sdk」；client 组件不得 import barrel；SDK 调用走 "use server" action（getClient 仅服务端）；本包 BFF route + order-payment action 均服务端，合规 |
| pallastrade-prd | 一句话需求→PRD 流程（查重 prd new 通过→ approved；用户已「继续」确认） |
| pallastrade-payments（补充 domain） | PaymentSessions::Start/PaymentSession 语义：transactions.create 委托 Start 并绑定 transaction_id；orders/payment_sessions#complete 已接 OnPaymentSuccess→Finalize；前端 complete 不驱动则订单停留 pending（须保持 complete 调用）；card 流 client_secret 经 external_data.payment_intent 透传 |

## 实施
1. `storefront/src/app/api/checkout/start/route.ts#POST`：session_required 分支改 `orders.transactions.create(orderId,{payment_method_id,external_data?},checkoutOptions)`；`session` = `payment_execution`；响应加 `transaction:{id,state}`；PATCH 不动。
2. `storefront/src/app/api/checkout/start/__tests__/route.test.ts`：mock transactions.create（OrderTransactionStart 形状），断言/失败用例更新。
3. `storefront/src/lib/data/order-payment.ts#createOrderPaymentSession`：内部走 transactions.create（透传 external_data/mode）；成功返回 payment_execution 作为 session（+transaction meta）；complete* 保持 paymentSessions.complete。
4. `OrderPaymentContent.tsx#handleSessionCreateError`：`quote_changed` 与 checkout_version_conflict 同分支（quoteUpdated toast + refreshView）。
5. `OrderPaymentContent.test.tsx` 增补 quote_changed 用例。

## 验证
- storefront vitest（route.test.ts + OrderPaymentContent.test.tsx + checkout 相关）全绿
- tsc / biome（storefront lint）全绿
- 代码路径核对：payment_execution.external_data.client_secret 仍可被 extractSessionClientSecret 消费

## 收尾
prep（user-confirmed 以用户「继续」授权清除）→ 实施 → 验证 → evidence（review/knowledge + verifier）→ coverage-gate → commit（单引号）→ 重跑 verifier（staged/HEAD）→ finish → push dev（doc-impact：storefront 代码→storefront SKILL/E2E）。
