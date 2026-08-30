# 技术设计 — 下单链路统一化（TASK-20260830163006-5f6397c0）

> 关联 PRD：PRD-20260830-checkout-下单链路规范化统一化；Gate：GATE-2026-08-30T16-30-18

## Part A：现状识别（Baseline）

### A1 业务系统盘点

- **场景 A/B（购物车下单）**：`/cart`（新购物车勾选）→ `/checkout-info/[cartId]`（独立确认页：地址+物流+提交）→ `/checkout/[or_id]`（纯支付页 `OrderPaymentContent`）。目标：合并为统一下单页（一页确认+支付）。
- **场景 C（个人中心）**：`/account/orders`（`OrderCombinedPay` 勾选）→ 单笔跳 `/checkout/[or_id]`、多笔跳 `/combined-payment/[pcom_id]`（两步骤页）。目标：改为收银台弹窗（仅支付方式）。
- **前端系统**：Next.js 16 storefront（`(checkout)` 极简布局 + `(storefront)` 全站布局），SDK `@pallastrade/sdk`。
- **后端系统**：Rails 8.1 + PallasTrade gem 分层（core/api/admin）；新 Cart 实体（`pallastrade_carts`）与 Order（`pallastrade_orders`）分表；合并支付 `PaymentCombination`/`PaymentSplit`；标准状态机（pending→paid→…）+ 拆单引擎（flag 灰度）。
- **已知已修复依赖**：`OrdersController#show` 用 `:show`（105a2cc）；`Carts::Update` 全局 `dm_` 查物流（ca49dd3）；`cart_` 前缀不落 legacy checkout（447cbf0）。

### A2 数据模型识别

- `pallastrade_carts`（`cart_` 前缀）：token/status(active→converted)/email/地址 FK/shipping_method_id/currency/locale + `cart_items.selected` 勾选；**无金额/支付字段**。
- `pallastrade_orders`（`or_` 前缀）：完整电商字段 + `parent_id`/`split_from_id`/`payment_combination_id`/`submitted_at`；`payment_methods` 由 `store.payment_methods.active.available_on_front_end` 派生。
- `pallastrade_payment_combinations` + `payment_splits`：合并支付载体与各单分摊记账。
- **无 schema 变更**（本需求仅读模型 + 一个 serializer 字段补充）。

### A3 字段盘点

| 字段/接口 | 现状 | 变更 |
|---|---|---|
| `GET /carts/:id`（ShoppingCartSerializer） | 输出 `shipping_method_id`、items、地址、item_total；**无 `payment_methods`** | 新增 `payment_methods`（复用 `payment_method_serializer`，与 Order serializer 一致） |
| `GET /orders/:id`（OrderSerializer） | 已输出 `payment_methods` | 不变 |
| 前端 `ShoppingCart` SDK 类型 | 无 `payment_methods` | 同步生成 |
| i18n messages（en/de/fr/es/pl） | 无统一下单页/弹窗文案 | 新增 key |

### A4 代码结构

- **Storefront 页面**：`storefront/src/app/[country]/[locale]/(checkout)/checkout/[id]/page.tsx`（分流：`or_`→`OrderPaymentContent`、`cart_`→checkout-info、legacy→`CheckoutPageContent`）、`checkout/[id]/CheckoutPageContent.tsx`（legacy 一页式）、`checkout-info/[cartId]/CheckoutInfoContent.tsx`（现确认页）。
- **Storefront 组件**：`components/checkout/`（`PaymentSection`[含 `PaymentSectionHandle.submit`]、`StripePaymentForm`、`AddressFormFields`、`DeliveryMethodSection`、`Summary`、`OrderPaymentContent`、`CombinedPaymentCheckout`）；`components/account/OrderCombinedPay.tsx`、`OrderDetail.tsx`；`components/cart/CartDrawer.tsx`。
- **后端**：`shopping_cart_serializer.rb`（补字段）；`Carts::Submit/Complete`、`PaymentCombinations::*`（复用，不改）。
- **SDK**：`platform/packages/sdk/src/types`（ShoppingCart 类型生成）。

## Part B：复用决策矩阵

| 需求点 | 决策 | 目标/方式 | 依据 |
|---|---|---|---|
| 支付方式选择 + 表单 | 调用已有 | `PaymentSection`（`PaymentSectionHandle.submit`） | 现成组件，弹窗与统一下单页共用，避免重复实现 |
| Stripe 支付 | 调用已有 | `StripePaymentForm` | 现成 PaymentElement |
| 收件地址表单 | 调用已有 | `AddressFormFields` | 现成 |
| 物流选择 | 调用已有 | `DeliveryMethodSection` | 现成 radio（dm_ 前缀） |
| 订单小结 | 调用已有 | `Summary` | 现成金额汇总 |
| `or_` 订单支付态 | 调用已有 | `OrderPaymentContent` | 只读地址+支付，直接作为统一下单页支付模式 |
| 购物车提交 | 调用已有 | `submitCartAndGoToCheckout`（Carts::Submit） | 现成 server action，返回 or_ 订单 |
| 合并支付完成 | 调用已有 | `completeCombinationSession`（幂等 Complete） | 现成 server action |
| 商品行列表（下单页左侧） | 新封装公用 | 抽 `OrderLineItems` 小组件 | 多场景（统一下单页/支付页）需独立商品信息展示 |
| 统一下单页 | 新建局部 | `UnifiedCheckout.tsx` | 无现成"购物车内联提交+支付"页 |
| 收银台弹窗 | 新建局部 | `PaymentCheckoutModal.tsx` | 全库无支付弹窗（Dialog 仅地址/灯箱用） |
| legacy 一页式 | 调用已有 | `CheckoutPageContent`（保留存量 `or_`） | 存量兼容，不复制其逻辑到新流程 |

## 技术方案

### 1. 统一下单页（场景 A/B）

- `checkout/[id]/page.tsx` 分流扩展：
  - `cart_`（新购物车）→ 渲染 `UnifiedCheckout`（购物车模式）
  - `or_` 且标准流程（`standard_flow?`）→ `OrderPaymentContent`（支付模式，现有）
  - `or_` legacy → `CheckoutPageContent`（存量兼容）
- `UnifiedCheckout.tsx`（client component）：左侧 `AddressFormFields` + 商品信息（`OrderLineItems`）+ `DeliveryMethodSection` + `PaymentSection` + Pay Now；右侧 `Summary`。Pay Now 流程：校验 → `updateShoppingCartDetails`（PATCH cart）→ `submitCartAndGoToCheckout`（提交生成 or_ 订单）→ `router.replace(/checkout/[order.id])` 同页切换支付态 → 支付区复用 `OrderPaymentContent` 逻辑（createOrderPaymentSession → Stripe → confirm）。
- 边界：购物车 404 → redirect `/cart`；提交中 loading；支付失败可重试。

### 2. 收银台弹窗（场景 C）

- `PaymentCheckoutModal.tsx`（Dialog + `PaymentSection`）：金额（单笔订单金额 / 组合总额+各单分摊）+ 支付方式 radio + 支付表单 + [Cancel]/[Pay Now]。
- `OrderCombinedPay.handlePay` 改为：1 笔 → 打开单笔弹窗；2+ 笔 → `createPaymentCombination` → 打开组合弹窗。
- `OrderDetail.tsx` 补 Pay Now（`balance_due` 且非子订单）→ 打开弹窗。
- 成功 → `updateTag("orders")` + 关闭弹窗 + 刷新；失败 → 弹窗内错误重试。

### 3. API / SDK

- `shopping_cart_serializer.rb` 增加 `many :payment_methods`。
- SDK `ShoppingCart` 类型同步（`generated:check` 验证）。

### 4. i18n

- 五语言新增 key（统一下单页提交按钮态、弹窗标题/分摊/按钮、订单详情 Pay Now），`check-locale-parity.ts` 校验。

## 风险与回滚

- 最高风险：统一下单页内联「保存+提交+支付」状态切换（cart_→or_）链路；购物车提交中途转换/过期兜底。
- 兼容风险：`or_` 前缀双语义（标准 vs legacy）分流需准确（`standard_flow?` 判定）。
- 回滚：前端为主（页面/组件/路由），revert 前端提交即可；API 仅补字段（向后兼容）。
