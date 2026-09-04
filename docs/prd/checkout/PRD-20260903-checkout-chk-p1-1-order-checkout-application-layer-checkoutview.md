# PRD-20260903-checkout-chk-p1-1a-read-only-checkoutview

| 元数据      | 值                                                                                                  |
| -------- | -------------------------------------------------------------------------------------------------- |
| 状态       | draft                                                                                              |
| 创建日期     | 2026-09-03                                                                                         |
| 来源       | CHK-P1-0 Order-centric Checkout 审计 + CHK-P1 架构评审                                                   |
| 分类       | checkout                                                                                           |
| 关联 Skill | `pallastrade-checkout` / `pallastrade-customization` / `pallastrade-api-v3`                        |
| 关联 REQ   | `REQ-20260903-chk-p1-1a.md`                                                                        |
| 关联 PRD   | `PRD-20260830-checkout-下单链路规范化统一化` 建议由 CHK-P1 系列 MERGE/SUPERSEDE；其余 Order/Payment PRD 作为 Reference |
| 前置依赖     | CHK-P1-0 Current-State Audit 已完成                                                                   |
| 后续工作包    | CHK-P1-1B Mutation Facade → CHK-P1-2 Invalidation/Version/Expiration → CHK-P1-3 Readiness/Snapshot |
| 需求类型     | 优化迭代：Read-only Server-driven Checkout Projection                                                   |

---

# 1. 背景与目标

## 1.1 一句话需求

在现有 Order 域之上新增一个**只读、无副作用、服务端生成的 CheckoutView Projection**，统一投影 Order 当前 Checkout 商业事实，为后续 Storefront 收敛、Mutation 编排、Version、Readiness 和 CheckoutSnapshot 提供稳定读取契约。

---

## 1.2 已确认现状

CHK-P1-0 已确认：

* `Cart` 是提交前购物编辑态。
* `Carts::Submit` 后生成 `Order`。
* `Order + line_items + addresses + shipments + adjustments + tax + totals` 已经承载 canonical checkout 商业事实。
* `OrderUpdater` 已是金额计算权威。
* `Order.amount_due + currency` 已是 PaymentSession 创建时的资金权威。
* Storefront 当前仍存在多个数据副本和多个 API 响应拼装 Checkout 状态的问题。
* 当前没有统一 Server-driven Checkout View。
* Payment P0 已完成 PaymentSession/Payment/Webhook/Express 等支付基础加固。

因此：

> P1 不创建 CheckoutSession，不复制 Order 数据，不新建 Pricing Engine。

---

## 1.3 本包目标

本包仅完成：

```text
Existing Order Facts
        ↓
PallasTrade::OrderCheckout::View
        ↓
CheckoutView DTO
        ↓
Store API Serializer
        ↓
GET Order Checkout API
```

本包必须满足：

* Read-only
* Deterministic
* No DB Migration
* No Domain Mutation
* No Payment Change
* No Checkout State Transition
* No Repricing / Requote / Retax
* No Storefront Change

---

## 1.4 成功指标

* Canonical Order 可生成完整 CheckoutView。
* Complete / legacy Order 可以 best-effort 投影。
* View 中的金额完全来自现有 Order 权威字段。
* GET Checkout 不产生任何写操作或领域副作用。
* 无明显 N+1。
* P0 Payment regression 全绿。
* Existing Order Flow regression 全绿。
* 无 DB migration。
* 无 Storefront 行为变化。

---

# 2. Scope Lock

## 2.1 本包实现

* `PallasTrade::OrderCheckout` namespace
* `OrderCheckout::View`
* CheckoutView DTO / Value Object
* Checkout Serializer
* Order Checkout GET API
* Authorization / Store Isolation
* OpenAPI 文档
* 单元测试 / Request Spec / Regression

---

## 2.2 本包明确不实现

```text
❌ UpdateAddress
❌ UpdateContact
❌ SelectShipping
❌ ApplyPromotion
❌ Refresh
❌ Invalidation
❌ Requote
❌ Re-tax
❌ Repricing

❌ Checkout Version 正式语义
❌ Price Version
❌ Expiration
❌ Readiness
❌ missing_requirements
❌ CheckoutSnapshot

❌ CheckoutSession
❌ Checkout 数据镜像表
❌ 新 Pricing Engine

❌ PaymentSession 修改
❌ Payment 修改
❌ Stripe 修改
❌ Carts::Complete 修改

❌ Legacy Checkout state machine 修改
❌ Storefront 重构
❌ SDK 新能力
```

上述能力分别进入后续：

```text
CHK-P1-1B
Mutation Facade

CHK-P1-2
Invalidation / Version / Expiration

CHK-P1-3
Readiness / CheckoutSnapshot

CHK-P1-4
Storefront Consolidation
```

---

# 3. 架构原则

## 3.1 数据所有权

正式边界：

```text
Cart
=
提交前购物编辑态

Order
=
Canonical Checkout 商业事实载体

CheckoutView
=
Order Checkout 当前事实的只读 Projection

PaymentSession
=
一次支付执行上下文

Payment
=
资金结果
```

CheckoutView 不拥有任何业务数据。

---

## 3.2 CheckoutView 定义

CheckoutView 是：

> 某个时刻对现有 Order Checkout 商业事实的 Server-side Projection。

CheckoutView 不是：

```text
CheckoutSession
Checkout Intent Aggregate
Order 副本
Snapshot Persistence
Pricing Engine
Workflow State Machine
```

---

## 3.3 Deterministic Projection

给定未变化的同一 Order 数据：

```text
View.call(order)
View.call(order)
View.call(order)
```

必须得到业务上相同的 Projection。

调用 View 不得：

* 修改 Order
* 修改 Shipment
* 创建 ShippingRate
* 更新 Adjustment
* 触发 Promotion
* 重新计算 Tax
* 触发 OrderUpdater
* 修改 `updated_at`
* 推进 Checkout State
* 创建 PaymentSession

---

# 4. 功能需求（FR）

## FR-101 — OrderCheckout::View

新增：

```ruby
PallasTrade::OrderCheckout::View
```

调用契约：

```ruby
call(order:)
```

返回：

```text
CheckoutView DTO / Value Object
```

数据只能来自：

* order
* line_items
* addresses
* shipments
* persisted shipping rates
* adjustments
* existing monetary columns
* associated display/reference data

禁止在 View 内重新执行业务计算。

---

## FR-102 — CheckoutView DTO

CheckoutView 至少包含以下事实字段。

### Identity

```text
order_id
```

使用现有 prefixed ID convention。

---

### Order State

根据现有 Order Serializer 正式语义分别表达，例如：

```text
state
status
payment_state
shipment_state
```

不得使用模糊的：

```text
status = state/status
```

实际字段以当前 Order API contract 为准。

---

### Items

至少：

```text
line_item_id
variant/product reference
name
variant information
quantity
unit price
line subtotal
currency
image/display data（如现有 serializer 已提供）
```

价格直接读取现有 Order/LineItem 字段。

不得重新计算：

```text
unit_price * quantity
```

作为新的权威金额来源。

---

### Contact

至少：

```text
email
```

如当前 canonical Order 已有其他正式 Contact 字段，可按现有契约投影。

---

### Addresses

```text
shipping_address
billing_address
```

缺失时：

```text
nil
```

不得因为地址缺失触发任何状态推进或校验流程。

---

### Shipping

CheckoutView 可表达：

```text
existing_shipping_options
selected_shipping
shipping_amount
```

其中：

> `existing_shipping_options` 只能投影当前已经存在/持久化的 ShippingRate。

本包禁止：

```text
ensure_available_shipping_rates
requote
create rates
update shipment cost
```

---

### Discounts

输出：

```text
discounts[]
```

作为 Adjustment / Promotion 的解释性明细。

但：

```text
price.discount_total
```

必须读取现有 Order 权威汇总。

禁止：

```text
discount_total = sum(discounts)
```

重新建立第二套计算。

---

### Taxes

输出：

```text
taxes[]
```

作为现有 Tax Adjustment 的解释性明细。

但：

```text
price.tax_total
```

必须读取 Order 权威税汇总。

禁止：

```text
tax_total = sum(taxes)
```

重新建立第二套税计算。

---

### Price

至少：

```text
item_total
shipment_total
discount_total
tax_total
adjustment_total（如现有契约需要）
total
amount_due
currency
```

所有字段：

> 直接读取现有 Order / OrderUpdater 已落地的权威结果。

CheckoutView 不拥有任何独立 pricing formula。

---

## FR-103 — 暂不输出未来语义字段

P1-1A 不建立下列正式 API contract：

```text
version
price_version
expires_at
ready
missing_requirements
```

不得使用：

```text
order.updated_at.to_i
```

模拟 Checkout Version。

不得使用临时 true/false 模拟 Readiness。

不得用固定 nil 字段提前冻结未来 API 语义。

上述字段在 P1-2/P1-3 正式设计完成后加入。

---

## FR-104 — Store API Endpoint

新增只读接口：

```http
GET /api/v3/store/orders/:id/checkout
```

具体路径应遵循当前 v3 Store routes convention。

返回：

```json
{
  "data": {
    "id": "or_xxx",
    "type": "checkout",
    "attributes": {}
  }
}
```

访问控制必须复用现有：

```text
order_resolvable
customer/token authorization
store isolation
```

禁止创建第二套 Order access control。

---

## FR-105 — Checkout Serializer

新增：

```ruby
PallasTrade::Api::V3::Store::CheckoutSerializer
```

或仓库等价命名。

负责：

```text
CheckoutView
→ Store API Representation
```

Serializer 只能格式化。

不得：

```text
调用 OrderUpdater
重新计算金额
触发 Shipping Quote
修改 Domain
```

---

## FR-106 — Money Representation

CheckoutView/API 所有金额：

> 必须完全遵循当前 Store API Order/Cart serializer 已有金额 convention。

本包禁止引入新的金额表达方式。

特别禁止因为 Payment/Express 使用 minor units，而把 CheckoutView 全部改成 cents。

原则：

```text
Domain / Store API
→ 继续沿用现有 major-unit decimal/string display contract

PSP Boundary
→ 继续由 Payment 层负责 minor-unit conversion
```

---

## FR-107 — hide_prices

如现有 Store API 存在：

```text
hide_prices
```

或同等权限门控：

CheckoutView 必须完全遵循既有规则。

不得因为新增 Checkout endpoint 绕过 Price Visibility Policy。

---

## FR-108 — Legacy Compatibility

Canonical：

```text
state=pending / 当前标准 Order
```

必须提供完整 CheckoutView。

Complete Order：

必须仍能生成历史 View。

Legacy 在途 Order：

采用：

```text
best-effort projection
```

缺失字段输出：

```text
nil
[]
```

不得为了 Legacy View：

* advance checkout
* 调用 `next`
* 触发 requirements
* 触发 checkout flow
* 迁移 legacy state
* 搬入完整 legacy current_step 语义

---

# 5. 非功能需求（NFR）

## NFR-101 — Zero Mutation

本包：

```text
无 DB migration
无 Domain Mutation
无 State Transition
```

GET API 必须严格无副作用。

---

## NFR-102 — Payment Isolation

不得修改：

```text
PaymentSession
Payment
Gateway
Stripe
Webhook
Carts::Complete
```

P0 Payment Foundation 必须保持不变。

---

## NFR-103 — Pricing Isolation

不得修改：

```text
OrderUpdater pricing formula
Promotion calculation
Tax calculation
Shipping calculation
amount_due semantics
```

CheckoutView 只读取结果。

---

## NFR-104 — Query Efficiency

必须显式预加载必要关联，例如实际需要时：

```text
line_items
variants/products
addresses
shipments
shipping_rates
adjustments
```

具体 preload 以查询分析结果为准。

不得出现明显：

```text
N line_items
→ N additional product queries

M shipments
→ M shipping-rate query groups
```

---

## NFR-105 — Canonical First

优先保证：

```text
Canonical Order Checkout
```

合同完整。

Legacy：

```text
best-effort compatibility
```

不得因迁就 Legacy 扭曲新 CheckoutView contract。

---

## NFR-106 — No Money-State Regression

调用 CheckoutView 不得影响：

```text
Payment creation
Payment completion
Order payment state
PSP reconciliation
```

P0 已有：

```text
PSP SUCCESS
≠
因为 Checkout 读取异常重新支付
```

原则必须继续成立。

---

# 6. 验收标准（AC）

## AC-101 — Canonical Projection

标准：

```text
state=pending
```

Order 可以生成完整 CheckoutView。

逐字段断言：

* items
* contact
* addresses
* shipping
* discounts
* taxes
* price
* currency
* order states

与现有 Order facts 一致。

---

## AC-102 — No Recalculation

CheckoutView：

```text
item_total
shipment_total
discount_total
tax_total
total
amount_due
currency
```

全部与 Order 权威字段一致。

不得通过 View 内部求和重新得出 authoritative total。

---

## AC-103 — Representation Compatibility

CheckoutView：

* ID 使用现有 prefix ID。
* Money 使用现有 Store API monetary representation。
* 地址使用现有 API 地址语义。
* `hide_prices` 完全兼容。
* 不新增新的 cents/minor-unit API contract。

---

## AC-104 — Complete Order Projection

已完成 Order：

```text
complete
```

仍可生成历史 CheckoutView。

GET View 不要求重新进入 Checkout 流程。

---

## AC-105 — Legacy Best-effort

Legacy 在途 Order：

* View 不抛出非必要异常。
* 缺失数据使用 nil/[]。
* 不触发 `next`。
* 不 advance legacy state machine。
* 不修改 checkout state。

---

## AC-106 — Authorization

GET：

```http
/orders/:id/checkout
```

必须正确执行：

* customer authorization
* token authorization
* store isolation

无权限：

```text
403 / existing contract
```

不存在：

```text
404 / existing contract
```

具体状态码遵循当前 API 既有行为，不为本接口发明新语义。

---

## AC-107 — Zero Side Effect

读取 CheckoutView 前后：

以下数据不得发生变化：

```text
order attributes
order.updated_at
shipment
shipping rates
adjustments
state
payment state
```

并确认：

```text
PaymentSession.count unchanged
Payment.count unchanged
```

---

## AC-108 — Deterministic Projection

同一未变化 Order 连续生成 CheckoutView：

```text
business facts identical
```

调用顺序不得影响结果。

---

## AC-109 — Query Safety

使用包含多个：

```text
line_items
shipments
shipping_rates
adjustments
```

的 Order 测试。

必须验证：

> 查询数量不会随关联数量产生明显 N+1 线性增长。

可以采用现有 query detector / query count convention。

不要求为了本 PR 引入新第三方依赖。

---

## AC-110 — Regression

以下全部全绿：

```text
P0 payment regression baseline
p1-order-flow regression
Order serializer/request specs
affected checkout specs
```

并确认：

```text
无 migration
无 Payment/Stripe diff
无 Storefront behavior diff
```

---

# 7. 跨层影响

| 层          | 影响                                           |
| ---------- | -------------------------------------------- |
| App        | 无                                            |
| Core       | 新增 `OrderCheckout::View` + DTO               |
| API        | Checkout Serializer + GET Controller + Route |
| Admin      | 无                                            |
| Storefront | 无                                            |
| SDK        | 本包不改                                         |
| Payment    | 无                                            |
| DB         | 无 migration                                  |
| Docs       | OpenAPI + Checkout architecture docs         |

---

# 8. 技术影响与候选文件

## Core

新增候选：

```text
pallastrade_core/
  app/services/pallastrade/order_checkout/view.rb
```

DTO 可以根据当前代码约定：

```text
独立 Value Object
Struct
Data class
Service Result payload
```

选择最符合现有项目 convention 的方式。

禁止创建 AR Model。

---

## API

新增候选：

```text
pallastrade_api/
  app/controllers/.../store/orders/checkout_controller.rb

  app/serializers/.../store/checkout_serializer.rb
```

修改：

```text
config/routes.rb
```

---

## Docs

修改：

```text
backend/public/api-docs/store.yaml

docs/checkout/CHK-P1-1A_ReadOnly_CheckoutView.md

ai/skills/pallastrade-checkout/SKILL.md

docs/prd/README.md
```

---

# 9. 测试计划

## 9.1 Service Spec

新增：

```text
spec/services/pallastrade/order_checkout/view_spec.rb
```

覆盖：

* canonical pending Order
* complete Order
* legacy Order
* parent/child member Order
* combined-payment member Order
* missing billing address
* missing shipping address
* no shipping rates
* adjustments
* tax
* hide_prices relevant projection input
* deterministic output
* no mutation

---

## 9.2 Serializer Spec

新增：

```text
checkout_serializer_spec.rb
```

覆盖：

* prefixed IDs
* money representation
* nil handling
* arrays
* hide_prices
* state fields
* authoritative totals

---

## 9.3 Request Spec

新增：

```text
checkout_controller_spec.rb
```

覆盖：

```text
200
404
403 / equivalent authorization contract
store isolation
complete order
legacy order
GET no side effects
```

---

## 9.4 Query Spec

针对关联数量构造测试：

```text
1 line item
10 line items

1 shipment
multiple shipments/rates

multiple adjustments
```

验证没有明显 N+1。

---

## 9.5 Regression

必须运行：

```text
p1-order-flow-rspec

P0 payment regression suite

harness affected

rubocop

generated:check
```

如项目已有 PRD gate：

```text
harness prd verify
```

必须通过。

---

# 10. Execution Gate

本 PR 只能实现：

```text
OrderCheckout::View
CheckoutView DTO
Serializer
GET API
Tests
Docs
```

发现以下需求时立即停止扩 Scope：

```text
需要更新地址
需要 requote shipping
需要重税
需要 version
需要 expires_at
需要 readiness
需要 price_version
需要 snapshot
```

输出：

```text
DEFERRED_TO_NEXT_WORK_PACKAGE
```

并分别归入：

```text
CHK-P1-1B
CHK-P1-2
CHK-P1-3
```

---

# 11. Definition of Done

CHK-P1-1A 完成时：

```text
Order
+ Existing Associations
        ↓
OrderCheckout::View
        ↓
CheckoutView
        ↓
GET Store API
```

并确认：

```text
✅ Server 已有单一 Checkout Projection

✅ CheckoutView 是 DTO，不是新数据源

✅ 金额只读取 Order 权威结果

✅ GET 无写操作

✅ 不 requote

✅ 不 retax

✅ 不 repricing

✅ 不推进状态机

✅ 不新增 CheckoutSession

✅ 不新增 DB 表

✅ 不新增 Pricing Engine

✅ 不改 PaymentSession

✅ 不改 Stripe

✅ 不改 Storefront

✅ P0 Payment baseline 全绿

✅ Order Flow baseline 全绿
```

---

# 12. 后续交接

## CHK-P1-1B

在 CheckoutView 稳定后再建设：

```text
OrderCheckout::UpdateContact
OrderCheckout::UpdateAddress
OrderCheckout::SelectShipping
OrderCheckout::ApplyPromotion
```

> ⚠️ 标注（2026-09-04）：`OrderCheckout::ApplyPromotion` 与 billing 独立编辑已 **DEFERRED**（1B REQ/设计文档记录：Order 域无既有可 WRAP 的 promotion/billing 服务，仅 Cart 域存在）——PRD 与实施对齐。

只 WRAP 已有 Domain Services。

禁止复制已有 mutation logic。

---

## CHK-P1-2

建设：

```text
Invalidation Graph

Requote / Re-tax / Recalculate

Checkout Version

Price Version

Expiration

Refresh
```

其中：

```text
state_lock_version
≠
checkout_version
```

正式 Version 语义必须单独设计。

不得使用：

```text
updated_at.to_i
public_metadata
```

直接冒充长期 transaction-critical version。

---

## CHK-P1-3

建设：

```text
Server Readiness

CheckoutSnapshot

Payment Start Gate
```

Readiness 必须聚合已有 Domain Validation，而不是复制规则。

Snapshot 定义为：

> 某个 Order + Checkout Version + Price Version 的确定性 transaction projection。

P1-3 再评估：

```text
PaymentSession 是否需要记录 price_version / price fingerprint
```

P1-1A 不触碰 PaymentSession。

### CHK-P1-3 实施（2026-09-03 用户确认范围）

建设交付：

- **OrderCheckout::Readiness**（只读）——聚合既有 Order/Shipment 谓词（email / ship_address / amount_due / shipment selected rate，digital 免 shipping_address、无 shipments 免 delivery_rate），返回 `ready` + `missing_requirements`（`contact`/`shipping_address`/`delivery_rate`/`balance`）。不复制校验规则。
- **OrderCheckout::Snapshot**（只读）——确定性 transaction projection 值对象（order_id+number+state+currency+checkout_version+price_version+checkout_expires_at+权威金额列 to_s）+ `fingerprint`（SHA256 前 16 hex）。不落库。
- **Payment Start Gate**（quote 作用域，`PaymentSessions::Start` 内部）：
  - 仅作用于 standard-flow 未完成且已有 quote（`checkout_expires_at` present）的订单；无 quote 订单/legacy/completed 账户补付直通（行为不变）。
  - 过期 → 自动 `OrderCheckout::Refresh`（重算+续期）后继续支付（金额以新权威为准）；`quote_refreshed: true` 入 session external_data。
  - 就绪缺失（contact/shipping_address/delivery_rate）→ `failure({code:'checkout_not_ready', missing_requirements:[...]})`，不建会话。
  - 新会话 external_data 记录 `price_version`（无 migration）。
- **CheckoutView/Serializer** 输出 `ready` + `missing_requirements`（供 P1-4 storefront）。
- 本轮不做：409 CHECKOUT_VERSION_CONFLICT 端点语义（留后续）。

AC（与测试映射，`REQ-20260903-chk-p1-3`）：

- AC-301：Readiness 对标准流 pending 订单返回 `ready`/`missing_requirements`（email/地址/物流齐全 → ready；缺项 → 对应 code；digital 免 shipping_address；无 shipments 免 delivery_rate）。
- AC-302：Snapshot 确定性（同 order 同状态两次调用 fingerprint/字段一致）；字段与 order 权威列一致；零副作用。
- AC-303：Start 对「有 quote 且过期」订单自动 Refresh 后续期并建会话，external_data 含 `price_version` + `quote_refreshed:true`。
- AC-304：Start 对「有 quote 但缺 contact/地址/物流」订单拒绝建会话（`checkout_not_ready` + missing list）。
- AC-305（回归）：无 quote pending 订单 / completed 账户补付订单 / legacy cart 会话启动行为与 P1-2 前完全一致（start_spec/order_payment_sessions/cart 支付回归全绿）；新会话 external_data 记录 price_version 不影响 reuse/幂等。

### CHK-P1-4 实施（2026-09-03 用户确认范围：4A 只读试点 + 手写 SDK/yaml + 轻量收编）

交付（详见 `REQ-20260903-chk-p1-4`）：

- **SDK（手写，仿 `orders.paymentSessions`）**：`orders.checkout.get(orderId)` → GET `/orders/:id/checkout`；`CheckoutView` interface（镜像 CheckoutSerializer：状态/email/currency/version/price_version/expires_at/ready/missing_requirements + money display_* + items/地址/discounts/taxes/fulfillments）。
- **storefront 读取层**：`lib/data/order-checkout.ts`（server）`getOrderCheckout`。
- **试点 `OrderPaymentContent`（or_ 纯支付页）**：金额/商品/地址改由 CheckoutView 投影；`ready === false` → 禁用 Pay + missing_requirements 提示（回退 order 快照防抖动）；不改 session create/complete。
- **legacy 轻量收编**：删无调用者死代码（`submitCartOrder`/`submitCartAndGoToCheckout`）；孤儿 `combined-payment` 页加「候选 4C 移除」注释；legacy 分支文件头边界注释。
- **API docs 手写同步**（store.yaml×2：backend + platform docs）：`/orders/{order_id}/checkout`（GET+PATCH）+ `components/schemas/Checkout`。
- 不做：PATCH mutation 消费（4B）、legacy 退役重构、409、rswag/typelizer 基建（R1 独立包）。

AC（与测试映射）：

- AC-401：SDK `orders.checkout.get` 返回类型化 CheckoutView（字段与后端契约一致）；tsc 通过。
- AC-402：`getOrderCheckout` server action 返回 CheckoutView（null 安全）。
- AC-403：OrderPaymentContent 金额/商品/地址以 CheckoutView 为准（view 缺失回退 order 快照）；`ready=false` 时禁用 Pay 并展示 missing_requirements。
- AC-404（回归）：or_ 页 Stripe payment_intent / 非 session / 其它 session 三条 Pay 路径行为不变（组件测试）。
- AC-405：死代码移除后全仓无引用；legacy 边界注释就位；store.yaml×2 与 platform 副本含 checkout 路径与 Checkout schema。

### CHK-P1-5 实施（2026-09-04 用户确认范围）——Checkout Quote-Conflict 409（P1-2/3 DEFERRED 落地）

交付（详见 `REQ-20260903-chk-p1-5`）：

- **Start 比对**（quote-active 标准流订单内）：可选 `expected_version` / `expected_price_version` 顶层参数；过期先 Refresh（既有 P1-3）续期后比对；任一不匹配 → `failure({code:'checkout_version_conflict', details:{order_id, latest:{version, price_version, expires_at, amount_due, display_amount_due}}})`，不建会话。
- **API**：`orders/payment_sessions#create` permit + 传参；`error_handler` code→409 映射（`checkout_version_conflict` → `:conflict`），details 透传。
- **缺省兼容**：不提供 expected → 行为与 P1-3 完全一致（幂等/reuse/operation_key 不变；legacy/completed/无 quote 直通）。

AC（与测试映射）：

- AC-501：Start 收到匹配的 expected_version+expected_price_version → 正常创建/复用会话（无 409）。
- AC-502：expected_version 不匹配 → failure `checkout_version_conflict`（details.latest 含最新 version/price_version/expires_at/amount_due），不建会话。
- AC-503：expected_price_version 不匹配 → 同上；两者皆提供时任一不匹配即 409。
- AC-504：过期订单带 expected → 先 Refresh（续期）后比对：quote 未变放行；变了才 409。
- AC-505（回归）：无 expected / 无 quote / legacy / completed 账户补付行为与 P1-3 前完全一致（start_spec/order_payment_sessions 回归全绿）；409 响应 HTTP status=409 + code + details。

### CHK-P1-4B 实施（2026-09-04 用户确认范围）——Storefront mutation 前端消费 + 409 UI

交付（详见 `REQ-20260903-chk-p1-4b`）：

- **SDK**：`orders.checkout.update(orderId, params)`（contact/shipping_address(_id)/delivery_rate_id 其一）→ 最新 `CheckoutView`。
- **读取层**：`lib/data/order-checkout.ts` `updateOrderCheckout`（server action，409/业务错误结构化透传）。
- **OrderPaymentContent（or_ 页）编辑 UI**：收货地址（复用 AddressFormFields）与物流 rate 单选可编辑 → PATCH → 采用服务端返回最新 view 刷新（金额/ready/version 同步）。
- **409 UI**：createOrderPaymentSession 遇 `checkout_version_conflict` → 提示「订单已更新」+ 重取 view（不自动支付）。
- **PRD 对齐**：§12 CHK-P1-1B 标注 `ApplyPromotion`/billing DEFERRED。

AC（与测试映射）：

- AC-601：SDK `orders.checkout.update` 存在且类型正确（tsc 0）；PATCH 后返回最新 view。
- AC-602：`updateOrderCheckout` 成功返回 view；409/业务失败返回结构化 {error}。
- AC-603：or_ 页地址编辑保存 → 新 view 生效（summary/地址刷新）；completed 订单无编辑入口。
- AC-604：or_ 页物流 rate 变更保存 → 新 view（金额可能变化）生效。
- AC-605（409 UI）：会话创建返回 checkout_version_conflict → 提示 + 重取 view，不自动支付。
- AC-606（回归）：read 路径（view 缺失回退 order）与既有 Pay 三条路径行为不变。

### CHK-P1-4C 实施（2026-09-04 用户确认范围）——Storefront 清理：孤儿页移除 + 死代码清理

交付（详见 `REQ-20260903-chk-p1-4c`）：

- **4C-2**：删除孤儿两步合并支付页 `combined-payment/[id]/page.tsx` + `CombinedPaymentCheckout.tsx`（4A 决策注释落地；旧深链 404，弹窗/账户列表为现行入口）。
- **4C-3**：删除孤儿页独占死代码 `lib/data/payment-combination.ts#updateOrderShippingAddress`（仅孤儿页调用）；保留 `getPaymentCombination`（payment-result + modal）、`createPaymentCombination`/`completeCombinationSession`（modal）。
- **保留边界**：legacy 一页式（CheckoutPageContent/PaymentSection/Express/confirm-payment）服务无前缀存量订单——**4C-4（退役）本轮不做**。

AC（与测试映射）：

- AC-701：`CombinedPaymentCheckout` 与 `combined-payment/[id]` 路由删除后全仓 0 引用、无测试断裂。
- AC-702：`updateOrderShippingAddress` 删除后全仓 0 引用；`payment-combination.ts` import 清理干净。
- AC-703（回归）：PaymentCheckoutModal / payment-result / 账户（OrderCombinedPay/OrderPayButton）组合支付与单笔支付测试全绿；typecheck/biome/locales 0。
- AC-704：legacy 一页式相关文件未被删除（4C-4 保留）。

### CHK-P1-4C4 实施（2026-09-04 用户确认范围）——legacy 一页式支付页退役

交付（详见 `REQ-20260904-chk-p1-4c4`）：

- **4C-4a**：删除 legacy 一页式独占子树 9 文件——`checkout/[id]/CheckoutPageContent.tsx`、`CheckoutSidebar.tsx` + `components/checkout/` 下 `AddressSection`、`DeliveryMethodSection`、`PaymentSection`、`AddressSelector`、`Summary`、`AdyenPaymentForm`、`PayPalPaymentForm`（Adyen/PayPal 内嵌表单仅 legacy PaymentSection 使用；新流程走网关跳转 + confirm-payment）。
- **4C-4b**：`checkout/[id]/page.tsx` 兜底改造——删除 legacy 渲染与 `getAddresses`/`CheckoutInitialData` 等配套；无前缀/不可解析 id → `redirect('/{urlCountry}/{locale}')` 首页。可达性依据：后端整数 id 序列化恒 `or_` 前缀 → 存量订单被 or_ 分支（OrderPaymentContent）承接；cart_ 被 UnifiedCheckout 承接；兜底实为错误路径。
- **4C-4c**：data 孤儿清理——checkout.ts 删 `applyCode/removeDiscountCode/removeGiftCard`（UnifiedCheckout 走 BFF /api/checkout/coupon，不经此）；payment.ts 删 `createDirectPayment`（仅 PaymentSection）；barrel index.ts 移除已删导出（CouponCode/ExpressCheckoutButton/StripePaymentForm 保留）。
- **保留**：`AddOnsSection/SaveInfoSection/AddressEditModal/AddressFormFields/CouponCode/CardPaymentForm/StripePaymentForm/ExpressCheckoutButton/PolicyConsent/CheckoutSectionTitle`（现行流程共享）；`updateOrderAddresses/selectDeliveryRate/completeCheckoutOrder/completeCheckoutPaymentSession/createCheckoutPaymentSession/getCompletedOrder/updateCartMarket`（express-checkout-flow/order-placed/useCountrySwitch 现行调用）；Express/CartDrawer/confirm-payment/order-placed 路由与后端全部不动。

AC（与测试映射）：

- AC-705：`checkout/[id]/page.tsx` 不再渲染 CheckoutPageContent；不可解析/无前缀 id → 重定向首页 `/{country}/{locale}`（cart_/or_ 分支行为不变）。
- AC-706：9 个 legacy 文件删除后全仓 0 引用（组件/barrel/测试/e2e）。
- AC-707：`applyCode/removeDiscountCode/removeGiftCard/createDirectPayment` 删除后全仓 0 引用；对应 data 测试块移除；保留函数测试仍绿。
- AC-708（回归）：UnifiedCheckout / OrderPaymentContent / PaymentCheckoutModal / order-placed / account / express / checkout.test / payment.test 全绿；typecheck/biome/locales 0。
- AC-709：共享组件未被删除且 barrel 保留共享导出（CouponCode/ExpressCheckoutButton/StripePaymentForm）。

---

# 13. 最终产物

本工作包完成后输出：

```text
CHK_P1_1A_COMPLETION_REPORT
```

至少包含：

```text
CheckoutView Contract

Data Source Mapping

Authoritative Money Mapping

Legacy Compatibility

Authorization

Query / N+1 Result

No-side-effect Verification

API Changes

OpenAPI Changes

Test Matrix

P0 Regression Result

Order Flow Regression Result

Files Changed

Deferred Items

Remaining Risk

CHK-P1-1B Readiness
```

---

# 14. 变更记录

| 日期         | 版本  | 变更                                                                                                                       | 操作者    |
| ---------- | --- | ------------------------------------------------------------------------------------------------------------------------ | ------ |
| 2026-09-03 | 0.1 | 原 CHK-P1-1 初稿                                                                                                            | AI     |
| 2026-09-03 | 0.2 | 经架构评审收窄为 CHK-P1-1A Read-only CheckoutView；移除 Mutation/Version/Expiration/Readiness；强化 Projection/No-side-effect/N+1/金额边界 | Review |
| 2026-09-03 | 0.3 | §12 追加 CHK-P1-3 实施块（Readiness/Snapshot/Payment Start Gate/price_version 记录；409 留后续）+ AC-301~305 | AI |
| 2026-09-03 | 0.4 | §12 追加 CHK-P1-4 实施块（SDK orders.checkout + 读取层 + OrderPaymentContent 只读试点 + legacy 轻量收编 + store.yaml 手写同步）+ AC-401~405 | AI |
| 2026-09-04 | 0.5 | §12 追加 CHK-P1-5 实施块（Quote-Conflict 409：expected_version/price_version 顶层参数 + Refresh 后比对 + compact latest quote）+ AC-501~505 | AI |
| 2026-09-04 | 0.6 | §12 追加 CHK-P1-4B 实施块（SDK checkout.update + 编辑 UI + 409 前端处理）+ AC-601~606；§12 1B 标注 ApplyPromotion/billing DEFERRED（PRD-实施对齐） | AI |
| 2026-09-04 | 0.7 | §12 追加 CHK-P1-4C 实施块（孤儿页移除 + updateOrderShippingAddress 死代码清理；4C-4 legacy 退役延后）+ AC-701~704 | AI |
| 2026-09-04 | 0.8 | §12 追加 CHK-P1-4C4 实施块（legacy 一页式退役：删 9 文件 + page.tsx 兜底改首页重定向 + data/barrel 孤儿清理）+ AC-705~709 | AI |


## 4. 非功能需求（NFR）

- 无 DB migration；不改 Order/Payment 模型结构；不加表。
- 不改 PaymentSession/Payment/Stripe/Carts::Complete；P0 支付回归基线保持全绿。
- 只读端点不产生副作用（无写）；UpdateAddress 与现有服务事务语义一致。
- CheckoutView 投影 N+1 可控（预加载 line_items/addresses/shipments.rates/adjustments）。
- 兼容 legacy 在途订单（不假设 state=pending）。
- 本包不触碰 Storefront 渲染与 SDK（防 scope creep，前端收敛归 P1-4）。

## 5. 验收标准（AC，与测试一一映射）

- AC-101 ← FR-101：`OrderCheckout::View.call(order:)` 返回结构完整 DTO，金额/地址/行项目与 order 权威列一致（spec 断言逐字段）。
- AC-102 ← FR-101：state=pending 标准订单可投影；complete 订单可投影（status=complete）；父子单成员/组合成员订单投影不抛错。
- AC-103 ← FR-102：DTO 字段契约存在且类型正确（金额 string/子单位语义遵守现有 serializer 规则；id 使用 prefixed）。
- AC-104 ← FR-103：`OrderCheckout::UpdateAddress` 更新 ship/bill/email 后返回的 View 反映新值；已 complete 订单拒绝更新；不重置 legacy 状态机（回归断言）。
- AC-105 ← FR-104：`GET /store/orders/:id/checkout` 200 返回 v3 信封；无权限/不存在 404/403；不改变订单任何列。
- AC-106 ← FR-105：hide_prices 门控与金额序列化遵守 `store.yaml` 既有 Cart/Order 语义（不引入新金额格式）。
- AC-107（回归）：既有 order-flow/P0 回归 spec 全绿；无 migration 产生（`git status` 无 db 文件）。

## 6. 跨层搜索记录（6 层，CHK-P1-0 审计已全量执行，此处固化结论）

| 层 | 路径 | 搜索关键词 | 找到的文件（代表） | 是否满足 |
|---|---|---|---|---|
| App | `backend/app/` | checkout/order 服务 | host 无相关代码（仅 user/admin_user 模型） | N/A |
| Core | `pallastrade_core/app/` | Order/OrderUpdater/Carts::Submit/Orders::* | `order.rb`、`order_updater.rb`、`services/orders/{update_shipping_address,update_contact_information}.rb`、`services/carts/submit.rb`、`models/order/checkout.rb` | ✅ WRAP 基座已存在 |
| API | `pallastrade_api/app/` | store orders controllers/serializers | `store/orders/payment_sessions_controller.rb`、`customer/orders/shipping_address_controller.rb`、`order_serializer.rb`、`cart_serializer.rb`、`middleware/request_id.rb` | ✅ 复用序列化/访问控制模式 |
| Admin | `pallastrade_admin/app/` | checkout_advance 等 | admin orders 控制器（advance 依赖，勿动） | N/A（不触碰） |
| Storefront | `storefront/src/` | checkout view/multi-source | `CheckoutPageContent.tsx`/`UnifiedCheckout.tsx`/`lib/data/checkout.ts`（多副本+裸 fetch） | 前端收敛归 P1-4，本包只读不改 |
| Platform | `platform/packages/` | sdk checkout types | SDK 无 checkout view 类型 | 本包不加 SDK（P1-4） |

**结论**：Order 域已有全部事实与修改入口；本包新增"只读投影 + WRAP 编排 + 读端点"，**无重复实现**。防重复：不建新聚合、不复制 OrderUpdater 公式、不动 legacy 状态机。

## 7. 技术影响

- 新增（core）：`app/services/pallastrade/order_checkout/view.rb`、`update_address.rb`、`view.rb`（值对象/结构）。
- 新增（api）：`serializers/pallastrade/api/v3/store/checkout_serializer.rb`（或等价）；`controllers/pallastrade/api/v3/store/orders/checkout_controller.rb`（GET show）；`config/routes.rb` 一条只读路由。
- 修改（core）：无（若需把 address 赋值提取共享，则以模块内 private 复制现有逻辑，不做跨文件重构）。
- DB：无 migration。
- 影响面：`harness affected`（仅上述新文件 + routes）；不触碰支付/前端。
- SDK/OpenAPI：`backend/public/api-docs/store.yaml` 增补 checkout 端点 schema（若生成器可用；否则记录 R1 类待办）。

## 8. 测试计划

- 新增：`backend/spec/services/pallastrade/order_checkout/view_spec.rb`（AC-101/102/103）
- 新增：`backend/spec/services/pallastrade/order_checkout/update_address_spec.rb`（AC-104）
- 新增：`backend/spec/requests/api/v3/store/orders/checkout_controller_spec.rb`（AC-105/106）
- 回归：`p1-order-flow-rspec` + P0 基线相关 spec（AC-107）；`rubocop`；`generated:check`（预期无 drift 或按 R1 记录）。
- AC↔测试映射见上；`harness prd verify --id PRD-20260903-checkout-chk-p1-1-...`。

## 9. 文档同步清单

- [ ] `backend/public/api-docs/store.yaml`（checkout 端点）
- [ ] `ai/skills/pallastrade-checkout/SKILL.md`（OrderCheckout 层/CheckoutView 契约）
- [ ] `docs/checkout/CHK-P1-1_OrderCheckout_Application_Layer.md`（本包设计记录，供 P1-2/3 接续）
- [ ] `docs/prd/README.md` 索引
- [ ] 状态推进 approved→implementing→verifying→done

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-03 | 0.1 | 初稿（依据 CHK-P1-0 审计 + 用户授权） | AI |