# REQ-20260919-checkout-billing-details-passthrough

> 任务：`（gate 时回填 TASK-ID）` ｜ Gate：`（待创建）` ｜ 风险：待 `risk check`
> 关联 PRD：`docs/prd/checkout/PRD-20260919-checkout-billing-details-passthrough.md`（draft）

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

关键词：`billing_details` / `billingDetails` / `billing_mode` / `billing_address` / `bill_address` / `IncompleteBillingAddress`。

| 层 | 搜索路径 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|
| App — models/controllers/views | `backend/app/` | 无（宿主不构造 Stripe 载荷） | 否（无需改） |
| Core Gem — services | `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/` | `carts/update.rb#assign_billing_mode` + `#validate_billing_address!`（**`custom` 且字段不齐 → `IncompleteBillingAddress` 回滚**）、`carts/submit.rb`（账单快照：显式优先，否则复制配送）、`order_checkout/view.rb#billing_mode`（只读派生） | 部分：契约已存在 → 本需求只加「钱包账单不完整 → 降级 `same_as_shipping`」，**不改写路径语义** |
| API Gem | `backend/pallastrade_gems/pallastrade_api/app/` | `store/carts_controller.rb`（参数白名单含 `billing_mode`）、`serializers/.../checkout_serializer.rb`（`capabilities` / `billing_mode`） | 是：契约无需变更 |
| Admin Gem | `backend/pallastrade_gems/pallastrade_admin/app/` | 无 `billing_details` 相关 | 不适用 |
| Storefront | `storefront/src/` | `CardPaymentForm.tsx:146`（只发 `billing_details.name`）、`ExpressCheckoutButton.tsx:346`（读 `event.billingDetails` → 订单快照 `billing_mode: custom`，**未传 PM**）、`WalletPaymentButtons.tsx:#handleConfirm`（**完全忽略** `billingDetails`）、`UnifiedCheckout.tsx:886`（页面选择 → `billing_mode`）、`lib/utils/express-checkout.ts:145#buildPallasTradeAddress`、`lib/checkout/server.ts:35`（BFF `billing_mode`/`billing_address`） | **否 → 本需求主战场** |
| Platform | `platform/packages/` | 无（SDK 仅承载 `billing_mode` 类型） | 否（无需改） |

额外（Stripe 适配器，属 gem 源码层）：`backend/pallastrade_gems/pallastrade_stripe/app/presenters/pallastrade_stripe/payment_intent_presenter.rb`
（`ship_address_payload` 已发 `shipping`，**无 `billing_details`**）、`.../checkout_session_presenter.rb`（`payment_intent_data`，含 3DS 透传先例）。

### 搜索结论

- **账单信息到 Stripe 的链路整体缺失**（PI/CS 载荷无 `billing_details`；卡表单只发 name）→ 需在 presenter 层新建，前台卡表单补透传。
- **钱包路径存在真实缺陷**：无条件 `billing_mode: "custom"` + 服务端 `IncompleteBillingAddress` 校验 → 钱包地址不完整时支付被卡死。
- **防重复**：不新增 Store API 参数、不新增前端账单输入控件（一期已完成）、不改 `Carts::Update` 语义；服务端只**新增载荷字段**与前台**降级判定**。
- 变更面：2 个后端 presenter（+ 可能的共享构造器）+ 4 个前台组件/工具 + 对应测试 + 文档同步。

## Step 1：Skill 文件咨询（优化迭代 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 定制决策树按「代价从低到高」排序；本仓库对 gem 采用**直接修改 + `# PALLAS-CUSTOM:` 标记**（AGENTS.md §1/§3 第 8 档），升级按 merge 处理 —— 因此 presenter 改动直接落在 `pallastrade_stripe` gem 源码 |
| `ai/skills/pallastrade-payments/SKILL.md` | ✅ 已读 | 「Stripe PaymentIntent mode (5.6)」：PI 模式 `external_id` 直存 `pi_…`，前端 `stripe.confirmCardPayment(pi_secret, { payment_method: { card } })` 消费 `pi_…_secret`；`CheckoutSessionPresenter` 已有「服务端判定 → `payment_intent_data.*` 透传」先例（3DS `request_three_d_secure`），账单详情沿用同一位置 |
| `ai/skills/pallastrade-security/SKILL.md` | ✅ 已读 | 「Sensitive logs」：PII 泄露主要来自参数被写进日志；新增账单字段**不得新增日志/DOM 输出**，只经服务端 → Stripe API 单向发送 |

**按需 Skill（本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ | ✅ 已读 | Checkout 章节：`billing_mode` 语义 + 「取消勾选需完整地址（`billingAddressIncomplete`）」； Express 钱包 canonicalize 的五步顺序（本需求改第 3 步载荷与第 4 步 confirm 参数） |
| `ai/skills/pallastrade-testing/SKILL.md` | ✅ | ✅ 已读 | 「Real factories, not stubs, unless the stubbed thing is external (HTTP, Stripe API)」→ presenter spec 用真实 Order/Address 工厂，只 stub Stripe API 调用 |
| `ai/skills/harness-prd/SKILL.md` | ✅ | ✅ 已读 | 一句话需求 → PRD → 用户确认 → gate → 实施 → AC↔测试映射 → 知识同步 |
| `pallastrade-checkout` / `pallastrade-api-v3` / `pallastrade-data-model` | ❌ | — | 无契约/DB 变更 |

---

## 需求标题

checkout 账单地址二期：把账单详情透传到 Stripe（PI/Checkout Session + 卡支付 PaymentMethod），并显式采纳钱包 `billingDetails`（不完整时降级为同配送而不是支付失败）。

## 任务类型

优化迭代（前端 + Stripe 适配器；零 DB、零 API 契约变更）。

## 需求描述

一期把账单区块的语境、作用域和确认区回显做好了，但账单信息本身**没有真正到达 Stripe**：服务端 PaymentIntent 只发 `shipping`，前台卡表单只发 `billing_details.name`；钱包返回的账单详情只写进订单快照，`or_` 订单页的钱包甚至完全忽略它；更严重的是，钱包账单地址只要有字段缺失（Google Pay 部分地区无邮编），无条件 `billing_mode: custom` 就会撞上服务端 `IncompleteBillingAddress` 校验，导致顾客**无法付款**。

本次把这条链补全：① 服务端两条会话模式（PI / Checkout Session）都带上 `billing_details`（来自 `order.bill_address`，地址不完整则整体不发）；② 结算页卡支付把「同配送 / 自定义」的账单地址作为 `payment_method.billing_details` 随卡提交；③ 钱包确认时显式透传 `event.billingDetails`，并在地址不完整时**降级为 `same_as_shipping`**，保证支付可用。

## 影响范围

- 后端（gem 源码 + `# PALLAS-CUSTOM:` 标记）：`payment_intent_presenter.rb`、`checkout_session_presenter.rb`
- 前端：`CardPaymentForm.tsx`（新 prop）、`UnifiedCheckout.tsx`（投影）、`lib/utils/express-checkout.ts`（映射 + 完整性）、`ExpressCheckoutButton.tsx`、`WalletPaymentButtons.tsx`
- 测试：后端 presenter spec；前台 4 个测试文件
- 文档：PRD/REQ、`pallastrade-storefront` + `pallastrade-payments` Skill、场景库 GS-193
- **零**：DB 迁移、Store API 契约、SDK 类型（除非实施中发现必须）

## 技术方案（初步）

① `PaymentIntentPresenter` 增加 `billing_details`（name/email/phone/address），`bill_address` 缺失或 `address1` 空 → 不发该键；② `CheckoutSessionPresenter` 的 `payment_intent_data` 复用同一构造；③ `CardPaymentForm` 新增可选 `billingDetails` prop → `confirmCardPayment({ payment_method: { card, billing_details } })`；`UnifiedCheckout` 按当前选择投影；④ `express-checkout.ts` 新增 `buildStripeBillingDetails(walletBillingDetails)` + `isCompleteBillingAddress(...)`；⑤ 钱包两入口：完整 → `custom` + 地址 + `payment_method_data.billing_details`；不完整 → `same_as_shipping`（不发地址）。

## 验证方案（AC 映射）

| AC | 命令/测试 |
|---|---|
| AC-001 / AC-002 | 后端 presenter spec（`billing_details` 逐字段 + 缺失不发 + CS 同源） |
| AC-003 | `CardPaymentForm.test.tsx` + `UnifiedCheckout.test.tsx`（同配送/自定义投影、姓名空不发） |
| AC-004 | `ExpressCheckoutButton.test.tsx`（完整 → custom + PM 透传；缺邮编 → same_as_shipping 且不发地址） |
| AC-005 | `WalletPaymentButtons.test.tsx`（订单页钱包透传） |
| AC-006 | `npx harness verify storefront-test --task <TASK-ID>` + 后端 rspec 相关文件 + `checkout-billing-mode-guard` 回归 |
| 格式化/类型 | `pnpm -C storefront check`、`typecheck`、`check:locales` |

## 用户确认

✅ **已确认（2026-09-19）** —— 用户原话：**「实施第 4 项二期」** → 授权按本 REQ 全量实施 FR-001 ~ FR-005。

- **范围（用户授权）**：服务端 `billing_details` 透传 + 卡支付前台透传 + 钱包采纳与降级。
- **实现决策（授权范围内由 AI 确定，非用户逐条点选）**，三条均遵循「不猜、不补、不卡死支付」：
  1. 钱包返回的账单地址不完整（缺 `line1`/`city`/`postal_code`/`country` 任一）→ **降级为 `same_as_shipping`**（用配送地址副本，保证支付可完成；报错会让顾客无路可走）。
  2. `order.bill_address` 不完整或缺失 → **整体不发** `billing_details` 键（绝不发半空地址触发 AVS 误判）。
  3. 前台只**补空位**：Elements / 钱包已收集值优先（Stripe 合并语义），不覆盖网关权威值。
