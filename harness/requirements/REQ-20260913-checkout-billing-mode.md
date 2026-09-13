# REQ-20260913-checkout-billing-mode — Checkout 账单地址同配送建模（billing_mode）+ 订单账单地址兜底

> 关联 PRD：`docs/prd/checkout/PRD-20260913-checkout-billing-mode.md`（draft → 用户确认后 approved）
> 来源：用户指令「继续」（2026-09-13，延续 `docs/research/RESEARCH-20260913-checkout-plan-review-and-decision.md` 的实施序列）
> 上游依据：RESEARCH §9.1 P0-b（billing 缺陷）、§11「PRD-2」行（用户确认项：无）、豆包方案 §7/§17/§19-20〔A-20260913〕
> Task：`TASK-20260913163308-045c73c9`；Gate：`GATE-2026-09-13T16-33-23`（bugfix）
> 产出：Cart 侧账单语义建模（`billing_mode`）+ Order 账单地址兜底 + API/SDK/Storefront 载荷同步

## Step 0：跨层搜索（已执行）

| 层 | 路径 | 关键词 | 结果 | 已满足？ |
|---|---|---|---|---|
| App | `backend/app/` | billing / bill_address / use_shipping | 无宿主层实现 | — |
| Core | `pallastrade_core/app/` | `use_shipping` / `billing_mode` / `billing_address` | `services/pallastrade/carts/update.rb` L17（仅显式 `billing_address`，**无 `use_shipping`/`billing_mode`**）；`services/pallastrade/carts/submit.rb` L100（`if cart.billing_address.present?` 条件复制，**无兜底**）；`models/pallastrade/cart.rb` L18/L30-31（`Metadata` concern + `belongs_to :billing_address`）；`models/pallastrade/order.rb` L254-255/L1406（`use_shipping?` + `clone_shipping_address` 先例）；`lib/pallastrade/permitted_attributes.rb` L100 | 部分（Order 侧有先例） |
| API | `pallastrade_api/app/` | `permitted_params` / billing | `store/carts_controller.rb` L122-140（有 `billing_address`，**无 `billing_mode`/`use_shipping`**）；`store/orders/checkout_controller.rb`（PATCH 仅 contact/shipping_address/delivery_rate_id）；`shopping_cart_serializer.rb`（已暴露 `billing_address`） | 否（需扩参数） |
| Admin | `pallastrade_admin/app/` | `billing_address_type` | `orders/billing_address_controller.rb`（`same_as_shipping` **命名先例**）、`users/_billing.html.erb`（`use_shipping_address` 文案） | 是（仅先例，不改代码） |
| Storefront | `storefront/src/` | `use_shipping` / billAddress | `components/checkout/UnifiedCheckout.tsx` L333/L609-611/L974-1000；`app/api/checkout/start/route.ts` L26-31、L128-133（原样透传）；`lib/data/checkout.ts` L37-40；`lib/data/express-checkout-flow.ts` L84-95（express 已显式发 `billing_address`） | **本次改动点** |
| Platform | `platform/packages/` | `use_shipping` / `UpdateCartParams` | `sdk/src/types/index.ts` L419；`sdk/CHANGELOG.md` L171 | 否（需增类型） |

**结论**：缺陷根因 = 前端发 `use_shipping` → Store API 未 permit → `Carts::Update` 无该语义 → `build_order!` 无兜底 → `Order.bill_address` 为空（链路 4 段已逐段核验）。Core/API/Storefront/SDK 四层需改；**不新增数据库列**（语义派生），无重复实现可复用。

## Step 1：Skill 咨询

| Skill | 状态 | 关键结论引用 |
|---|---|---|
| `pallastrade-api-v3` | ✅ 已读 | Store API 契约：`/api/v3/store/*` + publishable key + `X-PallasTrade-Token`（购物车令牌）；PATCH 类端点请求体字段**必须**同步 OpenAPI（`backend/public/api-docs/store.yaml` → `platform/docs/api-reference/store.yaml`）与生成式类型；参数经 `permitted_params` 白名单过滤（未 permit = 静默丢弃，正是本缺陷根因） |
| `pallastrade-storefront` | ✅ 已读（Checkout 章节 + BFF 契约 + Money 契约段） | `cart_` 统一下单页与 BFF `/api/checkout/start` 的载荷契约；BFF 错误信封 `{ error: { code, message } }`；UI 文案一律经 `normalizeErrorMessage`；金额字段以 API 为准 |

## 需求标题

把「账单地址 = 同配送 / 独立」从**前端瞬时布尔**升级为**服务端显式建模**（`billing_mode: same_as_shipping | custom`），并在提交订单时对账单地址做确定性兜底，保证有配送地址时 `Order.bill_address` 永不为空。

## 任务类型

Bug 修复（Core + Store API 参数扩展 + Storefront 载荷/校验；无 DB 迁移）

## 验收标准（AC）

见 PRD §5（AC-001..AC-012，每项映射到 RSpec / Vitest / `generated:check` 证据）。

## 影响面

- **修改**：`pallastrade_core/app/services/pallastrade/carts/{update,submit}.rb`、`pallastrade_api/app/controllers/pallastrade/api/v3/store/carts_controller.rb`、`storefront/src/components/checkout/UnifiedCheckout.tsx`、`storefront/src/app/api/checkout/start/route.ts`、`storefront/src/lib/data/checkout.ts`、`storefront/messages/{de,en,es,fr,pl}.json`
- **契约/文档**：`backend/public/api-docs/store.yaml`、`platform/docs/api-reference/store.yaml`、`platform/packages/sdk/src/types/index.ts`（+ `CHANGELOG.md`）、`ai/skills/{pallastrade-api-v3,pallastrade-storefront}/SKILL.md`、`harness/scenarios/scenarios.json`、`docs/prd/README.md`
- **测试**：`backend/spec/services/pallastrade/carts/{update,submit}_spec.rb`、`storefront/src/components/checkout/__tests__/UnifiedCheckout.test.tsx`、`storefront/src/lib/__tests__/checkout-i18n-keys.test.ts`（+ 新增 billing 载荷守护测试）
- **数据库/迁移**：**无**

## 实施结果（2026-09-13 完成）

| 项 | 结果 |
|---|---|
| Cart 账单语义（FR-001..003） | ✅ `Carts::Update#assign_billing_mode`/`resolve_billing_mode`：`same_as_shipping` 清账单地址、`custom` 落库；legacy `use_shipping`（true/'true'/'1'、false/'false'/'0'）映射；未知枚举值忽略；`IncompleteBillingAddress` + 事务回滚（无半空地址） |
| Order 账单兜底（FR-004） | ✅ `Carts::Submit#build_order!`：`billing_source = cart.billing_address \|\| cart.shipping_address` → `order.bill_address` 快照 |
| API/SDK/契约（FR-005..007） | ✅ `carts_controller#permitted_params` 放行 `:billing_mode`/`:use_shipping`；两份 OpenAPI（backend + platform）`PATCH /carts/{id}` 新增字段；SDK `UpdateCartParams.billing_mode` + `use_shipping` 标 `@deprecated` + CHANGELOG |
| Storefront 载荷/初值/校验（FR-008..011） | ✅ BFF 类型 + `lib/data/checkout.ts`；`UnifiedCheckout` 发 `billing_mode`、初值 `!cart.billing_address`、取消勾选且不完整时页内拦截；五语言新增 `checkout.billingAddressIncomplete` |
| 范围外声明（FR-013） | ✅ 记录于 PRD §3（`PATCH /orders/:id/checkout` 账单字段不在本次范围） |
| 知识同步 | ✅ Skill ×2（api-v3 / storefront）+ 场景库 GS-113 + PRD/README/REQ |

## 验证与证据（2026-09-13）

| 证据 | 结果 |
|---|---|
| `p1-order-flow-rspec`（含 `submit_spec.rb` AC-004/005 + `carts_controller_spec.rb` AC-006） | ✅ 全绿 |
| `update_spec.rb` 定向 RSpec（6 例，AC-001..003） | ✅ 全绿（`harness evidence run` 记录） |
| `chk-p1-4b-storefront` / `chk-p1-4c-storefront` | ✅ 全绿 |
| `storefront-test`（全量 vitest，含新增守护测试） | ✅ 全绿 |
| `harness generated:check` | ✅ no drift detected |
| `harness prd verify --id PRD-20260913-checkout-billing-mode` | ✅ 全部 AC 已有测试覆盖 |
| `harness sync-check --id PRD-20260913-checkout-billing-mode --ack` | ✅ 已评估并确认（详见 PRD §9） |

> 证据 ID 以 `npx harness evidence list --task TASK-20260913163308-045c73c9` 为准（每次重跑生成新 ID，绑定当下暂存树）。

## 后续任务

| # | 类型 | 内容 |
|---|---|---|
| PRD-3 | 优化 | 报价确认闭环（`cart_` 页 Pay Now 携带 expected versions + 409 页内确认）——feature gate，需用户确认 |
| PRD-4 | 需求 | 优惠码断面（`cart_` 阶段端点决策 + legacy 观测）——需用户决策 |
| 后续 | 优化 | `PATCH /orders/:id/checkout` 账单字段支持（若 `or_` 页引入地址编辑入口时另开 PRD） |
