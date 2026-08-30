# REQ-20260830-order-module-single-combined-payment

> 关联 PRD：`docs/prd/checkout/PRD-20260829-checkout-订单模块-单笔走现有checkout-多笔走组合支付新流程-收货信息独立填写.md`（approved 2026-08-30）
> 任务：TASK-20260829221552-2d7e8025 ｜ Gate：GATE-2026-08-29T22-20-31

## Step 0：跨层搜索

| 层 | 搜索路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | 合并支付 | —（组合支付在 gem 层） | N/A |
| Core | `pallastrade_core/app/` | PaymentCombination、UpdateContactInformation、Checkout::Update | `payment_combination.rb`、`payments/payment_combinations/*`、`orders/update_contact_information.rb`（仅 email）、`checkout/update.rb`（地址更新+IDOR 校验+country_iso→id） | 组合载体 ✅；订单地址更新 ❌（需新增） |
| API | `pallastrade_api/app/` | payment_combinations、customers/me/orders、shipping_address | `store/payment_combinations_controller.rb`、`store/customer/orders_controller.rb`（只读）、`store/carts_controller.rb`（Carts::Update 地址模式） | 组合创建/查询 ✅；订单收货地址更新 ❌（需新增） |
| Admin | `pallastrade_admin/app/` | 订单地址编辑 | `admin/orders/shipping_address_controller.rb`（ship_address_attributes 模式） | Admin ✅；Store 侧需新增 |
| Storefront | `storefront/src/` | OrderCombinedPay、CombinedPaymentCheckout、checkout/[id]、AddressBlock、AddressFormFields | `components/account/OrderCombinedPay.tsx`（多选→组合，无分流）、`components/checkout/CombinedPaymentCheckout.tsx`（组合收银台，无收货步骤/无明细）、`app/.../(checkout)/checkout/[id]/page.tsx`（or_ 订单→OrderPaymentContent 纯支付 ✅）、`app/.../(storefront)/checkout-info/[cartId]/AddressFormFields`（地址表单 ✅ 可复用） | 分流 ❌（需改）；合并流程收货/明细 ❌（需新增）；单笔 checkout ✅（复用 P1） |
| Platform | `platform/packages/` | paymentCombinations、orders | `sdk/src/store-client.ts`（paymentCombinations.get 无 expand 参数）、`sdk/src/types/generated/PaymentCombination.ts`（orders?: expand 时返回） | 组合客户端 ✅；expand 支持 ❌（需加）；订单地址更新方法 ❌（需新增） |

**搜索结论**：单笔订单 checkout 已由 P1 实现（`checkout/[id]` 对 `or_` 订单渲染 OrderPaymentContent 只读确认+支付），可复用。需新建：① 后端订单收货地址更新 API；② SDK `paymentCombinations.get` 支持 expand=orders + 订单地址更新方法；③ `OrderCombinedPay` 单笔/多笔分流；④ 合并流程增强（收货步骤 → 商品明细+支付步骤）。

## Step 1：Skill 文件咨询

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：新增 Store API 端点 → 直接在 `pallastrade_api` gem 的 controller 层实现（本项目 gem 为团队产品，直接改 gem 源文件）；行为复用优先于装饰器——订单地址更新复用 `Carts::Update` 的地址赋值模式 + `Checkout::Update` 的 country_iso→id/IDOR 校验，不新增回调/订阅者。 |
| `pallastrade-api-v3/SKILL.md` | ✅ 已读 | Store API 约定：`X-PallasTrade-Api-Key: pk_*`；认证客户 `Authorization: Bearer <jwt>`；prefixed ID；单资源响应 `{ data: {...} }`；所有查询经 `current_store` + 归属校验（本任务：`current_user.orders.for_store(current_store)`）。 |
| `pallastrade-storefront/SKILL.md` | ✅ 已读 | 客户端组件 SDK 调用必须经 `"use server"` action（`getClient()` 仅服务端）；地址表单复用 `AddressFormFields`（P1 已建，含国家/州加载）；金额一律用 API `display_*` 字段，禁止客户端计算；i18n 键存 `messages/*.json` 五语言。 |
| `pallastrade-testing/SKILL.md` | ✅ 已读 | RSpec request spec 模式：`include_context 'API v3 Store guest'` / 认证请求用 JWT；前端 Vitest + @testing-library/react 组件测试；改动必须跑最小验证矩阵。 |

## 需求标题

订单模块：单笔待支付订单走现有 checkout（同 cart），多笔走新合并支付流程（收货信息独立步骤 + 商品明细 + 组合支付），收货信息从支付区拆出。

## 任务类型

新功能（PRD approved）

## 需求描述

- **单笔**：账户订单页勾选恰好 1 笔待支付订单 → 跳 `/checkout/[orderId]`（P1 已实现：只读确认地址/配送 + 支付，不重新填写）。
- **多笔**：勾选 2+ 笔 → 跳合并流程 `combined-payment/[id]`，增强为两步骤：
  1. **收货**：逐单展示/编辑各成员订单收货地址（`PATCH /customers/me/orders/:id/shipping_address` 落库），无地址订单强制填写，全部完成才能进入支付。
  2. **商品 + 支付**：展示所有成员订单商品明细（订单号/商品/数量/小计/运费/合计）+ 组合总金额 + Stripe PaymentElement 支付；支付卡片区域无地址输入。
- 组合支付复用现有 `PaymentCombination`（金额服务端计算、单次扣款、按单分摊、完成后所有成员订单完成）。

## 影响范围

- `backend/pallastrade_gems/pallastrade_api/`（新 controller + 路由 + spec）
- `platform/packages/sdk/`（paymentCombinations.get expand + orders.updateShippingAddress）
- `storefront/src/`（OrderCombinedPay 分流、CombinedPaymentCheckout 两步骤、新组件、i18n、测试）
- 文档：store.yaml、3 个 skill、scenarios.json、PRD README 索引

## 技术方案（初步）

1. **后端**：新增 `Store::Customer::Orders::ShippingAddressController#update`（PATCH `customers/me/orders/:order_id/shipping_address`），`require_authentication!`，订单按 `current_user.orders.for_store(current_store)` 且仅未支付（balance_due / 未 paid）可改；地址赋值复用 `Carts::Update` 模式（shipping_address_id 解析用户地址 / 就地更新挂载地址），country_iso 直接存 Address（Address 模型已支持 country_iso 解析）。
2. **SDK**：`paymentCombinations.get(id, params?, options?)` 支持 `expand`；`orders.updateShippingAddress(orderId, addressParams, options?)`。
3. **前端**：`OrderCombinedPay`：selected.size===1 → `/checkout/[orderId]`；>1 → 创建组合跳 `combined-payment/[id]`。`CombinedPaymentCheckout` 改造：加载组合（expand=orders）→ 步骤 1 收货（AddressFormFields 逐单编辑+保存，校验完整后启用下一步）→ 步骤 2 明细+StripePaymentForm+支付（复用现有会话确认逻辑）。

## 风险点

- R1：单笔订单 `/checkout/[orderId]` 对已下单未支付订单的兼容性——P1 OrderPaymentContent 已按 or_ 订单只读展示，已验证（AC-001 覆盖）。
- R2：地址更新仅限未支付订单，防止已支付订单篡改（controller 校验）。
- R3：合并流程步骤状态（本地 useState，不持久化）——避免破坏既有组合入口；支付会话仍由后端组合完成。
