# REQ-20260913-checkout-plan-review-and-decision — 商城前台 Checkout 方案评审与决策落档（方案 A：维持单页一步）

> 关联 PRD：N/A（方案评审 + 决策落档；实施按 §后续任务 拆分为独立 PRD）
> 来源：用户指令「先同步修订 research 文档」= 采纳评审选项 1：**新建 docs/research 评审文档 + 修订豆包方案文档**
> 评审对象：`豆包梳理业务需求/商城前台 Checkout + Transaction + Promotion + 履约完整方案.md`（55 节 / 2197 行；git-ignored 本地源规格）
> Task：`TASK-20260913144749-671fc348`；Gate：`GATE-2026-09-13T14-48-20`（docs）
> 产出：`docs/research/RESEARCH-20260913-checkout-plan-review-and-decision.md` + 源规格文档修订（决策回写）
> 决策：**2026-09-13 用户拍板 —— 维持单页一步支付（方案 A）**

## Step 0：跨层搜索（已执行）

| 层 | 搜索路径 | 关键词 | 结果 | 已承载？ |
|---|---|---|---|---|
| App | `backend/app/` | CheckoutView / checkout_version / 两段式 / 单页一步 | 唯一命中为生成类型文件 `app/javascript/types/serializers/PallasTradeApiV3StoreCommerceTransaction.ts`（`checkout_version` 字段）；无宿主层实现 | 否 |
| Core | `…/pallastrade_core/app/` | 同上 | Checkout 域实现即**评审对象**：`order_checkout/{view,snapshot,readiness,refresh,recalculate,expiration}.rb`、`transactions/start.rb`（INV-P3-2 Reserve-before-PaymentSession）、`carts/{update,submit}.rb`（`use_shipping` 未处理；billing 仅显式 `billing_address`）、`promotions/projection/discount_projection.rb`（批次2 已统一三层口径） | 否 |
| API | `…/pallastrade_api/app/` | 同上 | `checkout_controller`（PATCH 仅 contact/shipping_address/delivery_rate）、`checkout_serializer`（已有 version/price_version/expires_at/ready/discounts/taxes/items/fulfillments；**缺** credits/capabilities/available_payment_methods/billing_mode）、`routes.rb`（无 `orders/:id/checkout/promotions`）、`carts/discount_codes_controller`（仍走 legacy `find_cart!`） | 否 |
| Admin | `…/pallastrade_admin/app/` | 同上 | `use_shipping` 命中 `users/_billing.html.erb`（后台地址表单，与本方案无关）；无相关实现/文档 | 否 |
| Storefront | `storefront/src/` | 同上 | `UnifiedCheckout`（单页一步 Pay Now → BFF `update+submit+transactions.create` → Stripe 内联确认）、`OrderPaymentContent`（`or_` 补付/恢复；无折扣/礼卡/余额渲染）、`payment-result`（错误统一落 pending）、`api/checkout/start`（错误码仅透传）、`api/checkout/coupon`（`cart_` → legacy `discount_codes`）、`proxy.ts`（`?token=` 仅 `/checkout/`） | 否 |
| Platform | `platform/packages/` | 同上 | SDK `store-client`：`POST /carts/{cartId}/discount_codes`（`cart_` 原样透传，落 legacy 解析）；CLI/dashboard 无相关面 | 否 |

**结论**：现有评审/研究资产（`harness/reviews/REVIEW-20260908-promotions-module-audit.md`、`docs/research/RESEARCH-20260913-*` 三份）**均不承载** Checkout 前台方案评审与决策 → **须新建** `docs/research` 评审文档；六层均无实现级重复。

## Step 1：Skill 咨询

| Skill | 状态 | 关键结论引用 |
|---|---|---|
| `harness-docs` | ✅ 已读 | 文档同步方法论：起草 → 人确认 → 写回；更新后跑 `npx harness docs:check`；本评审以代码核验结论为唯一证据源 |
| `pallastrade-prd` | ✅ 已读 | 后续实施必须走 PRD 工作流（`prd new` 查重 → 分类 → FR/AC → gate → 证据 → 知识同步门）；本评审文档 **≠ PRD**，故在 §后续任务 明确拆分 |

## 需求标题

把《商城前台 Checkout + Transaction + Promotion + 履约完整方案》的评审结论与用户决策（**维持单页一步支付**）落为可追溯的 research 文档，并把决策回写源规格文档，消除方案叙述与现状实现的冲突。

## 任务类型

文档 / 研究（docs）

## 验收标准（AC）

| AC | 内容 | 验证方式 | 结果 |
|---|---|---|---|
| AC-1 | research 评审文档落档（逐项核验 / 过时项 / 缺口 / 决策 / 实施方案 / 证据索引） | 文件存在 + 章节齐备 | ✅ |
| AC-2 | 决策可追溯：方案 A + 被否决项（B/C）+ 复议条件 | 文档 §6 | ✅ |
| AC-3 | 源规格文档修订与决策一致：文首决策备忘 + §2/§19/§20/§21/§40/§53/§54（修订处标 `〔A-20260913〕`） | grep 修订标记 | ✅ |
| AC-4 | 已过时项显式标注，防重复开发（§14 projection / §2 三套壳 / §41 码名 / §13 DELETE 矛盾） | 文档 §4 | ✅ |
| AC-5 | 零代码改动 | `git status --porcelain`（源规格 git-ignored，不入 diff） | ✅ |
| AC-6 | 后续实施拆分可执行（PRD-1..4 + 待澄清项） | 文档 §11/§12 | ✅ |

## 影响面

- **新增**：`docs/research/RESEARCH-20260913-checkout-plan-review-and-decision.md`、本 REQ
- **修改**：`豆包梳理业务需求/商城前台 Checkout + Transaction + Promotion + 履约完整方案.md`（git-ignored 本地源规格，**不入版本库**）
- 接口 / 迁移 / 运行时：**无**
- 知识同步：无 Skill / 规范 / 反模式 / 场景库变更（决策记录在 research 文档；是否写入 repo memory 由用户决定）

## 后续任务

| # | 类型 | 内容 | 前置 |
|---|---|---|---|
| PRD-1 | 修复 | 错误落点分流（quote_changed/库存/恢复）+ Money 契约（raw/display） | 无 |
| PRD-2 | 修复 | billing 缺陷（`use_shipping` → `billing_mode` 建模：`Carts::Update` + `Carts::Submit` + PATCH checkout + UI） | 无 |
| PRD-3 | 优化 | 报价确认闭环（`cart_` 页 Pay Now 携带 expected versions + 409 页内差异确认） | 无 |
| PRD-4 | 需求 | 优惠码断面（`cart_` 阶段端点方案 + legacy 观测） | 用户确认端点方向 |
| 待澄清 | — | §13「移除 DELETE /orders/:id/checkout/promotions/:promotion」表述；§47 占位功能排期 | 用户 |
