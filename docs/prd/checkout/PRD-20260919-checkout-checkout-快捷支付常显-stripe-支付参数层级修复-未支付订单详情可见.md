# PRD-20260919-checkout-checkout-快捷支付常显-stripe-支付参数层级修复-未支付订单详情可见

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-19 |
| 来源 | 用户原话：「优化：1、checkout页面实现快捷支付常显 2、点击confirm pay按钮，会报错：Received unknown parameter: billing_details，多次点击页面会跳转，显示空购物车页面？，order列表中有订单，但是点击订单详情提示：Order not found … 订单编号：#R729701382」→ 要求先定位根因再实施 |
| 分类 | checkout |
| 关联 Skill | `pallastrade-payments` / `pallastrade-storefront` / `pallastrade-testing` / `pallastrade-api-v3` |
| 关联 REQ | REQ-20260919-checkout-express-always-visible-and-pi-params.md |
| 关联 PRD | 回归自 `PRD-20260919-checkout-billing-details-passthrough`（引入点）；行为变更自 `PRD-20260919-payments-checkout-top-express-pay-locale`（顶部快捷区的显示策略） |
| 需求类型 | 回归修复（P0）+ 优化迭代（P1） |

## 1. 背景与目标

### 1.1 现象（dev 实测，含证据）

1. **卡/钱包支付全部失败**：点击 Pay now / 钱包 Confirm → `Received unknown parameter: billing_details`，会话从未建立。
   dev 证据（`pallastrade-dev-web-1` 日志 + Stripe 面板）：
   ```
   error_code=parameter_unknown  param=billing_details
   message="Received unknown parameter: billing_details"
   idempotency_key="pallastrade-order-293-method-4-payment_intent-amount-129.99-attempt-1"
   ```
   订单实例 `#R729701382`（`or_X35bb5HTmV`）：`state=pending / payment_state=空 / completed_at=nil / payments=0 / sessions=0`，
   其购物车 `cart_VMWXmZF31w` 已 `converted`（同 cart 仅 1 张订单 → 无重复下单）。
2. **失败后仍跳转**：`start` 返回未知错误码 → 前端按「未知 code + 有 order_id」兜底 `router.replace(payment-result/{id})`；
   而 PI 失败发生在 **confirm 之前**，用户实际看到的是“报错后页面还是跳了”。
3. **空购物车**：回到结算页时 cart 已 `converted` → `checkout/[id]/page.tsx` 执行 `redirect('/{country}/{locale}/cart')` → 空购物车。
4. **订单列表有、详情 404**：详情页把所有 `completed_at === null` 的订单当作 not found（列表页不过滤）→ “Order not found”。
5. **快捷支付不常显**：`TopExpressPay` 在设备能力不可用（桌面浏览器 `availablePaymentMethods` 为空 / 看门狗 timeout）时**整区 `return null`**。
6. **第二个非法参数（dev 真机验证阶段发现）**：同一类错误在 **Checkout Session** 路径也存在 ——
   ```
   error_code=parameter_unknown
   param="payment_intent_data[billing_details]"
   message="Received unknown parameter: payment_intent_data[billing_details]"
   idempotency_key="pallastrade-order-293-method-4-default-amount-129.99-attempt-1"
   ```
   （默认（非 `payment_mode=payment_intent`）的 Stripe 入口走 Checkout Session `ui_mode: elements`，因此**默认卡支付路径同样全量失败**。）

### 1.2 根因

- **A（直接原因，服务端参数层级）**：`PallasTradeStripe::PaymentIntentPresenter#call` 把 `billing_details` 合并进 **PaymentIntent 顶层参数**；
  Stripe 的 `PaymentIntent.billing_details` 是**只读**字段，只在 retrieve 时返回，**创建/更新不接受**。
  合法位置仅两处：服务端 `payment_method_data.billing_details`（需 `confirm: true`）或**客户端**
  `confirmCardPayment(payment_method.billing_details)` / `confirmPayment(payment_method_data.billing_details)`。
  > 引引入点：`PRD-20260919-checkout-billing-details-passthrough`；当时 spec 只断言 presenter 输出形状，未覆盖 Stripe 侧参数合法性。
- **B（前端失败语义）**：`handlePayNow` 调用 `confirmPayment()` 后**不检查返回值**，无论成败都 PATCH complete + 跳结果页。
- **C（订单可见性）**：`account/orders/[id]/page.tsx` 用 `completed_at === null` 判 not found，与列表页口径不一致。
- **D（快捷支付显示策略）**：`TopExpressPay` 把“设备不可用”等同于“不展示”，而用户预期是**常显**（按钮置灰 + 说明）。
- **E（第二个参数层级错位，Checkout Session）**：`CheckoutSessionPresenter#payment_intent_data` 同样合并了 `billing_details`；
  Stripe 的 `payment_intent_data` 不接受任何只读字段（真机 400 `parameter_unknown: payment_intent_data[billing_details]`）。
  ⇒ 账单详情**没有任何服务端上行载体**，唯一合法载体是**客户端 PM 级** `billing_details`（+ 支付后 `charge.billing_details` 回读）。

### 1.3 目标

1. 支付链路恢复（PI 创建不再报 `parameter_unknown`），卡与钱包均可完成支付；
2. 失败**不跳转**、不清空上下文（页内提示 + 可重试）；
3. 未支付订单详情可访问且自带重付入口；
4. 快捷支付区在服务端有入口时常显（不可用则降级展示）。

### 1.4 成功指标

- dev 真机：同一购物车下单 → `PaymentSession` 建立 + PI 创建成功（无 `parameter_unknown`），支付完成 → 订单 `payment_state=paid`；
- `billing_details` 不再出现在 `Stripe::PaymentIntent.create/update` 的顶层参数（白名单 spec 锁定）；
- 详情页对 `#R729701382` 这类未支付订单可用（含重付入口）。

## 2. 用户故事 / 场景

1. 作为**买家**，我在结算页点 Pay now / 钱包 Confirm 后应当完成支付，而不是看到 Stripe 参数错误。
2. 作为**买家**，支付被拒时我应当**留在结算页**看到原因并可重试，而不是被抛到结果页/空购物车。
3. 作为**买家**，我列到订单后应当能打开详情（包括“已下单未付款”的单）并直接**继续支付**。
4. 作为**买家**（桌面浏览器），我想看到快捷支付区即使当前设备不支持钱包（按钮置灰 + 说明），而不是入口整个消失。
5. **边界**：已发生过资金事实（`INVENTORY_RECOVERY_REQUIRED` / `transaction_not_payable`）→ 仍跳结果页，禁止重付。
6. **异常**：Stripe 配置类错误（如 `parameter_unknown`）→ 页内提示 + 保留重试，**不跳转**。

## 3. 功能需求（FR）

- **FR-001（Stripe 参数层级，P0）**：`PaymentIntentPresenter` 输出的 PI 载荷**不得包含顶层 `billing_details`**，
  `CheckoutSessionPresenter` 的 `payment_intent_data` **同样不得包含 `billing_details`**（真机证据见 §1.1-6）；
  账单信息只有两条合法通路：① 客户端 confirm 时的 PM 级 `billing_details`（卡：`confirmCardPayment.payment_method.billing_details`；
  钱包：`confirmPayment.confirm_params.payment_method_data.billing_details`）；② 支付完成后用 `charge.billing_details` 回读快照。
  两处 gateway（`PaymentIntents` 与 Checkout Session）各补白名单断言，在发请求前本地拒发非法键。
  `update_payment_intent` 已 `.slice(...)` 丢弃该键——补断言固定住。
- **FR-002（失败不跳转，P0）**：`UnifiedCheckout.handlePayNow` 必须检查 `confirmPayment()` 的返回：
  失败 → 页内错误 + **不 PATCH complete、不 router.replace 结果页**；成功才走结果页。
- **FR-003（未知错误码不盲跳，P0）**：只有**资金/状态事实**类 code（`INVENTORY_RECOVERY_REQUIRED` / `transaction_not_payable`）或
  **已知状态类 code** 才跳结果页；其余未知 code（如 `parameter_unknown`）→ 页内提示（可重试），保留当前页面。
- **FR-004（未支付订单详情可见，P1）**：`account/orders/[id]` 仅在订单**取不到**时 not found；
  未完成订单正常渲染详情（时间行用 `completed_at ?? created_at` 兜底），并复用已有 `OrderPayButton` 作为重付入口。
- **FR-005（快捷支付常显，P1）**：`TopExpressPay` 只要**服务端有 express 入口**就渲染区域；
  设备不可用（`device` / `unsupported`）或未配置（`unconfigured`）→ 控件降级（禁用/说明文案），保留 timeout 的 toast + 重试；
  仅“服务端无 express 入口”时不渲染。
- **FR-006（转换后购物车恢复路径，P0；实施期根因补充）**：Prepare 建单后旧 `cart_` URL 再次被服务端渲染时（刷新 /
  RSC 重渲染），**不得**再回落到**空购物车页**（实际路径：`getCheckoutOrder(cartId)` 已切到后继空车 → `cartData.id !== cartId`
  → `redirect('/cart')`）。正确行为：读已有 `_pallastrade_checkout_order` cookie（Prepare/Start 已写入，
  `setCheckoutCookies`）→ 重定向到该订单的支付页 `/{country}/{locale}/checkout/or_...`（标准纯支付页，含补付）；
  只有**确实没有任何待支付上下文**时才回购物车页。

## 4. 非功能需求（NFR）

- **安全**：不新增 PII 落库；`billing_details` 仅经 Stripe.js / 服务端完成回写，不写日志。
- **兼容**：不改变订单/会话数据模型与 API 契约（无迁移、无接口变更）。
- **可测**：两条支付路径（卡 inline / 钱包 express）与失败降级均有自动化断言；Stripe 参数用**白名单**锁定，避免同类回归。
- **可维护**：账单信息来源写回 Skill（“PI 顶层 billing_details 是只读字段”铁律）。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001 ← FR-001**：`PaymentIntentPresenter` 输出不含 `billing_details` 键；`Gateway::PaymentIntents#create_payment_intent` 传给 `Stripe::PaymentIntent.create` 的载荷通过白名单（不含 `billing_details`）；`update` 路径也不含。
- **AC-002 ← FR-001**：Checkout Session 的 `payment_intent_data` **不含** `billing_details`（真机 400 回归守卫）；`Gateway#create_payment_session` 的 CS 载荷通过白名单（`CHECKOUT_SESSION_TOP_LEVEL_KEYS` / `CHECKOUT_SESSION_PAYMENT_INTENT_DATA_KEYS`）。
- **AC-003 ← FR-002**：组件测试：`confirmPayment` 返回 `{error}` → 不调用 `router.replace`、不发 PATCH complete；成功 → 跳结果页。
- **AC-004 ← FR-003**：未知 code → 页内错误展示且 URL 不变；`INVENTORY_RECOVERY_REQUIRED` 仍跳结果页。
- **AC-005 ← FR-004**：未支付订单详情页渲染（含重付入口）；订单取不到才 not found。
- **AC-006 ← FR-005**：`TopExpressPay` 在 `unavailable(device)` / `unconfigured` 时仍渲染区域与降级控件；无入口时不渲染。
- **AC-009 ← FR-006**：转换后的 `cart_` 页重渲染 → 落到 `checkout/or_...`（订单支付页）；无 cookie 时才回 `/cart`。
- **AC-007（真机回归）**：dev 下单 → PI 创建成功 + 会话建立 + 支付完成（订单 `payment_state=paid`）。
  - **ed 实测（2026-09-19，d10ea0f6 上线后）**：
    ```
    store=shop method=Stripe (4)
    --- start session: order R729701382 (or_X35bb5HTmV) ---  # 事故订单（幂等键曾被 400 占用）
      SESSION_OK id=300 status=pending external_id=cs_test_a1Qu30fuLYOSYHtnJkARxui36S2ZQeCrF3r7wJnpEaYdzHcwxGlTOmnhpY
    --- start session: order R885808370 (or_5emQZnCRf8) ---
      SESSION_OK id=301 status=pending external_id=cs_test_a1ug45sUzldt3GyOy0PD4BDzoLyh0FPVIsCqc39QuB6C7zcxszAIIoqcc0
    parameter_unknown in log: 0
    ```
    结论：① 两处非法参数均已消除（Checkout Session 与 PaymentIntent 两条路径）；
    ② 曾报 `parameter_unknown` 的幂等键**能正常复用**（Stripe 不缓存 400 验证失败的幂等记录）——无需等待 24h 或换键；
    ③ 卡主确认（`confirmPayment`）仍需真实设备交互，已由 storefront 组件测试卡死失败/成功两分支；
    ④ 真实扣款验证不在本 PRD 范围（dev 使用 Stripe 测试凭据，`cs_test_*`）。
- **AC-008（回归）**：`harness verify billing-details-rspec` + `storefront-test` 全绿；`generated:check` 无漂移。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `billing_details` / `preview` | 仅序列化类型（`PallasTradeApiV3*`）；无支付参数构造 | 不适用 |
| Core | `pallastrade_gems/pallastrade_core/app/` | `OrderPayButton` / `PaymentSessions::Start` | `PaymentSessions::Start` 调 gateway（不构造 PI 参数）；订单快照含 `bill_address` | 已有能力（不改） |
| API | `pallastrade_gems/pallastrade_api/app/` | `payment_sessions` / `transactions` | `payment_sessions_controller` / `transactions_controller` 透传 gateway | 已有能力（不改） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | `billing_details` / `pay` | 后台不构造 Stripe PI 参数；无重复实现 | 不适用 |
| Storefront | `storefront/src/` | `confirmPayment` / `billing_details` / `completed_at` / `TopExpressPay` | `CardPaymentForm`（`confirmCardPayment.payment_method.billing_details`）、`ExpressCheckoutButton`（`confirmParams.payment_method_data.billing_details`）、`UnifiedCheckout#handlePayNow`、`account/orders/[id]/page.tsx`、`TopExpressPay` | **主战场**（FR-002~FR-005） |
| Platform | `platform/packages/` | `billing_details` / `checkout` | SDK 仅透传会话/PI client_secret；不构造 stripe 参数 | 不适用 |

**结论**：①服务端只需**删除一个非法参数**（唯一构造点在 `pallastrade_stripe` presenter）；
②前端两处已有 PM 级透传（本会话已完成）作为账单信息的正确通路；③订单可见性与快捷支付常显均只需单文件行为调整；
**不得**新增第二套支付参数构造，不得改 API 契约。

## 7. 技术影响

- `backend/pallastrade_gems/pallastrade_stripe/app/presenters/pallastrade_stripe/payment_intent_presenter.rb`（去掉顶层 `billing_details`）
- `backend/pallastrade_gems/pallastrade_stripe/spec/presenters/payment_intent_presenter_spec.rb`（断言反向 + 白名单）
- `backend/pallastrade_gems/pallastrade_stripe/spec/models/gateway/*`（新增 `create_payment_intent` 载荷白名单断言）
- `storefront/src/components/checkout/UnifiedCheckout.tsx`（FR-002/FR-003）
- `storefront/src/app/[country]/[locale]/(storefront)/account/orders/[id]/page.tsx`（FR-004）
- `storefront/src/components/checkout/TopExpressPay.tsx`（FR-005）+ 相关测试
- i18n：如新增文案需 ×5 语言 + `checkout-i18n-keys` 守护
- 数据库：**无迁移**；接口：**无变更**

## 8. 测试计划

| AC | 测试 |
|---|---|
| AC-001/AC-002 | `pallastrade_stripe/spec/presenters/payment_intent_presenter_spec.rb`、`spec/models/gateway/payment_intent_payload_spec.rb`、`spec/presenters/checkout_session_presenter_spec.rb`、`spec/models/gateway/checkout_session_payload_spec.rb`（新增：两处白名单）→ `harness verify billing-details-rspec` |
| AC-003/AC-004 | `storefront/src/components/checkout/__tests__/UnifiedCheckout.test.tsx`（confirm 失败不跳转 / 未知 code 不跳） |
| AC-005 | `storefront/src/app/[country]/[locale]/(storefront)/account/orders/[id]/__tests__/page.test.tsx`（页面层：未支付也渲染、取不到才 not found）+ `storefront/src/components/account/__tests__/OrderDetail.test.tsx`（详情真实渲染：Pay Now + `completed_at ?? submitted_at`） |
| AC-006 | `storefront/src/components/checkout/__tests__/TopExpressPay.test.tsx`（不可用 → 仍渲染 + 降级） |
| AC-009 | `storefront/src/lib/checkout/__tests__/recovery.test.ts`（恢复路由：有 `or_` → 订单支付页，无/非法 → 购物车页） |
| AC-007 | dev 真机：下单 → PI 创建 → 支付完成 |
| AC-008 | `harness verify storefront-test` + `generated:check` |

**验证命令**：`npx harness verify billing-details-rspec --task <ID>`、`npx harness verify storefront-test --task <ID>`。

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-payments/SKILL.md`：**PI 顶层 `billing_details` 是只读字段**铁律（含 2026-09-19 事故记录 + 三条合法通路表 + gateway 白名单）
- [x] `ai/skills/pallastrade-storefront/SKILL.md`：快捷支付常显策略 + 支付失败不跳转/未知 code 页内处理 + 转换购物车恢复路由 + 订单详情口径（未支付可见 + 重付）
- [x] `harness/scenarios/scenarios.json` 新增 GS-196（`eval-ai --scenarios` 197/197 合法）
- [x] `AGENTS.md` §6：更新 `billing-details-rspec` 行（加 PI 顶层禁止 + 白名单）+ 新增「结账失败体验/转换购物车恢复/未支付订单可见」行
- [x] `harness.config.mjs`：`billing-details-rspec` 命令扩入 gateway 载荷 spec + 描述更新
- [x] 本 PRD 状态 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-19 | 0.1 | 初稿 + 根因定位（dev 日志/订单实况证据）；用户「实施」确认 | AI |
| 2026-09-19 | 0.2 | 实施期补充 FR-006/AC-009（转换购物车恢复路由 —— 实施中定位到「空购物车页」的服务器端根因）；AC-005 二层测试口径；知识同步勾选 | AI |
| 2026-09-19 | 0.3 | **dev 真机验证发现第二个非法参数**：Checkout Session 的 `payment_intent_data[billing_details]` 同样 400 ⇒ FR-001/AC-002 口径修正（服务端无任何合法载体，只留客户端 PM 级 + 回读）；新增 CS 载荷白名单断言与 spec；知识文档（payments/storefront Skill、AGENTS §6）同步修正 | AI |
| 2026-09-19 | 1.0 | **收口（done）**：dev 真机复测通过（订单 293 与新订单均 `SESSION_OK`，`cs_test_*`；日志零 `parameter_unknown`；幂等键可复用）—— AC-001/002/003/004/005/006/007/008/009 全部完成；CI 全绿（ae0835f5 / d10ea0f6） | AI |
