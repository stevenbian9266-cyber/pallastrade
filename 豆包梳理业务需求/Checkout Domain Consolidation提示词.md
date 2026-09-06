下面这版可以直接喂给 Coding AI。它已经按最新方案改成 **Order-centric Checkout Consolidation**，并明确继承 P0 已完成的支付基础，删除了独立 `CheckoutSession`、多表快照和新 Pricing Engine 的设计。

你现在要在现有 PallasTrade 项目中实施：

# CHK-P1 — Order-centric Checkout Consolidation

本阶段建立在已经完成的 Payment P0 Foundation Hardening 之上。

当前项目的 canonical checkout 真实链路是：

```text
Cart
→ Submit
→ Order
→ Order-domain Checkout
→ PaymentSession
→ Gateway
→ Stripe
→ Payment
→ Carts::Complete
```

因此本阶段：

**禁止新建独立 CheckoutSession 领域。**

Order 已经是当前 canonical checkout 的商业事实载体。

P1 的目标是在现有 Order Checkout 之上增加：

* Checkout Application Layer
* CheckoutView
* Checkout Version
* Price Version
* Invalidation
* Expiration / Refresh
* Server-side Readiness
* CheckoutSnapshot
* Frontend Consolidation
* Express / Legacy Consolidation

最终形成：

```text
Cart
↓
Submit
↓
Order
↓
Order Checkout Application Layer
├── CheckoutView
├── Version / Price Version
├── Invalidation
├── Expiration
├── Readiness
└── CheckoutSnapshot
        ↓
     Future OTS
```

---

# 一、必须继承的 P0 基础

以下能力已经存在，本阶段必须保护，禁止重复实现：

* PaymentSession ↔ Payment 正式关联
* PaymentSessions::Start
* active session reuse
* operation_key
* Stripe idempotency
* Webhook Event Store
* Webhook Dedup / Retry / Replay
* Carts::Complete 单点订单完成
* verify_payment_intent_matches!
* Express payment idempotency
* Express server-authoritative amount
* Payment Trace / Audit
* Standard Flow = Canonical
* Legacy Flow = Compatibility Only

任何 P1 修改不得降低上述能力。

---

# 二、正式数据所有权

必须以以下边界作为设计基础：

```text
Cart
=
用户购物编辑态

Order
=
Canonical Checkout 商业事实载体

PaymentSession
=
一次支付执行上下文

Payment
=
资金结果

PaymentWebhookEvent
=
PSP 事件事实
```

因此：

```text
Items
Address
Shipping
Promotion
Tax
Price
Currency
```

继续由：

```text
Order + Existing Associated Models
```

承载。

不得为了 P1 再复制一套同义 Checkout 数据。

---

# 三、P1 Scope

本阶段实施：

## CHK-P1-0

Checkout Current-State Audit

## CHK-P1-1

Order Checkout Application Layer + CheckoutView

## CHK-P1-2

Version / Price Version / Invalidation / Expiration

## CHK-P1-3

Server Readiness + CheckoutSnapshot

## CHK-P1-4

Unified Storefront CheckoutView

## CHK-P1-5

Express / Legacy Consolidation

## CHK-P1-6

Legacy Order::Checkout Governance

---

# 四、严格禁止事项

本阶段禁止：

* 新建 CheckoutSession 聚合
* 新建 Checkout Items/Address/Tax/Discount 等整套镜像表
* 新建平行 Pricing Engine
* 实现 OTS
* 实现 Saga
* 实现 Inventory Reserve / Commit / Release
* 新建 PaymentAttempt
* 实现 Payment Router
* 实现 ProviderRegistry
* 新接入 Adyen
* 重写 PaymentSession
* 重写 Stripe Gateway
* 重写 Payment 状态机
* 重写 Order payment_state
* 实现 Refund / Dispute / Ledger / Reconciliation
* decimal → bigint 金额迁移
* 替换现有 ID 体系
* 删除 Legacy Flow
* 未审计就删除 Order::Checkout legacy state machine
* 大规模无关重构
* Frontend authoritative price calculation

如果你认为必须突破 Scope：

不要自行实现。

先输出：

```text
BLOCKER
WHY
MINIMAL_ALTERNATIVE
```

---

# 五、工作方式

每个工作包必须独立执行。

顺序：

1. Inspect
2. CURRENT_STATE
3. DATA_OWNERSHIP
4. CHANGE_PLAN
5. FILE_CHANGE_LIST
6. DB_MIGRATION_PLAN
7. Tests First
8. Implementation
9. Run Tests
10. RESULT
11. REMAINING_RISK

原则：

```text
一个 Coding Task / PR
≈
一个工作包
```

禁止一次性实施全部 CHK-P1。

---

# 六、CHK-P1-0：只读现状审计

当前第一轮只执行本工作包。

**禁止修改代码。**

必须完整核实以下内容。

## 6.1 Canonical Checkout Flow

画出真实链路：

```text
Cart
→ Submit
→ Order
→ Address
→ Shipping
→ Promotion
→ Tax
→ Price
→ Payment
→ Complete
```

明确每个步骤：

* Controller
* Service
* Model
* Frontend
* BFF
* SDK

分别由谁负责。

---

## 6.2 Cart → Order Boundary

确认：

* Cart 什么时候 submit
* Order 创建时复制哪些数据
* 哪些数据 submit 后继续在 Order 上修改
* Cart submit 后是否仍承担 canonical checkout 数据职责
* Order state/status 的真实含义

---

## 6.3 Checkout Data Ownership

输出：

```text
CHECKOUT_DATA_OWNERSHIP
```

至少覆盖：

| 数据               | 当前权威对象 | 修改入口 | 计算入口 | 前端来源 |
| ---------------- | ------ | ---- | ---- | ---- |
| Items            | ?      | ?    | ?    | ?    |
| Contact          | ?      | ?    | -    | ?    |
| Shipping Address | ?      | ?    | -    | ?    |
| Billing Address  | ?      | ?    | -    | ?    |
| Shipping         | ?      | ?    | ?    | ?    |
| Promotion        | ?      | ?    | ?    | ?    |
| Tax              | ?      | ?    | ?    | ?    |
| Total            | ?      | ?    | ?    | ?    |
| Currency         | ?      | ?    | ?    | ?    |

---

## 6.4 Current Price Flow

必须精确画出：

```text
Line Items
↓
Discount / Adjustment
↓
Shipping
↓
Tax
↓
Order Total / amount_due
↓
PaymentSession
```

确认：

* authoritative subtotal
* authoritative discount
* authoritative shipping
* authoritative tax
* authoritative total
* authoritative currency

分别来自哪里。

同时确认 Frontend 是否还存在重新计算 authoritative total 的路径。

---

## 6.5 Address Flow

分析：

* shipping address 更新入口
* billing address 更新入口
* address validation
* country/state rules
* address change 会触发什么重新计算
* 哪些逻辑在 Server
* 哪些逻辑仍散落 Frontend

---

## 6.6 Shipping Flow

分析：

* Fulfillment / Shipment / DeliveryMethod / ShippingRate 等真实模型
* quote 来源
* selected shipping 保存位置
* address/item 变化是否使旧 rate 失效
* shipping amount 如何进入 Order total
* Frontend 是否参与 shipping price calculation

---

## 6.7 Promotion Flow

分析：

* Promotion
* Adjustment
* Coupon / DiscountCode
* automatic discount
* item discount
* order discount
* shipping discount

明确：

```text
输入变化
→ promotion re-evaluation
```

真实触发机制。

---

## 6.8 Tax Flow

分析：

* Tax Engine
* Tax Rate
* Adjustment
* external provider（如有）
* 地址依赖
* Shipping 依赖
* Promotion 依赖
* rounding

明确 Tax 何时重新计算。

---

# 七、Canonical / Legacy Matrix

输出：

```text
CANONICAL_LEGACY_MATRIX
```

至少包含：

```text
Standard Order Checkout

Express Checkout

Legacy one-page checkout

redirect fallback

Cart-domain payment

Order-domain payment
```

每条标记：

```text
CANONICAL

COMPATIBILITY

LEGACY_ACTIVE

STUB

DEAD
```

不得根据文件名猜。

必须基于真实调用方和路由判断。

---

# 八、Payment Handoff Audit

确认 Order Checkout 与 PaymentSession 的真实交接：

```text
Order
↓
PaymentSessions::Start
```

至少核实：

* amount 来源
* currency 来源
* payment_method 来源
* operation_key
* session reuse
* payment creation
* complete flow

输出：

```text
PAYMENT_HANDOFF_FLOW
```

同时判断未来是否需要让 PaymentSession 记录：

```text
checkout_version
price_version
```

当前只做评估。

禁止未经评审直接修改 PaymentSession。

---

# 九、Legacy Order::Checkout State Machine Audit

专项审计：

```text
Order::Checkout

checkout_flow

checkout_steps

step

requirement

registry
```

查找全部引用。

按以下分类：

```text
ACTIVE_PRODUCTION

PROVIDER_DEPENDENCY

ADMIN_DEPENDENCY

COMPATIBILITY

DEAD_CODE
```

输出：

```text
LEGACY_ORDER_CHECKOUT_STATE_MACHINE_USAGE
```

每项给出建议：

```text
KEEP

WRAP

DEPRECATE

REMOVE_LATER
```

当前禁止删除。

---

# 十、Frontend Checkout Audit

分析：

```text
CheckoutPageContent
UnifiedCheckout
Contact
Address
Shipping
Promotion
OrderSummary
PaymentSection
ExpressCheckout
checkout BFF
checkout state/store
```

输出：

```text
FRONTEND_CHECKOUT_ARCHITECTURE
```

重点判断：

* Frontend 是否自行编排多个领域请求
* 是否存在多个金额来源
* 是否存在多个 readiness 判断
* 是否存在重复 order/cart state
* 哪些 section 已经 Server-driven

---

# 十一、Payment Component Usage Matrix

当前前端可能存在：

* Card Elements
* PaymentElement
* ExpressCheckoutElement
* PayPal
* Adyen

逐个核实真实状态：

```text
ACTIVE

LEGACY

STUB

UNUSED
```

输出：

```text
PAYMENT_COMPONENT_USAGE_MATRIX
```

禁止因为组件文件存在就判断 Provider 已上线。

---

# 十二、Existing PRD 查重

搜索：

```text
docs/prd/checkout
docs/prd/order
standard ecommerce
order lifecycle
checkout normalization
legacy checkout
```

输出：

```text
P1_PRD_OVERLAP_MATRIX
```

每份已有 PRD 分类：

```text
MERGE

SUPERSEDE

REFERENCE

KEEP_SEPARATE
```

禁止创建重复需求链。

---

# 十三、P1-0 最终必须输出

本轮不允许 Coding。

只输出：

```text
CURRENT_CHECKOUT_ARCHITECTURE

CHECKOUT_DATA_OWNERSHIP

CANONICAL_FLOW

LEGACY_FLOW

CURRENT_PRICE_FLOW

CURRENT_ADDRESS_FLOW

CURRENT_SHIPPING_FLOW

CURRENT_PROMOTION_FLOW

CURRENT_TAX_FLOW

PAYMENT_HANDOFF_FLOW

FRONTEND_CHECKOUT_ARCHITECTURE

PAYMENT_COMPONENT_USAGE_MATRIX

LEGACY_ORDER_CHECKOUT_STATE_MACHINE_USAGE

P1_PRD_OVERLAP_MATRIX

P1_REUSE_MATRIX

P1_CHANGE_PLAN

P1_DB_DESIGN_PROPOSAL

P1_FILE_CHANGE_LIST

P1_RISK_LIST
```

其中：

```text
P1_REUSE_MATRIX
```

必须把现有能力分类成：

```text
REUSE_AS_IS

EXTEND

WRAP

DEPRECATE_LATER

DO_NOT_TOUCH
```

---

# 十四、CHK-P1-1：Order Checkout Application Layer

只有 P1-0 评审通过后才允许执行。

目标：

将 Checkout mutation orchestration 从：

```text
Controller / BFF / Frontend
```

收敛到：

```text
Order Checkout Application Layer
```

候选能力：

```text
OrderCheckout::View

OrderCheckout::UpdateContact

OrderCheckout::UpdateAddress

OrderCheckout::SelectShipping

OrderCheckout::ApplyPromotion

OrderCheckout::RemovePromotion

OrderCheckout::Refresh
```

实际命名遵循项目现有 convention。

---

# 十五、CheckoutView

建立统一 Server-driven DTO。

至少表达：

```text
order_id

status

version
price_version

items

contact

shipping_address
billing_address

shipping_options
selected_shipping

discounts
taxes

price

ready
missing_requirements

expires_at
```

Frontend 不应自己拼多个 API 得出最终 Checkout 状态。

---

# 十六、Mutation Contract

目标：

```text
PATCH Checkout Data
↓
Application Service
↓
Domain Update
↓
Invalidate
↓
Recalculate
↓
Evaluate Readiness
↓
CheckoutView
```

禁止：

```text
Frontend 更新 address
↓
Frontend 自己依次请求 shipping/tax/promotion/price
```

---

# 十七、CHK-P1-2：Version

优先检查现有：

```text
lock_version
updated_at
optimistic locking
```

可否满足需求。

如不足，才设计 checkout version。

目标解决：

```text
stale browser request

multi-tab overwrite

concurrent mutation
```

错误：

```text
CHECKOUT_VERSION_CONFLICT
```

---

# 十八、Price Version

影响金额的数据变化：

```text
items
quantity
address
shipping
promotion
tax
currency
```

必须能够识别为新的：

```text
price_version
```

目标是：

> 能回答某次支付基于哪个价格版本产生。

不要因为这一需求重写现有 Pricing Domain。

---

# 十九、Invalidation Graph

集中定义依赖关系。

至少：

```text
Items changed
→ Shipping stale
→ Promotion re-evaluate
→ Tax stale
→ Price stale
→ Readiness stale
```

```text
Address changed
→ Shipping stale
→ Tax stale
→ Price stale
→ Readiness stale
```

```text
Shipping changed
→ Tax may change
→ Price stale
→ Readiness stale
```

```text
Promotion changed
→ Tax may change
→ Price stale
→ Readiness stale
```

实际规则必须以当前业务代码为准。

---

# 二十、Pricing 原则

禁止新建第二套 Checkout Pricing Engine。

继续复用现有：

```text
Order
LineItem
Adjustment
Shipping
Tax
OrderUpdater
```

如需统一入口，只增加 Facade，例如：

```text
OrderCheckout::Recalculate
```

它只能编排现有能力。

不能复制公式。

---

# 二十一、Expiration

P1 建立：

```text
expires_at
```

或现有等价机制。

Expiration 表示：

> 当前 Checkout 商业条件需要重新验证。

不表示：

```text
Order canceled
```

Expired 后不能直接以旧报价开启新的 PaymentSession。

---

# 二十二、Refresh

Refresh 必须重新验证：

```text
Items

Shipping

Promotion

Tax

Price
```

并产生最新：

```text
version
price_version
```

最后重新 Evaluate Readiness。

---

# 二十三、CHK-P1-3：Server Readiness

建立：

```text
OrderCheckout::Readiness
```

或等价服务。

Server 至少判断：

```text
order checkout-able

items valid

contact complete

shipping address valid

shipping available

shipping selected

promotion current

tax current

price current

currency valid

not expired
```

返回：

```json
{
  "ready": false,
  "missing_requirements": [
    "SHIPPING_ADDRESS",
    "SHIPPING_METHOD"
  ]
}
```

Frontend 不得自行定义最终 READY。

---

# 二十四、CheckoutSnapshot

这是 P1 最重要的后端产物。

优先实现为：

```text
Server-generated DTO / Value Object
```

而不是新数据库模型。

Snapshot 由 Order 和已有关联对象投影。

至少包含：

```text
order_id

checkout_version
price_version

customer / guest
contact

items

shipping_address
billing_address

shipping_method

discounts
taxes

price

currency

expires_at
generated_at
```

---

# 二十五、Snapshot Gate

只有：

```text
READY

not expired

price current

shipping current

tax current
```

才允许生成 transaction-grade Snapshot。

否则返回明确错误：

```text
CHECKOUT_NOT_READY

CHECKOUT_EXPIRED

CHECKOUT_PRICE_STALE

SHIPPING_STALE

TAX_STALE
```

---

# 二十六、Internal Snapshot Contract

未来 OTS 的唯一可信 Checkout 输入应来自：

```text
GetCheckoutSnapshot(order_id)
```

或项目等价内部接口。

未来 OTS 不应从 Frontend 接收可信：

```text
amount
items
shipping
discount
tax
currency
```

而只接收：

```text
order_id
```

然后获取 CheckoutSnapshot。

---

# 二十七、Payment Boundary

必须保持：

```text
Order Checkout
负责：
商业事实 + 最终金额 + readiness

PaymentSession
负责：
支付执行
provider session
idempotency
PSP state
```

交接：

```text
Order READY
↓
amount_due
currency
price_version
↓
PaymentSessions::Start
```

P1 不允许 Checkout Service 调 Stripe SDK。

---

# 二十八、No Money-State Regression

继承 P0：

```text
Payment 创建前
checkout stale
→ 可以阻止新支付

PSP 已成功
→ checkout 后续 stale
→ 不得重新创建第二次支付
```

任何 P1 修改不得造成：

```text
PSP SUCCESS
+
Local checkout stale
+
Customer asked to pay again
```

---

# 二十九、Trace

P0 已有：

```text
order
→ payment_session
→ payment
→ provider
→ webhook
```

P1 需要扩展为：

```text
order
→ checkout_version
→ price_version
→ payment_session
→ payment
→ provider
→ webhook
```

目标是能排查：

> 某次 Payment 是基于哪个 Order Checkout 版本产生的。

---

# 三十、CHK-P1-4：Unified Frontend

最终 Storefront：

```text
CheckoutPage
↓
CheckoutView
```

包含：

```text
ContactSection

AddressSection

ShippingSection

PromotionSection

BillingSection

OrderSummary

PaymentSection
```

所有 mutation：

```text
User Input
↓
Server
↓
CheckoutView
↓
Render
```

Frontend 不独立维护 authoritative business state。

---

# 三十一、PaymentSection

CheckoutPage 不直接调用 PSP SDK。

保持：

```text
CheckoutPage
↓
PaymentSection
↓
Provider-specific UI
```

现有 Card Elements / PaymentElement / Express 等路径是否合并，必须基于 P1-0 审计。

P1 不强制统一 Stripe Components。

---

# 三十二、CHK-P1-5：Express Consolidation

P0 已完成：

```text
Express idempotency
Express server amount
```

本阶段只做：

```text
Express
↓
Canonical Order Checkout facts
↓
PaymentSession
```

逐步减少：

```text
Cart-domain compatibility checkout
```

使用 P0 的：

```text
LEGACY_FLOW_BASELINE
usage metrics
```

决定迁移范围。

---

# 三十三、CHK-P1-6：Legacy Checkout Governance

针对：

```text
Order::Checkout
checkout_flow
checkout_steps
registry
requirements
```

只有 P1-0 确认安全后才允许：

```text
wrap
deprecate
isolate
remove dead code
```

如果 provider/admin 仍有复杂依赖：

输出：

```text
DEFER_TO_LATER
```

不得为了 P1 DoD 强拆。

---

# 三十四、测试要求

最终至少覆盖：

## Checkout Application Layer

* address update
* shipping selection
* promotion apply/remove
* refresh
* CheckoutView generation

## Version

* stale update rejected
* concurrent update protected
* version increments correctly

## Price Version

* shipping change
* coupon change
* relevant address change
* item change

正确更新。

## Invalidation

* address invalidates shipping
* address invalidates tax
* items invalidate price
* promotion recalculates price

## Expiration

* expired checkout cannot start new payment
* refresh restores valid checkout if conditions remain valid

## Readiness

* missing address
* missing shipping
* stale tax
* stale price
* expired
* fully ready

## Snapshot

* ready order creates complete snapshot
* not-ready rejected
* expired rejected
* contains version + price_version

## Frontend

* consumes CheckoutView
* does not recalculate authoritative total
* CheckoutPage does not directly call PSP SDK

## Payment Regression

P0 payment regression baseline must stay green.

## Order Regression

Existing order-flow regression baseline must stay green.

---

# 三十五、Acceptance Criteria

至少：

```text
AC-100
Canonical checkout 数据所有权明确且没有重复 Checkout 聚合。

AC-110
Storefront 能消费统一 CheckoutView。

AC-120
Address change 正确触发 Shipping/Tax/Price invalidation。

AC-130
Shipping 变化由 Server 更新 authoritative total。

AC-140
Promotion 变化正确更新 price_version。

AC-150
Frontend 不计算 authoritative total。

AC-160
Stale mutation 被版本机制拒绝。

AC-170
Expired/stale checkout 无法直接开启新的支付。

AC-180
Checkout Readiness 由 Server 唯一判定。

AC-190
READY Order 可以生成完整 CheckoutSnapshot。

AC-191
NOT READY Order 无法获得 transaction-grade Snapshot。

AC-192
Snapshot 包含 checkout version + price version。

AC-200
只给 order_id 可获取未来 OTS 所需的可信交易输入。

AC-210
CheckoutPage 不直接依赖 PSP SDK。

AC-220
Express 使用 Canonical Order Checkout facts。

AC-230
P0 Payment regression baseline 全绿。

AC-240
Order flow regression baseline 全绿。

AC-250
未创建 CheckoutSession / 第二套 Pricing Engine / Order 数据镜像体系。
```

---

# 三十六、Definition of Done

P1 最终必须达到：

```text
Cart
↓
Submit
↓
Order
↓
Order Checkout Application Layer
↓
CheckoutView
↓
Server Readiness
↓
CheckoutSnapshot
↓
Future OTS
```

并明确确认：

```text
没有独立 CheckoutSession

没有复制 Order 数据

没有新 Pricing Engine

没有 PaymentAttempt

没有 Router

没有 OTS

没有破坏 Payment P0
```

---

# 三十七、最终报告

全部完成后输出：

```text
CHECKOUT_P1_COMPLETION_REPORT
```

必须包含：

```text
Architecture Before / After

Checkout Data Ownership

Canonical / Legacy Flow

Application Layer

CheckoutView Contract

Version Strategy

Price Version Strategy

Invalidation Graph

Expiration / Refresh

Readiness Rules

CheckoutSnapshot Contract

Payment Handoff Contract

Frontend Consolidation

Express Consolidation

Legacy Order::Checkout Governance

DB Migrations

API Changes

Regression Matrix

Rollback Strategy

Remaining Technical Debt

OTS Readiness
```

---

# 三十八、本轮执行指令

**本轮只执行 CHK-P1-0。**

要求：

* 纯只读
* 禁止修改代码
* 禁止创建 migration
* 禁止新增模型
* 禁止生成 CheckoutSession
* 禁止直接开始 P1-1

完成审计后停止。

最终只输出：

```text
CURRENT_CHECKOUT_ARCHITECTURE

CHECKOUT_DATA_OWNERSHIP

CANONICAL_FLOW

LEGACY_FLOW

CURRENT_PRICE_FLOW

CURRENT_ADDRESS_FLOW

CURRENT_SHIPPING_FLOW

CURRENT_PROMOTION_FLOW

CURRENT_TAX_FLOW

PAYMENT_HANDOFF_FLOW

FRONTEND_CHECKOUT_ARCHITECTURE

PAYMENT_COMPONENT_USAGE_MATRIX

LEGACY_ORDER_CHECKOUT_STATE_MACHINE_USAGE

P1_PRD_OVERLAP_MATRIX

P1_REUSE_MATRIX

P1_CHANGE_PLAN

P1_DB_DESIGN_PROPOSAL

P1_FILE_CHANGE_LIST

P1_RISK_LIST
```

然后停止，等待评审。

建议第一轮就只使用最后这一条执行要求，让 AI **只做 CHK-P1-0 审计**；等它把 `Order::Checkout` 遗留依赖、真实 version 能力、Order 数据所有权和现有 PRD 重叠全部查清，再决定 CHK-P1-1 是否需要新增字段或 migration。
