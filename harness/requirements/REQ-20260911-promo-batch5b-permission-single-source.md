# REQ-20260911-promo-batch5b-permission-single-source

| 项 | 值 |
|---|---|
| 需求 | Promotion 批次 5b —— 权限单源收敛（PR-P8-1..3） |
| 类型 | 优化迭代（治理收敛：capability 单源 + 一致性校验） |
| 关联 PRD | `docs/prd/promotions/PRD-20260911-promotions-promo-batch5b-permission-single-source.md` |
| 关联任务 | TASK-20260911013946-c0f8574c |
| Gate | GATE-2026-09-11T01-39-55 |
| 风险 | critical（授权语义变更）→ 恢复计划 REC-6d123ac5134f48 |
| 分支 | dev（基线 98d796b6） |

---

## Step 0 — 跨层搜索（6 层，2026-09-11 实测）

| 层 | 搜索路径 | 关键词 | 结果 | 是否已满足需求 |
|---|---|---|---|---|
| App（宿主） | `backend/config/` | PermissionRegistry / promotions | `initializers/pallastrade_permission_registry.rb`：13 资源；`:promotions` → 单模型 `Promotion`；`:promotion_redemptions` → 只读 | ⚠️ 需补 `models` 覆盖 + `coupon_codes`/`promotion_categories` 资源 |
| Core | `pallastrade_core/app/models/pallastrade/` | registry / ability / permission_sets | `permission_registry.rb`（`Entry`/`register`/`[]`/`resources`/`reset!`）、`ability.rb`（`apply_function_permission` → `resolve_permission_target` 单模型）、`permission_sets/base.rb`、`permission_sets/promotion_management.rb`（硬编码 5 模型 + Metafield）、`role_permission.rb`（`FUNCTION_ACTIONS`） | ⚠️ 缺口：多模型覆盖 + 权限集派生 + validate! |
| API | `pallastrade_api/app/` | authorize / scope | v3 Admin 走 scope（`read_promotions`/`write_promotions`）与 `scoped_resource` | 不涉及（R7：不动 v3 授权语义） |
| Admin | `pallastrade_admin/app/` | roles / coupon_codes / model_class | `roles_controller.rb`（`@permission_resources = PermissionRegistry`）、`views/.../roles/_form.html.erb`（资源 × 动作矩阵）、`promotion_rules_controller.rb`、`promotion_actions_controller.rb`、`coupon_codes_controller.rb`（`ResourceController#model_class` → `authorize!`）、`lib/tasks/navigation.rake#validate_role_permissions` | ⚠️ D1：DB 角色授权后规则/动作/券码不可授权（本批次修复） |
| Storefront | `storefront/src/` | permission | 无 | 不涉及 |
| Platform | `platform/packages/` | permission | 无权限矩阵类型 | 不涉及 |

**结论**：权限声明分散在 3 处（宿主注册表 / 代码权限集 / DB 角色行），其中注册表只声明单模型导致"授予促销管理 ≠ 能管理促销规则"，且无自洽校验；本批次把注册表补成「资源 → 覆盖模型集合」的单一事实源，并让 Ability、代码权限集、nav:validate、矩阵都从它派生。

---

## Step 1 — Skill 咨询证据

| Skill | 读取 | 关键结论 |
|---|---|---|
| `pallastrade-customization` | ✅ | 决策树第 1/8 级：权限属配置/框架行为 → 改 gem 内部实现（不改业务语义），无需 decorator |
| `pallastrade-admin` | ✅ | §权限注册表：新增可授权资源须在 `backend/config/initializers/pallastrade_permission_registry.rb` 登记；矩阵 UI / Ability / nav:validate 均读 registry |
| `pallastrade-security` | ✅ | 权限与能力边界是安全面：授权变更必须可校验、可回滚（本批次建 critical 恢复计划 + 分级校验） |
| `pallastrade-promotions` | ✅ | 促销后台入口 = Promotions 列表 + 规则/动作弹窗 + Coupon Codes；batch3c 已加只读 Redemptions 资源 |
| `pallastrade-prd` | ✅ | R8：PRD（映射表/FR/规则/AC/测试映射/知识同步）→ approved → gate → 实施 → `prd verify` |
| `pallastrade-api-v3` | ✅ | v3 Admin 授权使用 scope（`read_promotions` 等），与后台 `authorize!(Model)` 是两套；本批次只动后者（R7） |

---

## Step 2 — 实施范围（写前确认）

- 修改：`permission_registry.rb`（`models` + `validate!`）、`ability.rb`（多目标应用）、`permission_sets/base.rb`（派生助手）、`permission_sets/promotion_management.rb`（改为派生）、宿主注册表初始化器（覆盖 + 新资源）、`navigation.rake`（覆盖断言）、权限 rake。
- 新增：4 个 spec（registry / permission set / 后台请求 / rake 校验）。
- 不改：v3 API 授权、SuperUser 行为、业务模型/迁移、导航结构与矩阵 UI 结构、Admin API scope。

## 用户确认记录

| 时间 | 用户输入 | 授权范围 |
|---|---|---|
| 2026-09-11 | 澄清问答中选择「批次 5b：PR-P8 权限单源」（承接 AI 声明的下一步） | 实施批次 5b（PR-P8-1..3），沿用 batch3a..5a 同一模式 |
