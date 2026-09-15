# REQ-20260915-d10-client-config

> 任务：`TASK-20260915141521-e1a110af` · gate `GATE-2026-09-15T14-15-43`
> PRD：`docs/prd/payments/PRD-20260915-payments-d10-client-config.md`（D10，业务方案 §78 / §68.4 / §76.1）
> 需求原文：用户 2026-09-15「实施」（承接「下一批建议 D10：前端密钥下发 `client_config` + 清 `NEXT_PUBLIC_*`」）

## Step 0：6 层跨层搜索（实查结论）

| 层 | 关键词 | 结论 |
|---|---|---|
| App `backend/app/` | `client_config` / `stripe` / `publishable` | **无命中** —— 宿主层无相关实现 |
| Core `pallastrade_core/app/` | `public_preferences` / `Credentials` / `available_payment_methods` | `PaymentMethod#public_preferences`（按 `public_preference_keys` 投影）、`public_preference_keys`（**protected，默认 `[]`**，`bogus.rb` 已示范覆写）、`credential_level`（D9）、`PaymentMethods::Credentials`（分级 + `env:` 引用解析）、`OrderCheckout::View#available_payment_methods` → `order.payment_methods`（D8 过滤同源） |
| API `pallastrade_api/app/` | `payment_method_payload` | `store/checkout/checkout_serializer.rb`：typelize 块（第 41 行附近）+ `payment_method_payload`（id/name/description/type/session_required/source_required/kind/frontend_kind）→ **承载点** |
| Admin `pallastrade_admin/app/` | `publishable` | 支付方式表单已可编辑 `publishable_key` 偏好（D1/D9 页面）；**零改动** |
| Storefront `storefront/src/` | `NEXT_PUBLIC_STRIPE` / `stripePromise` | `lib/utils/stripe.ts`（模块级 `loadStripe(env)` 单例）；消费方 `CardPaymentForm` / `StripePaymentForm` / `ExpressCheckoutButton`；装配点 `OrderPaymentContent`（`paymentMethods` → `selectedMethod`）；另 `payment-gateway.ts` 读 PayPal/Adyen env（D5/D6 未接线） |
| Platform `platform/packages/` | `available_payment_methods` | `sdk/src/types/generated/StoreCheckoutCheckout.ts` + `sdk/src/types/index.ts` + `dist/*`（生成物，随契约再生成） |

**防重复判定**：不新建凭据存储/分级（复用 D9 `Credentials`）、不新建入口模型（复用 D1 `PaymentOption` 过渡形态）、不改后台。

## Step 1：Skill 咨询证据表

| Skill | 结论（对本任务的具体约束） |
|---|---|
| `pallastrade-customization` | 决策树优先级 8（改 gem 源码 + `# PALLAS-CUSTOM:` 注释）—— 本期改 `pallastrade_stripe` / `pallastrade_core` / `pallastrade_api` 三个 gem 文件，均按此约定加注释 |
| `pallastrade-payments` | §Credentials & environments（D9）：凭据分级 `secret/publishable/internal`；`environment` 前台过滤；**本期只下发 publishable 级**；`session_token` 属「短时令牌」预期位，provider 侧签发属后续批次 |
| `pallastrade-api-v3` | Store API 用 `pk_`；契约变更必须同步 `backend/public/api-docs/store.yaml` + 再生成（`scripts/ci/contracts.sh`）→ `harness generated:check` 零漂移；字段为 **additive**，老客户端兼容 |
| `pallastrade-storefront` | ① 客户端组件不直连 Store API（走 server actions / 服务端投影）；② `NEXT_PUBLIC_*` 是**构建期内联**，构建期≠运行期会致 hydration #418 —— D10 正是要摆脱该依赖；③ 样式/组件约定（Tailwind、禁内联样式）不涉及 |
| `pallastrade-security` | §分级：`:password` 型 preference = `secret`；`public_preference_keys` 声明 = `publishable`；读分级用 `credential_level(key)`。**下发面只能是 publishable**（spec 负向断言 `secret_key` 不出现） |
| `pallastrade-typescript-sdk` | SDK 类型由生成器产出（勿手改生成物）；`StoreCheckoutCheckout` 类型随 OpenAPI 再生成 |
| `pallastrade-testing` | 后端 spec 走 `rails_helper` + 共享上下文；前端 vitest（`storefront` 目录内跑，biome 亦在目录内） |

## Step 2：设计要点（实施即按此落地）

1. **Stripe 声明 publishable**：`PallasTradeStripe::Gateway#public_preference_keys → %w[publishable_key]`（protected 覆写；`secret_key` 仍是 `:password` → secret）。
2. **组装服务**：`PallasTrade::PaymentMethods::ClientConfig.call(payment_method)` →
   ```ruby
   {
     provider: payment_method.class.api_type,       # 如 "stripe"
     environment: payment_method.environment,        # D9
     publishable: { 'publishable_key' => 'pk_live_…' },
     session_token: nil                              # 短时令牌预留位
   }
   ```
   - 仅 `Credentials.level == 'publishable'` 且值非空的键；`env:` 引用经 `Credentials.resolve`；解析失败省略键。
   - **零 provider 网络调用、零额外查询**。
3. **契约**：`payment_method_payload` 增 `client_config:`（typelize 里补结构），再 `contracts.sh` 生成 SDK/zod + platform 副本。
4. **前端双读**：
   - `resolveStripePublishableKey(clientConfig?)`：`clientConfig?.publishable?.publishable_key ?? process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY ?? null`
   - `getStripePromise(key?)`：按 key 缓存的 `Map`（同 key 复用，换 key 重新 `loadStripe`）
   - 组件：`CardPaymentForm` / `StripePaymentForm` / `ExpressCheckoutButton` 接收 `clientConfig`（由 `OrderPaymentContent` 从 `selectedMethod.client_config` 透传）；缺省时回落 env → 老行为不变。
5. **安全**：payload 永不含 secret；spec 负向断言。

## Step 3：切片

- **切片 1（后端）**：FR-001/002/003/005 —— provider 声明、组装服务、契约字段、specs（AC-001..005）。
- **切片 2（前端）**：FR-004/006 —— 双读工具 + 三组件接线 + vitest（AC-006/007）。
- **切片 3（契约 & 知识）**：`contracts.sh` 再生成 + `generated:check` + 文档/技能/场景/方案回写。

## 实施记录（2026-09-15 完成）

| 项 | 结果 |
|---|---|
| 后端改动 | `pallastrade_stripe/.../gateway.rb`（`public_preference_keys → [:publishable_key]`）· 新建 `pallastrade_core/.../payment_methods/client_config.rb` · `pallastrade_api` 两处 serializer（checkout + store PaymentMethodSerializer） |
| 前端改动 | `lib/utils/stripe.ts`（双读 + 按 key 缓存）· `CardPaymentForm` / `StripePaymentForm` / `ExpressCheckoutButton`（新增 `clientConfig`）· 三个装配点（`OrderPaymentContent` / `UnifiedCheckout` / `PaymentCheckoutModal`）· 4 个既有测试 mock 更新 |
| 测试 | 后端 `d10-client-config-rspec`（client_config_spec + checkout_serializer_spec + cart_serializer_spec + gem 内 gateway_spec）：**63 例 0 失败**（含 D9/D1 回归）；前端新建 `stripe-client-config.test.ts`（5 例）+ 全量 `storefront-test` |
| 契约 | `scripts/ci/contracts.sh` 再生成：store/admin `api-docs` yaml + platform 副本 + `PallasTradeApiV3*` 类型 + SDK `PaymentMethod.ts` / `StoreCheckoutCheckout.ts`（`backend/packages` 暂存 + `platform/packages/sdk`） |
| 知识同步 | 3 个 Skill（payments/api-v3/storefront）+ `platform/packages/README.md` + `AGENTS.md` §6 verifier 行 + GS-136（137/137 valid）+ 业务方案 §68.4 回写 + PRD §9/§10 |

### 决策与偏差

1. **键必须用 symbol**：`public_preference_keys` 返回值直接用于 `preferences[key]`，而 preferences 以 symbol 存储 —— 首版写成 `%w[publishable_key]`（string）会静默取 nil；改为 `[:publishable_key]`（与 `Bogus` 网关既有写法一致）。
2. **既有 spec 的语义修正（正当）**：`pallastrade_stripe/spec/models/gateway_spec.rb` 的 STR-012 原本断言「Stripe 没有任何 public preference」；D10 有意让 `publishable_key` 下发前台，故把断言改为「secret 仍不公开 + publishable 公开」，安全意图（secret 不出服务端）不变。
3. **顺手修契约漂移**：checkout serializer 的 typelize 此前缺 `kind` / `frontend_kind`（D1/D8 加了 payload 字段但类型字符串未同步）→ 本次补齐后 `generated:check` 零漂移。
4. **admin 契约的连带变化**：`Admin::PaymentMethodSerializer < V3::PaymentMethodSerializer`，所以 admin 侧也继承 `client_config`（publishable 非密，可接受并已记入 api-v3 Skill）。
5. **短时令牌留位**：`session_token` 恒 nil（provider 侧签发属后续批次）；`session_token_for` 为覆写点，契约不再变更。
6. **未覆盖的回落场景**：`CartDrawer` 的 Express 按钮暂未接 `client_config`（购物车 payload 已可带，但该组件入参未扩展）——现存回落环境变量路径仍可用；属后续小批。
7. **验证器路径坑**：gem 内规格必须按 `pallastrade_gems/<gem>/spec/...` 路径跑（写 `spec/models/pallastrade_stripe/...` 会 `cannot load such file`）。
