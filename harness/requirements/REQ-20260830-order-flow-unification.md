# REQ-20260830-order-flow-unification

> 关联 PRD：PRD-20260830-checkout-下单链路规范化统一化-场景a-b统一下单页-场景c收银台弹窗-参考阿里国际站（approved）
> 关联 Task：TASK-20260830163006-5f6397c0 ｜ Gate：GATE-2026-08-30T16-30-18

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App | `backend/app/` | shopping_cart / checkout-info / payment_methods | `backend/app/javascript/types/serializers/PallasTradeApiV3Cart.ts`（legacy 类型） | ⚠️ 仅 legacy 类型文件，需随 SDK 同步 |
| Core | `pallastrade_gems/pallastrade_core/app/` | Carts::Submit/Update/UpsertItems/Complete / payment_methods / shipping_method | `services/pallastrade/carts/*.rb`、`models/pallastrade/order.rb`（payment_methods L860）、`models/pallastrade/cart.rb`（belongs_to :shipping_method） | ✅ 后端服务能力完备，无需重构 |
| API | `pallastrade_gems/pallastrade_api/app/` | carts / orders / payment_sessions / payment_combinations / shipping_methods / ShoppingCartSerializer | `controllers/.../store/carts_controller.rb`、`orders_controller.rb`、`serializers/.../shopping_cart_serializer.rb` | ⚠️ `ShoppingCartSerializer` 缺 `payment_methods`（统一下单页需补） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | payment_methods 配置 / checkout | `admin/payment_methods/*`（仅后台配置） | ✅ 无影响 |
| Storefront | `storefront/src/` | cart / checkout / checkout-info / OrderCombinedPay / CombinedPaymentCheckout / PaymentSection / CartDrawer / OrderPaymentContent | `app/[country]/[locale]/.../(storefront)/cart/page.tsx`、`checkout-info/[cartId]/*`、`(checkout)/checkout/[id]/page.tsx`、`components/checkout/OrderPaymentContent.tsx`、`PaymentSection.tsx`、`StripePaymentForm.tsx`、`components/account/OrderCombinedPay.tsx`、`OrderDetail.tsx`、`components/cart/CartDrawer.tsx` | ⚠️ 核心改造层：统一下单页 + 收银台弹窗 + CartDrawer 收敛 |
| Platform | `platform/packages/` | SDK carts/orders/paymentCombinations/shippingMethods / 类型 | `sdk/src/store-client.ts`、`sdk/src/types/index.ts` | ⚠️ SDK 类型需支持 `ShoppingCartSerializer` 新字段（payment_methods） |

### 搜索结论

- **已有能力（复用，不重写）**：后端 `Carts::Submit/Complete`（提交+支付幂等）、`PaymentCombinations::{Create,Complete}`（合并支付）、`Orders::Splitter/AutoSplit`（拆单）、标准状态机；前端 `PaymentSection`（含 `PaymentSectionHandle.submit`，可作收银台弹窗核心）、`StripePaymentForm`、`AddressFormFields`、`OrderPaymentContent`、`OrderCombinedPay` 单笔/多笔分流。
- **需新建**：①统一下单页 `UnifiedCheckout`（`/checkout/[id]` 扩展，替代 checkout-info 独立提交步骤）；②收银台弹窗 `PaymentCheckoutModal`（Dialog）；③订单详情 Pay Now 入口。
- **需修改**：`ShoppingCartSerializer` 补 `payment_methods`；SDK 类型同步；`OrderCombinedPay` 改弹窗；`CartDrawer` 结算入口指向统一下单页（已部分完成 447cbf0）。
- **防重复**：`CheckoutPageContent`（legacy 一页式）保留给存量 `or_` 订单，不复制其逻辑；支付表单复用 `PaymentSection`，不重复实现。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：本需求为前端页面/组件改造 + API serializer 字段扩展，不涉及底层定制模式（events/dependencies/decorators 均不需要）；自定义顺序 Settings→Configuration→Events→Dependencies→…，本需求无需走低优先级定制 |
| `ai/skills/pallastrade-checkout/SKILL.md` | ✅ 已读 | §标准电商流程：`Carts::Submit` 创建 pending Order、`checkout/[or_id]` 纯支付、`OrderCombinedPay` 单笔/多笔分流、`PATCH /customers/me/orders/:id/shipping_address`；本需求统一这些入口 |
| `ai/skills/harness-prd/SKILL.md` | ✅ 已读 | PRD 工作流：`prd new` 查重 → 完整扩充 → 用户确认 → gate 实施 → `prd verify` 验收 → sync-check 知识同步 |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ✅ | ✅ 已读 | Store API 认证（publishable key + JWT/guest token）；`GET /carts/:id` 为购物车读取；订单域支付会话 `POST /orders/:id/payment_sessions`；`Order` serializer 输出 `payment_methods`（order.payment_methods） |
| `pallastrade-storefront` | ✅ | ✅ 已读 | Storefront 架构：server component + client component 分层；`checkout-info` 提交后跳 `/checkout/[or_id]`；支付组件 `PaymentSection`/`StripePaymentForm` 复用 |
| `pallastrade-decorators` | ❌ | — | 不涉及模型/控制器结构变更 |
| `pallastrade-dependencies` | ❌ | — | 不涉及核心服务替换 |
| `pallastrade-events-webhooks` | ❌ | — | 不新增事件/订阅者 |
| `pallastrade-testing` | ✅ | ✅ 已读（既有约定） | RSpec request spec（carts_controller 等）+ vitest 组件测试模式 |
| `pallastrade-i18n` | ✅ | ✅ 已读 | 五语言 messages（en/de/fr/es/pl）需同步新增文案 key |

> 本表已全部填写，无"未读"项。

---

## 需求标题

下单链路规范化统一化：场景 A/B 共用统一下单页（左右布局，一页确认+支付），场景 C 个人中心收银台弹窗（仅支付方式信息），参考阿里国际站。

## 任务类型

优化迭代（下单链路统一化，含 API serializer 字段补充）

## 需求描述

1. **场景 A/B**：购物车（cart）进入统一下单页 `/checkout/[cart_id]`，一页内完成收件地址、商品信息、物流方式、支付方式选择与 Pay Now；左侧为订单基础信息，右侧为订单小结；提交后同页无缝切换为订单支付态（`Carts::Submit` 生成 `or_` 订单），不再跳独立确认页。
2. **场景 C**：个人中心订单选择后点 Pay Now，弹出收银台弹窗（仅支付方式 radio + 支付表单 + 应付金额）；单笔直接支付、多笔走合并支付（组合金额 + 各单分摊，不提供逐单收货编辑）；订单详情页补 Pay Now 入口。
3. 兼容：存量 legacy `or_` 订单仍走原 `CheckoutPageContent`；支付幂等、拆单 flag 语义不变。

## 影响范围

- 前端：`(checkout)/checkout/[id]/page.tsx`（分流扩展）、新建 `components/checkout/UnifiedCheckout.tsx`、`components/checkout/PaymentCheckoutModal.tsx`、改 `OrderCombinedPay.tsx`、`OrderDetail.tsx`、`CartDrawer.tsx`（已部分改）、`lib/data/shopping-cart.ts`。
- API：`shopping_cart_serializer.rb`（补 `payment_methods`）。
- SDK：`platform/packages/sdk` 类型生成同步。
- 数据库：无 schema 变更。

## 技术方案（初步）

- **层级**：前端页面/组件改造（决策树第 4 层 Storefront 自定义）+ API serializer 字段扩展（非底层定制）。
- **统一下单页**：`checkout/[id]` 分流扩展——`cart_` 前缀进入 `UnifiedCheckout`（内联 `updateShoppingCartDetails` + `submitCartAndGoToCheckout`，提交后以返回订单渲染支付区）；`or_` 标准订单进入现有 `OrderPaymentContent`（支付区）；legacy `or_` 保持 `CheckoutPageContent`。
- **收银台弹窗**：`PaymentCheckoutModal` 复用 `PaymentSection`（`PaymentSectionHandle.submit`）+ `StripePaymentForm`；多笔先 `createPaymentCombination` 再弹窗。
- **复用**：`PaymentSection`/`StripePaymentForm`/`AddressFormFields`/`Summary` 组件直接复用；后端服务零改动。

## 风险点

- **最高风险**：统一下单页内联「保存+提交+支付」链路长，提交后状态切换（cart_ → or_）需严谨；购物车在提交中途被转换/过期需兜底。
- **回滚难度**：前端为主，改页面/组件；API 仅补字段（向后兼容）。回滚为 revert 前端提交。
- 其他：i18n 五语言同步、legacy 兼容（`or_` 前缀双语义）、弹窗支付成功后状态刷新。

## 决策节点

> ⏸️ 用户已确认 PRD（approved）：①完全阿里式一页确认+支付；②C 弹窗仅显示支付方式；③CartDrawer 同期切换；④合并支付弹窗不扩展收货编辑。设计文档完成后需用户再次确认设计（design-confirmed）。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| 前端组件 | `UnifiedCheckout.tsx`/`PaymentCheckoutModal.tsx`/`OrderCombinedPay.tsx`/`OrderDetail.tsx`/`CartDrawer.tsx` | `pnpm lint` + vitest 组件测试 + 浏览器 E2E 截图 | | ⬜ |
| API serializer | `shopping_cart_serializer.rb` | `harness check --profile quick` + carts spec | | ⬜ |
| SDK 类型 | `platform/packages/sdk` | `pnpm build` + `harness generated:check` | | ⬜ |
| 知识同步 | PRD §9 | `harness sync-check --id PRD-xxx` + `--ack` | | ⬜ |
