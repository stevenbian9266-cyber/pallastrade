# PRD-20260913-checkout-billing-mode

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-13 |
| 来源 | 修复：Checkout 账单地址同配送建模（use_shipping→billing_mode）与订单账单地址兜底 |
| 分类 | checkout |
| 关联 Skill | pallastrade-api-v3 / pallastrade-storefront |
| 关联 REQ | REQ-20260913-checkout-billing-mode.md |
| 关联 PRD | N/A（`harness prd new` 查重未命中；全新缺陷修复） |
| 需求类型 | Bug 修复（含 Store API 可选参数扩展） |

> 依据：`docs/research/RESEARCH-20260913-checkout-plan-review-and-decision.md` §9.1 P0-b + §11「PRD-2」行（用户确认项：无）。
> 关联既有先例：legacy `PallasTrade::Order#use_shipping?`（`order.rb` L254-255/L1406）与 Admin `billing_address_type == 'same_as_shipping'`（`orders/billing_address_controller.rb`）。

> 🔁 **查重回写**：`harness prd new` 自动查重（相似度 > 0.3 阻止新建）。
> 若本需求命中相似 PRD，用 `harness prd update --path <原PRD> --title "<需求>"` 回写原 PRD，
> 并在原文档内完整更新（背景/FR/AC/变更记录），**不得新建重复 PRD**；确属全新需求才 `--force`。

## 1. 背景与目标

- **一句话需求原文**：修复：Checkout 账单地址同配送建模（use_shipping→billing_mode）与订单账单地址兜底
- **背景**（缺陷链路，已逐段核验）：
  1. `cart_` 统一下单页 "Same as shipping" 复选框**默认勾选**（`UnifiedCheckout.tsx` L333 `useState(true)`），点击 Pay now 时**只发送** `checkout.use_shipping = true`（L609-611）。
  2. BFF `/api/checkout/start` 把 `body.checkout` **原样透传**给 `client.carts.update`（`app/api/checkout/start/route.ts` L128-133）。
  3. Store API `Store::CartsController#permitted_params`（L122-140）**未 permit `use_shipping`** → ActionController::Parameters 静默丢弃；`Carts::Update` 也只处理显式 `billing_address`/`billing_address_id`（`update.rb` L17）。
  4. 购物车 `billing_address_id` 恒为 `nil` → `Carts::Submit#build_order!` L100 `order.bill_address = cart.billing_address.dup if cart.billing_address.present?` 不成立 → **`Order.bill_address` 为空**。
- **影响面**：订单确认邮件 / `order-placed` 页 / 个人中心订单详情的账单区块缺失；PSP 部分场景需要 billing 信息（Admin `payments_controller.rb` 已有 `billing_address.nil?` 分支）；后续退款/风控口径缺失。
- **附带缺陷**：`useShippingForBilling` 初值恒为 `true`，若购物车已存在独立账单地址（会话恢复 / `buy_now` / express 路径写入），页面上"默认勾选"与本地上一次选择冲突，提交时会以"同配送"语义覆盖既有账单地址。
- **目标**：把「账单地址 = 同配送 / 独立」从**前端瞬时布尔**升级为**服务端显式建模**（`billing_mode: same_as_shipping | custom`），并在提交订单时对账单地址做**确定性兜底**，保证有配送地址时 `Order.bill_address` 永不为空。
- **成功指标**：
  1. 存在配送地址时，新流程图订单 `Order.bill_address_id` 非空比例 100%（RSpec 断言 + 手工走单验证）。
  2. 勾选/取消勾选两条路径的请求载荷 `billing_mode` 与 UI 状态一致（Vitest 断言）。
  3. 取消勾选且账单字段不完整时**客户端拦截**且服务端返回 `billing_address_incomplete`（不落半空地址）。
  4. 旧客户端 `use_shipping: true` 仍被接受（映射为 `same_as_shipping`），无破坏性变更。

## 2. 用户故事 / 场景

- 作为**顾客**，我希望勾选"账单地址同配送地址"后订单的账单地址与配送地址一致，以便支付与发票信息完整。
- 作为**顾客**，我希望取消勾选并填写独立账单地址后，订单保存我填写的地址，且重新进入结算页时保持该选择（不被默认值覆盖）。
- 作为**集成方（旧 SDK/旧前端）**，我希望继续发送 `use_shipping: true` 而不被拒绝。
- 场景列表：
  1. **正常流 A（默认勾选）**：cart 无账单地址 → 提交后 `order.bill_address` = `cart.shipping_address` 副本。
  2. **正常流 B（取消勾选 + 完整账单地址）**：`cart.billing_address` 落库 → 提交后 `order.bill_address` = 该地址副本（不回退）。
  3. **回退流 C（B 之后重新勾选）**：`billing_mode=same_as_shipping` 清除 cart 账单地址 → 提交后 = 配送地址副本。
  4. **边界 D（无配送地址）**：提交账单兜底不触发（`bill` 仍为空），不引入新失败路径；由既有必填校验/UI 拦截。
  5. **异常 E（自定义但字段不完整）**：服务端 422 `billing_address_incomplete`，UI 在点击 Pay now 前拦截并提示。
  6. **兼容 F（仅发 `use_shipping`）**：`true/'true'/'1'` → `same_as_shipping`；`false/'false'/'0'` → `custom`。
  7. **兼容 G（两者都不发且已有账单地址）**：以显式地址为准，不回退为配送地址。

## 3. 功能需求（FR）

- **FR-001**（Core · `Carts::Update`）：新增 `billing_mode` 语义解析 —— `same_as_shipping` → 清除购物车账单地址（`cart.billing_address = nil`，语义"同配送"）；`custom` → 走既有 `assign_address(:billing_address)` 落库显式地址。
- **FR-002**（Core · 向后兼容）：`use_shipping` 映射 —— `true/'true'/'1'` ⇒ `same_as_shipping`；`false/'false'/'0'` ⇒ `custom`；未提供则不改变现状。
- **FR-003**（Core · 校验）：`billing_mode=custom` 且提供的 `billing_address` 不完整（缺 `first_name`/`last_name`/`address1`/`city`/`postal_code`/`country_iso`）→ `Carts::Update::IncompleteBillingAddress` 抛出并回滚事务，**不得**落库半空地址；错误经既有 Store API 信封返回（`validation_error` + message `Billing address is incomplete (missing: …)`）。
- **FR-004**（Core · `Carts::Submit#build_order!`）：账单快照优先级 = 显式 `cart.billing_address` 副本 → 否则 `cart.shipping_address` 副本（兜底）→ 两者皆无则保持 `nil`。
- **FR-005**（API · `Store::CartsController`）：`permitted_params` 增加 `:billing_mode`、`:use_shipping`。
- **FR-006**（API · 契约文档）：`backend/public/api-docs/store.yaml` 与 `platform/docs/api-reference/store.yaml` 的 `PATCH /api/v3/store/carts/{id}` 请求体新增 `billing_mode`（enum）与 legacy `use_shipping`（标注 deprecated），并跑 `harness generated:check`。
- **FR-007**（SDK）：`platform/packages/sdk/src/types/index.ts#UpdateCartParams` 新增 `billing_mode?: 'same_as_shipping' | 'custom'`；`use_shipping` 标注 `@deprecated`（保留兼容）；`CHANGELOG.md` 记录。
- **FR-008**（Storefront · BFF）：`/api/checkout/start` 的 `CheckoutStartBody.checkout` 支持 `billing_mode` 并透传；`use_shipping` 保留兼容但不再由本站前端发送。
- **FR-009**（Storefront · UI 载荷）：`UnifiedCheckout#handlePayNow` 按勾选态发送 `billing_mode: 'same_as_shipping'`（不发送账单地址）或 `billing_mode: 'custom'` + `billing_address`。
- **FR-010**（Storefront · UI 初值）：`useShippingForBilling` 初值 = `cart.billing_address ? false : true`，避免静默覆盖既有独立账单地址。
- **FR-011**（Storefront · UI 校验 + i18n）：取消勾选时账单地址不完整 → 点击 Pay now 前拦截并提示（`checkout.billingAddressIncomplete`，五语言齐全），不发请求。
- **FR-012**（Storefront · server action）：`lib/data/checkout.ts#updateOrderAddresses` 参数类型新增 `billing_mode`（与 BFF 载荷一致）。
- **FR-013**（范围外，显式声明）：`PATCH /api/v3/store/orders/:id/checkout` 不支持账单字段（`or_` 页当前无账单编辑入口，`OrderPaymentContent` 无账单 UI）；本 PRD **不改其协议**，仅在文档中记录现状；若后续引入 `or_` 地址编辑，另开 PRD。

## 4. 非功能需求（NFR）

- **兼容性**：新增参数可选；`use_shipping` 保留映射，旧 SDK / 旧前端 / 旧购物车恢复路径不破坏。
- **安全**：沿用 `resolve_address_id` 的 store 作用域（不跨店取地址）；`billing_mode` 为白名单枚举，非法值不落库。
- **数据**：**不新增数据库列、不做迁移** —— `billing_mode` 语义由"显式账单地址是否存在"派生 + 服务端即时处理，避免 `pallastrade_carts` 表结构变更与 `harness check --profile full` 的迁移面。
- **可维护性**：语义单点定义（写入 = `Carts::Update`，快照 = `Carts::Submit`），两处均补 RSpec；前端载荷由 Vitest 契约守护（禁止再发 `use_shipping`）。
- **可观测性**：`billing_address_incomplete` 错误码进入 BFF/前端既有错误信封（`{ error: { code, message } }`），前端经 `normalizeErrorMessage` 展示。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001** ← FR-001：`Carts::Update` 收到 `billing_mode: 'same_as_shipping'` 时清除既有 `billing_address`；收到 `'custom'` + 完整地址时落库新地址（`cart.reload.billing_address` 断言）。
- **AC-002** ← FR-002：`use_shipping: true`（及 `'true'`/`'1'`）触发清除；`use_shipping: false` 不创建地址、不清除既有地址。
- **AC-003** ← FR-003：`billing_mode: 'custom'` + 不完整地址 → 服务失败、`cart.billing_address` 保持原值（无半空地址落库）。
- **AC-004** ← FR-004：cart 无账单地址、有配送地址 → `Order.bill_address` 非空且 `first_name/city/postal_code/country_iso` 与配送地址一致。
- **AC-005** ← FR-004：cart 有独立账单地址 → `Order.bill_address` = 该地址（**不**被配送地址覆盖）。
- **AC-006** ← FR-005：`PATCH /api/v3/store/carts/:id` 带 `billing_mode` 时不被参数过滤丢弃（controller spec：参数到达服务层）。
- **AC-007** ← FR-006：`harness generated:check` 通过（OpenAPI ↔ 生成类型一致）。
- **AC-008** ← FR-009：Vitest 断言勾选态载荷 `{ billing_mode: 'same_as_shipping' }`（且不含 `use_shipping`）；取消勾选载荷 `{ billing_mode: 'custom', billing_address: {...} }`。
- **AC-009** ← FR-010：cart 已带 `billing_address` 时复选框默认**未勾选**（渲染断言）。
- **AC-010** ← FR-011：取消勾选 + 账单字段不完整 → `fetch` 未被调用且展示 `checkout.billingAddressIncomplete`。
- **AC-011** ← FR-011：五语言 messages 均含 `checkout.billingAddressIncomplete`（i18n 键守护测试）。
- **AC-012** ← FR-013：`or_` 页 `OrderPaymentContent` 现有测试保持全绿（无回归）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | billing / bill_address | 无计费地址相关实现 | — |
| Core | `pallastrade_gems/pallastrade_core/app/` | use_shipping / billing_mode / billing_address | `services/pallastrade/carts/update.rb` L17（`assign_address(:billing_address)`，**无 `use_shipping`/`billing_mode`**）；`services/pallastrade/carts/submit.rb` L100（`if cart.billing_address.present?` 条件复制，**无兜底**）；`models/pallastrade/cart.rb` L18（`Metadata` concern）、L30-31（`belongs_to :billing_address`）；`models/pallastrade/order.rb` L254-255/L1406（`use_shipping?` + `before_validation :clone_shipping_address` 先例）；`lib/pallastrade/permitted_attributes.rb` L100 | 部分（Order 侧有先例，Cart 侧缺失）→ 本 PRD 补齐 |
| API | `pallastrade_gems/pallastrade_api/app/` | permitted_params / billing | `store/carts_controller.rb` L122-140（有 `billing_address`/`billing_address_id`，**无 `billing_mode`/`use_shipping`**）；`store/orders/checkout_controller.rb`（PATCH 仅 `contact`/`shipping_address`/`delivery_rate_id`）；`serializers/.../shopping_cart_serializer.rb`（已暴露 `billing_address`）；`serializers/.../store/checkout/checkout_serializer.rb` L35（含 `billing_address`） | 否（需扩参数） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | billing_address_type | `orders/billing_address_controller.rb`（`billing_address_type == 'same_as_shipping'` **命名先例**）、`users/_billing.html.erb`（`use_shipping_address` 文案）、`config/locales/en.yml` L1475 | 是（仅命名/文案先例，不改代码） |
| Storefront | `storefront/src/` | use_shipping / billAddress | `components/checkout/UnifiedCheckout.tsx` L333（默认 `true`）/L609-611（只发 `use_shipping`）/L974-1000（账单表单）；`app/api/checkout/start/route.ts` L26-31、L128-133（原样透传）；`lib/data/checkout.ts` L37-40；`lib/data/express-checkout-flow.ts` L84-95（express 路径显式发 `billing_address`） | 否（需改载荷/初值/校验） |
| Platform | `platform/packages/` | use_shipping / UpdateCartParams | `sdk/src/types/index.ts` L419（`use_shipping?: boolean`）；`sdk/CHANGELOG.md` L171（历史语义说明） | 否（需增类型） |

**结论**：Core / API / Storefront / SDK 四层需改；Admin 提供 `same_as_shipping` 命名与文案先例；无既有实现可复用（不存在重复实现，无 NEEDS-DEDUP）。**数据层不新增列**（派生语义），规避 carts 表迁移。

## 7. 技术影响

- **涉及文件（预计）**：
  - Core：`backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/carts/update.rb`、`.../carts/submit.rb`（变更块加 `# PALLAS-CUSTOM:` 标注）
  - API：`backend/pallastrade_gems/pallastrade_api/app/controllers/pallastrade/api/v3/store/carts_controller.rb`
  - 契约/文档：`backend/public/api-docs/store.yaml`、`platform/docs/api-reference/store.yaml`、`platform/packages/sdk/src/types/index.ts`、`platform/packages/sdk/CHANGELOG.md`
  - Storefront：`storefront/src/components/checkout/UnifiedCheckout.tsx`、`storefront/src/app/api/checkout/start/route.ts`、`storefront/src/lib/data/checkout.ts`、`storefront/messages/{de,en,es,fr,pl}.json`
  - 测试：`backend/spec/services/pallastrade/carts/{update,submit}_spec.rb`（update spec 若不存在则新建）、`storefront/src/components/checkout/__tests__/UnifiedCheckout.test.tsx`、`storefront/src/lib/__tests__/checkout-i18n-keys.test.ts`（或新增 billing 守护测试）
  - 知识：`ai/skills/pallastrade-storefront/SKILL.md`、`ai/skills/pallastrade-api-v3/SKILL.md`、`harness/scenarios/scenarios.json`
- **数据库**：无迁移、无 `schema.rb` 变更。
- **接口**：`PATCH /api/v3/store/carts/:id` 请求体**新增可选字段**（向后兼容，无破坏性变更）。
- **影响面**：`harness affected` 输出在实施阶段记录到 REQ。

## 8. 测试计划

- **新增**：
  - `backend/spec/services/pallastrade/carts/update_spec.rb`（AC-001/002/003；若文件已存在则追加 describe 块）
  - `storefront/src/lib/__tests__/checkout-billing-mode-guard.test.ts`（AC-008 契约守护：扫描 `UnifiedCheckout.tsx`/`route.ts` 源码，禁止再出现 `use_shipping` 载荷字段）
- **更新**：
  - `backend/spec/services/pallastrade/carts/submit_spec.rb`（AC-004/005 账单兜底与优先级）
  - `storefront/src/components/checkout/__tests__/UnifiedCheckout.test.tsx`（AC-008/009/010）
  - `storefront/src/lib/__tests__/checkout-i18n-keys.test.ts`（AC-011 新增键五语言守护）
- **AC → 测试映射**：AC-001/002/003 → `carts/update_spec.rb`；AC-004/005 → `carts/submit_spec.rb`；AC-006 → `spec/requests/.../carts_spec.rb`（若既有请求规格未覆盖参数放行，则以服务级 + 手工 curl 证据补充）；AC-007 → `harness generated:check`；AC-008/010 → `UnifiedCheckout.test.tsx` + guard 测试；AC-009 → `UnifiedCheckout.test.tsx`；AC-011 → `checkout-i18n-keys.test.ts`；AC-012 → 既有 `OrderPaymentContent.test.tsx`（回归）。
- **验证器**：`backend-rspec`（或 `p1-order-flow-rspec`）、`chk-p1-4b-storefront`、`chk-p1-4c-storefront`、`storefront-test`。

## 9. 文档同步清单（知识同步门）

| 知识资产 | 结论 | 依据 |
|---|---|---|
| `backend/public/api-docs/{store,admin}.yaml` | ✅ 已更新 | `PATCH /api/v3/store/carts/{id}` 新增 `billing_mode`（enum）+ legacy `use_shipping`（deprecated） |
| `platform/docs/api-reference/store.yaml` | ✅ 已同步 | 同上（两份契约副本保持一致） |
| SDK 类型（`generated:check`） | ✅ 已更新 | `UpdateCartParams.billing_mode` + `use_shipping` 标 `@deprecated`；`harness generated:check` 无漂移 |
| `pallastrade-api-v3` Skill | ✅ 已更新 | 新增「`permitted_params` 即契约（未 permit 静默丢弃）+ `billing_mode` 账单语义」段 |
| `pallastrade-storefront` Skill | ✅ 已更新 | Checkout 章节新增「账单地址同配送建模」（载荷/初值/校验/五语言+守护） |
| `harness/scenarios/scenarios.json` + 场景库 | ✅ 已更新 | 新增 GS-113（账单语义服务端建模 + 订单账单兜底） |
| 组件测试 | ✅ 已更新 | `update_spec.rb`（新建 6 例）、`submit_spec.rb`（+2）、`carts_controller_spec.rb`（+2）、`UnifiedCheckout.test.tsx`（+2）、新增 `checkout-billing-mode-guard.test.ts`；`storefront-test` 全量绿 |
| `pallastrade-typescript-sdk` Skill / `platform/packages/README.md` / 根 README | ⬜ 已评估无需更新 | SDK 变更为纯类型新增（+ `@deprecated` 标注），由 `CHANGELOG` 与 OpenAPI 承载；README 不逐字段记录 API 参数 |
| `pallastrade-prd` Skill / `AGENTS.md` / `copilot-instructions.md` | ⬜ 已评估无需更新 | 按既有 PRD/门禁流程执行，未改机制、未新增前缀或导航条目 |
| 反弹式库 / 任务规则 | ⬜ 已评估无需更新 | 未新增/违反 AP-*（未写内联样式、裸 fetch、硬编码色，未新增 DB 列） |
| 本 PRD 状态 + `docs/prd/README.md` 索引 | ✅ 已更新 | 状态 `done` + 索引已回填 REQ 关联 |

> `harness sync-check --id PRD-20260913-checkout-billing-mode` → 逐项处置 → `--ack`（见 §10）。

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-13 | 0.1 | 初稿（跨层检索完成；缺陷链路逐段核验；待用户确认后开 gate） | AI |
| 2026-09-13 | 1.0 | 实施完成：Core（`Carts::Update` billing_mode/use_shipping/不完整地址拦截、`Carts::Submit` 账单兜底）、Store API permit、OpenAPI×2、SDK 类型+CHANGELOG、Storefront（载荷/初值/校验/五语言）、测试（RSpec 8 例、Vitest +1 例）；偏差：错误码沿用既有 `validation_error`（message 携带 `Billing address is incomplete`），未新增专用 code | AI |
