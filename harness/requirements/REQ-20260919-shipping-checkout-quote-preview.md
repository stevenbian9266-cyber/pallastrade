# 需求文档：checkout 配送方式按 header 国家过滤 + 运费/税费 dry-run 预览报价

> 对应 PRD：`docs/prd/shipping/PRD-20260919-shipping-checkout-quote-preview.md`
> 任务：`TASK-20260919112020-ad56d514`

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 关键词 | 结果 |
|---|---|---|---|
| App | `backend/app/` | `dry_run` / `preview_quote` / `shipping_method_id` | 仅序列化类型（`PallasTradeApiV3ShoppingCart.ts`）；无定价能力 |
| Core | `backend/pallastrade_gems/pallastrade_core/app/` | `dry_run` / `preview` / `shipping_method_id` | **house 模式已存在**：`Products::BulkOperation#preview → run(dry_run: true)`、`BulkChannelAssignment/BulkInventoryAdjust/BulkMediaRemoval`、`Disputes::Recover(dry_run:)`；`Carts::Update` 可落 `shipping_method_id`；`Carts::Submit` 唯一建单路径；`Stock::Estimator` 用 `ShippingMethod#include?(address)` 过滤费率（无地址 → false） |
| API | `backend/pallastrade_gems/pallastrade_api/app/` | `preview` / `shipping_methods` | `ShippingMethodsController#index`（**已支持 `?country=`，前台未用**）；`admin/orders/refund_calculations` 是既有 preview 端点范式 |
| Admin | `backend/pallastrade_gems/pallastrade_admin/app/` | `preview` / `shipping` | 无相关（本需求不改后台） |
| Storefront | `storefront/src/` | `preview` / `estimated` / `quote` | `lib/checkout-quote.ts`（权威报价形状）、`app/api/checkout/{prepare,start}`（BFF 同源 Route Handler 范式）、`getShippingMethods()` **未传 country**、`UnifiedCheckout` 费用行三级读模型 |
| Platform | `platform/packages/` | `preview` / `shippingMethods` | SDK `shippingMethods.list`（支持 options）、`carts.update/submit`；无 preview 方法 |

### 搜索结论

- **不重复实现**：不新增定价算法（复用 `Carts::Submit` 管线 dry-run）；不新增地址输入控件；不改 `prepare` 语义。
- **需新增**：core `Carts::PreviewQuote`（+ `Submit#dry_run`）、API `preview_quote` 端点、SDK `carts.previewQuote`、BFF `/api/checkout/preview`、前台默认选中与四级读模型。
- **防重复证据**：`?country=` 能力已存在但未被调用（本次接线）；`dry_run:` 是本仓库既有约定（4 处服务已用），不是新范式。

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树优先级「Settings → Config → Events → Dependencies → Admin/Ransack → Generators → Decorators → Extensions」；本需求属**框架能力补口**（core 服务 + API 契约），按仓库既定做法**直接改 gem 源码**并标 `# PALLAS-CUSTOM`，不走 decorator |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | 一句话需求 → PRD（查重>0.3 阻止）→ 6 层搜索 → 用户确认 → gate → 实施 → AC↔测试 → 接口文档同步 → 知识同步门；本 REQ 即其 Step 0/1 产物 |
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ 已读 | 结算页两段语义（prepare→确认→pay）、费用读模型三级优先、"绝不把整句说明当金额"、BFF 同源 Route Handler 模式、`pnpm check/typecheck` 与 biome 80 列 CI 红线 |

**按需 Skill（本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `ai/skills/pallastrade-api-v3/SKILL.md` | ✅ | ✅ 已读 | Store API 前缀 ID、`data/meta` 信封、`current_store` 作用域、契约需同步 `store.yaml` 与 `generated:check` |
| `ai/skills/pallastrade-payments/SKILL.md` | ✅ | ✅ 已读 | 金额只来自服务端；PaymentIntent 金额与 Order 一致；**预览不得触碰支付会话** |
| `ai/skills/pallastrade-testing/SKILL.md` | ✅ | ✅ 已读 | 新增能力需 registration + verifier + spec；docs 与代码同批 |
| `ai/skills/pallastrade-data-model/SKILL.md` | ⚪ | — | 无迁移、无模型改动 |
| `ai/skills/pallastrade-security/SKILL.md` | ⚪ | — | 预览不新增 PII 落库/日志（地址只在请求内使用） |

## 需求标题

`优化：checkout 配送方式按 header 国家过滤 + 运费/税费 dry-run 预览报价（默认选中首个可计价方式）`

## 任务类型

优化迭代（前台接线 + 核心只读模式 + 新接口契约）

## 需求描述

1. 结算页配送方式列表按 **header 国家**过滤（用上既有 `?country=`）；
2. 进入页面即**默认选中**服务端指定的配送方式（管道口径：成本最低），无需手点；
3. **服务端只读预览**（`Carts::Submit` dry-run）返回运费/税费/折扣/应付的估算金额，右栏不再显示"提交时计算"；
4. 填写/修改地址后 **AJAX 重取**（防抖 + 竞态保护），无地址时以 header 国家作临时地址；
5. 缺州/邮编而**无法计价**的方式显式返回 `address_required`，不可判定时保留诚实降级。

## 影响范围（`harness affected` 输出）

- core：`carts/submit.rb`（+dry_run）、新增 `carts/preview_quote.rb`
- api：`config/routes.rb`、新增 `store/carts/preview_quote_controller.rb`
- platform：`packages/sdk`（`carts.previewQuote`）
- storefront：`lib/data/shopping-cart.ts`、`app/api/checkout/preview/route.ts`、`lib/checkout/server.ts`、`components/checkout/UnifiedCheckout.tsx`、`messages/*.json`（×5）、i18n 守护
- 契约：`backend/public/api-docs/store.yaml`、`platform/docs/api-reference/`
- 文档：Skill ×2、`AGENTS.md` §6、`harness.config.mjs`、`scenarios.json`（GS-195）

## 技术方案（初步）

```
UnifiedCheckout（客户端）
  ├─ 首屏：POST /api/checkout/preview { cart_id, country, shipping_method_id? }
  │     └─ BFF → SDK carts.previewQuote → Store API POST /carts/:id/preview_quote
  │           └─ Carts::PreviewQuote.call(cart:, shipping_method_id:, shipping_address:, country:)
  │                 ├─ 临时地址 = shipping_address || { country: header 国家 }
  │                 ├─ Carts::Submit.call(cart:, dry_run: true)  ← 同一管线
  │                 │     └─ 读金额 → ActiveRecord::Rollback（跳过 convert!/successor/事件）
  │                 └─ methods = scoped_methods(store, country) 与费率求并集（缺数据 → address_required）
  ├─ 地址/方式变更 → 400ms 防抖重取（requestId 丢弃过期响应）
  └─ prepare 成功后 → 权威金额替换预览（四级读模型）
```

## 风险点

| 风险 | 处置 |
|---|---|
| dry-run 泄漏副作用（事件/作业/状态推进） | preview 显式跳过 `cart.convert!` / successor cart / `publish_submitted_event`；spec 断言零副作用 |
| 无地址算不出运费（`include?(nil)=false`） | header 国家作临时地址；州级 zone 返回 `address_required` |
| 预览与提交漂移 | 同源调用 + 「preview == prepare」一致性断言 |
| 请求风暴/乱序 | 防抖 400ms + 短 TTL 缓存 + `requestId` |
| 前台算钱（AP-002/金额契约） | 前端只渲染 `display_*`；含税价不重复加 |

## 决策节点

- ☑ 采用 **dry-run 预览**（而非车级定价重构 / 前端自算）
- ☑ 默认选中 = **服务端**决定（成本最低），前台不自行排序
- ☑ 无地址时用 **header 国家**作临时地址（用户明确指示）
- ☑ 不可计价方式**保留在列表**并标 `address_required`（用户明确指示）

## 用户确认

✅ **已确认（2026-09-19）** —— 用户原话：**「实施」**（在对齐方案后），并在此之前明确：无地址可以用 **header 中的国家**估算；州级 zone 方式在填州前标"填写地址后显示"。

## 阶段③：实施后验证（不可跳过）

- 验证器：`checkout-preview-quote-rspec`（core dry-run 零副作用 + 同源一致性 + 方法集合/默认）+ `storefront-test`（默认选中/四级读模型/防抖竞态/i18n）
- 契约：`harness generated:check`
- dev：部署后以真实购物车验证首屏金额、地址变更刷新、`address_required` 表现

### 验证结论

（实施后回填）
