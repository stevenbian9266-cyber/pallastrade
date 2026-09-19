# PRD-20260919-checkout-billing-details-passthrough

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-19 |
| 来源 | 优化：checkout 账单地址二期 —— Stripe `billing_details` 透传 + 钱包 `billingDetails` 采纳与降级 |
| 分类 | checkout（关键词命中） |
| 关联 Skill | `pallastrade-payments` / `pallastrade-storefront` / `pallastrade-security` / `pallastrade-testing` |
| 关联 REQ | REQ-20260919-checkout-billing-details-passthrough.md（实施时回填） |
| 关联 PRD | 一期：`PRD-20260919-checkout-payment-billing-and-card-form-polish`（其「非目标」明示二期 = 本 PRD）。**不写回** `PRD-20260913-checkout-billing-mode`：该 PRD 定义的是 `billing_mode` 契约语义（已完成、权威），本 PRD 做的是「账单信息 → 网关」的透传与钱包采纳；查重命中 31% 属词汇重合，`--force` 新建。 |
| 需求类型 | 优化迭代（前台 + Stripe 适配器） |

## 1. 背景与目标

- **一句话需求原文**：`实施第 4 项二期`
- **背景**（一期已交付，二期缺口如下）：
  1. **账单信息从未到达 Stripe**：`PaymentIntentPresenter` 只发 `shipping` 不发 `billing_details`；前台卡表单 `confirmCardPayment` 也只发 `billing_details.name`。于是 Stripe Dashboard / Radar / AVS / 卡组织费率与争议取证都拿不到账单地址。
  2. **钱包 `billingDetails` 只落到订单快照**：`ExpressCheckoutButton` 读了 `event.billingDetails` 用于订单 `billing_address`，但**没有**把它作为支付方式级账单详情显式传给 `stripe.confirmPayment`；`or_` 订单页的 `WalletPaymentButtons` **完全忽略**该字段。
  3. **钱包账单地址不完整会卡死支付（真实缺陷）**：钱包路径无条件发 `billing_mode: "custom"`，而 `Carts::Update#validate_billing_address!` 在 `custom` 且字段不齐时抛 `IncompleteBillingAddress` 并回滚事务。Google Pay 在部分地区不返回 `postal_code`、部分钱包不返回 `state` —— 此时顾客**无法完成支付**，且用户看到的是「购物车校验失败」而非「钱包地址不全」。
- **目标**：
  1. 账单详情（姓名 / 邮箱 / 电话 / 地址）**全入口**到达 Stripe（服务端兜底 + 卡支付前台按页面选择精确透传）；
  2. 钱包 `billingDetails` 被**显式采纳**（支付方式级 + 订单快照级），不完整时**降级为同配送**而不是失败；
  3. 两条链路均有测试锁定；金额、3DS、可用性门禁、`billing_mode` 契约零回归。
- **成功指标**：
  - PI/CheckoutSession 载荷在 `bill_address` 完整时含 `billing_details`，缺失时**不含该键**（不伪造、不发半空地址）；
  - 钱包账单地址缺 `postal_code` 的场景可 100% 完成支付（降级 `same_as_shipping`），订单账单快照无半空地址；
  - 卡支付 PM 级 `billing_details.address` 与页面「同配送 / 自定义」选择一致（可断言）。

## 2. 用户故事 / 场景

- 作为**卡支付买家**：我在结算页选择/填写的账单地址，应当随这笔支付一起到 Stripe（而不是空）。
- 作为**钱包买家**：我在 Apple/Google Pay 里选的账单地址应当被采纳；即使钱包没给邮编，我也要能付款成功。
- 作为**卖家/风控**：Stripe Dashboard 与 Radar 能看到账单字段（邮编/国家/州），争议与对账有据。
- 场景：
  1. 正常流（卡 · 同配送）：默认勾选 → 支付成功 → PM/PI 均带账单地址（= 配送地址）。
  2. 正常流（卡 · 自定义）：取消勾选填完整账单地址 → 支付成功 → PM 带该地址。
  3. 正常流（钱包 · 完整）：钱包返回完整地址 → 订单 `billing_mode: custom` + 钱包地址；PM 带同一地址。
  4. **边界（钱包 · 不完整）**：缺 `postal_code`/`state`/`line1` 任一 → 降级 `same_as_shipping`，下单成功，快照 = 配送地址副本。
  5. **边界（订单账单地址缺失/非法）**：服务端不输出 `billing_details`（不发空对象、不发半空地址）。
  6. **异常（`or_` 订单页）**：前端无账单输入，行为不变（不改订单快照），PI 级仍有服务端注入的账单详情。

## 3. 功能需求（FR）

- **FR-001（服务端 · PaymentIntent 级兜底）**：`PallasTradeStripe::PaymentIntentPresenter` 在 `order.bill_address` 存在且 `address1` 非空时输出
  `billing_details: { name, email, phone, address: { line1, line2, city, state, postal_code, country } }`（与既有 `shipping` 对称，子字段缺失不发）；`bill_address` 缺失/非法 → **整体不发** `billing_details`。
- **FR-002（服务端 · Checkout Session 同源）**：elements 模式的 `payment_intent_data` 复用**同一构造逻辑**（不复制实现）。
- **FR-003（前台 · 卡支付按页面选择透传）**：`CardPaymentForm` 增加可选 `billingDetails`（`name` + `address`），在 `confirmCardPayment` 的 `payment_method.billing_details` 提交；`UnifiedCheckout` 按选择投影（同配送 → 配送地址；自定义 → 所填账单地址）；姓名沿用「非空才传」。未传该 prop 的入口（`or_` 订单页 / 收银台弹窗）→ 不传，交由 FR-001 兜底（**不伪造前端没有的数据**）。
- **FR-004（前台 · 钱包采纳与降级）**：
  (a) 把 `event.billingDetails` 透传为 `confirmParams.payment_method_data.billing_details`（Elements 已收集值优先，仅补空位）；
  (b) 完整性判定：`line1` + `city` + `postal_code` + `country` 齐备 → `billing_mode: "custom"` + 钱包地址；任一缺失 → `billing_mode: "same_as_shipping"`（**不发** `billing_address`）；
  (c) 两个钱包入口同源：`ExpressCheckoutButton`（结算页内联 / 顶部快捷 / 购物车抽屉）与 `WalletPaymentButtons`（`or_` 订单页）。
- **FR-005（回归与可观测）**：后端 presenter spec + 前台 vitest 锁定 FR-001..FR-004；`billing_mode` 契约、金额、3DS、可用性门禁零回归。

## 4. 非功能需求（NFR）

- **安全/合规**：只发送订单已持有的账单字段与购物者在钱包/表单中主动提供的字段；**不新增 PII 落库、不写日志、不进 DOM**。
- **兼容**：Store API 契约不变（`billing_mode` / `billing_address` 语义与序列化保持）；不传新 prop 的旧调用方行为不变。
- **可维护**：服务端账单详情构造只有一处实现；前台只有一处映射函数（`buildStripeBillingDetails`）。
- **风险可控**：透传账单地址会启用 AVS —— 只发真实值；订单账单地址不完整时整体不发。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：`bill_address` 完整 → PI 载荷含 `billing_details.address`（逐字段 `line1/line2/city/state/postal_code/country`）；`bill_address` 为 nil 或 `address1` 空 → 载荷**无** `billing_details` 键（不是空对象）。
- AC-002 ← FR-002：elements 模式载荷的 `payment_intent_data.billing_details` 与 PI 模式同值（同一构造器）。
  > ⚠️ **2026-09-19 修正**：本条已被 `PRD-20260919-checkout-express-always-visible-and-pi-params` 推翻 ——
  > dev 真机证明 `payment_intent_data.billing_details` 同样被 Stripe 拒绝（`parameter_unknown: payment_intent_data[billing_details]`）。
  > 账单详情的唯一合法载体是**客户端 PM 级** `billing_details`（+ 支付后 `charge.billing_details` 回读）；
  > 本 PRD 中「服务端上行 billing_details」的两处载体（PI 顶层 / CS `payment_intent_data`）均已移除并加白名单守卫。
- AC-003 ← FR-003：结算页「同配送」→ `confirmCardPayment` 收到 `billing_details.address` = 配送地址；「自定义」→ 等于页面所填；姓名空 → 载荷不含 `name`；未传 prop 的入口 → 不传 `billing_details`。
- AC-004 ← FR-004：钱包地址完整 → `billing_mode: "custom"` + 钱包地址 + `payment_method_data.billing_details` 透传；缺 `postal_code` → `billing_mode: "same_as_shipping"` 且 **不发** `billing_address`。
- AC-005 ← FR-004(c)：`or_` 订单页钱包同样透传 `billingDetails`（此前完全忽略）。
- AC-006 ← FR-005：既有回归全绿（billing_mode 契约守护、两段语义、钱包 canonical、i18n 键守护）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `billing_details` | 无（应用层不触碰 Stripe 载荷） | 不适用（由 gem 承担） |
| Core | `pallastrade_gems/pallastrade_core/app/` | `billing_mode` / `billing_address` / `IncompleteBillingAddress` | `services/pallastrade/carts/update.rb`（`assign_billing_mode` / `validate_billing_address!`）、`services/pallastrade/order_checkout/view.rb`（只读派生） | 部分：契约与校验已存在 → 本 PRD 只加**降级策略**，不改写路径语义 |
| API | `pallastrade_gems/pallastrade_api/app/` | `billing_mode` | `store/carts_controller.rb`（白名单）、`serializers/.../checkout_serializer.rb`（`capabilities` + `billing_mode`） | 是：契约无需变更 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | `billing_details` | 无相关 | 不适用 |
| Storefront | `storefront/src/` | `billing_details` / `billingDetails` / `billing_mode` | `CardPaymentForm.tsx`（只发 `name`）、`ExpressCheckoutButton.tsx`（读 `event.billingDetails` → 订单快照，未传 PM）、`WalletPaymentButtons.tsx`（**完全忽略**）、`UnifiedCheckout.tsx`（页面选择来源）、`lib/utils/express-checkout.ts#buildPallasTradeAddress`、`lib/checkout/server.ts`（BFF） | **否 → 主战场（FR-003/FR-004）** |
| Platform | `platform/packages/` | `billing_details` | 无（SDK 只承载 `billing_mode` 类型） | 不适用 |

**结论**：
- 需**新建**：服务端 `billing_details` 构造（presenter 层，PI + Checkout Session 复用）；前台卡表单 `billingDetails` 透传；钱包两入口的采纳与「完整性 → billing_mode」降级。
- **防重复**：不新增 Store API 参数、不动 `Carts::Update` 校验语义、不新增前端账单输入控件（一期已完成）。
- Stripe 依据：`stripe.confirmPayment` 的 `confirmParams.payment_method_data.billing_details` 与 Elements 收集值**合并且 Elements 优先**（官方文档 `js/payment_intents/confirm_payment`），故前台只「补空位」，不覆盖钱包权威值。

## 7. 技术影响

- 后端（gem 源码直接修改，标 `# PALLAS-CUSTOM`）：
  `backend/pallastrade_gems/pallastrade_stripe/app/presenters/pallastrade_stripe/payment_intent_presenter.rb`、
  `.../checkout_session_presenter.rb`（+ 可能的共享构造器）。
- 前台：
  `storefront/src/components/checkout/CardPaymentForm.tsx`（新增 prop）、
  `storefront/src/components/checkout/UnifiedCheckout.tsx`（投影账单详情）、
  `storefront/src/lib/utils/express-checkout.ts`（新增 `buildStripeBillingDetails` + 完整性判定）、
  `storefront/src/components/checkout/ExpressCheckoutButton.tsx`（采纳钱包账单 + 完整性→降级）、
  `storefront/src/components/checkout/WalletPaymentButtons.tsx`（同上）、
  `storefront/src/lib/utils/stripe-billing.ts`（新增：`isCompleteBillingAddress` / `billingDetailsFromFormData` / `billingDetailsFromWallet`，唯一映射点）、
  BFF `storefront/src/lib/checkout/server.ts`（若需转发新字段——预期**不需要**）。
- 数据库：无迁移。
- 接口：Store API 契约不变（不新增字段、不改序列化）。

## 8. 测试计划

- 新增/更新后端 spec：`backend/pallastrade_gems/pallastrade_stripe/spec/presenters/payment_intent_presenter_spec.rb`（AC-001/AC-002；若无则新建）、`checkout_session_presenter_spec.rb`（AC-002）。
- 新增/更新前台测试：
  `storefront/src/components/checkout/__tests__/CardPaymentForm.test.tsx`（AC-003）、
  `storefront/src/components/checkout/__tests__/UnifiedCheckout.test.tsx`（AC-003 投影）、
  `storefront/src/components/checkout/__tests__/ExpressCheckoutButton.test.tsx`（AC-004）、
  `storefront/src/components/checkout/__tests__/WalletPaymentButtons.test.tsx`（AC-005；若无则新建）、
  `storefront/src/lib/utils/__tests__/stripe-billing.test.ts`（完整性判定 + 两个映射函数）。
- 验证命令：`harness verify storefront-test --task <TASK-ID>`；后端：本地 rspec（Stripe presenter 单测不依赖网络）。
- AC ↔ 测试映射：AC-001/002 → presenter specs；AC-003 → CardPaymentForm + UnifiedCheckout；AC-004/005 → 钱包组件测试；AC-006 → 既有回归 + `checkout-billing-mode-guard`。

## 9. 文档同步清单（知识同步门）

- [x] API 文档：**不涉及**（契约不变）——实施中确认无新增参数/字段，未改 `backend/public/api-docs/*.yaml`
- [x] Skill 文档：`ai/skills/pallastrade-storefront/SKILL.md`（账单透传与钱包降级段）、`ai/skills/pallastrade-payments/SKILL.md`（PI/CS 载荷含 `billing_details`）
- [x] 反模式 / 任务规则 / 场景库：新增 GS-193（账单透传 + 钱包降级）
- [x] 本 PRD 状态更新 + `docs/prd/README.md` 索引（`prd-status-sync`）
- [x] 知识同步门：`harness sync-check --id PRD-20260919-checkout-billing-details-passthrough`
- [x] 验证登记：`harness.config.mjs` 新增 `billing-details-rspec`（Stripe presenter specs）+ `AGENTS.md` §6 验证矩阵行

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-19 | 0.1 | 初稿（draft）：跨层搜索完成，等待用户确认后进入 gate | AI |
| 2026-09-19 | 0.2 | **approved**：用户原话「实施第 4 项二期」→ 本期范围 = FR-001~FR-005（Stripe `billing_details` 透传 + 钱包 `billingDetails` 采纳与降级）；钱包账单地址不完整 → **降级 `same_as_shipping`**；服务端 `bill_address` 不完整 → **整体不发 `billing_details`** | AI |
| 2026-09-19 | 0.3 | **verifying（实施完成）**：新增 `PallasTradeStripe::BillingDetailsPresenter`（唯一构造点，PI 顶‏级 + Checkout Session `payment_intent_data.billing_details` 同源，不完整则整体不发）；前台新增 `src/lib/utils/stripe-billing.ts`（`isCompleteBillingAddress` / `billingDetailsFromFormData` / `billingDetailsFromWallet`）；`UnifiedCheckout` 按页面选择投影 → `CardPaymentForm#billingDetails` → `confirmCardPayment` PM 级；钱包两入口采纳 `event.billingDetails` → `confirmParams.payment_method_data.billing_details` 且地址不完整降级 `same_as_shipping`；验证：`billing-details-rspec` + `storefront-test` 均通过 | AI || 2026-09-19 | 0.4 | **done（dev 验证通过）**：提交 `139be201` → dev 部署（`/opt/pallastrade/.pull-deploy-state-dev` = `139be201… / sha256:4a29ff23…`，容器与状态文件一致；health + nginx smoke 全绿）。① **FR-001/002 服务端（rails runner on dev，真实订单）**：`billing_details` = `{name, email, address{city,country,line1,postal_code,state}}`（无空字段）；无 `bill_address` → `nil`；合成不完整地址（`address1` 空）→ `nil`；PI 载荷同时含 `billing_details` 与 `shipping`；CS `payment_intent_data.billing_details` 与 PI 载荷 **SAME_SOURCE=true**，无账单地址时该键不存在。② **FR-003 前台（浏览器，`/de/de/checkout/cart_gbMHJdmfrX`）**：结算页正常渲染（仅一条第三方 hCaptcha 图片请求被取消，无页面错误），卡表单 `Name auf der Karte` 占位 `(optional)` 且 `required=false`，账单区块「Rechnungsadresse｜Wie Lieferadresse」默认勾选。③ 部署产物 grep：`billingDetailsFromWallet` / `isCompleteBillingAddress` 均存在于 `/app/.next` chunks。④ CI：Storefront / Deploy / AI / Monorepo Contract success。 | AI |