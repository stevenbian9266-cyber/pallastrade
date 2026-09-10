# PRD-20260910-promotions-promo-batch3c-redemption-readonly

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-10 |
| 来源 | batch3b PRD §4 Phase B（FR-007/FR-008，当时标记未实施）；拆解文档 PR-P4-7（Admin 只读核销页数据源） |
| 分类 | promotions |
| 关联 Skill | pallastrade-api-v3、pallastrade-admin、pallastrade-promotions、pallastrade-testing |
| 关联 PRD | batch3a（ledger）、batch3b（运行时加固） |
| 需求类型 | 功能新增（只读可观测面：Admin API + Rails Admin） |

> **原则**：纯只读。不新增写入路径、不改金额/核销语义（batch3a/3b 已冻结）。

---

## 1. 背景与目标

batch3a/3b 建立了核销台账（`pallastrade_promotion_redemptions`）与运行时加固，但**没有任何观测入口**：运营/财务无法在后台看到「哪些订单核销了哪张券、何时释放、释放原因」。本批次提供只读观测面：

- **Admin API**：`GET /api/v3/admin/promotion_redemptions`（列表 + 过滤 + 分页）、`GET /api/v3/admin/promotion_redemptions/:id`
- **Rails Admin**：Promotions → Redemptions 只读列表页（表格 + 导航 + 面包屑）

成功指标：运营能在后台按订单/促销/状态检索核销记录；API 消费方（Dashboard）可通过契约类型读取；权限矩阵可单独授予 `read` 能力。

---

## 2. 功能需求（FR）

- **FR-001 Admin API 列表端点**：`GET /api/v3/admin/promotion_redemptions`，支持 `order_id`（prefixed）、`promotion_id`（prefixed）、`state`（reserved/committed/released）过滤 + 分页（`page`/`limit`，返回 `{ data, meta }` 契约）。默认按 `created_at desc`。
- **FR-002 Admin API 详情端点**：`GET /api/v3/admin/promotion_redemptions/:id`（prefixed `redemption_…`）。
- **FR-003 Serializer**：`PallasTrade::Api::V3::Admin::PromotionRedemptionSerializer`（typelize 字段：`id`/`promotion_id`/`order_id`/`user_id?`/`coupon_code?`/`state`/`amount?`/`currency?`/`reserved_at?`/`reserved_until?`/`committed_at?`/`released_at?`/`release_reason?`/`created_at`/`updated_at`），只读、无写路径。
- **FR-004 权限注册**：在 `config/initializers/pallastrade_permission_registry.rb` 注册 `:promotion_redemptions`（`model_class: PallasTrade::PromotionRedemption`，`actions: %w[read]`，`data_fields: %w[store_id]`）；Ability 派生随现有机制生效。
- **FR-005 Rails Admin 只读列表页**：`pallastrade_admin` 下 `promotion_redemptions#index`（`ResourceController` + 表注册 `:promotion_redemptions`），Promotions 导航组新增子项（`admin.promotions.redemptions`），面包屑由导航推导；无 new/edit/delete。
- **FR-006 契约再生**：`typelizer:generate` + `api:docs:schemas`（admin.yaml 增加 schema）+ `platform/docs/api-reference/` 副本同步。
- **FR-007 文档同步**：`pallastrade-api-v3` / `pallastrade-admin` SKILL 增补只读端点与后台入口说明；`scenarios.json` 新增 GS-085；PRD 索引。

---

## 3. 验收标准（AC）

| AC | 对应 | 判定 |
|---|---|---|
| AC-001 | FR-001 | 列表返回本店核销记录；分页 meta 正确（`count/current_page/total_pages`）；默认倒序 |
| AC-002 | FR-001/002 | `order_id` / `promotion_id` / `state` 过滤生效；非法过滤值返回空集（不 500）；`show` 返回单条 |
| AC-003 | FR-001/002/004 | 鉴权：无 `read` 权限 → 403；未认证 → 401；跨 store 数据不可见 |
| AC-004 | FR-005 | Admin 页面 200 且渲染表格行；导航注册包含 Redemptions 项；`node scripts/nav-validate-static.mjs` 通过 |
| AC-005 | FR-004 | 权限注册表包含 `:promotion_redemptions`（read + store_id 数据域），Ability 对超管允许、对无权限用户拒绝 |
| AC-006 | FR-006 | `rake api:docs:schemas:check` clean；`typelizer:generate` 产出 `PromotionRedemption` 类型 |
| AC-007 | §原则 | 回归：batch1/2/3a/3b 既有 spec 全绿（无写入路径变更） |

---

## 4. 跨层搜索记录（6 层，本轮实测）

| 层 | 路径 | 关键词 | 找到 | 满足？ |
|---|---|---|---|---|
| App | `backend/app/` | redemption | 无宿主逻辑 | 不涉及 |
| Core | `pallastrade_core/app/` | promotion_redemptions | batch3a 模型（store-scoped、`has_prefix_id :redemption`、`active/committed/reserved/released` scope） | 数据源就绪 |
| API | `pallastrade_api/app/controllers|serializers` | admin read-only | `admin/coupon_codes_controller`（只读模板）、`ResourceController`；无核销端点 | **需新增** |
| Admin | `pallastrade_admin/app|config` | read-only index / nav / tables | `admin/transactions_controller` + `transactions` 表注册 + 导航（Orders → Transactions）为最佳模板；`promotions` 导航组已存在（Promotions/Gift Cards） | **需新增** |
| Storefront | `storefront/src/` | redemption | 无消费点 | 不涉及 |
| Platform | `platform/packages/` | redemption | SDK 无相关类型 | **契约再生**（dashboard 可用） |

---

## 5. 技术影响

- **新增**：API controller + serializer + routes；Admin controller + view + 表注册 + 导航项；权限注册；2 个 request spec。
- **修改**：`pallastrade_api/config/routes.rb`、`pallastrade_admin/config/{routes.rb,initializers/*}`、`pallastrade_permission_registry.rb`、契约产物（typelizer/api-docs/platform 副本）。
- **不涉及**：核销语义、金额、订阅者、sweeper、storefront。

---

## 6. 测试计划

| 文件 | 覆盖 |
|---|---|
| `backend/spec/requests/api/v3/admin/promotion_redemptions_spec.rb`（新） | AC-001/002/003/006 |
| `backend/spec/requests/pallastrade/admin/promotion_redemptions_spec.rb`（新） | AC-004/005 |
| 既有批次 spec（promotions 目录 + jobs/subscribers） | AC-007 回归 |

运行：容器 rspec；`node scripts/nav-validate-static.mjs`；`rake api:docs:schemas:check`；`typelizer:generate`。

---

## 7. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-api-v3/SKILL.md`：新增只读端点条目。
- [x] `ai/skills/pallastrade-admin/SKILL.md`：Promotions → Redemptions 只读页（导航/表格/权限）。
- [x] `ai/skills/pallastrade-promotions/SKILL.md`：指向后台/API 观测入口。
- [x] `harness/scenarios/scenarios.json`：GS-085。
- [x] `docs/prd/README.md` + 本 PRD 状态（done）。
- [x] `backend/public/api-docs/admin.yaml` + `platform/docs/api-reference/`（契约再生）。

---

## 8. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-10 | 0.1 | 初稿并实施（用户"继续"授权，延续 batch3b Phase B） | AI |
| 2026-09-10 | 1.0 | done：API + Admin 只读面落地；新 spec 10 例全绿；全量回归（含导航一致性）绿；契约再生（admin-sdk PromotionRedemption 类型 + admin.yaml schema） | AI |
