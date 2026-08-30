# PRD-20260829-checkout-订单模块-单笔走现有checkout-多笔走组合支付新流程-收货信息独立填写

| 元数据 | 值 |
|---|---|
| 状态 | approved（用户 2026-08-30 确认实施） |
| 创建日期 | 2026-08-29 |
| 来源 | 需求：在order模块中，如果选择的是单笔订单则走现有checkout路径，同cart。如果选择了多笔订单就走另一套checkout页面流程，这是新流程，要体现多笔订单组合支付多笔订单的商品，收货信息等。另外，我建议 下单时候收货信息拆出来，不要放checkout页面填写 |
| 分类 | checkout |
| 关联 Skill | pallastrade-checkout / pallastrade-storefront / pallastrade-api-v3 |
| 关联 REQ | REQ-20260830-order-module-single-combined-payment.md |
| 关联 PRD | N/A（全新需求，查重未命中） |
| 需求类型 | 新功能 |

## 1. 背景与目标

- **一句话需求原文**：在 order 模块中，选择单笔订单走现有 checkout 路径（同 cart）；选择多笔订单走另一套 checkout 页面流程（新流程，体现多笔订单组合支付、多笔订单的商品、收货信息等）。另建议：下单时收货信息拆出来，不要放 checkout 页面填写。
- **背景**：
  - 现有「我的订单」合并支付（P5，2026-08-27）：任意勾选 1 笔或多笔未支付订单 → `POST /payment_combinations` → 跳转简化收银台 `combined-payment/[id]`（仅展示组合金额 + Stripe PaymentElement），**无商品明细、无收货信息、无配送确认**。
  - 单笔订单目前也走合并流程，缺少完整 checkout 体验（用户期望与正常购物一致）。
  - 收货信息（地址/配送）目前分散在 cart checkout 页面；订单模块的合并支付没有独立的收货确认环节。
- **目标**：
  1. **单笔订单** → 走现有 checkout 路径（同 cart）：沿用订单已有收货地址与配送方式，checkout 页做「确认 + 支付」，不重新填写。
  2. **多笔订单** → 新合并流程页面：独立「收货信息」步骤（逐单确认各自收货地址）→「商品明细 + 组合支付」步骤。
  3. **收货信息拆出 checkout**：收货地址在合并流程的独立步骤中确认/编辑，支付表单区不再出现地址填写。
- **成功指标**：
  - 单笔未支付订单从「我的订单」到支付成功 ≤ 4 步（选择 → 确认 → 支付 → 完成）。
  - 多笔未支付订单合并支付流程可完整展示每笔订单商品明细与各自收货地址，支付成功后所有成员订单同时完成。

## 2. 用户故事 / 场景

- 作为顾客，我希望在我的订单里勾选**单笔**待支付订单后直接进入与购物车一致的下单确认流程（地址/配送已确认），以便快速完成补款。
- 作为顾客，我希望勾选**多笔**待支付订单后进入专门的合并支付流程，先逐单确认收货地址，再看到所有订单的商品明细与合并金额，最后一次支付，以便清楚知道付的是什么、送到哪。
- 作为顾客，我希望收货信息在独立的「收货」步骤确认，而不是在支付卡片里填地址，以便支付界面聚焦、降低填错概率。

**场景**：
- 正常流 S1：勾选 1 笔 → 跳单订单 checkout → 确认地址/配送 → 支付 → 完成。
- 正常流 S2：勾选 2+ 笔 → 跳合并流程 → 步骤 1 收货（逐单确认/编辑地址）→ 步骤 2 商品明细 + 组合金额 → Stripe 支付 → 所有订单完成。
- 边界 S3：勾选订单中混有已支付订单（仅未支付可勾选，已支付不显示勾选框）。
- 边界 S4：某笔订单无收货地址 → 收货步骤强制填写该单地址才能进入支付。
- 异常 S5：支付失败 → 停留在合并流程，展示错误，可重试。
- 异常 S6：合并支付会话过期/失效 → 提示重新发起。

## 3. 功能需求（FR）

- FR-001：账户订单页勾选**恰好 1 笔**待支付订单时，走**单订单 checkout**——跳转现有 checkout 流程，沿用订单已有收货地址与配送方式，页面展示确认信息 + 支付（不重新填写地址/配送）。
- FR-002：账户订单页勾选 **2 笔及以上**待支付订单时，走**新合并流程**——跳转合并支付收银台（增强版），流程分为「收货信息」与「商品 + 支付」两个步骤。
- FR-003：合并流程**步骤 1（收货）**：逐单展示各成员订单的收货地址；每笔订单地址可查看/编辑（选择已存地址或手动填写），保存后落库到对应订单的 shipping_address。
- FR-004：合并流程**步骤 2（商品 + 支付）**：展示所有成员订单的商品明细（订单号、商品、规格、数量、单价、小计、运费、订单合计）与组合总金额；经 Stripe PaymentElement 组合支付。
- FR-005：组合支付复用现有 `PaymentCombination`（P4/P5）能力：服务端计算金额、单次扣款、按成员订单记账分摊，支付完成后所有成员订单进入完成态。
- FR-006：收货信息从支付表单区拆出：合并流程中 Stripe PaymentElement 区域不含地址输入；地址编辑只在步骤 1。

## 4. 非功能需求（NFR）

- 性能：合并流程加载成员订单明细与地址并行请求，首屏 ≤ 2s（dev 环境）。
- 安全：订单/地址操作仅限当前登录用户自己的订单；沿用 `require_authentication!` + 订单归属校验。
- 兼容：新流程页在桌面/移动端响应式；不破坏现有单订单 cart checkout。
- 可维护性：新增后端能力（订单收货地址更新 API）与前端流程组件解耦；合并流程页面组件化（收货步骤 / 商品明细 / 支付）。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：勾选 1 笔待支付订单后点击 Pay → 跳转单订单 checkout 页，展示该订单的收货地址、配送方式与商品，可完成支付；不出现地址/配送编辑表单。
- AC-002 ← FR-002：勾选 2+ 笔待支付订单后点击 Pay → 跳转合并流程页，且流程含「收货」与「支付」两个步骤。
- AC-003 ← FR-003：合并流程收货步骤逐单显示各订单收货地址；编辑某单地址并保存后，后端该订单 shipping_address 已更新。
- AC-004 ← FR-003：某笔订单无收货地址时，收货步骤对该单强制要求填写，未完成不能进入支付步骤。
- AC-005 ← FR-004：合并流程支付步骤展示所有成员订单商品明细与组合总金额（= Σ 未支付 amount_due）。
- AC-006 ← FR-005：使用 4242 测试卡完成组合支付后，所有成员订单 payment_state 变为 paid、completed_at 有值，且每单分摊金额正确。
- AC-007 ← FR-006：Stripe PaymentElement 支付卡片区域不包含任何地址输入项。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | 无相关（合并支付在 gem 层） | — | N/A |
| Core | `pallastrade_gems/pallastrade_core/app/` | PaymentCombination、PaymentSplit、PaymentCombinations::Create/Complete、Orders::UpdateContactInformation | `models/pallastrade/payment_combination.rb`、`services/pallastrade/payments/payment_combinations/*`、`services/pallastrade/orders/update_contact_information.rb`（仅 email） | 组合支付载体 ✅；订单地址更新 ❌（需新增） |
| API | `pallastrade_gems/pallastrade_api/app/` | payment_combinations、customers/me/orders、shipping_address | `controllers/.../store/payment_combinations_controller.rb`、`customers_controller.rb`、`orders_controller.rb`（只读 show） | 组合创建/查询 ✅；订单收货地址更新 API ❌（需新增） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | 订单地址编辑 | `admin/orders/shipping_address_controller.rb`（Admin 侧） | Admin 有地址编辑；Store 侧需新增 |
| Storefront | `storefront/src/` | OrderCombinedPay、CombinedPaymentCheckout、checkout/[id]、OrderDetail、AddressBlock | `components/account/OrderCombinedPay.tsx`、`components/checkout/CombinedPaymentCheckout.tsx`、`app/[country]/[locale]/(checkout)/checkout/[id]/page.tsx`、`components/account/OrderDetail.tsx`、`components/order/AddressBlock.tsx` | 单笔/多笔分流 ❌（需改）；合并流程收货步骤 ❌（需新增）；商品明细展示 ❌（需新增）；地址组件 ✅ 可复用 |
| Platform | `platform/packages/` | paymentCombinations、orders、addresses | `sdk/src/types/index.ts`、`sdk/src/store-client.ts` | 组合 API 客户端 ✅；订单地址更新 API ❌（需新增 SDK 方法） |

**结论**：
- 已有能力：PaymentCombination 组合支付（后端 + SDK + 前端收银台雏形）、订单只读展示（OrderDetail/AddressBlock）、cart checkout 完整流程。
- 需新建：
  1. 账户订单页**单笔/多笔分流**逻辑（1 笔 → checkout；多笔 → 合并流程）。
  2. **单订单 checkout 确认页**（沿用地址/配送，仅支付；可复用/改造现有 checkout 页为只读模式，或新增轻量确认页）。
  3. **合并流程页增强**：收货步骤（逐单地址确认/编辑）+ 商品明细展示 + 支付。
  4. **后端 Store API**：更新已下单订单收货地址（`PATCH /api/v3/store/customers/me/orders/:id/shipping_address` 或复用 Checkout::Update 能力）——当前缺口。
  5. SDK：订单地址更新客户端方法。
- 防重复：不新建重复的 PaymentCombination；复用现有组件（AddressBlock、StripePaymentForm、Button 等）。

## 7. 技术影响

- **后端**：
  - 新增 `Store::Orders::ShippingAddressController`（`PATCH /api/v3/store/customers/me/orders/:id/shipping_address`），仅允许当前用户自己的未支付订单，更新 ship_address（校验国家/州/邮编）。
  - 复用 `PallasTrade::Checkout::Update` / `Carts::Update` 的地址解析逻辑（country/state 校验、地址替换、市场校验）。
  - 涉及文件：`pallastrade_api/config/routes.rb`、新 controller + spec。
- **前端 Storefront**：
  - `OrderCombinedPay.tsx`：`selected.size === 1` → 跳单订单 checkout；`>1` → 跳合并流程。
  - 新增/改造合并流程：`combined-payment/[id]/page.tsx` 增强为多步骤（收货 → 商品+支付）；新增收货步骤组件（复用 AddressBlock / 地址选择器）、商品明细组件。
  - 单笔 checkout：评估复用 `checkout/[id]`（需要只读模式：已下单订单不再重走地址/配送，仅确认 + 支付）或新增单订单确认页。
  - 涉及文件：`components/account/OrderCombinedPay.tsx`、`components/checkout/CombinedPaymentCheckout.tsx`、新组件 + 测试。
- **SDK**：`platform/packages/sdk/src/types/index.ts` + `store-client.ts` 增加订单地址更新方法（可选）。
- **API 文档**：`backend/public/api-docs/store.yaml` + `platform/docs/api-reference/`（generated:check）。
- **知识同步**：`ai/skills/pallastrade-checkout/SKILL.md`、`pallastrade-storefront/SKILL.md`、`docs/prd/README.md` 索引。

## 8. 测试计划

- 后端：`spec/requests/api/v3/store/...` 新增订单收货地址更新测试（归属校验、无地址订单、非法国家）。
- 前端：`OrderCombinedPay` 分流测试（1 笔 / 多笔）；合并流程组件测试（收货步骤、商品明细、步骤流转）。
- E2E：dev 环境浏览器验证 S1（单笔）与 S2（多笔）全流程（4242 测试卡）。

## 9. 文档同步清单

- [x] `docs/prd/README.md` 索引（已加行 + 状态 approved）
- [x] `ai/skills/pallastrade-checkout/SKILL.md`（新增「订单模块：单笔 checkout / 多笔合并支付新流程」小节）
- [x] `ai/skills/pallastrade-storefront/SKILL.md`（新增 Account orders: single vs combined payment 小节）
- [x] `ai/skills/pallastrade-api-v3/SKILL.md`（新增 shipping_address / payment_combinations expand 端点）
- [x] `backend/public/api-docs/store.yaml` + `platform/docs/api-reference/store.yaml`（新增 shipping_address 端点定义）
- [x] `platform/packages/README.md`（SDK 新方法说明）
- [x] `harness/scenarios/scenarios.json`（新增 GS-040）
- [x] `generated:check`（SDK 类型已重建，无 drift）

## 10. 风险与开放问题

- **R1 已解决**：单笔订单复用 `checkout/[id]`（P1 OrderPaymentContent 只读确认+支付）——已下单未支付订单（or_ 前缀）直接分支渲染，地址/配送不重填。
- **R2 已解决**：新增 `PATCH /customers/me/orders/:order_id/shipping_address`，仅 `!paid? && amount_due > 0` 订单可改，`shipping_address_id` 仅解析当前用户自己的地址（IDOR-safe）。
- **R3 已解决**：合并流程在既有 `combined-payment/[id]` 路由上扩展两步骤（客户端步骤状态，不持久化），不破坏已发布合并支付入口；支付会话完成仍由后端 `PaymentCombinations::Complete` 驱动。
- **O1**：单笔订单确认页不修改配送方式（按用户确认）；如需改配送可后续在单订单 checkout 增加。
- 实施结论（2026-08-30）：后端（服务+控制器+路由+spec 8 例）、SDK（expand + updateShippingAddress）、前端（OrderCombinedPay 分流 + CombinedPaymentCheckout 两步骤 + i18n 五语言 + 测试 4 例）已完成；后端回归 18/18、前端 vitest 221/221、tsc 0 错误、next build 编译通过。
