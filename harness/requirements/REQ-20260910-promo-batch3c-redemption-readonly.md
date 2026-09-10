# REQ-20260910-promo-batch3c-redemption-readonly

| 元数据 | 值 |
|---|---|
| 状态 | done（API + Admin 只读观测面已实施） |
| 任务类型 | 功能新增（只读可观测面） |
| 关联 PRD | `docs/prd/promotions/PRD-20260910-promotions-promo-batch3c-redemption-readonly.md` |
| 关联任务 | TASK-20260910105928-9e65dc6f / GATE-2026-09-10T11-00-37 |
| 前置 | batch3a（ledger）、batch3b（运行时加固） |

---

## Step 0：跨层搜索（本轮实测）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | redemption | 无 | 不涉及 |
| App — views/decorators | `backend/app/` | redemption | 无 | 不涉及 |
| Core Gem — models | `pallastrade_core/app/models/` | PromotionRedemption | `promotion_redemption.rb`（batch3a：store-scoped + `redemption_` 前缀 id + 4 个 scope） | ✅ 数据源就绪 |
| Core Gem — services/jobs | `pallastrade_core/app/{services,jobs}/` | redemption | 5 服务 + sweeper（batch3a/3b） | 无需改动（只读） |
| API Gem — controllers | `pallastrade_api/app/controllers/pallastrade/api/v3/admin/` | readonly | `coupon_codes_controller`（index/show 只读模板）、`ResourceController`（`scoped_resource`/`model_class`/`serializer_class`） | ❌ 需新增核销端点 |
| API Gem — routes | `pallastrade_api/config/routes.rb` | admin resources | `resources :coupon_codes, only: [:index, :show]` 等 | ❌ 需新增路由 |
| Admin Gem — controllers | `pallastrade_admin/app/controllers/pallastrade/admin/` | read-only index | `transactions_controller`（`model_class`/`scope`/`object_name`/`find_object` + TableConcern） | ❌ 需新增控制器 |
| Admin Gem — config | `pallastrade_admin/config/` | tables / navigation / routes | `pallastrade_admin_tables.rb`（`:transactions` 注册模板）、`pallastrade_admin_navigation.rb`（`promotions` 组已存在）、`routes.rb`（`resources :transactions, only: [:index,:show]`） | ❌ 需新增表注册/导航/路由 |
| Admin Gem — 权限 | `backend/config/initializers/pallastrade_permission_registry.rb` | register | `:promotions` 等 12 个已注册资源（model_class + actions + data_fields） | ❌ 需注册 `:promotion_redemptions` |
| Storefront | `storefront/src/` | redemption | 无 | 不涉及 |
| Platform | `platform/packages/` | redemption | 无类型（batch2 后无核销类型） | ❌ 契约再生（typelizer + admin.yaml） |

### 搜索结论

- 数据源（`PromotionRedemption`）与运行时（batch3a/3b）已就绪，本批次**只加只读消费面**。
- Admin 只读页与 Admin API 均有成熟模板（transactions / coupon_codes / refunds_ops），照此落位即可，无需新机制。
- 权限体系为「注册表 + Ability 派生 + 导航 `if: can?` 守卫」，注册 `:promotion_redemptions` 后 UI/API 授权自动可用。

---

## Step 1：Skill 文件咨询（真实结论）

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-api-v3/SKILL.md` | ✅ 已读（本会话批次2 期间） | Admin API 只读资源沿用 `ResourceController` + `scoped_resource`；响应统一 `{ data, meta }`；ID 必须 prefixed（`redemption_…` 已具备）。 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读（本会话） | 新增 admin 页面三要素：**页面标题 + 面包屑 + 图标**；`skip_breadcrumb_derivation` 控制器需手写面包屑；表格经 `PallasTrade.admin.tables` 注册；导航经 `sidebar_nav.add`，`if: can?` 守卫。 |
| `ai/skills/pallastrade-promotions/SKILL.md` | ✅ 已读（本会话深化） | batch3a/3b 语义：ledger 为唯一口径；本批次只读，不得引入写入路径或改动语义。 |
| `ai/skills/pallastrade-testing/SKILL.md` | ✅ 已读 | RSpec + FactoryBot；admin 请求 spec 用 `stub_authorization!`/真实 Ability 两种模式。 |
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：Admin 扩展（导航/表格/部分视图）优先于装饰器；本项目允许直接改 gem 源（git 跟踪）。 |
| `pallastrade-data-model` | ✅ 已读 | `PromotionRedemption` 关系与 scope 已在 batch3a 记录。 |

---

## 需求标题

核销台账只读观测面：Admin API（列表/详情/过滤/分页）+ Rails Admin 只读列表页（导航/权限/表格）。

## 任务类型

功能新增（只读）。

## 需求描述

运营/财务需要能看到每笔核销：哪个订单、哪张券、金额、状态（占用中/已核销/已释放）、核销/释放时间与原因。本批次提供 Admin API 只读端点与后台只读页面，并纳入权限矩阵（可单独授予 read 能力）。

## 影响范围（`harness affected` 预估）

- 新增：2 个 controller（API/Admin）、1 serializer、1 view、表注册、导航项、权限注册、2 spec。
- 修改：routes ×2、契约产物、Skill ×3、scenarios。
- 不改：核销服务/模型语义、金额、storefront。

## 技术方案（初步）

1. API：`resources :promotion_redemptions, only: %i[index show]`；`ResourceController` 子类，`scoped_resource :promotion_redemptions`；过滤参数转 `where`；serializer typelize。
2. Admin：`promotion_redemptions#index`（`ResourceController` + `TableConcern`），`scope = current_store.promotion_redemptions.order(created_at: :desc)`；表注册列（id/state/promotion/order/amount/时间/原因）；导航挂 Promotions 组。
3. 权限：注册表新增 `:promotion_redemptions`（read + store_id）。
4. 契约：`typelizer:generate` + `api:docs:schemas` + 平台副本同步；`api:docs:schemas:check` 必须 clean。

## 风险点

| 风险 | 等级 | 缓解 |
|---|---|---|
| 导航/表格注册遗漏导致后台报错 | 低 | 复用 transactions 模板 + `nav-validate` + 请求 spec 渲染断言 |
| API 过滤参数注入/500 | 低 | 仅接受白名单参数，非法值退化为空集；request spec 覆盖 |
| 契约漂移 | 低 | `api:docs:schemas:check` + typelizer 再生后提交 |

## 决策节点

> ✅ 用户连续「继续」= 授权按推荐方案（batch3b Phase B 全量：API + Admin 页）实施；无额外决策点。
