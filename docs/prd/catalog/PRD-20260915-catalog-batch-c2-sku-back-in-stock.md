# PRD-20260915-catalog-batch-c2-sku-back-in-stock

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-15 |
| 来源 | 《商品升级方案 V1.0》§九「SKU 化：第二条重要演进主线」（用户授权原话：「那就以此为作为 PRD 理想输入，实施」+「继续」，2026-09-15） |
| 分类 | catalog（商品域 / 到货订阅） |
| 关联 Skill | pallastrade-catalog / pallastrade-api-v3 / pallastrade-storefront |
| 关联 REQ | REQ-20260915-batch-c2-sku-back-in-stock.md |
| 关联 PRD | 同计划：Batch C-1 = `PRD-20260915-catalog-batch-c1-discovery`；§九 的后续（Product History / Duplicate Detection）另行立项 |
| 需求类型 | 新功能（SKU 化） + 数据迁移 |

> 🔁 **查重**：`harness prd new` 通过。切片划分：C-2 = SKU 级到货订阅（本 PRD）。

## 1. 背景与目标

- **背景**（《商品升级方案》§九）：`BackInStockSubscription` 只有 `product_id`，没有 `variant_id`——顾客订阅「红色 M 码」，补货的却是「蓝色 L 码」也会被通知，订阅精度丢失；且商品级事件的触发口径是「整个商品有无可卖变体」，与顾客真正关心的 SKU 无关。
- **目标**：订阅变体化——① 表加 `variant_id`（**nullable**，历史商品级数据继续有效）；② 新增 `variant.back_in_stock` 事件（携带变体），**只有该 SKU 的订阅者**收到邮件；③ 历史商品级订阅仍由 `product.back_in_stock` 通知（两个通道互不重复发送）；④ 后台可按商品 / SKU 查看订阅。
- **成功指标**：① 同邮箱可同时订阅同一商品的多个 SKU（唯一键 = 商品 + SKU + 邮箱），且商品级规则（商品 + 邮箱）对 `variant_id IS NULL` 依然成立；② SKU 级事件只命中该 SKU 订阅者（其他 SKU 与商品级订阅者保持 `active`）；③ 商品级事件只命中历史商品级订阅（SKU 订阅者不再被误发）；④ 零重复通知（订阅发送后即标记 `notified`）。

## 2. 用户故事 / 场景

- 作为**顾客**，我在缺货的「红色 M 码」上留下邮箱，补货时只会因这个 SKU 收到通知（与我无关的 SKU 不会骚扰我）。
- 作为**顾客**，我可以在同一商品的两个 SKU 上各订阅一次（同一邮箱）。
- 作为**运营**，我在后台订阅列表看到 SKU 列（历史商品级订阅显示为 —），并能按 SKU/邮箱/商品名搜索。
- 边界：未选 SKU（商品级订阅）→ 仍走商品级通道；同一 (商品, SKU, 邮箱) 重复提交 → 幂等复用并重新激活；`variant_id` 不属于该商品 / 不存在 → 404。
- 异常：事件载荷缺变体 → 跳过（不误发）；邮件投递失败 → 记录日志且**不**标记 notified（下次事件可重试，沿用既有容错）。

## 3. 功能需求（FR）

- **FR-001 数据模型**：`pallastrade_back_in_stock_subscriptions` 增加 `variant_id`（bigint，nullable，索引 + 外键）；唯一约束改为：`(product_id, variant_id, email)` **WHERE variant_id IS NOT NULL** + `(product_id, email)` **WHERE variant_id IS NULL**（保留历史语义，避免 Postgres NULL 唯一性歧义）。
- **FR-002 模型校验**：`belongs_to :variant, optional: true`；`variant` 必须属于 `product`；唯一性 scope 纳入 `variant_id`；新增 scope `for_variant` / `product_level`。
- **FR-003 事件层**：`StockMovement::CustomEvents` 在**变体**从不可买（无现货且不可缺货/预售）转为可买时发布 `variant.back_in_stock`，载荷 `{ id: variant 前缀 id, product_id: product 前缀 id }`；原 `product.out_of_stock` / `product.back_in_stock` 语义不变。
- **FR-004 通知分流**：`BackInStockSubscriber` 订阅两个事件——`variant.back_in_stock` → 仅该变体的 `active` 订阅；`product.back_in_stock` → 仅历史商品级（`variant_id IS NULL`）的 `active` 订阅；发送后 `mark_notified!`（幂等）。
- **FR-005 Store API**：`POST /api/v3/store/products/:product_id/back_in_stock_subscriptions` 接受可选 `variant_id`（前缀 id `variant_…` 或整数 id，必须属于该商品）；返回体新增 `variant_id`；OpenAPI（`store.yaml` 请求体/响应示例）与 SDK 类型同步。
- **FR-006 前台**：PDP 的「到货通知」按**当前所选变体**订阅（`BackInStockNotify` 新增 `variantId` 属性并从 `ProductDetails` 传入所选 SKU）。
- **FR-007 后台**：订阅表格新增 `variant` 列（显示 SKU；商品级显示 —），搜索扩展为 `email_or_product_name_or_variant_sku_cont`。
- **FR-008 兼容**：历史行保持 `variant_id = NULL` 且行为不变；无 v3 破坏性变更（新增可选参数）；无新表。

## 4. 非功能需求（NFR）

- **数据迁移安全**：迁移先加列/索引/外键，再替换唯一索引（旧索引名复用为 partial 索引），`down` 可完整回滚。
- **幂等**：同一 (商品, SKU, 邮箱) 重复提交返回既有订阅并重新激活；通知发送后立即标记，不重复发送。
- **可观测**：邮件失败记录 `[BackInStock] failed to notify subscription <id>` 且保持 `active`（可重试）。
- **可测试性**：模型约束、事件分流、API 参数、后台列渲染各有规格；事件层通过 handler 直驱（测试环境经 Sidekiq）。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001/FR-002：同邮箱 + 同商品 + 同 SKU 重复订阅 → 无效；同邮箱 + 同商品 + 不同 SKU → 有效；商品级（SKU 为空）保持「一商品一邮箱」规则。
- AC-002 ← FR-002：`variant` 属于其他商品 → 无效。
- AC-003 ← FR-004：`variant.back_in_stock` → 只发该 SKU 订阅者（其他 SKU 与商品级订阅保持 `active`）。
- AC-004 ← FR-004：`product.back_in_stock` → 只发历史商品级订阅（SKU 订阅者保持 `active`）；已 `notified` 的不再发。
- AC-005 ← FR-004：未知变体载荷 → 不发送任何邮件。
- AC-006 ← FR-005：带 `variant_id` 的 POST → 201 且响应 `variant_id` = 该 SKU；同一邮箱可分别为商品级与两个 SKU 建立 3 条订阅。
- AC-007 ← FR-005：未知 `variant_id` / 属于其他商品的 `variant_id` → 404。
- AC-008 ← FR-007：后台列表渲染 SKU 值。
- AC-009 ← FR-006：PDP 到货通知把所选变体 id 传给数据层（storefront 规格 + 类型检查）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/db/`、`backend/config/` | back_in_stock | 迁移 `20260815000003_create_pallastrade_back_in_stock_subscriptions.rb`、schema（无 variant_id） | 缺口：需新迁移 |
| Core | `pallastrade_core/` | back_in_stock / stock movement | `models/.../back_in_stock_subscription.rb`、`stock_movement/custom_events.rb`（仅商品级事件）、`subscribers/.../back_in_stock_subscriber.rb`（通知全部订阅）、`mailers/.../back_in_stock_mailer.rb`、factories、4 个既有 spec | **事件/通知/邮件链路齐备** → 只需加变体维度 |
| API | `pallastrade_api/` | back_in_stock_subscriptions | `store/back_in_stock_subscriptions_controller.rb`（无 variant 参数）、`serializers/.../back_in_stock_subscription_serializer.rb`（typelize 生成 SDK 类型） | 需加可选参数 + 序列化字段 |
| Admin | `pallastrade_admin/` | back_in_stock | 控制器（index/destroy）、`pallastrade_admin_tables.rb`（product/email/status 列）、导航项 | 需加 variant 列 + 搜索扩展 |
| Storefront | `storefront/src/` | backInStock | `lib/data/backInStock.ts`、`components/products/BackInStockNotify.tsx`、`ProductDetails.tsx`（调用点） | 需透传所选变体 |
| Platform | `platform/packages/` | BackInStockSubscription | `sdk/src/store-client.ts`（手写方法）、`types/generated/BackInStockSubscription.ts`（typelize 生成） | 需加可选 `variant_id` + 再生成类型 |

**结论**：链路（事件 → 订阅者 → 邮件 → API → 前台 → 后台）**全部已存在**，缺口仅是「变体维度」的贯通——含一次可回滚迁移与 OpenAPI/SDK 契约再生成。

## 7. 技术影响

- **迁移（新增）**：`backend/db/migrate/20260915130000_add_variant_to_back_in_stock_subscriptions.rb`（列 + 索引 + 外键 + 两个 partial 唯一索引）。
- **Core（改动）**：`back_in_stock_subscription.rb`（关联/校验/scope）、`stock_movement/custom_events.rb`（`variant.back_in_stock`）、`subscribers/.../back_in_stock_subscriber.rb`（双通道分流）、`back_in_stock_subscription_factory.rb`。
- **API（改动）**：store 控制器（`variant_id` 解析 + 404）、序列化器（`variant_id` 前缀 id）。
- **契约**：`backend/public/api-docs/store.yaml`（请求体/描述/示例）→ `scripts/ci/contracts.sh` 再生成 `platform/docs/api-reference/store.yaml` + SDK 生成类型（`generated:check` 守护）。
- **Admin（改动）**：`pallastrade_admin_tables.rb`（variant 列 + 搜索参数）、`en.yml`（`variant` 标签）。
- **Storefront（改动）**：`lib/data/backInStock.ts`、`BackInStockNotify.tsx`、`ProductDetails.tsx`。
- **测试（改动/新增）**：model / subscriber / API request / admin request 规格扩展（含 SKU 级用例）。
- **风险**：唯一索引替换需在低峰执行（当前表数据量小）；回滚 = `db:rollback` + revert 提交。

## 8. 测试计划

- `spec/models/pallastrade/back_in_stock_subscription_spec.rb`：AC-001/002。
- `spec/jobs/pallastrade/back_in_stock_subscriber_spec.rb`：AC-003/004/005。
- `spec/requests/api/v3/store/back_in_stock_subscriptions_spec.rb`：AC-006/007。
- `spec/requests/pallastrade/admin/back_in_stock_subscriptions_spec.rb`：AC-008。
- `spec/mailers/pallastrade/back_in_stock_mailer_spec.rb`：回归。
- 前台：`pnpm -C storefront typecheck` + vitest 全量（AC-009 由类型与既有组件规格覆盖）。
- 注册 verifier：`back-in-stock-rspec`（5 个 spec 文件，容器内 ≈1 min）。

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-catalog/SKILL.md`（Back-in-stock 章节：双粒度表 + 双 partial 唯一索引 + 铁律）
- [x] `ai/skills/pallastrade-storefront/SKILL.md`（changelog：PDP 到货通知按所选 SKU 订阅）
- [x] `harness/scenarios/scenarios.json`（GS-133：SKU 级到货订阅；`harness eval-ai --scenarios` → 134/134 valid）
- [x] `harness.config.mjs`（verifier `back-in-stock-rspec`）+ `AGENTS.md` §6 行
- [x] API 文档：`store.yaml` + `platform/docs/api-reference/store.yaml` + SDK 类型（`contracts.sh` 再生成，`generated:check` 通过）
- [x] 本 PRD 状态 + `docs/prd/README.md` 索引（`prd-status-sync --fix/--check`）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-15 | 0.1 | 初稿（Batch C-2：FR-001~008 / AC-001~009） | AI |
| 2026-09-15 | 1.0 | 实施完成：迁移 + core 三件（模型/事件/订阅者）+ API/序列化器/契约再生成 + 后台 SKU 列 + 前台按 SKU 订阅；后端定向 28 例绿、前台 67 文件 401 例绿、`generated:check` 通过 | AI |
