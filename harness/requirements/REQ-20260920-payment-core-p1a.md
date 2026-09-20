# REQ-20260920-payment-core-p1a（P1-a 前台：一次点击支付 + 支付区瞬时骨架）

> 任务：`TASK-20260920122600-da9e6c4c`｜Gate：`GATE-2026-09-20T12-26-09`（feature）
> 关联 PRD：`docs/prd/checkout/PRD-20260920-checkout-支付核心统一-厂商层-支付方式层-方式级路由-组合支付-订单失效期.md`（切片 P1-a）
> 前置：P0-A/P0-B（厂商层）、P3-A/B/C（方式级路由）已交付（`e31647aa` / `e1c9de0a` / `9c2b74b2` / `a8dc148b` / `88bef800`）
> 本切片范围：**只动 storefront**（FR-011 / FR-012）；**不碰契约**（读模型 `form/state/reason/requires_authentication`、SDK 重生成、OpenAPI 同步属 P1-b）

## Step 0：跨层搜索（6 层）

关键词：`一次性支付` / `payNow` / `prepare` / `quote` / `client_config` / `publishable` / `entries` / `frontend_kind` / `express` / `wallet` / `骨架`

| 层 | 路径 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|
| App | `backend/app/` | 仅生成物类型：`app/javascript/types/serializers/{PallasTradeApiV3PaymentMethod,PallasTradeApiV3StoreCheckoutCheckout,PallasTradeApiV3Cart}.ts`（`entries` / `client_config` / `express_payment` 形状） | ❌ 无需改动（纯前台切片） |
| Core | `pallastrade_core/app/` | `models/pallastrade/payment_method.rb`（`payment_option_entries` / `option_frontend_kind`）、`services/pallastrade/payment_methods/client_config.rb`（**publishable 凭据唯一装配点**）、`payments/availability/**`（入口集合权威） | ⚠️ 只消费：前台「与 `PaymentMethods::ClientConfig` 同源」= 同一份 `payment_methods[].client_config` |
| API | `pallastrade_api/app/` | `serializers/.../payment_method_serializer.rb`（`entries` + `client_config` 下发）、`serializers/.../store/checkout/checkout_serializer.rb`（同字段，checkout 投影） | ⚠️ 只消费：两条通道都已在**首屏 payload** 下发 `client_config` → 本切片零契约变更 |
| Admin | `pallastrade_admin/app/` | `payments_helper.rb` / `payment_methods/_options`（后台入口与形态列）、`storefront_controller#find_or_create_publishable_key` | ❌ 不涉及（后台无「一次点击」概念） |
| Storefront | `storefront/src/` | `components/checkout/{UnifiedCheckout,OrderPaymentContent,PaymentSection,TopExpressPay,ExpressCheckoutButton,WalletPaymentButtons,CardPaymentForm}.tsx`、`lib/{checkout/wallet-availability,checkout-quote,utils/stripe,utils/stripe-billing}.ts`、`app/[country]/[locale]/(checkout)/layout.tsx` | ✅ **就是本切片**：两处待改——① `UnifiedCheckout` 的「prepare → 确认区 → 再点 Pay」两步；② 快捷区首帧只显示 spinner（无固定高度骨架）、Stripe.js 懒加载无预连接/预加载 |
| Platform | `platform/packages/` | `sdk/src/types/index.ts#CartPreviewQuoteResult`（预览报价字段=与 prepare 逐字段一致）、`sdk/src/types/generated/PaymentMethod.ts`（`entries` / `client_config` 已在类型里） | ⚠️ 只消费类型：本切片**不改 SDK**（`dist/` 为构建产物，Deploy 会重建） |

**结论**：需求的两项（FR-011/FR-012）都在 storefront 层，且服务端能力**已齐备**（`client_config` 随首屏 payload、`preview` 报价与 `prepare` 报价同源同值、`quote_changed` 语义已存在）→ 本切片是**纯前台改造**：不新增接口、不新增 i18n 键、不改 SDK/OpenAPI。

## Step 1：Skill 咨询

| Skill | 状态 | 关键结论（对本切片的约束） |
|---|---|---|
| `pallastrade-customization` | ✅ | storefront 直接改源码（`storefront/src/**` 可自由修改）；不为前台新增抽象层 |
| `pallastrade-storefront` | ✅ | ① 预览报价测试脚手架约定：预览走**独立 mock**；② 改动后必须 `vitest + tsc + biome check .` 三绿（biome 扫全量含 `__tests__`，行宽 80）；③ 「两段语义」段落需随本切片改写；④ 钱包入口集合**只由服务端决定**（客户端不得按 kind 隐藏）——骨架只做「占位」，不改变入口集合 |
| `pallastrade-payments` | ✅ | ① `billing_details` **只能**走客户端 PM 级透传（本切片不动该口径，回归守护）；② 失败处理口径：`confirmPayment` 返回 error → 页内报错，不 PATCH、不跳转；③ 只有「钱的事实已确定」的 code 才跳结果页 |
| `pallastrade-api-v3` | ⏭️ 不涉及 | 零契约变化（P1-b 才动读模型与文档） |
| `harness-prd` | ✅ | P1 是既有 PRD 的切片（PRD 在册、状态 implementing）→ 不新建 PRD；交付后回写 §8/§9/§10 |
| `pallastrade-testing` | ⚠️ 参考 | 组件级行为用 vitest（jsdom）+ 既有脚手架；不引入新测试框架 |

## 需求（本切片 = PRD FR-011 / FR-012）

**FR-011 快捷支付区瞬时渲染**（`TopExpressPay` / `UnifiedCheckout` 第 5 节钱包槽 / 或经 `ExpressCheckoutButton` 的任意入口）：

1. 首帧渲染**固定高度骨架**（钱包按钮位：`h-12` 脉冲块，列数 = `maxColumns`），不再用居中 spinner 占位；`ExpressCheckoutElement` 仍**常挂载**（Stripe 初始化所需），仅视觉隐藏。
2. **预连接 + 预加载 `js.stripe.com`**：当且仅当**首屏 payload**（`payment_methods[].client_config`）里带 publishable 凭据、且本页确有 Stripe 支付方式时，下发 `<link rel="preconnect|dns-prefetch" href="https://js.stripe.com">` + `<link rel="preload" as="script" href="https://js.stripe.com/v3/">`（React 19 自动提升到 `<head>`；`https://js.stripe.com/v3/` 与 `@stripe/stripe-js#loadStripe` 注入的脚本 URL 一致，预加载可被复用）。无凭据 → 不预热（不白付连接/流量成本）。
3. **元素就绪原位替换**（CLS < 0.02）：骨架与真实按钮占同一槽位、同高（`min-h-12` 容器恒定）；`showDivider` 的「or」分隔线**不再等 available 才渲染**（否则按钮出现时整段内容下移）。

**FR-012 一次点击直达**：

4. 删除「首次点击只 Prepare → 展示确认区 → 再点确认」的**强制两步**。首次点击：`prepare`（建单 + 权威报价）后，**若金额与顾客已看到的金额一致，同一次点击继续发起支付**。
5. **只有金额发生变化时**才显示**变化块**（沿用既有 `checkout-quote-diff`：Shipping / Promotion / Amount due 旧→新）+ 确认块（`order-quote-confirm`），并要求顾客重新点击确认（与既有 `quote_changed` 语义一致：显示变化 + 让顾客确认，**绝不偷偷换价**、绝不自动扣款）。
6. 「顾客已看到的金额」口径 = **只读预览报价**（`POST /api/checkout/preview`，同参数与 prepare 逐字段一致）优先；无预览则取上次报价快照（`readQuoteSnapshot`）；两者皆无 → 无可比对基准（无变化可判）→ 直接支付（金额由支付控件/结果页展示）。
7. 合计与明细**常显**：右栏订单摘要（`UnifiedOrderSummary`）在 prepare 后即刻切到权威金额（`totalDue`），移动端折叠按钮始终带「N 件 · 金额」；不再出现「点 Pay 才展开小计」。

**随本切片一并修正的两处既有缺陷**（否则一次点击路径会卡死或展示旧价）：

8. **409 后死循环**：`quote_changed` 冲突处理后仅更新快照，但后续点击仍用 `preparedOrder.quote`（旧版本）→ 永远 409。修正：冲突响应带最新报价时同步更新 `preparedOrder.quote`，确认后一次点击即携带新版本。
9. **改动后权威金额陈旧**：用户在 prepare 之后修改地址/配送方式/账单模式时，摘要仍显示旧权威报价。修正：这些输入变化即清空 `preparedOrder` / `quoteDiff`（下次点击重新 prepare，服务端把新输入写进同一订单）。

**不做（属 P1-b）**：统一读模型字段（`form` / `state` / `reason` / `requires_authentication`）、SDK 类型重生成、OpenAPI 同步、`or_` 页 `WalletPaymentButtons` 形态渲染改造；**不做**：账单地址优先级与 `billing_details` 载体口径任何改动（保持「钱包/卡已收集值 > 独立账单地址 > 同收货地址」与「仅客户端 PM 级」）。

## AC（验收标准）

| AC | 判定 | 验证 |
|---|---|---|
| AC-1（FR-012） | 金额未变化：一次点击 = `prepare + start` 同一轮完成并跳结果页（`fetch` 顺序 = prepare → start，零 `order-quote-confirm`、零 `checkout-quote-diff`） | vitest（UnifiedCheckout） |
| AC-2（FR-012） | 金额变化（预览 $X vs prepare $Y，Y≠X）：首次点击**不** start，显示变化块（`quote-diff-*` 旧→新）+ 确认块；第二次点击携带**新** `expected_checkout_version/expected_price_version` 发起 start | vitest |
| AC-3（FR-012） | 无预览且无快照 → 直接支付（不因「无法比对」拦人）；prepare 未返回报价（服务端降级）→ 同 | vitest |
| AC-4（FR-012） | 409 `quote_changed` 后再点：请求携带**服务端最新**版本（不再死循环），且旧行仍以 `before → after` 展示 | vitest |
| AC-5（FR-012） | prepare 之后修改地址/配送方式/账单模式 → `preparedOrder`/`quoteDiff` 清空（摘要不再展示旧权威金额） | vitest |
| AC-6（FR-011） | 首帧（`state=unknown`）渲染 `wallet-buttons-skeleton`（固定高度、列数 = maxColumns）；`onReady` 后骨架消失、按钮可见；`ExpressCheckoutElement` 全程挂载 | vitest（ExpressCheckoutButton） |
| AC-7（FR-011） | 有 Stripe 支付方式且 payload 带 publishable 凭据 → 渲染 `preconnect` / `dns-prefetch` / `preload as=script` 指向 `js.stripe.com`；无凭据 → 一个都不渲 | vitest（StripeResourceHints） |
| AC-8（回归） | `billing_details` 仍只出现在客户端 PM 级（`confirmCardPayment.payment_method.billing_details` / `confirmPayment.confirmParams.payment_method_data.billing_details`），服务端载荷（prepare/start body）不含该键 | 既有 vitest 用例（billing probe）+ 人工核对 |
| AC-9（回归） | 钱包入口集合仍只由服务端 `entries` 决定；骨架不改变「点谁显示谁」「探测不可用可重试」既有行为 | 既有 vitest 用例 |

## 测试计划

- 组件回归：`node storefront/node_modules/vitest/vitest.mjs run --root storefront`（`UnifiedCheckout` 新 AC-1..5 / `ExpressCheckoutButton` AC-6 / 新 `StripeResourceHints` AC-7 + 既有用例全绿）
- 类型：`cmd /c "cd storefront && npx tsc --noEmit"`
- 格式/lint：`storefront` 目录 `node node_modules/@biomejs/biome/bin/biome check .`（全量，含 `__tests__`）
- 注册验证器：`harness verify storefront-test --task <TASK-ID>`（复用既有 id，不新建）
- 产物：更新 `ai/skills/pallastrade-storefront/SKILL.md` + `harness/scenarios/scenarios.json`（GS-200）+ PRD §8/§9/§10

## 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-20 | 1.0 | 初稿：P1-a（一次点击支付 + 支付区瞬时骨架 + 预连接/预加载 + 两处既有缺陷修正） | AI |
