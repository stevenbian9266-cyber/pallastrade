# CHK-P1-4B — Storefront mutation 前端消费 + 409 UI

> 日期：2026-09-04 ｜ PRD：`PRD-20260903-checkout-chk-p1-1...`（§12 CHK-P1-4B）
> Task：`TASK-20260903171925-67152487`；Gate：`GATE-2026-09-03T17-19-38`
> 范围（用户确认 2026-09-04）：数据层 + or_ 页编辑 UI（复用 AddressFormFields/rate 单选）+ 409 前端处理 + PRD ApplyPromotion 标注。

## 1. SDK / 数据层

- SDK `orders.checkout.update(orderId, params)`（`CheckoutUpdateParams`：contact{email}/shipping_address(_id)/delivery_rate_id 其一）→ 最新 `CheckoutView`；构建 + `.sdk-vendor` 刷新。
- `lib/data/order-checkout.ts`：`updateOrderCheckout`（server action，成功 {view} / 失败 {code?, error}，PallasTradeError.code 透传）。
- `lib/data/order-payment.ts`：`createOrderPaymentSession` 失败时透传 `code`（如 checkout_version_conflict）——行为兼容（成功分支不变）。

## 2. OrderPaymentContent（or_ 页）编辑 UI + 409

- 物流：`effectiveView.fulfillments[].delivery_rates` radio 编辑 → PATCH delivery_rate_id → 采用服务端最新 view（金额/ready/version 同步）。
- 地址：内联 AddressFormFields（countries 由页面 loader 解析传入；states 用 useCountryStates+getCountry）→ PATCH shipping_address。
- 409：会话创建失败 `code=checkout_version_conflict` → toast「订单已更新」+ `getOrderCheckout` 刷新 view（不自动支付）。
- liveView state：服务端 view 可被编辑/409 刷新覆盖（回退 props.view/order 不变）。
- i18n：edit/cancel/save/saved/shippingMethod/quoteUpdated/failedToUpdateCheckout/addressHint（checkout 组，5 locale，parity OK）。

## 3. PRD 对齐

- §12 CHK-P1-1B 标注 `ApplyPromotion`/billing DEFERRED（消除 PRD-实施不一致）。

## 4. 测试结果

- storefront typecheck 0；biome 0；check:locales sync。
- OrderPaymentContent 10/10（新增：delivery PATCH / address PATCH / 409 refresh）；checkout 相关 28/28（含 PaymentCheckoutModal/UnifiedCheckout 回归）。
- SDK typecheck/build OK。

## 5. DEFERRED

- 4C：legacy 退役重构 / 组合支付双实现收敛 / 孤儿页移除。
