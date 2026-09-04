# CHK-P1-1A — Read-only CheckoutView（Order-centric Checkout Consolidation 首包）

> 日期：2026-09-03 ｜ PRD：`docs/prd/checkout/PRD-20260903-checkout-chk-p1-1a-read-only-checkoutview.md`
> Task：`TASK-20260903110446-5a7993ae`；Gate：`GATE-2026-09-03T11-05-06`
> 定位：CHK-P1 系列第一个实施包（只读投影），后续：1B(mutation) → P1-2(version/expiration) → P1-3(readiness/snapshot) → P1-4(storefront)。

## 1. 交付内容

```text
Order + Existing Associations
        ↓ (预加载，零副作用)
PallasTrade::OrderCheckout::View.call(order:)
        ↓
CheckoutView DTO（只读值对象，委托 Order 权威列）
        ↓
Store CheckoutSerializer（只格式化；金额 major-unit string；hide_prices 门控）
        ↓
GET /api/v3/store/orders/:order_id/checkout（复用 OrderResolvable 授权/store isolation）
```

## 2. 文件清单

| 文件 | 类型 |
|---|---|
| `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/order_checkout/view.rb` | 新增：View + CheckoutView DTO + Line |
| `backend/pallastrade_gems/pallastrade_api/app/serializers/pallastrade/api/v3/store/checkout/checkout_serializer.rb` | 新增：Serializer |
| `backend/pallastrade_gems/pallastrade_api/app/controllers/pallastrade/api/v3/store/orders/checkout_controller.rb` | 新增：GET 端点 |
| `backend/pallastrade_gems/pallastrade_api/config/routes.rb` | 修改：orders 下嵌套 `resource :checkout, only: [:show]` |
| `backend/spec/services/pallastrade/order_checkout/view_spec.rb` | 新增（14 例） |
| `backend/spec/serializers/pallastrade/api/v3/store/checkout/checkout_serializer_spec.rb` | 新增（8 例） |
| `backend/spec/requests/api/v3/store/orders/checkout_controller_spec.rb` | 新增（7 例） |

## 3. CheckoutView 契约要点

- **金额零计算**：`item_total / delivery_total / adjustment_total / discount_total / tax_total / included_tax_total / additional_tax_total / total / amount_due`（+ 各自 display_*）全部委托 Order 权威列；不做求和/重算。
- **明细解释性**：`discounts[]`（eligible promotion 调整）、`taxes[]`（eligible tax 调整）每行 `{ id, amount, currency }`；合计仍读权威列。
- **无未来占位**：不输出 version / price_version / expires_at / ready / missing_requirements（P1-2/3 正式化后再加）。
- **复用**：items → `line_item_serializer`；fulfillments → `fulfillment_serializer`（含 delivery_rates/selected）；地址 → `address_serializer`；金额格式沿用 Store Order/Cart serializer（major-unit string，Rails BigDecimal 序列化为普通十进制）；`hide_prices` 门控金额与明细为 null。
- **访问控制**：复用 `OrderResolvable`（customer/token + store isolation；legacy checkout 态 `cart/address/.../confirm` 订单不通过订单 API 暴露——与服务层 legacy best-effort 投影分开）。

## 4. 测试结果（2026-09-03）

- 新增 29 例全绿（service 14 + serializer 8 + request 7）。
- Order 域回归 22 例全绿（customer orders / shipping address / order payment sessions / parent-child serializer）。
- RuboCop 新文件 0 offenses；`generated:check` 无 drift；无 DB migration。

## 5. 已知边界与后续

- 真实折扣明细行（Promotion 引擎产物）在测试中以"空数组 + 权威列一致"验证；税调整由引擎重算权威值后投影。明细格式非交易输入（合计权威在 Order）。
- Storefront 消费 CheckoutView → CHK-P1-4。
- Mutation Facade（UpdateAddress 等 WRAP）→ CHK-P1-1B。
- Version/Price Version/Expiration/Refresh → CHK-P1-2；Readiness/Snapshot → CHK-P1-3。
- OpenAPI `store.yaml` 补 checkout 端点 → 待生成源可用后统一 swaggerize（R1 类，同 P0 处理）。
