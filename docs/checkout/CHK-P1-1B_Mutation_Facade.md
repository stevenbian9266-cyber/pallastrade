# CHK-P1-1B — Order Checkout Mutation Facade

> 日期：2026-09-03 ｜ PRD：`PRD-20260903-checkout-chk-p1-1-order-checkout-application-layer-checkoutview`（§12）
> Task：`TASK-20260903121735-49fbe41e`；Gate：`GATE-2026-09-03T12-17-49`
> 前置：CHK-P1-1A（Read-only CheckoutView）已完成。

## 1. 交付内容

```text
PATCH /orders/:order_id/checkout
        │ 按 body 分派（每次一类）
        ▼
OrderCheckout::UpdateContact   ──WRAP──▶ Orders::UpdateContactInformation ──▶ CheckoutView
OrderCheckout::UpdateAddress   ──WRAP──▶ Orders::UpdateShippingAddress   ──▶ CheckoutView
OrderCheckout::SelectShipping  ──WRAP──▶ Shipments::Update              ──▶ CheckoutView
                                          （selected rate + cost 镜像 + totals/payment_state 重算，
                                           全部复用既有语义；不复制逻辑）
```

## 2. 文件清单

| 文件 | 类型 |
|---|---|
| `core/app/services/pallastrade/order_checkout/update_contact.rb` | 新增（WRAP UpdateContactInformation → View） |
| `core/app/services/pallastrade/order_checkout/update_address.rb` | 新增（WRAP UpdateShippingAddress → View） |
| `core/app/services/pallastrade/order_checkout/select_shipping.rb` | 新增（WRAP Shipments::Update → View） |
| `api/.../store/orders/checkout_controller.rb` | 修改：新增 `update` + 分派（contact / shipping_address / delivery_rate_id） |
| `api/config/routes.rb` | 修改：`resource :checkout, only: [:show, :update]` |
| `spec/services/pallastrade/order_checkout/mutation_facade_spec.rb` | 新增（7 例） |
| `spec/requests/api/v3/store/orders/checkout_controller_spec.rb` | 修改：+PATCH 用例（6） |

## 3. 契约要点

- **PATCH body（每次一类）**：`{ contact: { email } }`、`{ shipping_address: {...} | shipping_address_id }`、`{ delivery_rate_id }`；空 body → 422。
- 服务层守卫 `!order.completed?`；API 层 `find_order!`（`:update` ability + store isolation + legacy 态订单排除）→ 未授权 404/403（完成订单由 ability 拒 403）。
- SelectShipping：取首个未 shipped/cancelled shipment；rate 必须属于该 shipment 可用 rates（`dr_` 前缀或裸 id）；重算完全走 `Shipments::Update`（含 amount_due 变化，不影响 PaymentSession——P0 Start 对金额变化不再复用会话）。
- **DEFERRED → P1-2**：运费敏感税一致性（Shipments::Update 现不重算 tax）、price-version/失效图；**ApplyPromotion**（仅 Cart 域）、**billing 独立编辑**（无既有 customer 服务）。

## 4. 测试结果（2026-09-03）

- 新增 13 例全绿（service 7 + request PATCH 6）；合并回归 **64/64**（1A 29 + 1B 20 + customer shipping/order payment/customer orders/parent-child 15）。
- RuboCop 0；无 DB migration；不改 Payment 链/Storefront/SDK。

## 5. 后续

- CHK-P1-2：Invalidation Graph / Requote / Re-tax / Checkout Version / Price Version / Expiration / Refresh（本包 SelectShipping 已复用 Shipments::Update 重算，1B 服务预留扩展点）。
- Storefront 消费 CheckoutView + mutation 收敛 → P1-4。
