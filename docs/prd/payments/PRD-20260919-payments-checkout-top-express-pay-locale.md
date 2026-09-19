# PRD-20260919-payments-checkout-top-express-pay-locale

| 元数据 | 值 |
|---|---|
| 状态 | verifying |
| 创建日期 | 2026-09-19 |
| 来源 | 优化：checkout 页面：把 Google Pay / Apple Pay 从下方「支付方式」移到页面上方「快捷方式入口」；渲染出的按钮文案必须跟随商城前台选择的语种 |
| 分类 | payments |
| 关联 Skill | `pallastrade-storefront` / `pallastrade-payments` / `pallastrade-checkout` |
| 关联 REQ | REQ-20260919-checkout-top-express-pay-locale.md |
| 关联 PRD | N/A（全新；D7 相邻但范围不同） |
| 需求类型 | 优化迭代 |

> **用户决策冻结（2026-09-19，逐项确认）**：
> ① 位置 = 行业惯例（H1 下、第 1 节 Contact 之前）；② 钱包按钮**直接可见、点击即付**，**横向自适应（不自动堆叠）**；
> ③ 按**服务端全部 `frontend_kind=express` 入口**渲染；④ 第 5 节入口行**同时保留**（双触点）；
> ⑤ 仅改 **cart_ 统一下单页**（or_ 订单支付页不动）；⑥ **Stripe 渲染面整体**跟随站点语种；
> ⑦ 失败/超时 = **toast 3 秒后消失**（不常驻）。用户原话指令：「实施」。

## 1. 背景与目标

- **背景**：
  1. D7（PRD-20260918-payments-d7-payment-section-express）把 Apple Pay / Google Pay 作为**入口行**放在第 5 节支付区，选中后再挂载钱包按钮 —— 钱包快付不在页面顶部，不符合行业惯例（Shopify dynamic checkout / Stripe Express Checkout Element 推荐把快捷支付放在结账表单之前）。
  2. 全部 Stripe `Elements` 实例均未传 `locale`，Stripe 默认按**浏览器语言**自动检测 —— 中文浏览器上按钮/表单渲染中文文案，与商城前台语种（en/de/es/fr/pl）不符。
- **目标**：① 结账页顶部新增「快捷支付区」，钱包按钮直接可见、点击即付；② Stripe 渲染面（钱包按钮 / 卡表单 / 校验文案）统一跟随站点语种。
- **成功指标**：支持钱包的设备在结账页顶部即可一键起付（无需先选入口行）；Stripe 可控文案 = 站点语种；第 5 节既有行为零回归。

## 2. 用户故事 / 场景

1. 作为**买家（钱包用户）**，我希望在结账页顶部直接看到 Apple Pay / Google Pay 按钮，一键完成支付（地址/卡由钱包弹层提供），以便免填表单。
2. 作为**买家（德语站）**，我希望钱包按钮与 Stripe 表单文案跟随我当前浏览的商城语种，而不是浏览器语言的混排。
3. 作为**商家**，我在后台停用钱包入口后，顶部快捷区与第 5 节同时不再出现该入口（服务端同源决定）。
4. **边界**：桌面无钱包设备 → 顶部区整体隐藏、零噪音（不弹提示）；钱包区加载失败/超时 → 3 秒 toast 后自动消失，页面照常可用卡支付。
5. **异常**：后台只启用 `google_pay` 单钱包 → 顶部区只出现 Google Pay 按钮；`entries` 缺失的旧响应 → 顶部区按回退入口判定（无 express → 不渲染）。

## 3. 功能需求（FR）

| # | 需求 |
|---|---|
| FR-001 | **顶部快捷支付区**：位于 `<h1>Order Confirmation</h1>` 之下、第 1 节（Contact Information）之前；含区块标题（5 语言）与 `or` 分隔线；仅作用于 cart_ 统一下单页（`UnifiedCheckout`） |
| FR-002 | **入口来源 = 服务端投影（零筛选红线）**：取 `payment_methods[].entries`（含 `paymentEntriesFor` 旧响应回退）中 `frontend_kind === "express"` 的入口；仅其中 Stripe 元素可承载的 kind（`apple_pay` / `google_pay` / `link`）进入顶部区控件；**客户端不得按 kind 隐藏入口**（不可承载 kind 仍保留在第 5 节列表，行为不变） |
| FR-003 | **直付（不新增流程）**：复用 `ExpressCheckoutButton` 与 canonical 链（`/api/checkout/start` → `confirmPayment` → 结果页）；confirm 时透传 `option_kind`（`expressPaymentType` → 对应入口 `method_key`） |
| FR-004 | **横向自适应**：钱包按钮横向排布（`layout.maxColumns = 2`，由 Stripe 元素自适应宽度），不自动堆叠为竖排；窄屏实际表现以 dev 实测记录为准 |
| FR-005 | **双触点保留**：第 5 节入口行与「选中 express 入口 → 钱包槽位」行为**保持不变**（零回归；用户决策 ④） |
| FR-006 | **语种跟随**：`loadStripe` / `Elements` 传站点 `locale`（映射：`en/de/es/fr/pl` → 同码，未知 → `auto`），覆盖 `ExpressCheckoutButton` / `WalletPaymentButtons` / `CardPaymentForm` 三处 Elements 实例；Apple Pay 按钮/弹层语言由 **Apple 设备系统**决定（平台限制，见 NFR-007） |
| FR-007 | **顶部区降级**：加载失败/超时（`timeout`）→ `sonner` toast 3 秒（每页面最多一次），区块隐藏；`device` / `unsupported` / `unconfigured` → **静默隐藏**（不 toast、不占位、不常驻）；单钱包不可用 → 该按钮不出现，其余照常 |
| FR-008 | **文案 5 语言**：新增键 `expressCheckout.title` / `expressCheckout.unavailableToast` 在 `messages/{de,en,es,fr,pl}.json` 齐备，并登记 `lib/__tests__/checkout-i18n-keys.test.ts` 的 `REQUIRED` |

## 4. 非功能需求（NFR）

| # | 约束 |
|---|---|
| NFR-001 | **零接口/契约变更**：仅消费既有 `entries` 投影；不新增/修改 Store API 字段；`harness generated:check` 零漂移 |
| NFR-002 | **零资金语义变化**：不新增支付流程与会话链路，canonical 顺序不变（start → confirm → complete → 结果页） |
| NFR-003 | **兼容**：`entries` 缺失的旧响应按 `paymentEntriesFor` 回退单入口；判定为无 express 时顶部区不渲染、页面照常 |
| NFR-004 | **可测**：组件测试覆盖 AC-001 ~ AC-009；改动后 `pnpm check`（biome）/ `pnpm typecheck` 全绿 |
| NFR-005 | **零新增依赖**：复用 sonner / next-intl / Stripe 既有栈 |
| NFR-006 | **文案键集一致**：`pnpm check:locales` 通过（5 语言键集相等） |
| NFR-007 | **平台限制如实声明**：Apple Pay 按钮/弹层文案由设备决定，站点 `locale` 不保证改变之；实施后 dev 实测记录（若不可控，作为已知限制写入 Skill） |

## 5. 验收标准（AC，与测试一一映射）

| # | 验收标准 | 覆盖测试 |
|---|---|---|
| AC-001 | 有 ≥1 个可渲染 express 入口时，H1 之下/第 1 节之前渲染顶部区块（`data-testid="top-express-payment"`，含标题与钱包元素容器） | `TopExpressPay.test.tsx` / `UnifiedCheckout.test.tsx` |
| AC-002 | 无 express 入口（或全部不可用）→ 顶部区块不渲染（DOM 无该 testid），第 5 节照常 | 同上 |
| AC-003 | 顶部钱包元素的 `layout.maxColumns === 2` | `ExpressCheckoutButton.test.tsx` / `TopExpressPay.test.tsx` |
| AC-004 | 顶部区入口集合 = 服务端 express 入口中 Stripe 可承载 kind；不可承载 kind 不进入顶部区且**仍在第 5 节列表**（不隐藏） | `TopExpressPay.test.tsx` |
| AC-005 | 点击顶部钱包 → `startExpressCheckout` 请求体含 `option_kind`（= 对应入口 `method_key`） | `ExpressCheckoutButton.test.tsx` |
| AC-006 | 三处 Elements options 收到站点 locale 映射值（`en/de/es/fr/pl`；未知 → `auto`） | `stripe.test.ts` / `CardPaymentForm` 等组件测试 |
| AC-007 | 新增文案键在 5 语言齐备（`checkout-i18n-keys` REQUIRED 守护） | `checkout-i18n-keys.test.ts` |
| AC-008 | 顶部区降级：`timeout` → 触发一次 toast（3s）且区块隐藏；`device` → 静默隐藏、不 toast | `TopExpressPay.test.tsx` |
| AC-009 | 零回归：第 5 节入口行/钱包槽位既有用例全绿；旧响应（无 entries）时顶部区不渲染 | `UnifiedCheckout.test.tsx` |

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件（代表） | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `apple_pay\|google_pay\|wallet\|express` | 仅 `app/javascript/types/serializers/PallasTradeApiV3Cart.ts`（typelizer 生成类型含 `express_payment`） | 不涉及（本需求零后端改动） |
| Core | `pallastrade_gems/pallastrade_core/app/` | `WALLET_OPTION_KINDS\|option_frontend_kind\|payment_option_entries` | `models/pallastrade/payment_method.rb:455/474/494`（钱包 kind 集合、前端渲染形态、入口投影读模型） | ✅ 已有能力（不改） |
| API | `pallastrade_gems/pallastrade_api/app/` | `entries\|payment_option_entries` | `serializers/.../payment_method_serializer.rb:59`（cart 通道 entries）、`store/checkout/checkout_serializer.rb:164`（or_ 投影 entries） | ✅ 已有能力（不改） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | 入口 `position/frontend_kind` 配置 | `payment_methods/_options.html.erb`（D7 已具备） | ✅ 已有能力（不改） |
| Storefront | `storefront/src/` | `express\|wallet\|locale` | `components/checkout/{UnifiedCheckout,ExpressCheckoutButton,WalletPaymentButtons,PaymentSection}.tsx`、`lib/checkout/wallet-availability.ts`、`lib/utils/stripe.ts`、`messages/*.json` | ❌ **本需求改动区**（顶部区 + locale） |
| Platform | `platform/packages/` | `entries\|frontend_kind` | `sdk/src/types/generated/PaymentMethod.ts:16`（`entries[]` 已生成） | ✅ 已有能力（不改） |

**结论**：服务端「入口级投影（含 frontend_kind=express）」与 SDK 类型均已具备（D7 交付）；缺口仅在 storefront 展示层（顶部快捷区）与 Stripe `locale` 传参。**零后端改动、零契约变更。**

## 7. 技术影响

| 文件 | 变更 |
|---|---|
| `storefront/src/components/checkout/TopExpressPay.tsx` | **新增**：顶部快捷区（标题 + `ExpressCheckoutButton`（多入口）+ 降级/隐藏逻辑） |
| `storefront/src/components/checkout/UnifiedCheckout.tsx` | 插入顶部区（H1 与第 1 节之间）；传入 express 入口集合与 `clientConfig` |
| `storefront/src/components/checkout/ExpressCheckoutButton.tsx` | 新增 `entryKinds`（多入口钱包配置）与 `degradedDisplay`（`notice` \| `toast`）；`Elements` 传 `locale` |
| `storefront/src/lib/checkout/wallet-availability.ts` | 新增 `expressPaymentMethodsForKinds(kinds)`（多入口 → Stripe `paymentMethods` 配置） |
| `storefront/src/lib/utils/stripe.ts` | 新增 `stripeLocaleFor(locale)`（站点→Stripe locale 映射；未知 → `auto`） |
| `storefront/src/components/checkout/{CardPaymentForm,WalletPaymentButtons}.tsx` | `Elements` 传 `locale`（语种一致性） |
| `storefront/messages/{de,en,es,fr,pl}.json` | 新增 `expressCheckout.title` / `expressCheckout.unavailableToast` |
| `storefront/src/lib/__tests__/checkout-i18n-keys.test.ts` | REQUIRED 登记新键 |
| `storefront/src/components/checkout/__tests__/*` | 新增/更新测试（见 §8） |
| `ai/skills/pallastrade-storefront/SKILL.md` | 顶部快捷区 + locale 口径 + Apple Pay 平台限制 |
| `harness/scenarios/scenarios.json` | 新增 Eval Scenario（Skill 变更联动） |

**不做**：or_ 订单支付页布局不动（用户决策 ⑤）；第 5 节入口行保留（④）；不新增预加载/探针；不新增 API。

## 8. 测试计划

| 层 | 文件 | 覆盖 |
|---|---|---|
| 单测 | `storefront/src/lib/__tests__/stripe-locale.test.ts`（新增） | AC-006（映射 + 未知回退） |
| 组件 | `storefront/src/components/checkout/__tests__/TopExpressPay.test.tsx`（新增） | AC-001/002/004/008 |
| 组件 | `storefront/src/components/checkout/__tests__/ExpressCheckoutButton.test.tsx`（扩展） | AC-003/005 + `degradedDisplay=toast` 行为 |
| 集成 | `storefront/src/components/checkout/__tests__/UnifiedCheckout.test.tsx`（扩展） | AC-001/002/009（顶部区渲染位置 + 零回归） |
| 守护 | `storefront/src/lib/__tests__/checkout-i18n-keys.test.ts`（扩展 REQUIRED） | AC-007 |
| 验证器 | `harness verify storefront-test`（既有注册验证器，全量 vitest） | 全部 AC（标记法 `# PRD-20260919-payments-checkout-top-express-pay-locale AC-00x`） |

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-storefront/SKILL.md`：「顶部快捷支付区 + Stripe 语种跟随」章节（含双触点、toast 降级、`option_kind`、Apple Pay 平台限制）
- [x] `harness/scenarios/scenarios.json`：GS-188（顶部快捷区/语种跟随/安静降级；`eval-ai --scenarios` 189/189 valid）
- [x] `docs/prd/README.md`：索引由 `prd-status-sync --fix` 生成（190/190 一致）
- [x] 评估（无需更新）：`pallastrade-payments` Skill —— 服务端能力/契约零变化（仅前台展示位置 + 客户端 locale）
- [x] sync-check 评估结论（7 项）：`pallastrade-storefront Skill`(updated) / `组件测试`(updated) / `场景库`(updated) / `scenarios.json`(updated) /
  `pallastrade-prd Skill`(reviewed-no-change：沿用既有工作流) / `AGENTS.md`(reviewed-no-change：零后端/零契约/无新验证器) / `copilot-instructions.md`(reviewed-no-change)
- [ ] 本 PRD 状态更新（dev 部署验证通过后 → `done`，独立文档提交）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-19 | 0.1 | 初稿：用户 7 项决策冻结（含「双触点保留」「toast 3s」「仅 cart_ 页」）并明确指示「实施」 | AI |
| 2026-09-19 | 0.2 | 实施完成（转 `verifying`）：`TopExpressPay` 顶部区 + `entryKinds`/`degradedDisplay` 扩展 + `option_kind` 透传 + `stripeLocaleFor` 三处 Elements；5 语言 2 键；测试：新增 `TopExpressPay.test.tsx` / `stripe-locale.test.ts`、扩展 4 个既有测试文件（定向 9 文件 109 例全绿）；biome/typecheck/locales/generated:check 全绿 | AI |
