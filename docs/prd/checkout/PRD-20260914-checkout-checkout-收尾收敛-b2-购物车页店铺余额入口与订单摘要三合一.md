# PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-14 |
| 来源 | 需求：Checkout 收尾收敛 B2 —— 购物车页店铺余额入口与订单摘要三合一（承接 B1：`PRD-20260914-checkout-checkout-收尾收敛-b1-*`） |
| 分类 | checkout（自动判定，见 `harness/policies/prd-categories.json`） |
| 关联 Skill | `pallastrade-storefront`（主）、`pallastrade-payments`（抵扣/余额语义）、`pallastrade-api-v3`（序列化器契约） |
| 关联 REQ | REQ-20260914-checkout-b2-cart-credits.md（实施时回填） |
| 关联 PRD | 同系列 B1 的后续批次（非重复需求；`harness prd new` 查重未触发阻止） |
| 需求类型 | 优化迭代（storefront 消费既有 API + 1 处序列化器 additive 字段） |

> 📌 本 PRD 为「Checkout 收尾收敛」系列第 **B2** 批，依据《商城前台 Checkout + Transaction + Promotion + 履约完整方案》§15/§16 + research §5.1；总体节奏表见 B1 PRD §1.1。

---

## 1. 背景与目标

- **一句话需求原文**：需求：Checkout 收尾收敛 B2 —— 购物车页店铺余额入口与订单摘要三合一
- **背景**：B1 已把「订单结账页（`or_`）」的抵扣展示与支付方式收敛到服务端 CheckoutView；但**购物车页**（`/{country}/{locale}/cart`，canonical `cart_`）仍然只有商品勾选/数量/删除 + `item_total` 两行摘要：既无折扣码/礼卡入口，也无**店铺余额**入口。跳层搜索证实后端能力早已就绪（`PRD-20260914-checkout-cart-{discount-codes,gift-cards,store-credits}-canonical`）：`cart_` 上三种抵扣都是**意图**（零资金副作用，提交时由 `Carts::Submit` 兑现）；余额端点要求登录（401 `store_credit_requires_login`）并与礼卡互斥（422 `store_credit_gift_card_conflict`）。SDK 也已有 `carts.storeCredits.apply/remove` —— 缺口在 BFF（`/api/checkout/coupon` 只覆盖折扣码 + 礼卡）与 UI。另有一个**契约缺口**：`ShoppingCartSerializer` 既未回显车阶段折扣码意图，也未给 `gift_card` / `store_credit` 精确类型（SDK 生成为 `unknown`），前端无法据此渲染「三合一」摘要。
- **目标**：
  1. 购物车页提供「优惠与抵扣」模块：折扣码 / 礼卡 / 店铺余额三种抵扣的输入与移除入口。
  2. 购物车页 Order Summary 与结账页口径一致地展示三行抵扣（折扣码 / 礼卡 / 余额）。
  3. 游客/登录用户差异显式化：余额仅登录可用 → 游客看到登录引导（不产生 401 噪声请求）。
  4. 车阶段金额语义不乱：摘要合计仍是 `display_item_total`，并明示「运费/税费/优惠在结算时计算」。
- **成功指标**：
  - 登录用户在购物车页可应用/移除店铺余额，摘要行金额 == 服务端 `store_credit.display_amount`；
  - 游客点击余额入口 **0 次网络请求**，看到登录引导；BFF 未登录返回 401 结构化错误（不是 500）；
  - `pnpm test` / `pnpm check` / `pnpm typecheck` 三绿；`generated:check` 无漂移。

## 2. 用户故事 / 场景

- 作为**登录客户**，我希望在购物车页就能用店铺余额抵扣，以便结账时少填支付信息、一次结清。
- 作为**登录客户**，我希望购物车页能一眼看出「这单已经用了优惠码/礼卡/余额」，以便确认金额没有被悄悄改变。
- 作为**游客**，我希望知道店铺余额需要登录，并能一键登录后回到购物车，而不是看到一个报错。
- 场景列表：
  1. 正常流（余额）：登录用户点「使用店铺余额」→ 摘要出现余额行（`display_amount`）→ 提交订单时由 `Carts::Submit` 兑现。
  2. 正常流（移除）：点「移除」→ 余额行消失（服务端快照刷新）。
  3. 正常流（折扣码）：输入 `SAVE10` → 显示已应用码（**金额在提交后**才计算，故行上标注「结算时计算」）。
  4. 正常流（礼卡）：输入卡码 → 行显示 `code` + 卡内余额 `display_amount_remaining`。
  5. 边界：可用余额为 0 或币种不符 → 服务端 422 `store_credit_not_available` → 页内提示（不出现空白行）。
  6. 边界：金额非法（0/负数）→ 422 `store_credit_invalid_amount`。
  7. 异常：礼卡已在车上 → 余额入口禁用并说明原因；若强行请求 → 422 `store_credit_gift_card_conflict`。
  8. 异常：游客直接请求余额端点 → 401 `store_credit_requires_login` → 文案映射到「请先登录」。
  9. 边界：未勾选任何商品行 → 抵扣模块仍可用（选中行只影响提交的订单内容，抵扣在提交时按订单金额收敛）。

## 3. 功能需求（FR）

- **FR-001 摘要三合一**：购物车页 Order Summary 在 `item_total` 之外渲染三行抵扣（折扣码 / 礼卡 / 店铺余额），数据全部来自 `getShoppingCart()` 的服务端快照；任一行为空/0 → 不渲染该行（money 契约：raw 判逻辑、display 仅渲染）。
- **FR-002 折扣码入口**：购物车页可应用/移除优惠码（复用既有 BFF `POST/DELETE /api/checkout/coupon`，`kind: "discount"`），成功后直接采用返回的 cart 快照刷新，不在前端重算金额。
- **FR-003 礼卡入口**：同上 `kind: "gift_card"`；移除传 `gift_card_id`（`gc_` prefixed id）。
- **FR-004 余额入口（本批核心）**：数据层新增 `applyStoreCredit(cartId)` / `removeStoreCredit(cartId)` 服务端动作（`"use server"`，调用 `client.carts.storeCredits.apply/remove`）；购物车页提供「使用店铺余额」/「移除」控件；**省略金额 = 用尽可用余额**（服务端语义，前端不猜金额）。折扣码/礼卡同样走服务端动作（`applyDiscountCode` / `removeDiscountCode` / `applyGiftCard` / `removeGiftCard`）。
- **FR-005 登录门槛**：余额控件仅对登录用户可操作；未登录渲染登录引导（入口可见但不可用，点击跳登录并带回跳），BFF 未登录返回 401 + `store_credit_requires_login` 错误信封。
- **FR-006 互斥**：礼卡已应用 → 余额入口禁用并给出原因；余额已应用 → 礼卡输入提示冲突（服务端 `gift_card_using_store_credit_error`）。前端为**体验**层拦截，服务端仍是唯一权威。
- **FR-007 错误映射**：服务端错误码 → i18n 文案（`gift_card_not_found` / `gift_card_expired` / `gift_card_already_redeemed` / `store_credit_requires_login` / `store_credit_not_available` / `store_credit_invalid_amount` / `store_credit_gift_card_conflict`）；未知错误用通用文案，不回显内部异常文本。
- **FR-008 金额口径**：合计仍取 `display_item_total`，页面注明「运费/税费/优惠在结算时计算」；抵扣行只作展示，**不参与前端合计计算**。
- **FR-009 契约补全（additive）**：`ShoppingCartSerializer`（a）新增 `discount_code: [:string, nullable: true]`（回显用户自己输入、已校验的车阶段优惠码意图）；（b）把 `gift_card` / `store_credit` 的 typelize 升级为对象字面量（`{ code, display_amount_remaining }` / `{ amount, display_amount }`），使 SDK 生成类型不再是 `unknown`（沿用 B1 的 typelize 对象字面量先例）；随后再生成契约产物（api-docs / platform 副本 / zod / dist）。
- **FR-010 i18n**：新增键落在 `cart` / `coupon` 命名空间，覆盖 en / de / es / fr / pl 五语言，键集合一致。
- **FR-011 回归保护**：购物车页既有能力（勾选 / 全选 / 数量 / 删除 /「去结算」禁用逻辑）行为不变；BFF same-origin 校验保留。

## 4. 非功能需求（NFR）

- **安全**：BFF 保留同源校验（非同源 403）；余额请求凭 httpOnly access token（`getCartOptions().token` → Bearer JWT），不在客户端拼装金额、不新增 `NEXT_PUBLIC_` 变量；错误信封不泄露内部异常。
- **兼容**：不新增后端端点、不动数据库；新增字段全部 additive（旧前端忽略新键仍可渲染）。
- **一致性**：money 契约（raw 判逻辑、display 仅渲染，禁止 `parseFloat(display_*)`）；抵扣数值一律来自服务端快照。
- **可维护性**：抵扣 UI 抽成独立组件便于单测；服务端动作集中在 `lib/data/shopping-cart.ts`。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001 ← FR-001**：cart 快照含 `store_credit.display_amount` 时，Summary 渲染余额行（`data-testid="store-credit-row"`）。
- **AC-002 ← FR-001**：`store_credit` 为 null 或金额为 0 时不渲染余额行（边界）。
- **AC-003 ← FR-001/FR-008**：礼卡行显示 `code`，折扣码行显示码 + 「结算时计算」提示，合计仍等于 `display_item_total`。
- **AC-004 ← FR-004**：点击「使用店铺余额」→ 服务端动作调用 `carts.storeCredits.apply`（不带 amount）→ 用返回快照驱动 UI（行出现）。
- **AC-005 ← FR-004**：点击「移除」→ 调用 `carts.storeCredits.remove` → 行消失。
- **AC-006 ← FR-005**：未登录 → 余额控件禁用且点击**不调用服务端动作**（0 请求），并渲染登录引导链接（带 redirect 回跳）。
- **AC-007 ← FR-006**：礼卡已应用 → 余额控件禁用并带原因说明，单击不调用服务端动作。
- **AC-008 ← FR-007**：服务端错误码（如 `store_credit_not_available`、`store_credit_gift_card_conflict`）经数据层 `code` 透传后映射到对应 i18n 文案。
- **AC-009 ← FR-009**：生成物中 `ShoppingCart.gift_card` / `.store_credit` 为具体对象类型且 `discount_code` 存在；空手车上三个意图字段均为 null；`generated:check` 无漂移。
- **AC-010 ← FR-010**：五语言均含新增键（i18n 守护测试逐语言断言）。
- **AC-011 ← FR-011**：购物车页既有交互回归不变（选择/数量/删除/去结算禁用）；单一输入框兼容优惠码与礼品卡码（先优惠码、`coupon_code_not_found` 时再试礼品卡）。
- **AC-012 ← NFR 安全**：客户端组件只经 `"use server"` 动作访问 Store API（数据层测试断言 `getCartOptions()` 凭据透传）；无结构化错误码的失败**不伪造** `code`（不吞错、不回退成虚假业务码）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `store_credit` / `gift_card` / `shopping_cart` | 仅生成类型产物（`app/javascript/types/serializers/PallasTradeApiV3ShoppingCart.ts` 中 `gift_card: unknown`、`store_credit: unknown`） | ⚠️ 仅类型产物，无业务代码 |
| Core | `pallastrade_gems/pallastrade_core/app/` | `store_credit` / `ApplyStoreCredit` / `AddStoreCredit` | `services/pallastrade/carts/{apply_store_credit,apply_gift_card,apply_discount_code}.rb`、`carts/submit.rb`（提交兑现）、`checkout/{add,remove}_store_credit.rb`、`models/pallastrade/payment_method/store_credit.rb` | ✅ 车阶段意图 + 提交兑现齐备 |
| API | `pallastrade_gems/pallastrade_api/app/` | `store_credits` / `carts` | `controllers/.../store/carts/store_credits_controller.rb`（POST/DELETE，401/422 语义映射）、`carts/discount_codes_controller.rb`、`carts/gift_cards_controller.rb`、`serializers/.../shopping_cart_serializer.rb` | ✅ 端点齐备；⚠️ 序列化器缺 `discount_code` 且抵扣字段无精确类型 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | `store_credit` / `StoreCredit` | `admin/store_credits_controller.rb`、`admin/users/_tabs.html.erb`、`payments/source_forms/_store_credit.html.erb` | ✅ 后台已能发/查余额（本批无改动） |
| Storefront | `storefront/src/` | `storeCredit` / `giftCard` | `app/api/checkout/coupon/route.ts`（仅 discount + gift_card）、`components/checkout/CouponCode.tsx`、`UnifiedCheckout.tsx`、`app/[country]/[locale]/(storefront)/cart/page.tsx`（摘要仅 `item_total`）、`lib/data/shopping-cart.ts`（无抵扣动作） | ❌ 缺余额入口与摘要三合一 → 本批实现 |
| Platform | `platform/packages/` | `storeCredits` / `store_credit` | `sdk/src/store-client.ts` L659-675（`carts.storeCredits.apply/remove` 已有）、`types/generated/ShoppingCart.ts`（`unknown`） | ✅ SDK 方法齐备；⚠️ 类型待精度化 |

**结论**：Core / API / Admin / Platform 四层能力齐备 → B2 是**纯 storefront 消费 + 1 处序列化器 additive 补全**。禁止在 storefront 重复实现抵扣计算或余额扣减（车阶段零资金副作用，兑现唯一入口是 `Carts::Submit`）。

## 7. 技术影响

- **storefront**：`app/[country]/[locale]/(storefront)/cart/page.tsx`（挂载抵扣模块 + 三合一摘要行 + `shippingNote`）、`lib/data/shopping-cart.ts`（+6 个抵扣服务端动作）、`lib/data/utils.ts`（`actionResult` 透传服务端错误码 `code`）、新组件 `components/cart/CartCreditsPanel.tsx` 与 `CartCreditsSummary.tsx`、`messages/{en,de,es,fr,pl}.json`。既有 BFF `/api/checkout/coupon`（结账页用）**保持不动**。
- **backend（additive）**：`pallastrade_api/app/serializers/pallastrade/api/v3/shopping_cart_serializer.rb`（`discount_code` + 两处对象字面量类型）+ 生成物（`backend/packages/sdk/src/types/generated/StoreShoppingCart.ts`、`backend/app/javascript/types/serializers/*`、`backend/public/api-docs/store.yaml`）。
- **platform**：`sdk/src/types/generated/*`、`sdk/src/zod/generated/*`、`docs/api-reference/{store,admin}.yaml`、`sdk/dist/*`（提交需 `git add -f`）。
- **不涉及**：数据库迁移、新端点、订单状态机、支付会话创建、管理后台。

## 8. 测试计划

- **新增（storefront 组件）**：`storefront/src/components/cart/__tests__/CartCreditsPanel.test.tsx` → AC-001/002/003/004/005/006/007/008/011
- **新增（数据层）**：`storefront/src/lib/data/__tests__/shopping-cart-credits.test.ts`（vi.mock SDK 客户端；断言 `apply` 省略 amount、`remove` 调用、错误码透传、无码失败不伪造）→ AC-004/005/008/011/012
- **扩展（i18n 守护）**：`storefront/src/lib/__tests__/checkout-i18n-keys.test.ts` 追加 `cart` / `coupon` 必填键（五语言）→ AC-010
- **后端**：`backend/spec/requests/api/v3/store/carts/{discount_codes,store_credits}_spec.rb` 追加 `discount_code` 可见性与「空手车三意图均为 null」断言 → AC-009
- **回归**：既有 storefront 组件测试保持绿；`pnpm test` / `pnpm check`(biome) / `pnpm typecheck` 三绿（CI 红线教训）
- **AC ↔ 测试映射**：见上逐条标注；测试文件内同行写 `# PRD-<本PRD-ID> AC-xxx` 供 `prd verify` 校验

## 9. 文档同步清单（知识同步门）

- [x] API 文档：`backend/public/api-docs/store.yaml` + `platform/docs/api-reference/{store,admin}.yaml`（ShoppingCart schema 精度）—— `generated:check` no drift
- [x] Skill：`pallastrade-storefront`（购物车页抵扣模块口径）、`pallastrade-typescript-sdk`（ShoppingCart 抵扣字段）—— 已更新；`pallastrade-payments` / `pallastrade-api-v3` 评估为无需更新（意图语义与端点契约未变）
- [x] 场景库：新增 **GS-121**（车阶段抵扣意图 + 登录门槛 + 零资金副作用），`eval-ai --scenarios` = 122/122 valid
- [x] 包文档：`platform/packages/README.md`（三个意图字段已类型化）
- [x] 本 PRD 状态更新 → done + `docs/prd/README.md` 索引（`prd-status-sync --fix/--check`）
- [x] **已评估，无需更新**（`sync-check` 列出的其余资产）：
  - `根 README` —— 无字段级 SDK 内容，变更已在 `platform/packages/README.md` 记录
  - `pallastrade-prd Skill` / `AGENTS.md` / `.github/copilot-instructions.md` —— PRD/gate 机制与分层规则未变，本批按既有流程执行
  - `pallastrade-payments` / `pallastrade-api-v3` Skill —— 抵扣意图语义与 cart 端点契约未变（仅序列化器 additive 字段）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-14 | 0.1 | 初稿：B2 范围（购物车页余额入口 + 摘要三合一）+ FR-001..011 / AC-001..012 / 跳层搜索 / 测试与同步计划 | AI |
| 2026-09-14 | 0.2 | 实施：①抵扣调用统一走 `lib/data/shopping-cart.ts` 服务端动作（不再动 BFF，与购物车页既有模式一致）；②AC-012 由「BFF 同源 403」重划为「只经 server action + 不伪造错误码」；③测试计划改为组件/数据层/i18n 守护/后端 spec 四处 | AI |
