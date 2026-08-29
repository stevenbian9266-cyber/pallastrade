# 需求文档 REQ-20260829-stripe-checkout-sessions

> 关联 PRD：`docs/prd/payments/PRD-20260829-payments-升级-stripe-支付从-payment-intents-迁移到-checkout-sessions-api-ui_m.md`（approved）
> 关联 Task：TASK-20260829064700-15a7d705 / Gate：GATE-2026-08-29T06-47-22

## Step 0：跨层搜索（已完成，见 PRD §6 与 Explore 调研报告）

| 层 | 搜索关键词 | 找到的文件 | 是否满足 |
|---|---|---|---|
| App `backend/app/` | stripe/payment | 仅生成 types | 无需改动 |
| Core `pallastrade_core/app/` | payment_session/payment_combination/handle_webhook | `payment_session.rb`、`payments/handle_webhook.rb`、`payments/payment_combinations/*` | 契约保持，适配 |
| API `pallastrade_api/app/` | payment_sessions/webhooks | `webhooks/payments_controller.rb` 等 | 无需改 |
| Admin `pallastrade_admin/app/` | payment/stripe | `payment_methods_controller.rb` | 无需改 |
| Storefront `storefront/src/` | stripe/PaymentElement/confirmPayment | `checkout/{StripePaymentForm,PaymentSection,ExpressCheckoutButton,CombinedPaymentCheckout}.tsx`、`lib/data/{payment,express-checkout-flow}.ts` | **前端主改动区** |
| Platform `platform/packages/` | stripe/payment | sdk 类型 | 无重复 |

**结论**：后端改动集中在 `pallastrade_stripe` gem（gateway/payment_sessions、PaymentSessions::Stripe、webhook handlers）；前端改动集中在 checkout 组件。无重复实现。

## Step 1：Skill 咨询

| Skill | 状态 | 关键结论 |
|---|---|---|
| `pallastrade-customization` | ✅ 已读 | 决策树：支付网关属 Admin Settings；本迁移属 gem 内部实现改造（Direct Gem Modification 层级） |
| `pallastrade-payments` | ✅ 已读 | PaymentMethod type shorthand（stripe）；`preferences{publishable_key, secret_key}`；PaymentSession 模型与 webhook 接线（HandleWebhook + CompleteOrderFromSessionJob） |
| `pallastrade-prd` | ✅ 已读 | PRD 流程：一句话需求 → 查重 → PRD → 用户确认(approved) → gate → 实施 → AC 测试 → 知识同步门 |
| `pallastrade-storefront` | ✅ 已读 | 客户端组件规范；Stripe 依赖版本满足迁移要求 |
| `pallastrade-api-v3` | ✅ 已读 | API v3 前缀 ID / store 作用域 / generated:check |

## 需求标题：Stripe 支付从 Payment Intents 迁移到 Checkout Sessions API（ui_mode=elements）

### 分阶段实施计划（用户已确认）

**阶段 1（后端）**：
- 新增 `CheckoutSessionPresenter`（替代 PaymentIntentPresenter 的 session 路径）
- `gateway/payment_sessions.rb`：`create_payment_session` 改调 `Stripe::Checkout::Session.create`（mode=payment, ui_mode=elements, line_items, customer, return_url, payment_intent_data 保留 transfer_group/setup_future_usage/capture_method）；`external_id=cs_`；去 ephemeral_key
- `models/pallastrade/payment_sessions/stripe.rb`：鸭子类型适配（retrieve_checkout_session → expand payment_intent → charge；payment_status 判定）
- Webhook：`gateway.rb` WEBHOOK_EVENT_ACTIONS + configuration.rb 增加 `checkout.session.*`；新增 handler；`config/initializers/stripe.rb` 订阅同步
- `complete_payment_session` / `verify_payment_intent_matches!` 适配 session 语义
- 测试：gateway/payment_sessions spec、webhook handler spec、PaymentSessions::Stripe spec

**阶段 2（前端）**：
- `StripePaymentForm.tsx`：新卡主链路验证（Elements+client_secret 兼容）；`confirmWithSavedCard` 重构
- `PaymentSection.tsx`：保存卡分支适配
- `ExpressCheckoutButton.tsx`：Express 确认语义重构
- `CombinedPaymentCheckout.tsx`：补渲染 Elements
- `lib/data/express-checkout-flow.ts`：不再传 stripe_payment_method_id
- 测试：组件测试 + e2e checkout.spec.ts（4242）

**阶段 3（收尾）**：
- `backend/public/api-docs/store.yaml` + `platform/docs/api-reference/`（generated:check）
- `ai/skills/pallastrade-payments/SKILL.md` 同步
- scenarios.json（如涉及）+ PRD 状态 → done + README 索引

### 验收（AC → 测试）

见 PRD §5（AC-001~009）。核心：cs_ session 创建、webhook checkout.session.completed 完成订单、新卡 4242 E2E、保存卡/Express/合并支付回归、generated:check 通过。

### 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-29 | 0.1 | 初稿 | AI |
