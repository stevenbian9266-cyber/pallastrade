# REQ-20260919-checkout-top-express-pay-locale

> 完整版 REQ（改动 >5 文件且含逻辑变更）。
> 关联 PRD：`docs/prd/payments/PRD-20260919-payments-checkout-top-express-pay-locale.md`

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | `apple_pay\|google_pay\|wallet\|express` | 仅 typelizer 生成类型 `app/javascript/types/serializers/PallasTradeApiV3Cart.ts`（`express_payment`） | 不涉及（零后端改动） |
| App — views/decorators | `backend/app/` | 同上 | 无命中 | 不涉及 |
| Core Gem — models | `pallastrade_core/app/models/` | `WALLET_OPTION_KINDS\|option_frontend_kind\|payment_option_entries` | `pallastrade/payment_method.rb:455`（kind 集合）、`:474`（`option_frontend_kind`→`express`）、`:494`（`payment_option_entries`） | ✅ 已有（不改） |
| Core Gem — services | `pallastrade_core/app/services/` | `availability\|resolver` | `payments/availability/resolver.rb`（D8/D11/D15c 同源求值） | ✅ 已有（不改） |
| API Gem — controllers | `pallastrade_api/app/controllers/` | `option_kind` | `store/carts/payment_sessions_controller.rb`（D7 透传） | ✅ 已有（不改） |
| API Gem — serializers | `pallastrade_api/app/serializers/` | `entries\|payment_option_entries` | `payment_method_serializer.rb:59`（cart 通道 entries）、`store/checkout/checkout_serializer.rb:164`（or_ 投影） | ✅ 已有（不改） |
| Admin Gem | `pallastrade_admin/app/` | `frontend_kind\|position` | `payment_methods/_options.html.erb`（入口配置，D7） | ✅ 已有（不改） |
| Storefront | `storefront/src/` | `express\|wallet\|locale` | `components/checkout/{UnifiedCheckout,ExpressCheckoutButton,WalletPaymentButtons,PaymentSection}.tsx`、`lib/checkout/wallet-availability.ts`、`lib/utils/stripe.ts`、`messages/*.json`、`lib/__tests__/checkout-i18n-keys.test.ts` | ❌ **本需求唯一改动区** |
| Platform | `platform/packages/` | `entries\|frontend_kind` | `sdk/src/types/generated/PaymentMethod.ts:16`（`entries[]`）、`StoreCheckoutCheckout.ts` | ✅ 已有（不改） |

### 搜索结论

- 「入口级投影（含 `frontend_kind=express`）」在 Core/API/SDK 三层**均已具备**（D7 交付），Admin 可配置 —— **零后端改动、零契约变更**。
- 缺口 100% 在前台展示层：① 顶部快捷区不存在（钱包只在第 5 节选行后出现）；② 三处 Stripe `Elements` 未传 `locale`（按钮/表单按浏览器语言渲染）。
- 防重复判定：与 D7（入口行渲染）**互补而非重复** —— D7 建入口行与钱包槽位，本批新增顶部展示位并统一语种；第 5 节按用户决策保留。

---

## Step 1：Skill 文件咨询

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树优先级「Settings → Configuration → Events → Dependencies → Admin / Ransack APIs → Generators → Decorators → Extensions」；「Decorators are reserved for *structural* changes — for behavioral changes use Events」。本批为**纯前台展示层**，不触碰任何后端模式 → 无需 decorator/subscriber/DI。 |
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ 已读 | ①「**改钱包行为先看它**」= `lib/checkout/wallet-availability.ts`（三态 + 原因）；②「⚠️ **不得**在客户端根据 `kind`/`frontend_kind` 自己隐藏钱包入口 —— 隐藏 = 不出现由 `Payments::Availability::Resolver` 决定」（D8 §66.5 同源硬约束）；③「任何后续编辑（哪怕只改测试文件）都要重跑 `pnpm check`」；④ 文案 5 语言 + `checkout-i18n-keys.test.ts` REQUIRED 登记；⑤ D7 段：`expressPaymentMethodsFor` 的 `always/never` 语义、`link` 仅 `auto|never`。 |
| `ai/skills/pallastrade-payments/SKILL.md` | ✅ 已读 | ①「**前台红线**：**零筛选**——只按 `frontend_kind` 选渲染槽（`inline` 自绘卡字段 / `express` 钱包按钮 / `manual` 说明行）」；②「能力矩阵：前台 express 元素**只启用 `applePay` / `googlePay` / `link`**」；服务端 `WALLET_OPTION_KINDS` 含 `shop_pay/amazon_pay/paypal*` → 顶部区只承载可渲染 kind，其余留在列表（不隐藏）。 |

**按需 Skill（本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-checkout` | ✅ | ✅ 已读 | 「**客户端零筛选（红线）**：前端只按 `frontend_kind` 选渲染槽 …… 列表仍只含可用入口（隐藏 = 不出现）—— 认证需求 = 是时，不可保证认证的入口（钱包 express）**不在列表里**，前端**零筛选逻辑**」（D15c 闸门语义，顶部区必须消费同一 `entries` 投影）。 |
| `harness-prd` | ✅ | ✅ 已读 | 「**阶段 1：用户确认** —— 呈现 PRD 摘要 → 用户确认 → 状态 `approved`；**未确认 → 保持 draft，不进入实施**」；REQ 完整版判定「改动 >5 文件且有逻辑变更」→ 本批走完整版 REQ。 |
| `pallastrade-admin` / `pallastrade-catalog` | ⬜ | ⬜ 不适用 | 不涉及后台 UI / 商品域（零文件改动）。 |
| `pallastrade-testing` / `pallastrade-i18n` | ✅（部分） | ✅ 已读（storefront 段） | 前端测试/文案约定已在 storefront Skill §Verification / i18n 段覆盖（vitest + biome + typecheck 三件套；5 语言键集守护）。 |

---

## 需求标题

优化：checkout 顶部快捷支付区（钱包入口上移）+ Stripe 渲染面跟随站点语种

## 任务类型

功能优化（纯前台展示层 + 文案语种）

## 需求描述

1. 在 cart_ 统一下单页（`/checkout/[cartId]`）**页面顶部**（H1 之下、第 1 节之前）新增「快捷支付区」：Apple Pay / Google Pay 按钮**直接可见、点击即付**（横向自适应、不自动堆叠），走既有 canonical 链（不新增第二条流程）。
2. 钱包按钮及其余 Stripe 渲染面（卡表单等）的文案**跟随商城前台语种**（当前跟随浏览器语言，中文浏览器显示中文）。
3. 第 5 节支付区**保留**既有入口行（双触点）；or_ 订单支付页不动。
4. 顶部区降级：加载失败/超时 → toast 3 秒后消失；设备无钱包 → 静默隐藏（零噪音）。

## 影响范围（`harness affected` 输出）

本仓为 **dev-only**（无 `origin/main`），`harness affected` 无法按基线比对 → 以 PRD §7 文件清单为准（storefront 展示层 + 5 语言文案 + 测试 + Skill/场景同步；零后端、零契约）。

## 技术方案（初步）

| # | 方案 |
|---|---|
| 1 | 新增 `TopExpressPay.tsx`：从 `payment_methods[].entries`（`paymentEntriesFor` 回退）取 `frontend_kind=express` 且 Stripe 可承载（`apple_pay/google_pay/link`）的入口；渲染标题 + `ExpressCheckoutButton`（`entryKinds` 多入口 + `maxColumns=2` + `degradedDisplay="toast"`）；`onAvailabilityChange` 决定整区显隐 |
| 2 | `ExpressCheckoutButton` 扩展：`entryKinds`（多入口 `paymentMethods` 配置，`always/never` + `link:auto`）；`degradedDisplay`（`notice` 默认 / `toast`：timeout → sonner toast 3s + 隐藏，device/unsupported/unconfigured → 静默）；confirm 透传 `option_kind` |
| 3 | `wallet-availability.ts` 新增 `expressPaymentMethodsForKinds(kinds)`（与既有 `expressPaymentMethodsFor` 同构） |
| 4 | `lib/utils/stripe.ts` 新增 `stripeLocaleFor(siteLocale)`（`en/de/es/fr/pl` → 同码；未知 → `auto`，类型 `StripeElementLocale`）；三处 `Elements` 传 `locale` |
| 5 | 文案：`expressCheckout.title` / `expressCheckout.unavailableToast`（5 语言）+ REQUIRED 登记 |
| 6 | 测试：`TopExpressPay.test.tsx`（新）、`ExpressCheckoutButton.test.tsx` / `UnifiedCheckout.test.tsx`（扩展）、`stripe-locale.test.ts`（新）、`checkout-i18n-keys.test.ts`（REQUIRED） |

## 风险点

| 风险 | 处置 |
|---|---|
| Apple Pay 按钮语言由 **Apple 设备**决定，`locale` 可能无法改变按钮文案 | 实施后 dev 实测记录；不可控部分作为**已知平台限制**写入 storefront Skill（NFR-007） |
| 顶部区与第 5 节双入口可能引起审美争议 | 用户决策 ④ 明确保留；第 5 节零改动即回滚点 |
| 桌面无钱包设备（本仓主要验证环境）看不到按钮 | 属设备能力事实（D7 结论）；以"顶部区静默隐藏 + toast 仅异常"控制观感；真机验收 |
| 测试文件格式/超时（biome + 动态导入） | 改完跑 `pnpm check` + `pnpm typecheck`；动态等待显式 `{ timeout: 10000 }` |

## 决策节点

> ⏸️ 用户已于 2026-09-19 对 7 项设计决策**逐项答复确认**（位置/形态/范围/双触点/页面范围/语种范围/降级口径），随后明确指示「**实施**」→ 本 REQ 据此进入实施，无待确认项。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| 前端组件/展示 | `TopExpressPay.tsx` / `UnifiedCheckout.tsx` / `ExpressCheckoutButton.tsx` / `wallet-availability.ts` / `stripe.ts` / 文案 | `pnpm test`（定向 9 文件 → 全量由 `harness verify storefront-test` 收口） | 定向：**109 例通过**（九文件中 8 绿 + 1 修复后绿）；全量见同提交 `storefront-test` EVD | ✅ |
| 前端格式/类型 | 全部改动文件 | `pnpm check`（biome）+ `pnpm typecheck` | `pnpm -C storefront check` → **exit 0**（仅 4 条既有 warning，非本批文件：TurnstileWidget / CategoryNav / ProductReviews / order-payment.ts）；`typecheck` → **exit 0** | ✅ |
| i18n | `messages/*.json` + `checkout-i18n-keys.test.ts` | `pnpm check:locales` + vitest 守护用例 | `check:locales` → **All locale files are in sync**；守护用例含新键 `expressCheckout.title/unavailableToast` → 通过 | ✅ |
| 契约 | 无（零接口变更） | `harness generated:check`（预期零漂移） | **no drift detected** | ✅ |
| 场景库/Skill | `ai/skills/pallastrade-storefront/SKILL.md` + `harness/scenarios/scenarios.json` | `harness eval-ai --scenarios` | **189/189 valid**（含新增 GS-188） | ✅ |
| admin 页面三要素 | 无（未改 admin） | 不适用 | — | ✅ |

### 验证结论

- **定向测试**：`vitest run` 九个受影响文件 → 108 passed / 1 failed（`UnifiedCheckout` 新用例 — 夹具缺 `currency` 导致 `cart.currency.toLowerCase()` 报错；补 `currency: "USD"` 后该文件 **36/36 通过**）。
- **静态**：biome exit 0（本批文件零错误）；tsc --noEmit exit 0；locale 键集一致。
- **契约**：零接口改动 → `generated:check` 无漂移；场景库 189/189。
- **收口**：`harness verify storefront-test --task TASK-20260919040537-b4013e5d`（全量 vitest）作为注册验证器证据；dev 部署后前台实测见 PRD §变更记录后续条目。
