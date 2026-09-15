# PRD-20260915-payments-d10-client-config

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-15 |
| 来源 | 需求：D10 前端密钥下发改造 —— 服务端下发 `client_config`（publishable / 短时令牌）+ 前端双读迁移，清理 `NEXT_PUBLIC_*` 依赖 |
| 分类 | payments（依据：业务方案 §78-D10「前端密钥下发改造」） |
| 关联 Skill | `pallastrade-payments`、`pallastrade-api-v3`、`pallastrade-storefront`、`pallastrade-security`、`pallastrade-typescript-sdk`、`pallastrade-testing` |
| 关联 REQ | `harness/requirements/REQ-20260915-d10-client-config.md` |
| 关联 PRD | `PRD-20260915-payments-d9-支付凭据与环境.md`（D9：凭据分级 + environment）；`PRD-20260915-admin-管理后台支付配置选项化…`（D1：入口模型）；`PRD-20260915-payments-d8-…`（D8：前台过滤） |
| 需求类型 | 新功能 |

## 1. 背景与目标

- **一句话需求原文**：D10 前端密钥下发改造：服务端下发 `client_config`（含短时令牌）+ 前端双读迁移（业务方案 §68.4 / §76.1）。
- **背景（代码事实）**：
  - 今天前端支付 publishable 凭据来自**构建期环境变量**：`storefront/src/lib/utils/stripe.ts` 模块级 `loadStripe(process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY)`（三处组件共用 `stripePromise`：`CardPaymentForm` / `StripePaymentForm` / `ExpressCheckoutButton`）；`lib/utils/payment-gateway.ts` 同样构建期读 `NEXT_PUBLIC_PAYPAL_CLIENT_ID` / `NEXT_PUBLIC_ADYEN_CLIENT_KEY`。
  - `NEXT_PUBLIC_*` 会被**内联进客户端包**（`ai/skills/pallastrade-storefront` §「NEXT_PUBLIC_* build/runtime divergence」）→ 换支付商 / 换环境 = 改部署配置 + **重建镜像**；且构建期与运行期不一致会引发 hydration #418（历史 bug）。
  - 服务端侧：`PallasTrade::PaymentMethod#public_preferences` 已按 `public_preference_keys` 投影；D9 已落地凭据分级 `secret / publishable / internal`（`PaymentMethods::Credentials.level`）与 `environment`（test/live，前台过滤 + `test_mode` 打标）。**缺**：provider 未把 `publishable_key` 声明为 publishable（Stripe 仍是 `:password` → 判 secret）；Checkout 契约无 `client_config`；前端无服务端读取路径。
- **目标**：后台配置 publishable 字段 → 服务端在 `CheckoutView.payment.available_payment_methods[].client_config` 下发 → 前端**先读 API 下发值、回落环境变量**；换环境/换支付商不再需要重建镜像。
- **成功指标**：① 后台改 Stripe publishable key 后，前台**无需重新构建**即可用新 key 发起支付；② `client_config` 中不出现任何 secret/internal 级凭据（spec 断言）；③ 契约（OpenAPI + SDK 类型）与后端一致（`generated:check` 零漂移）。

## 2. 用户故事 / 场景

- 作为**运营**，我希望在后台改支付商凭据/环境后前台立即生效，以便不依赖发版。
- 作为**开发**，我希望前端不再硬依赖构建期 `NEXT_PUBLIC_*`，以便环境切换零重建。
- 作为**安全负责人**，我希望只有 publishable 级凭据可以下发前台，secret 永不出服务端。
- 场景：① 后台配好 Stripe publishable → 结账页卡片表单可用（无 NEXT_PUBLIC_ 也能用）；② 未下发（老后端/未配置）→ 前端回落环境变量，行为不变（**双读**）；③ 两处都缺 → 卡片表单进入「未配置」态，不抛错；④ publishable 值是 `env:STRIPE_PUBLISHABLE_KEY` 引用 → 服务端解析后下发（解析失败则省略该键）。

## 3. 功能需求（FR）

- **FR-001**：provider 声明 publishable 凭据 —— `PallasTradeStripe::Gateway` 覆写 `public_preference_keys` 返回 `%w[publishable_key]`（沿用 D9 既有分级机制，**不新增语法**）。
- **FR-002**：服务端组装 `PallasTrade::PaymentMethods::ClientConfig.call(payment_method)` → `{ provider:, environment:, publishable: { <publishable 级偏好> }, session_token: nil }`：
  - 只含 **publishable 级**（`Credentials.level == 'publishable'`）且值非空的键；
  - `env:` 引用经 `Credentials.resolve` 解析（缺失则省略该键）；
  - `session_token` 本期**恒 nil**（短时令牌的 provider 侧签发属后续批次，契约先留位）。
- **FR-003**：Checkout 契约扩展（additive）—— `payment.available_payment_methods[].client_config`；typelize 类型 + `backend/public/api-docs/store.yaml` + SDK/zod 再生成（`scripts/ci/contracts.sh`）。
- **FR-004**：前端双读迁移 —— `storefront/src/lib/utils/stripe.ts` 提供 `resolveStripePublishableKey(clientConfig)`（API 值 → 回落 `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` → null）与 `getStripePromise(key)`（按 key 缓存，避免重复 `loadStripe`）；`CardPaymentForm` / `StripePaymentForm` / `ExpressCheckoutButton` 改从**所选支付方式的 `client_config`** 取值。
- **FR-005**：安全护栏 —— `client_config` 永不含 secret/internal 级凭据；`hide_prices` 不适用（凭据与金额无关）。
- **FR-006**：老契约兼容 —— 未提供 `client_config` 时前端行为不变（回落环境变量）；`PaymentMethod` 既有字段（id/name/type/session_required/…）保持不变。

## 4. 非功能需求（NFR）

- **性能**：`client_config` 由已加载的 `PaymentMethod` 内联计算，**零额外查询**（不触发 provider 网络调用）。
- **安全**：只下发 publishable；日志不落凭据（沿用 D9 脱敏 + `filter_parameter_logging`）。
- **兼容**：契约 additive，老客户端忽略新字段；前端缺省回落。
- **可维护**：`ClientConfig` 为唯一组装点；后续 PayPal/Adyen 只需声明 `public_preference_keys`。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001** ← FR-001：Stripe provider 的 `publishable_key` 被判定为 `publishable` 级（`credential_level(:publishable_key) == 'publishable'`，`secret_key` 仍为 `secret`）。
- **AC-002** ← FR-002：`ClientConfig.call` 输出含 `provider` / `environment` / `publishable`（仅 publishable 级键）/ `session_token`（nil）。
- **AC-003** ← FR-005：`ClientConfig` 输出中**不含**任何 secret/internal 键（如 `secret_key`）。
- **AC-004** ← FR-002：`env:` 引用被解析为 ENV 值；ENV 缺失时该键省略、不抛错。
- **AC-005** ← FR-003：Checkout API 响应 `payment.available_payment_methods[].client_config` 存在且结构符合契约（请求级 spec）。
- **AC-006** ← FR-004：前端 `resolveStripePublishableKey` —— API 值优先；无 API 值时回落 env；两者皆无返回 null（vitest）。
- **AC-007** ← FR-006：缺 `client_config` 时卡片表单/Express 按钮仍可用（回落路径，vitest/渲染断言）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `client_config` / `stripe` / `publishable` | 无命中 | ❌ 未满足（需在 framework 层实现） |
| Core | `pallastrade_core/app/` | `public_preferences` / `Credentials` / `available_payment_methods` | `payment_method.rb`（`public_preferences`、`public_preference_keys`（protected，默认 `[]`）、`credential_level`）、`payment_methods/credentials.rb`（D9 分级/引用解析）、`order_checkout/view.rb#available_payment_methods`、`payments/availability/resolver.rb` | ⚠️ 部分（分级/引用已有 → 复用；缺 publishable 声明与组装服务） |
| API | `pallastrade_api/app/` | `available_payment_methods` / `payment_method_payload` | `serializers/…/store/checkout/checkout_serializer.rb`（`payment_method_payload`：id/name/description/type/session_required/source_required/kind/frontend_kind + typelize 块） | ⚠️ 部分（承载点在位 → 加 `client_config`） |
| Admin | `pallastrade_admin/app/` | `publishable` / payment methods form | `payment_methods` 视图/控制器（D1/D9 已含环境控件 + 凭据健康卡；preference 表单已可编辑 `publishable_key`） | ✅ 已满足（后台无需改动） |
| Storefront | `storefront/src/` | `NEXT_PUBLIC_STRIPE` / `stripePromise` / `client_config` | `lib/utils/stripe.ts`（模块级 env 单例）、`lib/utils/payment-gateway.ts`（PayPal/Adyen env）、`components/checkout/{CardPaymentForm,StripePaymentForm,ExpressCheckoutButton}.tsx`、`OrderPaymentContent.tsx`（`paymentMethods` + `selectedMethod` 装配点） | ❌ 未满足（需双读迁移） |
| Platform | `platform/packages/` | `available_payment_methods` | `sdk/src/types/generated/StoreCheckoutCheckout.ts`、`sdk/src/types/index.ts`、`sdk/dist/*`（生成物） | ⚠️ 需随契约再生成 |

**结论**：承载点唯一且清晰 —— Core 补「publishable 声明 + 组装服务」，API 补 payload 字段，Storefront 补双读；Admin 零改动；Platform 由 `contracts.sh` 再生成。**不新建重复能力**（复用 D9 的 `Credentials` 分级与 `public_preferences` 投影）。

## 7. 技术影响

- **后端**：`pallastrade_stripe/app/models/pallastrade_stripe/gateway.rb`；新增 `pallastrade_core/app/services/pallastrade/payment_methods/client_config.rb`；`checkout_serializer.rb`（typelize + payload）。
- **前端**：`storefront/src/lib/utils/stripe.ts`、`components/checkout/{CardPaymentForm,StripePaymentForm,ExpressCheckoutButton,OrderPaymentContent}.tsx`（装配）+ 对应 vitest。
- **契约**：`backend/public/api-docs/store.yaml`、`platform/docs/api-reference/store.yaml`、`platform/packages/sdk/src/types/generated/StoreCheckoutCheckout.ts`（均由 `scripts/ci/contracts.sh` 生成）。
- **数据库**：无迁移（复用 preferences + D9 `environment`）。
- **影响面**：结账页支付方式列表与卡片/Express 表单；不动后台、不动支付会话/交易链路。

## 8. 测试计划

| 层 | 文件 | 覆盖 AC |
|---|---|---|
| 后端（单元） | `backend/spec/services/pallastrade/payment_methods/client_config_spec.rb` | AC-002/003/004 |
| 后端（provider） | `backend/spec/models/pallastrade/payment_methods/credential_level_spec.rb` | AC-001 |
| 后端（请求） | `backend/spec/requests/pallastrade/api/v3/store/checkout_client_config_spec.rb` | AC-005 |
| 前端 | `storefront/src/lib/utils/__tests__/stripe-client-config.test.ts` | AC-006/007 |
| 契约 | `harness generated:check` | AC-005（类型/OpenAPI 一致） |

## 9. 收口清单

- [x] 本 PRD（approved → **done**，2026-09-15 实施完成）
- [x] REQ：`harness/requirements/REQ-20260915-d10-client-config.md`（含 6 层搜索 + Skill 咨询表 + 实施记录）
- [x] gate `GATE-2026-09-15T14-15-43` + 逐项 prep 清理；task `TASK-20260915141521-e1a110af`
- [x] 用户确认：用户 2026-09-15「实施」（承接「D10 建议下一批」）
- [x] 验证：`harness verify d10-client-config-rspec`（后端 4 文件）+ `storefront-test`（前端全量）+ `generated:check` 零漂移
- [x] 知识同步（`sync-check` 三组十项逐条评估）：**已更新** —— `pallastrade-storefront` / `pallastrade-payments` / `pallastrade-api-v3` Skill、`platform/packages/README.md`、`AGENTS.md`（§6 verifier 行）、`harness/scenarios/scenarios.json`（GS-136）、组件测试（新增双读 5 例 + 4 个 mock 更新）；**已评估无需更新** —— `pallastrade-typescript-sdk` Skill（仅生成类型变化，无 SDK 方法/用法变更）、根 `README.md`、`pallastrade-prd` Skill、`copilot-instructions.md`、业务方案 §68.4/§78 已回写

## 10. 变更记录

| 版本 | 日期 | 变更 |
|---|---|---|
| 0.1 | 2026-09-15 | 初版（切片 1 后端 + 切片 2 前端 + 切片 3 契约） |
| 1.0 | 2026-09-15 | 实施完成：`ClientConfig` 组装服务 + Stripe publishable 声明 + 契约下发（checkout + cart/order）+ 前端双读（`resolveStripePublishableKey`/`getStripePromise`）+ 类型/OpenAPI 再生成；后端 4 spec 文件 + 前端新建双读测试 5 例（另更新 4 个既有 mock）；顺手修复 checkout typelize 缺失 `kind`/`frontend_kind` 的契约漂移 |
