# PRD-20260831-payments-stripe-自绘卡支付表单-paymentintent-模式

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-08-31 |
| 来源 | bug：商品详情页 → add to cart → checkout → 填地址 → 卡在 Stripe 表单渲染 → 进入购物车为空页面 |
| 分类 | payments（自动判定） |
| 关联 Skill | pallastrade-payments、pallastrade-api-v3、pallastrade-storefront |
| 关联 REQ | REQ-20260831-stripe-自绘卡支付表单.md |
| 关联 PRD | N/A（全新需求；与 PRD-20260829-payments Checkout Session 迁移互补） |
| 需求类型 | Bug 修复 + 优化迭代 |

> 🔁 **查重回写**：`harness prd new` 自动查重（相似度 > 0.3 阻止新建）。本需求为全新方向，无相似 PRD。

## 1. 背景与目标

- **一句话需求原文**：bug：商品详情页，点击 add to cart 按钮，会弹出 cart，点击 checkout 按钮，进入下单页面，填写好地址后，会卡在 stripe 卡支付表单组件渲染，渲染不出来，会进入购物车为空页面，提示：# Your cart is empty...这是不对的，检查根因。另外，我希望 stripe 卡支付表单组件最开始就被渲染出来，有没有更好的方式实现？比如自己写卡支付字段，然后点击 pay now 按钮，再调用 stripe 支付？
- **背景**：
  - 当前下单页（`UnifiedCheckout`，checkout/cart_xxx）使用 `CheckoutProvider` + `PaymentElement`（`@stripe/react-stripe-js/checkout`）渲染 Stripe 卡表单。
  - PaymentElement 是**懒加载 iframe**：必须等后端 `createOrderPaymentSession` 返回 `client_secret`（Checkout Session 的 `cs_...` secret）后才初始化，且依赖 `js.stripe.com` 加载。在 CN 网络下 `js.stripe.com` 加载极不稳定（本会话多次 `ERR_TIMED_OUT`），导致表单卡在 "Loading payment form..."。
  - `UnifiedCheckout` 有"自动预显示" useEffect：地址填完 `canSubmit=true` 后 250ms 自动 `submitCartForPayment()`——**把 cart 购物车转成 or_ 订单**，然后创建 Checkout Session。若 PaymentElement 随后渲染失败，页面仍停留在 `/checkout/cart_xxx`，但 cart 已非 active。
  - 叠加 c6e2a9d 新增的 `isActiveCart` 检查（`cart.ts`：`status !== "active"` 返回 null + 清 cookie）→ `getCart` 返回 null → 页面显示 "Your cart is empty"。
  - 即：**自动提交转换 cart + PaymentElement 懒加载失败 + isActiveCart 新逻辑** 三者叠加产生空购物车。
- **目标**：
  1. **根治** Stripe 表单渲染依赖：改为**自绘卡字段**（number/expiry/cvc），表单在进入下单页/选中 Stripe 时**立即渲染**，不依赖 `client_secret` / `js.stripe.com` iframe。
  2. **根治**空购物车：移除"自动预显示" useEffect（不再提前把 cart 转订单）；提交订单成功后若停留 cart 页，明确跳转 or_ 支付页。
  3. 支付语义：填卡后点 **Pay Now** 才调用 Stripe 支付（`createPaymentMethod` + `confirmCardPayment`），符合用户预期。
- **成功指标**：
  - 下单页选中 Stripe 后表单**即时渲染**（无 "Loading payment form..." 空白期）。
  - CN 网络下 `js.stripe.com` 加载失败时，表单仍可见（卡字段为纯 HTML），仅确认支付时才依赖 Stripe.js。
  - 无 "Your cart is empty" 误报（cart 转订单后页面正确跳 or_ 支付页或完成页）。

## 2. 用户故事 / 场景

- 作为顾客，我希望在下单页填写地址后立即看到卡支付表单，以便快速完成支付，不被加载态卡住。
- 正常流 S1：商品页 → add to cart → cart → Checkout → 下单页填地址 → **卡表单立即显示** → 填卡 → Pay Now → 支付成功 → order-placed。
- 边界流 S2：网络差（js.stripe.com 超时）→ 卡表单仍显示（纯 HTML 字段）→ 填卡 → Pay Now → 若确认支付时 Stripe.js 加载失败 → 明确错误提示，不跳空购物车。
- 异常流 S3：支付被拒/3DS 验证 → 错误提示保留在表单，订单已提交（or_）→ 页面跳转 or_ 支付页可重试。
- 异常流 S4：下单页提交订单成功但支付未完成（用户离开）→ 下次进入显示 or_ 支付页而非空购物车。

## 3. 功能需求（FR）

- FR-001：后端 `create_payment_session` 支持 **PaymentIntent 模式**（`mode: 'payment_intent'`）：创建 `Stripe::PaymentIntent`，`external_id` 存 `pi_` id，`external_data.client_secret` 存 `pi_..._secret`（`confirmCardPayment` 可消费）。默认保持 Checkout Session 模式（兼容 PRD-20260829 迁移、合并支付、Express Checkout）。
- FR-002：`PaymentSessions::Stripe` 模型适配双模式：`external_id` 以 `pi_` 开头 → 直接 `retrieve_payment_intent`；`cs_` → 走 `retrieve_checkout_session`。`stripe_payment_intent` / `successful?` / `accepted?` 语义按模式解析。
- FR-003：`complete_payment_session` 适配 pi_ 模式：直接 retrieve PaymentIntent 验证金额/币种 + 状态，复用现有 `find_or_create_payment!` / Payment 状态机 / 订单完成路径。
- FR-004：Webhook 双路径（`parse_webhook_event` / `WebhookHandlers::Base#resolve_payment_session`）适配 pi_ 直存：`payment_intent.*` 事件先按 `external_id` 直查，未命中再反查 Checkout Session。
- FR-005：前端新建 `CardPaymentForm.tsx`：自绘卡号/有效期/CVC 字段（格式化 + 卡品牌检测 + Luhn 校验），暴露 `confirmPayment(clientSecret)` handle，内部 `stripe.createPaymentMethod({type:'card', card:{...}})` + `stripe.confirmCardPayment(pi_secret, {payment_method})`。
- FR-006：`UnifiedCheckout` 移除"自动预显示" useEffect（不再提前提交订单）；Stripe 分支改为**始终渲染** `CardPaymentForm`（无需 secret）；Pay Now → `submitCartForPayment`（提交订单）→ `createOrderPaymentSession(orderId, method.id, { external_data: { mode: 'payment_intent' } })` → `CardPaymentForm.confirmPayment(secret)` → 成功 → completeOrderPaymentSession + completeOrder → order-placed；失败 → 跳转 or_ 支付页可重试。
- FR-007：`OrderPaymentContent`（or_ 支付页）同步替换为自绘卡表单 + PaymentIntent 模式，与下单页一致。
- FR-008：`PaymentCheckoutModal`（收银台弹窗单笔）同步替换；组合支付（PaymentCombination）保持 Checkout Session（FR-001 默认模式）。

## 4. 非功能需求（NFR）

- **安全**：PCI 合规不变——卡数据经 `stripe.createPaymentMethod` 加密直传 Stripe，**不经过本服务器**；卡号不进日志/DB。
- **兼容**：Checkout Session 模式全保留（合并支付/Express Checkout/保存卡/手动捕获/webhook 异步完成），仅新增自绘卡字段分支。
- **可维护**：前端自绘卡字段为纯 React（无 iframe 依赖）；后端 mode 参数显式传递。
- **性能**：表单渲染零网络等待；PaymentIntent 创建一次 API 调用。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：`POST /orders/:id/payment_sessions` 传 `external_data.mode=payment_intent` → 返回 session 的 `external_data.client_secret` 以 `pi_` 开头，`external_id` 以 `pi_` 开头（后端 spec）。
- AC-002 ← FR-002：`PaymentSessions::Stripe#stripe_payment_intent` 对 pi_ 模式直接 retrieve，cs_ 模式走 checkout session（模型 spec）。
- AC-003 ← FR-003：pi_ 模式 complete 后 Payment 创建、状态机正确、订单完成（请求 spec / 集成验证）。
- AC-004 ← FR-004：`payment_intent.succeeded` webhook 对 pi_ 直存 session 能解析到本地 PaymentSession（spec）。
- AC-005 ← FR-005：`CardPaymentForm` 渲染卡号/有效期/CVC 输入；无效卡号/过期卡阻止确认并提示（组件测试）。
- AC-006 ← FR-006：下单页选中 Stripe 后**无 client_secret 也立即渲染**卡表单；不再自动提交订单（无自动 useEffect）；Pay Now 全链路支付成功跳 order-placed（浏览器 E2E）。
- AC-007 ← FR-006：支付失败 → 不出现 "Your cart is empty"，跳 or_ 支付页可重试（浏览器 E2E）。
- AC-008 ← FR-007：or_ 支付页选中 Stripe 立即渲染自绘卡表单，Pay Now 完成支付（浏览器 E2E）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | stripe/payment_session | 无业务逻辑（仅生成 types） | 否 |
| Core | `pallastrade_gems/pallastrade_core/app/` | PaymentSession/PaymentIntent | `payment_session.rb`（状态机）、`payment_method.rb`（接口）、`carts/complete.rb` | 部分（接口已存在，无需改） |
| API | `pallastrade_gems/pallastrade_api/app/` | payment_sessions | `orders/payment_sessions_controller.rb`、`carts/payment_sessions_controller.rb` | 部分（透传 external_data 已支持） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | payment/stripe | 无相关 | 否 |
| Storefront | `storefront/src/` | StripePaymentForm/CheckoutProvider/PaymentElement | `UnifiedCheckout.tsx`、`StripePaymentForm.tsx`、`OrderPaymentContent.tsx`、`PaymentCheckoutModal.tsx` | 否（需新增自绘 CardPaymentForm + 改造） |
| Platform | `platform/packages/` | confirmCardPayment/createPaymentMethod | 无（SDK 仅 types） | 否（SDK 已支持 external_data 透传） |

**结论**：后端 PaymentSession 接口已支持透传 `external_data`（含 mode），主要在 **Stripe gem**（`pallastrade_stripe`）增加 PaymentIntent 模式创建/complete/webhook 适配；前端新增自绘卡表单组件并替换 3 处 StripePaymentForm 使用点。无跨层重复能力需防。

## 7. 技术影响

- **后端**（`backend/pallastrade_gems/pallastrade_stripe/`）：
  - `app/models/pallastrade_stripe/gateway/payment_sessions.rb`：`create_payment_session` 支持 `mode: payment_intent`；`complete_payment_session` 适配 pi_。
  - `app/models/pallastrade/payment_sessions/stripe.rb`：双模式解析。
  - `app/models/pallastrade_stripe/gateway.rb`：`parse_webhook_event` 适配 pi_ 直存。
  - `app/services/pallastrade_stripe/webhook_handlers/base.rb`：`resolve_payment_session` 适配 pi_ 直存。
- **前端**（`storefront/src/`）：
  - 新建 `components/checkout/CardPaymentForm.tsx`。
  - `components/checkout/UnifiedCheckout.tsx`：移除自动预显示 useEffect；Stripe 分支换 CardPaymentForm；Pay Now 改 PaymentIntent 确认式。
  - `components/checkout/OrderPaymentContent.tsx`、`PaymentCheckoutModal.tsx`：同步替换。
  - `lib/data/order-payment.ts`：`createOrderPaymentSession` 支持传 `mode`（透传 external_data）。
  - `messages/*.json`：新增卡字段文案（5 语言）。
- 无数据库变更、无新依赖（`@stripe/stripe-js` 已装）。

## 8. 测试计划

- 新增测试：
  - `storefront/src/components/checkout/__tests__/CardPaymentForm.test.tsx`（渲染 + 校验 + 错误提示；mock `@stripe/stripe-js`）— AC-005。
  - 后端 spec：`backend/pallastrade_gems/pallastrade_stripe/spec/...`（PaymentIntent 模式 create/complete/webhook）— AC-001/002/003/004。
- 更新测试：`UnifiedCheckout` 相关组件测试（若有）适配新交互。
- 手动验证：浏览器 E2E（下单页即时渲染表单、Pay Now 成功、失败跳 or_、无空购物车）— AC-006/007/008。
- AC 映射：AC-001~004 → 后端 spec；AC-005 → CardPaymentForm 组件测试；AC-006/007/008 → E2E。

## 9. 文档同步清单（知识同步门）

- [x] API 文档：无新端点（复用 `/orders/:id/payment_sessions`，external_data 已有）；`backend/public/api-docs/*.yaml` 已评估无需更新（mode 为 external_data 自由字段）。
- [x] Skill 文档：`ai/skills/pallastrade-payments/SKILL.md` 已增加 PaymentIntent 模式说明（doc-impact 规则：stripe gem 改动）。
- [x] README / 场景库：`docs/prd/README.md` 索引已登记（PRD 关联到 payments 分类）。
- [x] 本 PRD 状态更新 + `docs/prd/README.md` 索引。

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-31 | 0.1 | 初稿 | AI |
| 2026-08-31 | 0.2 | 实施完成。最终方案：①cart 页 Pay Now = 提交订单 + 立即跳 or_ 支付页（?pm= 预选），支付确认在 or_ 页完成（同页支付会触发 Next.js server action 自动 refresh → checkout 页重定向回购物车竞态 = 空购物车根因）②Stripe.js v8 禁原始卡字段（PCI SAQ-A）→ 经典 Elements 三字段自绘表单（视觉等同自绘，仅需 publishable key 即时渲染）③后端 PaymentIntent 模式（pi_ 直存 + webhook 兜底）④修复嵌套路由 find_order（params[:id] 误取 ps_ 会话 id → complete 404）⑤active complete 后驱动 Carts::Complete（webhook 对已 completed 会话提前返回 → 订单否则永远 pending）。E2E 验证：订单 R835036135 全链路 paid 直达 order-placed（无空购物车）。 | AI |
