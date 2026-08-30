# PRD-20260830-checkout-下单链路规范化统一化-场景a-b统一下单页-场景c收银台弹窗-参考阿里国际站

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-08-30 |
| 来源 | 需求：下单链路规范化统一化-场景A/B统一下单页-场景C收银台弹窗-参考阿里国际站 |
| 分类 | checkout（自动判定） |
| 关联 Skill | `pallastrade-checkout`、`pallastrade-storefront`、`pallastrade-api-v3` |
| 关联 REQ | 实施时回填 |
| 关联 PRD | N/A（全新需求，研究见 `docs/research/RESEARCH-20260830-order-flow-unification-ali-international.md`） |
| 需求类型 | 优化迭代（下单链路规范化统一化） |

---

## 1. 背景与目标

- **一句话需求原文**：我们来整体把用户下单链路规范化、统一化。A：cart 场景点击 checkout → 下单页面 → 支付；B：viewcart 购物车勾选商品 → 下单页面 → 支付；C：个人中心 Order 选择订单 → pay now → 收银台弹窗。参考阿里国际站（含合并支付、拆单）。
- **背景**：当前三条入口被拆成多个独立页面（`/cart` → `/checkout-info/[cartId]` → `/checkout/[or_id]`），确认与支付分离；个人中心支付全部跳页、无收银台弹窗；`CartDrawer` 结算曾误入 legacy 一页式导致 "No payment methods available"（已热修 447cbf0）。用户希望按阿里国际站模式统一为「一页确认+支付」与「弹窗收银台」。
- **目标**：
  1. 场景 A/B 共用**同一个统一下单页**（左右布局：左=收件地址+商品+支付方式+物流+Pay Now；右=订单小结），购物车进入一页内联「保存+提交+支付」，不再跳独立确认页。
  2. 场景 C 点击 Pay Now 打开**收银台弹窗**（仅显示支付方式相关信息），单笔/多笔（合并支付）统一走弹窗。
  3. 合并支付弹窗**不扩展收货地址编辑**（订单详情页已可编辑地址）。
  4. `CartDrawer` 同期切换新流程（入口已修，统一化收尾）。
- **成功指标**：
  - A/B 从购物车到支付成功 ≤ 3 步（选中 → 一页确认+支付 → 完成）。
  - C 从订单列表到支付完成 ≤ 3 次点击（选择 → Pay Now → 弹窗支付）。
  - 三条入口不再出现 legacy checkout 页面（`CheckoutPageContent` 仅保留给存量 `or_` legacy 订单）。

## 2. 用户故事 / 场景

- 作为顾客（场景 A），我在购物车点击「去结算」，应进入**统一下单页**（同一页看到地址/商品/物流/支付方式/订单小结），确认后点 Pay Now 一次完成。
- 作为顾客（场景 B），我在购物车页勾选商品后「结算」，应进入**同一个统一下单页**（勾选范围即本次结算商品）。
- 作为顾客（场景 C），我在个人中心勾选 1 笔或多笔待支付订单后点 Pay Now，应弹出**收银台弹窗**（选择支付方式+支付表单），不跳页。
- 边界：未登录游客下单（邮箱+地址）、已存地址选择、无物流方式、无支付方式、支付失败/取消重试、3DS/离站回跳、订单已支付（防重复支付）。
- 异常：购物车已转换/过期（重定向购物车）、组合支付部分失败（资金先入账+状态补偿）、弹窗支付成功后的状态刷新。

## 3. 功能需求（FR）

- **FR-001（统一下单页）**：新建/改造 `/checkout/[id]` 为统一下单页 `UnifiedCheckout`，`cart_`（新购物车）与 `or_`（待支付订单）两种 ID 均进入；左右布局（左：收件地址 + 商品信息 + 物流方式 + 支付方式选择 + Pay Now；右：订单小结）。
- **FR-002（购物车内联提交）**：`cart_` 前缀进入时，页面内联保存地址/物流（`Carts::Update`）+ 提交（`Carts::Submit` 生成 `or_` 订单），提交后同页无缝切换为订单支付态（不跳页）；`shipping_method_id` 沿用全局 `dm_` 前缀（已修复 ca49dd3）。
- **FR-003（商品与小结）**：左侧商品信息展示所选购物车 items 或订单 line_items；右侧小结展示 Subtotal / Shipping / Tax / 优惠 / Total（购物车阶段由服务端实时计算，订单阶段取快照金额）。
- **FR-004（收银台弹窗）**：新建 `PaymentCheckoutModal`（Dialog）复用 `PaymentSection`/`StripePaymentForm`（`PaymentSectionHandle.submit`），仅展示支付方式相关信息（radio + 表单 + 金额），不包含地址/物流编辑。
- **FR-005（场景 C 单笔）**：个人中心订单列表勾选 1 笔 → Pay Now → 打开弹窗（直接以该订单支付，`Orders::PaymentSessions` 会话）。
- **FR-006（场景 C 多笔/合并支付）**：勾选 2+ 笔 → 先 `createPaymentCombination` → 弹窗显示组合金额 + 各单分摊 → 支付（复用 `PaymentCombinations::Complete` 幂等链路）；**不提供逐单收货地址编辑**（地址编辑留在订单详情）。
- **FR-007（订单详情 Pay Now）**：订单详情页（`/account/orders/[id]`）补充「Pay Now」按钮（当前缺失）→ 打开收银台弹窗。
- **FR-008（CartDrawer 收敛）**：迷你购物车「去结算」走新流程入口（已改 checkout-info，统一化后指向统一下单页），不再出现 legacy 一页式。

## 4. 非功能需求（NFR）

- **性能**：统一下单页 SSR 首屏 ≤ 3s；弹窗打开 ≤ 1s（复用已加载支付组件）。
- **安全**：支付金额服务端权威计算（防篡改）；订单访问走现有 `:show`/`:update` 授权（单笔订单 checkout 已修复 105a2cc）；组合支付同店/同用户/同币种校验。
- **兼容**：存量 legacy `or_` 订单仍走 `CheckoutPageContent`（不破坏）；`confirm-payment` 离站回跳兼容。
- **可维护性**：支付方式选择 + 表单抽取共享组件（`PaymentMethodSelector`），统一下单页与弹窗复用；避免重复实现。
- **幂等**：支付完成/Webhook 重复回调短路（`Carts::Complete` 既有）。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：访问 `/checkout/[cart_xxx]` 渲染统一下单页（左右布局），左侧含收件地址/商品/物流/支付方式/Pay Now，右侧为订单小结；不再跳 `/checkout-info`。
- AC-002 ← FR-002：购物车页「去结算」进入统一下单页后，填写地址/选物流/选支付方式，点 Pay Now 一次完成提交+支付；URL 由 `cart_` 切换到 `or_`（或弹窗完成），不出现独立确认页。
- AC-003 ← FR-003：左侧商品清单与右侧小结金额一致（购物车阶段实时、订单阶段快照）；含 Subtotal/Shipping/Tax/Total。
- AC-004 ← FR-004：个人中心点 Pay Now 弹出收银台弹窗；弹窗内仅支付方式 radio + 支付表单 + 应付金额；**不含地址/物流字段**。
- AC-005 ← FR-005：勾选 1 笔待支付订单 → 弹窗直接支付该订单；成功后订单 `payment_state=paid`、跳转完成页或就地刷新。
- AC-006 ← FR-006：勾选 2+ 笔 → 弹窗展示组合总金额与各单分摊；支付成功后所有成员订单 `paid`、`completed_at` 有值、分摊正确；弹窗无逐单收货编辑。
- AC-007 ← FR-007：订单详情页出现「Pay Now」按钮并可打开弹窗完成支付。
- AC-008 ← FR-008：`CartDrawer` 去结算进入新流程统一下单页；`/checkout/[cart_xxx]` 不再渲染 legacy 一页式（回归 447cbf0 修复）。
- AC-009 ← NFR 兼容：存量 legacy `or_` 购物车订单进入 `/checkout/[or_xxx]` 仍走 `CheckoutPageContent`，行为不变。
- AC-010 ← NFR 幂等：支付成功重复触发（前端回调 + Webhook）订单仍为 `paid`，不重复扣款/状态不回退。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | shopping_cart / checkout-info / payment_methods | `backend/app/javascript/types/serializers/PallasTradeApiV3Cart.ts`（legacy 类型） | ⚠️ host app 无新流程逻辑，类型文件需同步 SDK |
| Core | `pallastrade_gems/pallastrade_core/app/` | Carts::Submit/Update/UpsertItems/Complete、payment_methods、shipping_method | `services/pallastrade/carts/*.rb`、`models/pallastrade/order.rb`（payment_methods 860 行）、`cart.rb`（belongs_to shipping_method） | ✅ 后端能力完备，无需重构 |
| API | `pallastrade_gems/pallastrade_api/app/` | carts / orders / payment_sessions / payment_combinations / shipping_methods / ShoppingCartSerializer | `controllers/.../store/carts_controller.rb`、`orders_controller.rb`、`shopping_cart_serializer.rb` | ⚠️ ShoppingCartSerializer 缺 `payment_methods`（统一下单页需要，需补） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | payment_methods 配置 | `admin/payment_methods/*` | ✅ 仅后台配置，无影响 |
| Storefront | `storefront/src/` | cart / checkout / checkout-info / OrderCombinedPay / CombinedPaymentCheckout / PaymentSection / CartDrawer | `app/.../cart/page.tsx`、`checkout-info/[cartId]/*`、`(checkout)/checkout/[id]/page.tsx`、`components/checkout/OrderPaymentContent.tsx`、`PaymentSection.tsx`、`components/account/OrderCombinedPay.tsx`、`components/cart/CartDrawer.tsx` | ⚠️ 核心改造层：统一下单页 + 收银台弹窗 + CartDrawer 收敛 |
| Platform | `platform/packages/` | SDK carts/orders/paymentCombinations/shippingMethods | `sdk/src/store-client.ts`、`types/index.ts` | ⚠️ SDK 需支持 ShoppingCartSerializer 新字段（payment_methods）类型 |

**结论**：
- 后端（Core/API 服务层）能力已完备（Carts::Submit/Complete、PaymentCombinations、OrderPaymentContent、拆分引擎），**无需重构**。
- 主要工作在前端（Storefront）：①统一下单页 `UnifiedCheckout`（替代 checkout-info 独立页）；②收银台弹窗 `PaymentCheckoutModal`；③CartDrawer 收敛。
- API 层需补：`ShoppingCartSerializer` 增加 `payment_methods` 输出（供统一下单页支付方式选择），并同步 SDK 类型。
- 防重复判定：`CheckoutPageContent`（legacy 一页式）保留给存量 `or_` 订单，不复制其逻辑到新流程；`PaymentSection` 复用为弹窗核心，不重复实现支付表单。

## 7. 技术影响

- **涉及组件/文件**：
  - Storefront：`(checkout)/checkout/[id]/page.tsx`（分流扩展）、新建 `components/checkout/UnifiedCheckout.tsx`、新建 `components/checkout/PaymentCheckoutModal.tsx`、`components/account/OrderCombinedPay.tsx`（改弹窗）、`components/account/OrderDetail.tsx`（补 Pay Now）、`components/cart/CartDrawer.tsx`（已改，统一化收尾）、`lib/data/shopping-cart.ts`（如需提交后取订单）。
  - API：`shopping_cart_serializer.rb`（补 payment_methods）、对应 SDK `types` 生成。
- **数据库**：无 schema 变更（Cart/Order 分表、父子单、payment_combination_id 均已存在）。
- **接口**：无新增 REST 端点（复用 `carts/:id/submit`、`orders/:id/payment_sessions`、`payment_combinations`）；`GET /carts/:id` 响应新增 `payment_methods` 字段。
- **影响面**：`harness affected --base origin/main`（实施时记录）；主要波及 storefront checkout 相关页面与组件，后端 API serializer 一处 + SDK 类型。
- **正向**：`cart_` 购物车一页内联提交 → `or_` 订单支付（`Carts::Submit` + 标准状态机）；个人中心 `or_` 订单弹窗支付。
- **逆向**：支付失败/取消保持 `balance_due` 可重试；`Carts::Complete` 幂等；拆单 flag（`auto_split_orders`）默认关不改变语义。

## 8. 测试计划

- **新增测试**：
  - `storefront/src/app/[country]/[locale]/(checkout)/checkout/[id]/__tests__/page.test.tsx`：统一下单页分流（cart_ → 内联提交+支付；or_ → 直接支付；legacy or_ → CheckoutPageContent）→ AC-001/002/009
  - `storefront/src/components/checkout/__tests__/PaymentCheckoutModal.test.tsx`：弹窗渲染/打开/支付方式选择/提交/关闭 → AC-004/005/007
  - `storefront/src/components/account/__tests__/OrderCombinedPay.test.tsx`（更新）：单笔/多笔改为打开弹窗 → AC-005/006
  - `storefront/src/components/account/__tests__/OrderDetail.test.tsx`（如新建）：Pay Now 按钮 → AC-007
- **更新测试**：
  - `backend/spec/requests/api/v3/store/carts_controller_spec.rb`：`GET /carts/:id` 响应含 `payment_methods`（dm_ 前缀）→ AC-001
  - `storefront/src/lib/data/__tests__/shopping-cart.test.ts`：提交后订单返回
- **AC 映射**：AC-001/002 → checkout 页测试 + carts API spec；AC-003 → UnifiedCheckout 渲染测试；AC-004/005/006 → PaymentCheckoutModal + OrderCombinedPay 测试；AC-007 → OrderDetail 测试；AC-008 → CartDrawer 测试（既有）；AC-009/010 → 既有 checkout/支付幂等测试回归。
- **E2E（实施阶段）**：`harness e2e storefront` 覆盖 A/B/C 三入口 + 合并支付弹窗。

## 9. 文档同步清单（知识同步门）

- [ ] API 文档：`backend/public/api-docs/store.yaml`（carts 响应新增 payment_methods 字段）+ `platform/docs/api-reference/store.yaml`
- [ ] Skill：`ai/skills/pallastrade-checkout/SKILL.md`（统一下单页 + 收银台弹窗小节）、`pallastrade-storefront/SKILL.md`（§Checkout 更新）、`pallastrade-api-v3/SKILL.md`（ShoppingCartSerializer 字段）
- [ ] SDK 类型生成：`platform/packages/sdk` 类型 + `generated:check` 验证
- [ ] 场景库：`harness/scenarios/scenarios.json`（新增统一化下单/收银台弹窗场景）
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引
- [ ] `harness sync-check --id PRD-xxx` 逐项确认 + `--ack`

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-30 | 0.1 | 初稿（研究 + 用户 4 决策点确认后撰写） | AI |
