# 修复：支付表单预显示、Pay selected 报错与结算摘要布局

## Step 0：跨层搜索

| 层 | 结论 |
|---|---|
| `backend/app/` | 只有生成的支付会话类型，无结算实现。 |
| Core Gem | 已有 `Order`、`PaymentSession`、`PaymentCombination` 与 `Carts::Submit`；客户普通 `:update` 权限排除 completed 订单。 |
| API Gem | `Orders::PaymentSessionsController` 使用 `find_order!`，因此个人中心已完成但欠款订单无法创建支付会话。 |
| Admin Gem | 无相关 storefront 付款 UI。 |
| Storefront | `UnifiedCheckout` 要先点 Pay 才提交订单/创建 session；`PaymentCheckoutModal` 已自动建 session；两个 checkout 页面未把摘要发布到布局的 sticky sidebar。 |
| Platform | SDK 已有 `orders.paymentSessions` / `paymentCombinations`，无需新增客户端接口。 |

## Skill 咨询

- `pallastrade-storefront`：客户端支付调用必须经过 Server Action；Stripe 表单使用服务端返回的 `client_secret`。
- `pallastrade-payments`：支付会话与订单绑定，表单确认后完成 session。
- `pallastrade-security` / `pallastrade-api-v3`：订单必须按当前 store + 当前客户/token 隔离，不能仅依赖 prefixed ID。
- `pallastrade-testing`：bug 必须补回归测试；前端用 RTL/Vitest，API 用 request spec。

## 技术方案与风险

1. 统一下单页在资料完整且选中 Stripe 后自动保存 cart、提交订单并创建支付会话，直接渲染表单；Pay 只做最终确认。失败后保留按钮重试。
2. 订单支付会话改用已隔离的只读订单解析进行所有权校验，使本人 completed + balance_due 订单可付款，同时保持他人订单 404。
3. `UnifiedCheckout` / `OrderPaymentContent` 通过 `CheckoutContext` 发布摘要，由结算布局既有 sticky sidebar 展示，删除主内容内重复右栏。

风险：自动准备 Stripe 表单会把资料完整的 active cart 转成 pending order；失败可通过订单付款页继续支付，不丢失订单。支付授权范围仅放宽到当前 store、当前客户/token 已可见的订单。

## 新文件说明

新增 `backend/spec/requests/api/v3/store/order_payment_sessions_controller_spec.rb` 是必要的：现有测试没有覆盖订单域 payment-session controller，不能在无关的 payment-combination spec 中表达单订单授权回归。

## 验证

- Storefront 组件回归测试与 `pnpm check`。
- Rails request spec：本人 completed + balance_due 成功；他人订单仍 404。
- Harness quick / generated check / storefront UI DOM 或截图证据。
