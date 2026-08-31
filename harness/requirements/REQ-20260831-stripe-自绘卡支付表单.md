# REQ-20260831-stripe-自绘卡支付表单

> 关联 PRD：PRD-20260831-payments-stripe-自绘卡支付表单-paymentintent-模式
> 关联 Task：TASK-20260831152055-8c112760
> 需求类型：Bug 修复 + 优化迭代

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | stripe/payment_session | 无业务逻辑（仅生成 types） | 否 |
| App — views/decorators | `backend/app/` | stripe/payment | 无 | 否 |
| Core Gem — models | `backend/pallastrade_gems/pallastrade_core/app/models/` | PaymentSession/PaymentIntent | `payment_session.rb`（状态机）、`payment_method.rb`（PaymentSession 接口）、`payment_response.rb` | 部分（接口已存在，无需改） |
| Core Gem — services | `backend/pallastrade_gems/pallastrade_core/app/services/` | complete/payment | `carts/complete.rb`（标准分支 pay!+finalize!） | 复用 |
| API Gem — controllers | `backend/pallastrade_gems/pallastrade_api/app/controllers/` | payment_sessions | `orders/payment_sessions_controller.rb`、`carts/payment_sessions_controller.rb`（透传 external_data） | 部分（已支持透传） |
| Admin Gem — controllers | `backend/pallastrade_gems/pallastrade_admin/app/controllers/` | payment/stripe | 无相关 | 否 |
| Admin Gem — views | `backend/pallastrade_gems/pallastrade_admin/app/views/` | payment/stripe | 无相关 | 否 |
| Storefront | `storefront/src/` | StripePaymentForm/CheckoutProvider/PaymentElement | `UnifiedCheckout.tsx`、`StripePaymentForm.tsx`、`OrderPaymentContent.tsx`、`PaymentCheckoutModal.tsx`、`lib/data/order-payment.ts`、`lib/utils/stripe.ts` | 否（需新增自绘 CardPaymentForm + 改造） |
| Platform | `platform/packages/` | confirmCardPayment/createPaymentMethod | 无（SDK 仅 types，external_data 已支持） | 否 |

### 搜索结论

后端 PaymentSession 接口已支持透传 `external_data`（含 mode），核心改动在 **Stripe gem**（`pallastrade_stripe`）增加 PaymentIntent 模式：create/complete/webhook 适配；前端新增自绘卡表单组件并替换 3 处 StripePaymentForm 使用点（UnifiedCheckout / OrderPaymentContent / PaymentCheckoutModal 单笔）。无跨层重复能力需防。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：支付相关 → Payments skill；优先级 1 Settings/Config > ... > 8 Direct Gem Modification。本次后端改动在 Stripe gem 内（team product，可直改），前端新建组件。 |
| `ai/skills/pallastrade-payments/SKILL.md` | ✅ 已读 | PaymentSession 是 5.4+ 现代流程：storefront 创建 session → API 返回 provider session 数据 → 交互 → complete → Payment 创建 → 订单完成。Payment 状态机 checkout→processing→pending→completed。PaymentCombination 组合支付数据层已存在。 |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ✅ | ✅ 已读 | 无新端点，复用 `/orders/:id/payment_sessions`（external_data 透传已有）；Store API 返回 `{data, meta}` 信封、prefixed ID 约定不变 |
| `pallastrade-storefront` | ✅ | ✅ 已读 | 组件/样式规范（自绘卡表单用 Tailwind，禁内联样式 AP-001、禁硬编码色 AP-006） |
| `pallastrade-testing` | ✅ | ✅ 已读 | 后端 RSpec + Factory Bot；Storefront Vitest + Testing Library 组件测试；Capybara E2E |
| `pallastrade-decorators` | ⬜ | — | — |
| `pallastrade-dependencies` | ⬜ | — | — |
| `pallastrade-events-webhooks` | ✅ | ✅ 已读 | Webhook 双路径（HandleWebhook / StripeEvent）事件映射 `WEBHOOK_EVENT_ACTIONS`；`resolve_payment_session` 需适配 pi_ 直存 |
| `pallastrade-i18n` | ✅ | ✅ 已读 | messages/*.json 5 语言（en/de/es/fr/pl）新增卡字段文案，UI strings 走 storefront messages |

---

## 需求标题

Stripe 自绘卡支付表单（PaymentIntent 模式）——根治表单不渲染 + 空购物车 bug

## 任务类型

Bug 修复 + 功能优化

## 背景

下单页使用 CheckoutProvider + PaymentElement（懒加载 iframe，依赖 client_secret + js.stripe.com）。CN 网络下 js.stripe.com 加载失败 → 表单卡 "Loading payment form..."。叠加"自动预显示" useEffect（提前把 cart 转 or_ 订单）+ c6e2a9d isActiveCart 检查 → 空购物车页 "Your cart is empty"。

## 方案（用户已确认）

自绘卡字段（number/expiry/cvc，纯 HTML 立即渲染）+ PaymentIntent 模式后端会话：

1. 后端 `create_payment_session` 支持 `mode: 'payment_intent'`（external_data 透传）→ 创建 `Stripe::PaymentIntent`，`external_id=pi_`，`external_data.client_secret=pi_..._secret`。
2. `PaymentSessions::Stripe` 双模式解析（pi_ 直存 / cs_ 走 checkout session）。
3. `complete_payment_session` 适配 pi_ 模式；webhook 双路径适配 pi_ 直存。
4. 前端新建 `CardPaymentForm.tsx`（自绘卡字段 + createPaymentMethod + confirmCardPayment）。
5. `UnifiedCheckout` 移除自动预显示 useEffect；Stripe 分支始终渲染 CardPaymentForm；Pay Now → 提交订单 → 创建 PaymentIntent 会话 → confirmCardPayment → 完成；失败跳 or_ 支付页。
6. `OrderPaymentContent` / `PaymentCheckoutModal` 单笔同步替换；组合支付保持 Checkout Session。

## 验收标准

- AC-001~004：后端 PaymentIntent 模式 create/complete/webhook（spec）。
- AC-005：CardPaymentForm 组件测试（渲染/校验/错误）。
- AC-006~008：浏览器 E2E（即时渲染、Pay Now 成功、失败跳 or_、无空购物车）。
