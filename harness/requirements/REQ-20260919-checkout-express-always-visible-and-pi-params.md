# 需求文档：checkout 快捷支付常显 + Stripe 支付参数层级修复 + 未支付订单详情可见

> 对应 PRD：`docs/prd/checkout/PRD-20260919-checkout-checkout-快捷支付常显-stripe-支付参数层级修复-未支付订单详情可见.md`
> 任务：`TASK-20260919144159-78bf9c2d`
> 用户确认：用户原话「实施」（承接其「先定位根因，再输出解决方案」的根因报告）

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 关键词 | 结果 | 是否满足 |
|---|---|---|---|---|
| App | `backend/app/` | `billing_details` | 仅 Typelizer 序列化类型；无 Stripe 参数构造 | 不适用 |
| Core | `pallastrade_gems/pallastrade_core/app/` | `PaymentSessions::Start` / `bill_address` | Start 调 gateway、不构造 PI 参数；订单快照已含 `bill_address`（上一 PRD） | 已有能力，不改 |
| API | `pallastrade_gems/pallastrade_api/app/` | `payment_sessions` / `transactions` | 控制器仅透传入参给 gateway | 已有能力，不改 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | `billing_details` / `pi_` | 后台不创建 PI；无重复实现 | 不适用 |
| Storefront | `storefront/src/` | `confirmPayment` / `billing_details` / `completed_at` / `TopExpressPay` | ① `CardPaymentForm`：`confirmCardPayment({payment_method:{card, billing_details}})` ✅ 合法；② `ExpressCheckoutButton`：`confirmParams.payment_method_data.billing_details` ✅ 合法；③ `UnifiedCheckout#handlePayNow`：忽略 confirm 返回值 + 未知 code 盲跳结果页 ❌；④ `account/orders/[id]/page.tsx`：`completed_at === null` → notFound ❌；⑤ `TopExpressPay`：`unavailable → null` ❌ | **主战场** |
| Platform | `platform/packages/` | `billing_details` / client_secret | SDK 仅透传会话/PI client_secret，不构造 Stripe 参数 | 不适用 |

### 搜索结论

- **不重复实现**：不新增支付参数构造点；账单信息的合法通路（客户端 PM 级 / 服务端完成回写 / Checkout Session 的 `payment_intent_data`）均已存在，本需求只是**移除唯一的非法顶层参数**。
- **需修改**：
  1. `pallastrade_stripe`：`PaymentIntentPresenter` 去掉顶层 `billing_details`（+ 白名单 spec）；
  2. `storefront`：`handlePayNow` 检查 `confirmPayment` 返回并在失败时留在页内；收紧「未知 code 跳结果页」；
  3. `storefront`：订单详情页放宽未支付订单（复用已有 `OrderPayButton`）；
  4. `storefront`：`TopExpressPay` 常显 + 设备不可用降级展示。
- **防重复证据**：dev 日志（`parameter_unknown` + idempotency_key）证明报错来自服务端 PI 创建；订单实况（`payments=0 / sessions=0 / cart=converted`）证明失败发生在建会话阶段、且无重复下单。

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：本需求是**行为修复**（无新增扩展点），直接改 gem 源码/SDK 前端对应文件，不引入 decorator/subscriber |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | 一句话需求 → PRD（查重）→ 6 层搜索 → 用户确认 → gate → 实施 → AC↔测试 → 知识同步门；本 REQ 即其 Step 0/1 产物 |
| `ai/skills/pallastrade-payments/SKILL.md` | ✅ 已读 | 金额与服务端权威一致；`PaymentSessions::Start` 是唯一入口；**本次新增铁律**：`PaymentIntent.billing_details` 只读，只能经 PM / `payment_intent_data` 设置 |

**按需 Skill（本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ | ✅ 已读 | BFF/组件边界、`degradedDisplay`/`WalletAvailability` 语义、i18n 5 语言 + 键守护、biome 覆盖测试文件 |
| `ai/skills/pallastrade-testing/SKILL.md` | ✅ | ✅ 已读 | 新增能力需 verifier + spec；组件测试与页面测试范式；回归跑 `storefront-test` |
| `ai/skills/pallastrade-api-v3/SKILL.md` | ⚪ | ✅ 已读 | 接口**不变**（无契约同步项）；仅确认错误码透传口径（`extractErrorCode`） |
| `ai/skills/pallastrade-data-model/SKILL.md` | ⚪ | — | 无迁移、无模型改动 |

## 需求描述

1. **P0**：修复 `Received unknown parameter: billing_details`（服务端 PI 顶层参数非法）；卡与钱包均可完成支付。
2. **P0**：支付失败**不跳转**（页内提示 + 可重试）；未知错误码不盲跳结果页。
3. **P1**：订单列表有单但详情 404 → 详情页支持未支付订单（含重付入口）。
4. **P1**：checkout 顶部快捷支付**常显**（设备不可用时降级展示而非整区消失）。

## 影响范围（`harness affected` 输出）

- `backend/pallastrade_gems/pallastrade_stripe/**`（presenter + spec）
- `storefront/src/components/checkout/{UnifiedCheckout,TopExpressPay}.tsx` + 测试
- `storefront/src/app/[country]/[locale]/(storefront)/account/orders/[id]/page.tsx` + 测试
- 知识：`ai/skills/pallastrade-payments/SKILL.md`、`ai/skills/pallastrade-storefront/SKILL.md`、`harness/scenarios/scenarios.json`

## 验收与验证命令

- `npx harness verify billing-details-rspec --task TASK-20260919144159-78bf9c2d`
- `npx harness verify storefront-test --task TASK-20260919144159-78bf9c2d`
- dev 真机：同一购物车完成下单 + 支付（订单 `payment_state=paid`）；未支付订单详情可访问。
