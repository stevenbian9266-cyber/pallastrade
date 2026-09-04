# UI 设计 — 正向下单与支付关键链路强化

> Task：`TASK-20260901021947-06703155`

## 1. UnifiedCheckout

- 桌面端两列：左侧地址、商品、物流、支付；右侧 sticky Order Summary。
- Stripe 卡表单在选择卡支付方式后直接显示，不等待 Pay 后渲染。
- Pay Now 是唯一提交按钮；阶段文案依次为 Processing order、Starting payment、Confirming payment。
- 移动端单列，Order Summary 放在 Pay 前并保持金额可见。

```text
┌──────────────────────────────────────┬──────────────────────┐
│ Shipping address                     │ Order Summary        │
│ Items                                │ Items / subtotal     │
│ Delivery                             │ Shipping / tax       │
│ Payment method                       │ Total                │
│ ┌ Card number / expiry / CVC ┐       │ [sticky on desktop]  │
│ └────────────────────────────┘       │                      │
│ [ Pay Now ]                          │                      │
└──────────────────────────────────────┴──────────────────────┘
```

## 2. Account cashier modal

- 单笔和多笔共用 Dialog；只显示目标订单、应付金额、支付方式与预渲染表单。
- 不显示或编辑地址/物流。
- Pay 后进入统一结果页；失败不以无权限或 order not found 作为通用兜底。

## 3. Payment result

- success：成功图标、订单号/组合号、金额、支付方式、Continue Shopping。
- failed：失败状态、可公开原因、Retry Payment、Continue Shopping。
- canceled：取消状态、Retry Payment、Continue Shopping。
- pending：处理中状态、Refresh status、Continue Shopping。
- 页面不得根据 query string 单独渲染 success；必须以服务端状态为准。

## 4. 可访问性

- 阶段变化使用 `aria-live="polite"`；错误区域使用 `role="alert"`。
- Dialog 保持焦点圈闭和 Escape 关闭；支付处理中禁止关闭以避免不确定状态。
- 所有支付按钮具备明确 loading 文案，不能只显示 spinner。
