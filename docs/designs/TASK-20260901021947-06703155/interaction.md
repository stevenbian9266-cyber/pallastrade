# 交互设计 — 正向下单与支付关键链路强化

> Task：`TASK-20260901021947-06703155`

## 1. 场景 A：Add to Cart

```text
PDP Add to Cart → CartDrawer → Checkout → UnifiedCheckout
  → 地址/物流/支付表单已展示 → Pay Now（仅一次）
  → submitting order → starting payment → confirming payment
  → payment result
```

双击 Pay 被客户端 pending 状态拦截；网络重试由后端返回同一 Order/活动 PaymentSession。

## 2. 场景 B：Buy Now

```text
PDP Buy Now → 独立 Cart → UnifiedCheckout → 一次 Pay → payment result
```

独立 Cart 不替换或清空普通购物车；失败重试始终针对已创建的原 Order。

## 3. 场景 C：购物车选中商品

```text
/cart 选择部分商品 → Checkout → UnifiedCheckout → 一次 Pay
  ├─ selected items → Order
  └─ unselected items → successor active Cart
```

支付启动后导航离开确认页；返回购物车时只看到未选商品。

## 4. 场景 D：账户订单收银台

```text
/account/orders
  ├─ 1 order → PaymentCheckoutModal → existing Order session
  └─ N orders → PaymentCheckoutModal → existing PaymentCombination
       → Pay → payment result
```

弹窗不展示地址/物流，不创建 Cart/Order。关闭弹窗不改变订单；支付失败后 Retry 仍使用原订单或组合。

## 5. 结果与恢复

| 状态 | 页面动作 | 主操作 | 订单语义 |
|---|---|---|---|
| success | 显示订单号、金额、方式 | Continue Shopping | 原订单已支付 |
| failed | 显示安全映射后的原因 | Retry Payment | 复用原订单 |
| canceled | 明确已取消本次尝试 | Retry / Continue | 复用原订单 |
| pending | 显示处理中并短轮询 | Refresh status | 不创建新尝试 |

若创建订单成功但支付会话启动失败，直接进入 failed/pending 结果页并保留 order id，不回到空购物车。

## 6. 页面状态机

```text
idle → validating → submitting_order → starting_session → confirming_payment
  ├─ success → result/success
  ├─ provider failure → result/failed
  ├─ user cancel → result/canceled
  └─ timeout/unknown → result/pending
```

进入 `submitting_order` 后 Pay 按钮禁用并显示阶段文案；刷新或重试依赖服务端幂等恢复。
