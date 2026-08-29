# PRD-20260829-payments-升级-stripe-支付从-payment-intents-迁移到-checkout-sessions-api-ui_m

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-08-29 |
| 来源 | 升级：stripe提示升级 https://docs.stripe.com/payments/payment-element/migration-ewcs（前台右下角 Stripe 悬浮气泡提示迁移） |
| 分类 | payments（自动判定） |
| 关联 Skill | pallastrade-payments |
| 关联 REQ | N/A（实施时回填） |
| 关联 PRD | N/A（全新需求） |
| 需求类型 | 接口变更 / 优化迭代 |

## 1. 背景与目标

- **一句话需求原文**：升级：stripe提示升级 https://docs.stripe.com/payments/payment-element/migration-ewcs
- **背景**：Stripe 官方建议将 Payment Element 从 **Payment Intents API** 迁移到 **Checkout Sessions API（`ui_mode: "elements"`）**。Payment Intents 需要更多代码，而 Checkout Sessions 可管理税费、运费、折扣、货币换算（Adaptive Pricing 等仅在 Checkout Sessions 可用）。当前 `pallastrade_stripe` gem 是完整的 PI + PaymentElement 集成（`PaymentSessions::Stripe` 包装 `pi_` PaymentIntent；前端 `Elements + PaymentElement + stripe.confirmPayment`）。Stripe 在前台右下角悬浮提示迁移（用户已确认 **全量迁移**）。
- **目标**：将支付主链路从 PaymentIntents 迁移到 Checkout Session（`mode: payment, ui_mode: elements`），保持现有能力不回归：新卡支付、保存卡、Express Checkout（Apple/Google Pay）、合并支付（PaymentCombinations）、手动捕获、Webhook 异步完成。
- **成功指标**：
  - 新卡下单：创建 `cs_` Checkout Session → 前端 Elements 确认 → 完成订单，全链路可用
  - `checkout.session.completed` webhook 可完成订单（不再依赖 `payment_intent.succeeded` 主路径）
  - 保存卡 / Express Checkout / 合并支付 / 手动捕获回归通过
  - 前端 `pnpm check` + 后端 `rspec` 全绿

## 2. 用户故事 / 场景

- 作为 **顾客**，我希望用新信用卡支付，以便完成下单（正常流）
- 作为 **顾客**，我希望用已保存的卡支付，以便快速结账（正常流）
- 作为 **顾客**，我希望用 Apple/Google Pay（Express Checkout）支付，以便免输卡号（正常流）
- 作为 **顾客**，我希望合并支付多笔订单，以便一次付款（正常流）
- 作为 **管理员**，我希望手动捕获授权金额，以便发货后扣款（边界流）
- 作为 **系统**，我希望 webhook 异步完成订单，以便客户关闭浏览器也能履约（异常/可靠性流）
- 作为 **系统**，我希望支付失败/会话过期能正确标记订单，以便客户重试（异常流）

## 3. 功能需求（FR）

- FR-001：后端 `create_payment_session` 改用 `Stripe::Checkout::Session.create`（`mode: 'payment'`、`ui_mode: 'elements'`、`line_items`、`customer`、`return_url`、`payment_intent_data` 保留 `transfer_group` / `setup_future_usage: off_session` / `capture_method` 映射）；`external_id = cs_`；`external_data` 保留 `client_secret`；去掉 `ephemeral_key`（Elements 不需要）。
- FR-002：`PaymentSessions::Stripe` 鸭子类型适配 Checkout Session：`retrieve_checkout_session(external_id)` 后 expand `payment_intent` 再取 charge；`accepted? / successful? / charge_not_required?` 基于 `session.payment_status` / 关联 PI 状态。
- FR-003：Webhook 双路径（新 `HandleWebhook` + 旧 `StripeEvent`）接入 `checkout.session.completed`（→ captured/complete）、`checkout.session.async_payment_succeeded` / `async_payment_failed`、`checkout.session.expired`（→ canceled）；`payment_intent.amount_capturable_updated` 保留（手动捕获授权）；`setup_intent.succeeded` 不变。
- FR-004：前端 `StripePaymentForm` 新卡主链路保持 `Elements + clientSecret + stripe.confirmPayment({ elements, confirmParams: { return_url }, redirect: 'if_required' })`（react-stripe-js 5.6 / stripe-js 8.11 已兼容 Checkout Session client_secret）。
- FR-005：保存卡流程重构：`confirmWithSavedCard`（`confirmCardPayment` 不接受 `cs_` secret）改为 Checkout Session 语义（session 绑定 `customer` 后由 Elements 展示已存卡，或保留 PI 离线路径用于管理端）。
- FR-006：Express Checkout 重构：`createPaymentMethod + confirmPayment(payment_method)` 是 PI 专属；改为 Checkout Session 下 `stripe.confirmPayment({ elements })` 语义（PM 由 session/customer 决定）。
- FR-007：`CombinedPaymentCheckout` 补渲染 Elements（当前只 complete session，未真正确认支付）。
- FR-008：`payment_intents.rb` 离线路径（管理后台 `Payment#process`、`ensure_payment_intent_exists_for_payment`）保留 PI 能力。
- FR-009：OpenAPI / SDK 生成 + 文档同步（`external_data` 去 `ephemeral_key`、新增 `checkout.session.*` webhook 行为）。

## 4. 非功能需求（NFR）

- **兼容**：现有 `pi_` 历史订单/支付记录不迁移；灰度开关（feature flag）保留 PI 路径，可回退。
- **安全**：PCI 合规不变（Stripe.js 直连 `js.stripe.com`）；`return_url` 防开放重定向。
- **可维护**：新增 `CheckoutSessionPresenter` 抽象；`PaymentSessions::Stripe` 鸭子类型集中适配，`CompleteOrder/CreatePayment` 基本不动。
- **性能**：Checkout Session 创建不引入额外外部调用（ephemeral_key 移除反而减少一次调用）。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：`create_payment_session` 返回 `external_id` 以 `cs_` 开头且 `external_data['client_secret']` 存在（gateway spec）
- AC-002 ← FR-002：`PaymentSessions::Stripe#successful?` 对 `session.payment_status == 'paid'` 返回 true（gateway/session spec）
- AC-003 ← FR-003：`checkout.session.completed` webhook → `HandleWebhook` 完成订单（webhook handler spec）
- AC-004 ← FR-004：前端新卡支付 E2E（测试卡 4242）成功下单（storefront e2e）
- AC-005 ← FR-005：保存卡支付回归通过（PaymentSection spec）
- AC-006 ← FR-006：Express Checkout（Apple/Google Pay）回归通过（组件测试）
- AC-007 ← FR-007：合并支付完成时 session 已确认（payment_combinations spec）
- AC-008 ← FR-008：管理后台离线 PI 路径（授权/捕获/退款）不回归（gateway_spec 安全矩阵）
- AC-009 ← FR-009：`harness generated:check` 通过；`pallastrade-payments` SKILL 同步

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | stripe/payment | 无业务逻辑（仅生成 types） | 无需改动 |
| Core | `pallastrade_core/app/` | payment_session / payment_combination / handle_webhook | `models/pallastrade/payment_session.rb`、`services/pallastrade/payments/{handle_webhook,payment_combinations}*.rb` | 会话模型/组合/Webhook 收敛点，契约保持 |
| API | `pallastrade_api/app/` | payment_sessions / webhooks / payment_combinations | `webhooks/payments_controller.rb`、`store/payment_combinations_controller.rb`、`customer/payment_setup_sessions_controller.rb` | 无需改（服务层切换） |
| Admin | `pallastrade_admin/app/` | payment/stripe | `payment_methods_controller.rb` 等 | 无需改动 |
| Storefront | `storefront/src/` | stripe / PaymentElement / confirmPayment | `components/checkout/{StripePaymentForm,PaymentSection,ExpressCheckoutButton,CombinedPaymentCheckout}.tsx`、`lib/data/{payment,express-checkout-flow}.ts` | **主改动区**（FR-004~007） |
| Platform | `platform/packages/` | stripe / payment | `sdk` 类型（paymentSessions） | 无前端支付逻辑重复 |

**结论**：Storefront 层是前端主改动区；后端集中在 `pallastrade_stripe` gem（gateway/payment_sessions + PaymentSessions::Stripe + webhook handlers）。Core/API 契约（PaymentSession、PaymentCombination、HandleWebhook）保持，仅需适配。无重复实现。

## 7. 技术影响

- **后端必改**（`backend/pallastrade_gems/pallastrade_stripe/`）：
  - `app/models/pallastrade_stripe/gateway/payment_sessions.rb`（create/update/complete 改 Checkout Session）
  - 新增 `app/presenters/pallastrade_stripe/checkout_session_presenter.rb`
  - `app/models/pallastrade/payment_sessions/stripe.rb`（鸭子类型适配 cs_）
  - `app/models/pallastrade_stripe/gateway.rb`（WEBHOOK_EVENT_ACTIONS + supported_webhook_events）
  - 新增 `app/services/pallastrade_stripe/webhook_handlers/checkout_session_completed.rb` 等
  - `lib/pallastrade_stripe/configuration.rb`（webhook 事件默认值）
  - `config/initializers/stripe.rb`（旧路径订阅）
- **前端必改**（`storefront/src/`）：`StripePaymentForm.tsx`、`PaymentSection.tsx`、`ExpressCheckoutButton.tsx`、`CombinedPaymentCheckout.tsx`、`lib/data/express-checkout-flow.ts`
- **依赖**：`@stripe/react-stripe-js@^5.6.0`（resolve 5.6.1）、`@stripe/stripe-js@^8.7.0`（resolve 8.11.0）——已满足迁移文档要求（≥5.0.0 / ≥8.0.0），**无需升级**
- **数据库**：无 schema 变更（PaymentSession.external_id 语义变化：pi_ → cs_）
- **接口**：`external_data` 去 `ephemeral_key_secret`；`/api/v3/webhooks/payments/:id` 新增 `checkout.session.*` 事件
- **影响面**：`harness affected --base origin/main` 将覆盖 backend gem + storefront checkout 组件

## 8. 测试计划

- **新增**：
  - `backend/pallastrade_gems/pallastrade_stripe/spec/models/pallastrade/payment_sessions/stripe_spec.rb`（AC-002）
  - `backend/pallastrade_gems/pallastrade_stripe/spec/services/pallastrade_stripe/webhook_handlers/checkout_session_completed_spec.rb`（AC-003）
  - `backend/pallastrade_gems/pallastrade_stripe/spec/models/pallastrade_stripe/gateway/payment_sessions_spec.rb`（AC-001）
- **更新**：
  - `backend/pallastrade_gems/pallastrade_stripe/spec/models/gateway_spec.rb`（安全矩阵保留 + 沙箱 Checkout Session 用例）
  - `backend/spec/support/stripe_helper.rb`（新增 `create_test_checkout_session`）
  - `storefront/src/lib/data/__tests__/payment.test.ts`（external_data 断言更新）
  - 新增 `storefront/src/components/checkout/__tests__/StripePaymentForm.test.tsx`、`ExpressCheckoutButton.test.tsx`（AC-005/006）
  - `storefront/e2e/checkout.spec.ts`（4242 全链路，AC-004）
  - `backend/spec/services/pallastrade/payments/payment_combinations_*_spec.rb`（AC-007）
- **AC 映射**：AC-001~003 → 后端 spec；AC-004~006 → storefront e2e/组件测试；AC-007 → combinations spec；AC-008 → gateway_spec 矩阵；AC-009 → generated:check

## 9. 文档同步清单（知识同步门）

- [ ] API 文档：`backend/public/api-docs/store.yaml`（payment_sessions/combinations 的 `external_data`、webhook 事件）+ `platform/docs/api-reference/`（`generated:check`）
- [ ] Skill：`ai/skills/pallastrade-payments/SKILL.md`（PaymentSession→Checkout Session 语义、webhook 事件表）
- [ ] README / Agent 文件：按 `sync-check` 矩阵判定
- [ ] 场景库：`harness/scenarios/scenarios.json`（如涉及支付能力变更）
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-29 | 0.1 | 初稿（基于调研报告） | AI |
