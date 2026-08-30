# 交互设计 — 下单链路统一化（TASK-20260830163006-5f6397c0）

> 关联 PRD：PRD-20260830-checkout-下单链路规范化统一化；Gate：GATE-2026-08-30T16-30-18

## 1. 场景 A（cart 去结算）

```
购物车 /cart
  └ 点击「去结算」→ /checkout/[cart_id]（统一下单页）
       ├ ① 填/选收件地址（已存地址下拉 / AddressFormFields）
       ├ ② 查看商品信息（左侧列表）
       ├ ③ 选物流方式（radio，dm_ 前缀）
       ├ ④ 选支付方式（Stripe/Check radio）
       ├ ⑤ 点 Pay Now
       │     → 校验（地址必填/物流必选/支付方式）
       │     → 内联保存：updateShoppingCartDetails（email/地址/物流 → PATCH cart）
       │     → 内联提交：submitCartAndGoToCheckout（Carts::Submit → or_ 订单）
       │     → 无缝切换为 or_ 支付态（同页渲染 OrderPaymentContent 支付区）
       │     → 创建支付会话 createOrderPaymentSession → Stripe PaymentElement
       │     → confirmPayment / completePaymentSession
       │        ├ 成功 → /order-placed/[or_id]
       │        ├ 失败/取消 → 页面内错误提示 + 可重试（订单保持 balance_due）
       │        └ 3DS/离站 → /confirm-payment/[id] 回跳
```

边界：购物车已转换/过期（GET cart 404）→ 重定向 `/cart`（空态）。

## 2. 场景 B（购物车页勾选商品）

```
/cart 勾选（selected）→ 点「去结算」→ 与场景 A 同页 /checkout/[cart_id]
  （勾选范围即本次结算商品；与场景 A 完全同一统一下单页）
```

## 3. 场景 C（个人中心订单）

```
/account/orders（OrderCombinedPay 勾选区）
  ├ 勾选 1 笔 → 点 Pay Now
  │     └ 打开 PaymentCheckoutModal（单笔订单支付）
  │          ├ 选支付方式 → 支付表单
  │          ├ Pay Now → createOrderPaymentSession → confirm
  │          ├ 成功 → 关闭弹窗 + 刷新列表（订单 paid）
  │          └ 失败 → 弹窗内错误 + 重试
  └ 勾选 2+ 笔 → 点 Pay Now
        └ createPaymentCombination → 打开 PaymentCheckoutModal（组合支付）
             ├ 显示组合总额 + 各单分摊
             ├ 选支付方式 → 支付表单
             ├ Pay Now → completeCombinationSession（幂等 Complete）
             ├ 成功 → 关闭弹窗 + 刷新（所有成员 paid）
             └ 失败 → 弹窗内错误 + 重试（资金先入账、状态补偿）
```

订单详情 `/account/orders/[id]`：补「Pay Now」按钮（balance_due 且非子订单）→ 打开同一弹窗（单笔）。

## 4. 支付结果统一

| 结果 | 统一下单页 | 收银台弹窗 |
|---|---|---|
| 成功 | `/order-placed/[or_id]` | 关闭弹窗 + 就地刷新/跳完成态 |
| 失败/取消 | 页面错误 + 重试 | 弹窗错误 + 重试（可再次打开） |
| 3DS/离站 | `/confirm-payment/[id]` 回跳 | 同左（离站支付回跳中转） |
| 重复回调 | `Carts::Complete` 幂等短路 | 同左 |

## 5. 关键交互状态

- **提交中**：Pay Now 按钮 loading（禁用，防止重复提交）。
- **提交后切换**（cart_ → or_）：`submitCartAndGoToCheckout` 返回订单 → 用订单数据替换页面状态（购物车区域收起为只读，支付区激活），URL 用 `router.replace(/checkout/[or_id])` 保持可刷新。
- **弹窗关闭**：Cancel 或点遮罩；关闭后已选订单保持勾选（可重新打开）。
