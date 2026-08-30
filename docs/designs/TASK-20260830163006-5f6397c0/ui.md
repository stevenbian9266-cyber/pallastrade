# UI 设计 — 下单链路统一化（TASK-20260830163006-5f6397c0）

> 关联 PRD：PRD-20260830-checkout-下单链路规范化统一化；Gate：GATE-2026-08-30T16-30-18

## 1. 统一下单页 `UnifiedCheckout`（场景 A/B）

路由 `/checkout/[id]`（`cart_` 或 `or_` 均可进入），布局组 `(checkout)`（极简 header + Back to store）。

### 左右分栏（lg:grid-cols-3，对齐阿里国际站）

```
┌─────────────────────────────────────────────────────────────┬───────────────────────┐
│ 左侧 2/3 — 订单基础信息                                       │ 右侧 1/3 — 订单小结     │
│                                                             │                       │
│ ① 收件地址信息（AddressFormFields）                           │  Order Summary 卡片     │
│    - 登录用户：已存地址下拉 + 就地编辑                          │   ├ 商品清单（行项目缩略）│
│    - 游客：邮箱 + 表单                                        │   ├ Subtotal            │
│ ② 商品信息（行项目列表：图/名/规格/数量/单价）                   │   ├ Shipping（已选物流）  │
│ ③ 物流方式（DeliveryMethodSection radio，dm_ 前缀）           │   ├ Tax / 优惠           │
│ ④ 支付方式选择（PaymentSection 内嵌：Stripe/Check radio）      │   └ Total（强调金额）    │
│ ⑤ Pay Now 按钮（提交+支付）                                   │                       │
└─────────────────────────────────────────────────────────────┴───────────────────────┘
```

### 状态细分（按 id 前缀 + 订单状态）

| 状态 | 渲染 |
|---|---|
| `cart_` 购物车（active） | 全可编辑（地址/物流/支付方式）+ Pay Now（内联保存+提交+支付） |
| `or_` 标准订单（pending/balance_due） | 地址/物流**只读**（提交时已快照）+ 支付方式 + Pay Now（仅支付） |
| `or_` 订单已支付（paid/completed） | 跳转 `/order-placed/[id]` |
| legacy `or_`（cart/address/... 态） | 保留 `CheckoutPageContent`（存量兼容） |

## 2. 收银台弹窗 `PaymentCheckoutModal`（场景 C）

个人中心（订单列表 `OrderCombinedPay` / 订单详情 `OrderDetail`）点击 Pay Now → 弹窗。

```
┌──────────────── Dialog（max-w-md 居中）────────────────┐
│ 收银台（标题：Combined payment / Pay order）            │
│ ───────────────────────────────────────────────────── │
│ 应付金额（大号，如 $21.00 USD；多笔含各单分摊列表）       │
│ 支付方式（radio：Stripe / Check）                       │
│ 支付表单（StripePaymentForm PaymentElement / 非会话）   │
│ ───────────────────────────────────────────────────── │
│        [ Cancel ]                [ Pay Now ]          │
└───────────────────────────────────────────────────────┘
```

- 弹窗**仅支付方式相关信息**（金额 + radio + 表单 + 按钮），无地址/物流字段。
- 多笔合并支付：弹窗展示组合总额 + 各成员订单分摊（`expand=orders` 取 amount_due）。

## 3. 订单详情页 Pay Now

`/account/orders/[id]` 顶部支付信息区下方补「Pay Now」主按钮（仅 `balance_due` 且非子订单时显示）→ 打开 `PaymentCheckoutModal`。

## 4. 购物车页 / CartDrawer

- `/cart`「去结算」与 `CartDrawer`「去结算」均指向 `/checkout/[cart_id]`（统一下单页；CartDrawer 已改 checkout-info，统一化后指向统一下单页）。

## 5. 复用组件

| 组件 | 来源 | 用途 |
|---|---|---|
| `AddressFormFields` | `components/checkout/` | 收件地址表单 |
| `DeliveryMethodSection` | `components/checkout/` | 物流 radio |
| `PaymentSection` | `components/checkout/` | 支付方式 + `PaymentSectionHandle.submit` |
| `StripePaymentForm` | `components/checkout/` | PaymentElement |
| `Summary` | `components/checkout/` | 订单小结 |
| `OrderPaymentContent` | `components/checkout/` | `or_` 订单支付区（复用） |
