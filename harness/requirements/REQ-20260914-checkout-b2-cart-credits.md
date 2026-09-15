# REQ-20260914-checkout-b2-cart-credits

> 关联 PRD：`docs/prd/checkout/PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一.md`
> 关联任务：TASK-20260914230055-f585145a · Gate `GATE-2026-09-14T23-01-03`
> 前置批次：B1（`REQ-20260914-checkout-b1-checkoutview-extension.md`，已 done）

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | `store_credit` / `gift_card` / `shopping_cart` | 仅生成类型产物 `app/javascript/types/serializers/PallasTradeApiV3ShoppingCart.ts`（`gift_card: unknown`、`store_credit: unknown`）；无业务代码 | 否（宿主层无需业务改动） |
| Core Gem — models | `pallastrade_core/app/models/` | `store_credit` / `gift_card` / `covered_by_store_credit` | `models/pallastrade/{store_credit,store_credit_event,gift_card,payment_method/store_credit}.rb`、`order/store_credit.rb`（`total_applied_store_credit`、`covered_by_store_credit?`） | 是（数据源已存在） |
| Core Gem — services | `pallastrade_core/app/services/pallastrade/carts/` | `store_credit` / `ApplyStoreCredit` / `apply_discount_code` | `carts/{apply_store_credit,remove_store_credit,apply_gift_card,apply_discount_code}.rb`、`carts/submit.rb`（`apply_store_credit!`/`apply_gift_card` 提交时兑现）、`checkout/{add,remove}_store_credit.rb` | 是（车阶段意图 + 提交兑现齐备） |
| API Gem — controllers | `pallastrade_api/app/controllers/pallastrade/api/v3/store/carts/` | `store_credits` / `gift_cards` / `discount_codes` | `store_credits_controller.rb`（POST/DELETE，`STORE_CREDIT_ERROR_STATUS`：401/422 映射）、`gift_cards_controller.rb`、`discount_codes_controller.rb` | 是（端点齐备，无需新建） |
| API Gem — serializers | `pallastrade_api/app/serializers/pallastrade/api/v3/` | `shopping_cart_serializer` / `store_credit` | `shopping_cart_serializer.rb`（`gift_card: {code, display_amount_remaining}`、`store_credit: {amount, display_amount}`，均 `{ nullable: true }` **无精确类型**；**缺 `discount_code`**） | 部分（需 additive 补全） |
| Admin Gem | `pallastrade_admin/app/` | `store_credit` / `StoreCredit` | `admin/store_credits_controller.rb`、`admin/users/_tabs.html.erb`、`payments/source_forms/_store_credit.html.erb`、`gift_cards/show.html.erb` | 是（后台发/查余额自有用例，本批零改动） |
| Storefront | `storefront/src/` | `storeCredit` / `giftCard` / `coupon` | `app/api/checkout/coupon/route.ts`（仅 `discount` + `gift_card`）、`components/checkout/CouponCode.tsx`、`UnifiedCheckout.tsx`（摘要含礼卡行、无余额）、`app/[country]/[locale]/(storefront)/cart/page.tsx`（摘要仅 `item_total`）、`lib/data/shopping-cart.ts`（无抵扣动作） | **否 → 本批实现** |
| Platform | `platform/packages/` | `storeCredits` / `store_credit` | `sdk/src/store-client.ts` L659-675（`carts.storeCredits.apply(cartId, amount?)` / `.remove(cartId)` 已有）、`sdk/src/types/generated/ShoppingCart.ts`（`gift_card/store_credit: unknown`） | 部分（SDK 方法齐备，类型待精度化） |

### 搜索结论

- 能力载体（三个 cart_ 抵扣意图服务 + 三个端点 + SDK 方法）**全部已存在**；本批是 **storefront 消费 + 1 处序列化器 additive 补全**，不做后端业务逻辑。
- 防重复判定：`PRD-20260914-checkout-cart-{discount-codes,gift-cards,store-credits}-canonical` 已交付后端能力（done），本批只补前台入口与展示；`PRD-20260914-checkout-…-b1-*` 交付的是 `or_` 结账页（done），本批为**购物车页**（不同页面、不同数据源：`ShoppingCart` vs `CheckoutView`）。
- 关键语义（不得违反）：车阶段**零资金副作用**，余额/礼卡/折扣码仅为意图（`private_metadata`），兑现唯一入口是 `Carts::Submit`；余额要求登录（`store_credit_requires_login`）且与礼卡互斥（`store_credit_gift_card_conflict`）。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 定制优先级 Settings→Configuration→Events→Dependencies→Admin/Ransack→Generators→Decorators→Extensions；本批不新增定制模式（消费既有端点），故不做 decorator/subscriber，属最稳层级 |
| `ai/skills/harness-prd/SKILL.md` | ✅ 已读 | 阶段 0-5：`prd new`（自动分类 + 查重 >0.3 阻止）→ 模板扩充 → 用户确认 → gate → 实施 → AC↔测试（`prd verify`）→ 知识同步门；本批严格按序执行 |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-storefront` | ✅ | ✅ 已读 | ① 客户端组件不得直接 `getClient()`，必须走 `src/lib/data/` 的 `"use server"` action（返回 `{success,error}`）；② money 契约：raw 判逻辑、display 仅渲染；③ 验证清单：改 storefront 必须 `pnpm test` + `pnpm check`(biome) + `pnpm typecheck` 三绿（CI 红线教训）；④ 购物车页 `/{country}/{locale}/cart` 由 `lib/data/shopping-cart.ts` 驱动 |
| `pallastrade-payments` | ✅ | ✅ 已读 | 「Two stages, one authority」：`cart_` 上礼卡/余额仅 intent（`Carts::ApplyStoreCredit`/`ApplyGiftCard`），提交时由 `Carts::Submit` 收敛；余额按 user/store/currency 记账；礼卡与余额同单互斥（`gift_card_using_store_credit_error`） |
| `pallastrade-api-v3` | ✅ | ✅ 已读 | 序列化器契约 = typelizer 生成物 + OpenAPI；「whatever a serializer returns, `permitted_params` accepts on write under the same name」；契约改动走 `scripts/ci/contracts.sh` + `harness generated:check` 门禁 |
| `pallastrade-i18n` | ✅ | ✅ 已读 | UI 文案在 storefront 侧为 `messages/<locale>.json`；monorepo 约定五语言（en/de/es/fr/pl）键集合一致；JSON 重复键会被 biome `noDuplicateObjectKeys` 拦下（需 JSON.parse 之外的手段校验） |
| `pallastrade-testing` | ✅ | ✅ 已读 | 后端 RSpec + Factory Bot（禁 `Model.create` 于 spec 外、断言环境无关）；storefront 侧 vitest（组件/数据层单测），route handler 可直接 import 单测 |
| `pallastrade-decorators` / `pallastrade-dependencies` / `pallastrade-events-webhooks` | ⛔ | ⛔ | 不改既有类结构、不替换核心服务、无事件/订阅者改动 |
| `pallastrade-admin` | ⛔ | ⛔ | 本批零 admin 改动 |

---

## 需求标题

Checkout 收尾收敛 B2：购物车页店铺余额入口与 Order Summary 三合一（折扣码 / 礼卡 / 余额）

## 任务类型

功能优化（storefront 消费既有 API；后端仅 1 处序列化器 additive 字段 + 类型精度）

## 需求描述

购物车页当前只有商品操作与 `item_total` 两行摘要，用户无法在车上应用/移除店铺余额（也无折扣码/礼卡入口），且车阶段三种抵扣的服务端意图没有对应 UI。本批把 BFF + UI 补齐：BFF 支持 `store_credit` kind、购物车页新增「优惠与抵扣」模块与摘要三行（折扣码 / 礼卡 / 余额），游客看到登录引导；同时 additive 补全 `ShoppingCartSerializer`（`discount_code` + 两处对象字面量类型）让契约可表达这些意图。

## 影响范围（harness affected 输出）

受影响：storefront（BFF route / data actions / 新组件 / cart 页 / 5 语言文案）、Store API `ShoppingCart` 序列化（additive）、契约生成物（api-docs / SDK types / zod / dist）。
不涉及：数据库迁移、新端点、订单状态机、支付会话创建、admin 页面、legacy `or_` 结账页逻辑（B1 已完成）。

## 技术方案（初步）

1. 后端：`shopping_cart_serializer.rb` 加 `discount_code: [:string, nullable: true]`（读 `private_metadata['discount_code']`），并把 `gift_card`/`store_credit` typelize 改为对象字面量；契约再生成（typelizer + `api:docs:schemas` + platform 副本 + zod + dist）。
2. BFF：`/api/checkout/coupon` 增加 `kind: "store_credit"`（apply 调 `carts.storeCredits.apply(cart_id)`，remove 调 `.remove(cart_id)`），错误信封沿用 `{ error: { code, message } }`，未登录 → 401 `store_credit_requires_login`，冲突/不可用 → 422 + 服务端错误码。
3. 数据层：`lib/data/shopping-cart.ts` 增加 `applyStoreCredit(cartId)` / `removeStoreCredit(cartId)`（`"use server"`），沿用 `actionResult` + `updateTag("cart")`。
4. UI：新增 `components/cart/CartCreditsPanel.tsx`（输入/移除：折扣码、礼卡、余额；游客登录引导；礼卡互斥禁用）与 `CartCreditsSummary.tsx`（三行抵扣，`data-testid` 便于断言），挂到 `cart/page.tsx` 的 Order Summary。
5. i18n：`cart` / `coupon` 命名空间补键，五语言一致。
6. 测试：组件测试 + 数据层测试 + route handler 测试 + 后端 serializer spec；AC↔测试同行标记 `# PRD-<id> AC-xxx`。

## 风险点

- 最高风险：契约再生成（typelize/api-docs/SDK dist）漂移 → 以 `harness generated:check` 与 `pnpm typecheck` 为准；回滚成本低（additive 字段 + 独立提交）。
- 语义风险：车阶段金额是**意图**不是承诺（折扣码/礼卡金额在提交时计算）→ UI 不得展示"已省 ¥X"，也不得参与前端合计；本轮以文案「结算时计算」显式化。
- 登录态风险：`getCartOptions().token` 为空时 BFF 必须返回 401 而不是 500；游客 UI 不发请求。
- 回归风险：`cart/page.tsx` 为客户端组件，新增模块不得影响既有选择/数量/删除逻辑 → 既有断言 + 新增回归断言。

## 决策节点

> ⏸️ **等待用户确认**（R3/R7）：PRD 与 REQ 呈现后，用户明确「确认/实施/go ahead」才清除 `user-confirmed` 并进入实施；
> 用户 2026-09-14 已指示「继续」（承接 B1 后的 B2 批次），仍需对本文档做一次显式确认。
>
> 开放决策（供用户选择，AI 建议已在括号内）：
> 1. 余额入口形态：按钮「使用余额（用尽可用额度）」vs 输入金额框 —— 建议**按钮**（服务端"省略金额=用尽余额"语义最直白，少一个校验分支）。
> 2. 游客体验：入口禁用 + 登录引导 vs 完全隐藏 —— 建议**禁用 + 引导**（可见性教育用户"有余额可用"）。
> 3. 折扣码行文案：显示码 + 「结算时计算」 vs 暂不展示折扣行 —— 建议**显示**（避免"应用成功但界面无反馈"的困惑）。

---

## 阶段③：实施后验证（不可跳过）

> ⚠️ 每项改动都必须有对应的最低验证。

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| 后端（Serializer additive） | `shopping_cart_serializer.rb`、`discount_codes_spec.rb`、`store_credits_spec.rb` | `npx harness verify p1-order-flow-rspec --task <id>` | ✅ 全绿（canonical cart 全家族 + 新断言） | ✅ |
| 前端（数据层 + 组件 + 页面） | `lib/data/{shopping-cart,utils}.ts`、`components/cart/*`、`cart/page.tsx`、`messages/*.json` | `pnpm -C storefront test` / `check` / `typecheck` | ✅ 54 files / 327 tests 全绿；biome exit 0；tsc exit 0 | ✅ |
| 契约 | api-docs / SDK generated / zod / dist | `npx harness generated:check` | ✅ no drift detected | ✅ |
| AC 映射 | PRD AC-001..012 | `npx harness prd verify --id <本PRD>` | ✅ 18 AC 全覆盖 | ✅ |
| 其它 | PRD/README 状态 | `node scripts/ci/prd-status-sync.mjs --check` | ✅ 133/133 一致 | ✅ |
| 声明无需验证 → 原因：_____ | — | — | — | — |

### 新增 admin 页面三要素检查（固定检查项，凡新增/改动 admin 页面必填）

**本批不涉及 admin 页面** —— 无 admin 视图/控制器改动，三项检查豁免（记录在案）。

### 验证结论

- 后端：`p1-order-flow-rspec` 全绿（含 canonical cart gift cards / store credits / discount codes 与订单流程回归）；新增断言：应用后 `discount_code` 可读、空手车三意图均为 null。
- 前端：`pnpm -C storefront test` 54 文件 / 327 用例全绿（新增组件 16 例 + 数据层 5 例 + i18n 守护扩展）；`biome check` exit 0（仅 3 条既有 warning）；`tsc --noEmit` exit 0。
- 契约：`generated:check` = no drift（typelizer 对象字面量 + `discount_code` 字段 + OpenAPI + platform 副本 + zod + SDK dist 重建）。
- 零资金副作用：本批未接支付/未改提交路径 —— 三种抵扣仍只在 `Carts::Submit` 兑现（GS-121 场景守护）。

### 实施决策修正（与 REQ 初稿差异，已回写 PRD v0.2）

- 抵扣调用统一走 **`lib/data/shopping-cart.ts` 的服务端动作**（而非扩展 BFF `/api/checkout/coupon`）：与购物车页既有模式（选择/数量/删除均为 server action）一致，且无需新增同源校验分支；既有 BFF 供结账页使用，保持不动。
- AC-012 由「BFF 同源 403」重划为「只经 server action 边界 + 无结构化错误码时不伪造 code」。
