# PRD-20260911-promotions-promo-batch5b-permission-single-source

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-11 |
| 来源 | `promotion模块架构-任务拆解.md` 批次 5 → Phase 8（PR-P8-1..3）；架构 §103/§104（Capability + Store Scope；Admin API Store Context） |
| 分类 | promotions |
| 关联 Skill | pallastrade-admin、pallastrade-security、pallastrade-promotions、pallastrade-api-v3、pallastrade-prd |
| 关联 REQ | REQ-20260911-promo-batch5b-permission-single-source.md（实施时回填） |
| 关联 PRD | batch3c（`:promotion_redemptions` 注册）、batch5a（Definition Registry 收敛，同属"消除多份事实来源"治理线） |
| 需求类型 | 优化迭代（治理收敛：capability 单源 + 一致性校验） |

> **原则**：**收敛到既有 `PermissionRegistry`，不新起 registry**。registry 已经是后台权限矩阵 / Ability / `nav:validate`
> 的读取来源；本批次把它补成"资源 → 覆盖模型集合（capability）"的完整事实源，并让代码级权限集从它派生，
> 消除"注册表 / 权限集 / 控制器可授权"三处漂移。

---

## 1. 背景与目标

### 1.1 现状（PR-P8-1 盘点，2026-09-11 实测）

| 事实来源 | 位置 | 促销相关内容 |
|---|---|---|
| **PermissionRegistry**（宿主注册表） | `backend/config/initializers/pallastrade_permission_registry.rb` | `:promotions` → `model_class: Promotion`，`actions: read/create/update/destroy`，`data_fields: store_id`；`:promotion_redemptions` → `PromotionRedemption`，`actions: read`（batch3c） |
| **代码级权限集** | `pallastrade_core/.../permission_sets/promotion_management.rb` | `can :manage` → `Promotion` / `PromotionRule` / `PromotionAction` / `PromotionCategory` / `CouponCode`；`can [:read, :admin], Metafield` |
| **DB 角色权限** | `PallasTrade::RolePermission`（function/menu/data/set）+ `Ability#apply_permissions_from_db` | function 授权经 `resolve_permission_target(resource)` 解析为 **单一 `model_class`** 再 `can action, target` |
| **权限矩阵 UI** | `pallastrade_admin/.../roles_controller.rb` + `views/.../roles/_form.html.erb` | 遍历 `PermissionRegistry` 资源 × `%w[read create update destroy export manage]` |
| **nav 校验** | `pallastrade_admin/lib/tasks/navigation.rake#validate_role_permissions` | DB `role_permissions.resource` 必须注册于 registry（未注册 = violation） |

### 1.2 问题

| # | 问题 | 影响 |
|---|---|---|
| D1 | `:promotions` 只覆盖 `Promotion`，而促销后台还有 `PromotionRule` / `PromotionAction` / `CouponCode` / `PromotionCategory` 控制器 | DB 驱动角色授予「促销管理」后，**编辑规则/动作/券码会被 `authorize!` 拒绝**（`can?(:admin, PallasTrade::PromotionRule)` 为 false）；只有 SuperUser（`can :manage, :all`）能用 |
| D2 | 代码级 `PromotionManagement` 与 registry 各自硬编码同一份资源清单 | 新增促销子资源需改两处；无任何校验能发现漏改（batch5a 同类问题的权限版本） |
| D3 | `CouponCode` / `PromotionCategory` 无 registry 资源 | 权限矩阵里无法单独授权/查看（功能权限面板缺项） |
| D4 | `:promotion_redemptions`（batch3c 注册，只读）不在 `PromotionManagement` 集合内 | 代码集与 DB 资源再次不一致 |
| D5 | 注册表无自洽校验 | `models`/`actions`/`data_fields` 写错只能在运行时暴露（权限矩阵渲染错误/`accessible_by` 条件无效） |

### 1.3 目标

- **PR-P8-1**：把「capability（资源 × 动作）↔ 覆盖模型 ↔ 后台入口 ↔ 现有代码集」映射表固化为文档（本 PRD §2 + Skill）。
- **PR-P8-2**：`PermissionRegistry::Entry` 支持**多模型覆盖**；`Ability` 对同一 grant 覆盖全部模型；`PermissionSets::Base` 提供从 registry 派生的助手，`PromotionManagement` 改为派生 → **单一事实源**。
- **PR-P8-3**：补齐促销子资源注册（`coupon_codes` / `promotion_categories`）；新增 `PermissionRegistry.validate!` + `rake pallastrade:permissions:validate`；nav:validate 增补促销覆盖一致性断言；权限矩阵与导航回归 spec。
- 零业务语义变化：不动 Admin API v3 的 scope 授权、不动 SuperUser/默认角色、不动业务代码。

---

## 2. 映射表（PR-P8-1 产物，实施后以此为准）

| capability（资源.动作） | 覆盖模型（`models`） | 后台入口 / nav key | Admin API | 说明 |
|---|---|---|---|---|
| `promotions.read/create/update/destroy` | `Promotion`、`PromotionRule`（含 STI）、`PromotionAction`（含 STI） | Promotions（`promotions_list`）、规则/动作弹窗（`promotion_rules`/`promotion_actions` 控制器） | `/api/v3/admin/promotions*`（scope `read/write_promotions`） | **本批次新增覆盖**：规则/动作与促销同属一个 capability |
| `coupon_codes.read/create/update/destroy` | `CouponCode` | Promotions → Coupon Codes（`coupon_codes_controller`，promotion 嵌套只读列表 + 矩阵可授权） | 同 promotions scope（券码经 promotion 嵌套） | **本批次新增注册**（原仅存在于代码权限集）；CouponCode 无 `store_id` 列 → 数据范围经 `belongs_to :promotion` 上卷 |
| `promotion_redemptions.read` | `PromotionRedemption` | Promotions → Redemptions（只读页，batch3c） | `/api/v3/admin/promotion_redemptions`（只读） | 保持独立只读资源（R5） |
| （未入矩阵）`PromotionCategory` | `PromotionCategory` | 无后台控制器（盘点：无 admin 页面/无 v3 Admin 控制器） | — | 保留在 `PromotionManagement` 代码集的显式行（不入矩阵，避免空资源行，见 D3） |
| （代码集附加）`Metafield read/admin` | `Metafield` | 促销编辑的自定义字段 | — | 保持显式声明，不入 registry（非 admin 矩阵资源） |

**数据范围（Data Scope）**：`promotions` / `promotion_redemptions` 有 `store_id` 列 → 直接 `{ store_id: … }`；`coupon_codes` 无该列 → 经 `belongs_to :promotion` 上卷为 `{ promotion: { store_id: … } }`（架构 §103 Capability + Store Scope）。

**盘点发现的既有缺陷（D6）**：`:customers` 原声明 `data_fields: store_id`，但 `pallastrade_users` **无 store_id 列**且无法经关联到达 → 声明不可执行（数据范围选「按店」时 `accessible_by` 会生成 `users.store_id` 条件而报错）。因矩阵数据范围选项为固定列表（不渲染 `data_fields`），已改为空声明——**运行时能力与行为不变**，仅去掉无法兑现的声明（记录在案）。

---

## 3. 功能需求（FR）

- **FR-001 盘点固化（PR-P8-1）**：§2 映射表 + Skill（`pallastrade-admin` §权限注册表）同步。
- **FR-002 资源多模型覆盖（PR-P8-2）**
  - `PermissionRegistry::Entry` 新增 `models`（Array<Class>）；保留 `model_class`（= `models.first`，向后兼容，老调用方不受影响）；
  - `PermissionRegistry.register(:promotions, model_class: Promotion, models: [Promotion, PromotionRule, PromotionAction], actions:, data_fields:)`；
  - 未传 `models` 时 `models = [model_class].compact`。
- **FR-003 Ability 覆盖全部模型（PR-P8-2）**
  - `Ability#resolve_permission_targets(resource)` 返回 Entry 的 `models`（无 registry 时回退 `[resource.to_sym]`，`all` → `[:all]`）；
  - `apply_function_permission` 对每个目标模型应用同一 `can/cannot`（含 read 类动作的数据范围条件与 `:admin` 授予）；
  - 现有资源（单模型）行为逐字节不变。
- **FR-004 权限集从注册表派生（PR-P8-2）**
  - `PermissionSets::Base` 增加类级助手（如 `grant_registry_resource :promotions, :coupon_codes, actions: :manage`），内部遍历 `PermissionRegistry[res].models` 逐个 `can action, model`；
  - `PromotionManagement#activate!` = 派生 `:promotions` / `:coupon_codes` / `:promotion_categories`（manage）+ `:promotion_redemptions`（read）+ 既有 `Metafield read/admin` 行；
  - 保留 `PallasTrade.permissions.assign(:marketing, PromotionManagement)` 用法不变。
- **FR-005 新资源注册（PR-P8-3）**：注册 `:coupon_codes`（CouponCode，read/create/update/destroy，data_fields `store_id` 经 `promotion` 上卷）；`PromotionCategory` 无后台入口 → 不入矩阵，保留在代码权限集显式行；`:customers` 去掉不可执行的 `store_id` 声明（D6）。
- **FR-006 注册表自洽校验（PR-P8-3）**
  - `PermissionRegistry.validate!` → `[{ level:, code:, resource:, message: }]`：
    | code | level | 判定 |
    |---|---|---|
    | `invalid_model_class` | error | `models` 中存在非 `ActiveRecord::Base` 子类 |
    | `model_class_mismatch` | error | `model_class` 与 `models.first` 不一致 |
    | `invalid_action` | error | `actions` 不在 `RolePermission::FUNCTION_ACTIONS` 内 |
    | `invalid_data_field` | error | 字段不是覆盖模型的真实列，也不能经 `belongs_to` 链（深度 ≤ 2）到达 |
    | `missing_data_scope_path` | error | 某覆盖模型无该列且无关联路径（无法生成数据范围条件） |
    | `duplicate_model` | warning | 同一模型被多个资源覆盖（CanCan 语义为并集，提示而非阻断） |
    | `resource_without_model` | warning | 资源无模型（reports/emails/developers 等 UI-only 资源，Ability 以资源符号授权） |
  - rake `pallastrade:permissions:validate`（默认只报告；`STRICT=1` 有 error 非零退出）。
- **FR-007 nav:validate 增补（PR-P8-3）**：现有「DB 资源必须注册」保留；新增断言——存在 DB `promotions.*` 授权时，促销后台控制器模型（`Promotion`/`PromotionRule`/`PromotionAction`/`CouponCode`）均在 `promotions`/`coupon_codes` 的 `models` 覆盖内（缺失 = violation）。
- **FR-008 知识同步（PR-P8-3）**：`pallastrade-admin`（权限注册表节：多模型覆盖 + 校验命令）、`pallastrade-security`（capability 单源原则）、`pallastrade-promotions`（映射表指针）、GS-089、PRD README 索引。

---

## 4. 业务规则与边界

| # | 规则 | 说明 |
|---|---|---|
| R1 | 不新起 registry | 复用 `PallasTrade::PermissionRegistry`；不引入第二套权限声明机制 |
| R2 | 向后兼容 | `model_class` 保留；未声明 `models` 的资源行为不变（`models == [model_class]`） |
| R3 | 授权只增不减（对既有资源） | `orders/products/customers/...` 的 `models` 与 `actions` 不变 |
| R4 | SuperUser / 代码集回退路径不变 | DB 无配置的角色仍走 `PallasTrade.permissions` 代码集 |
| R5 | redemptions 独立只读 | 不并入 `promotions` 覆盖（避免顺带获得写权限） |
| R6 | 重复模型 = warning | 允许（并集语义），但报告以暴露"资源划分"问题 |
| R7 | 不改 v3 API 授权 | Admin API 的 scope/ability 体系独立，本批次不动；仅后台控制器 + Ability(function) |
| R8 | 校验分级 | 结构性错误（模型/动作/列/一致性）= error；资源划分重叠 = warning |

---

## 5. 验收标准（AC，与测试一一映射）

| AC | 对应 | 判定条件 | 映射测试 |
|---|---|---|---|
| AC-001 | FR-002/R2 | `Entry#models` 存在；未声明时 = `[model_class]`；`:promotions` 声明后 `models` = 3 个模型且 `model_class == models.first` | `backend/spec/models/pallastrade/permission_registry_spec.rb` |
| AC-002 | FR-003 | DB 角色授予 `promotions` 后 `can?(:admin/:update, PromotionRule/PromotionAction)` 为 true，`can?(:update, CouponCode)` 取决于 `coupon_codes` 授权；未授权资源仍 false | `backend/spec/models/pallastrade/ability_db_spec.rb`（扩展） |
| AC-003 | FR-003/D1 | DB 角色（非 SuperUser）在后台可访问促销规则/动作列表与编辑页（200），未授权资源 403 | `backend/spec/requests/pallastrade/admin/promotion_permission_spec.rb` |
| AC-004 | FR-005/D3 | registry 含 `:coupon_codes` / `:promotion_categories`；权限矩阵渲染出对应资源与动作列 | registry spec + `roles_permission_matrix_spec.rb` |
| AC-005 | FR-004/D2 | `PromotionManagement#activate!` 的 `can` 集合 == registry 覆盖集合（`Promotion/PromotionRule/PromotionAction/CouponCode/PromotionCategory` manage + `PromotionRedemption` read + Metafield read/admin） | `backend/spec/models/pallastrade/permission_sets/promotion_management_spec.rb` |
| AC-006 | FR-006 | `PermissionRegistry.validate!` 对默认注册表 0 error；合成缺口（非 AR 模型 / 非法 action / 非法 data_field / 缺少上卷路径 / model_class 不一致 / 重复模型 / 无模型告警）逐类命中；`store_id` 可经关联到达不算错误；rake `STRICT=1` 非零退出 | `spec/models/pallastrade/permission_registry_spec.rb` + `spec/lib/pallastrade/tasks/permission_registry_validator_spec.rb` |
| AC-007 | FR-007 | 促销后台 surface 覆盖：默认注册表通过（`rake pallastrade:admin:nav_validate` OK）；断言与 nav:validate 同一判定（模型均被某 capability 覆盖） | `spec/models/pallastrade/permission_registry_spec.rb`（surface 覆盖例）+ nav:validate |
| AC-008 | FR-008 | Skill ×3 更新 + GS-089 + PRD 索引 + `prd verify` 全覆盖 + `doc-impact` 无缺失 + promotions/权限回归全绿 | 回归命令 + `harness prd verify` / `doc-impact` |

---

## 6. 跨层搜索记录（6 层，2026-09-11 实测）

| 层 | 路径 | 关键词 | 找到 | 是否满足需求 |
|---|---|---|---|---|
| App（宿主） | `backend/config/initializers/` | PermissionRegistry / promotions | `pallastrade_permission_registry.rb`（13 资源，`:promotions` 单模型；`:promotion_redemptions` 只读） | ⚠️ 需补 `models` + 新资源（本批次核心） |
| Core | `pallastrade_gems/pallastrade_core/app/models/pallastrade/` | PermissionRegistry / ability / permission_sets | `permission_registry.rb`（Entry/register/[]/resources）、`ability.rb`（`apply_permissions_from_db` / `apply_function_permission` / `resolve_permission_target` / `data_condition_for`）、`permission_sets/base.rb`、`permission_sets/promotion_management.rb`、`role_permission.rb`（FUNCTION_ACTIONS） | ⚠️ 需多模型覆盖 + 派生助手 |
| API | `pallastrade_gems/pallastrade_api/app/` | authorize / scope | v3 Admin 授权走 scope/ability（`read_promotions`/`write_promotions`） | 不动（R7） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | roles / coupon_codes / promotions 控制器 | `roles_controller.rb`（矩阵加载 registry）、`views/.../roles/_form.html.erb`（资源 × 动作矩阵）、`promotion_rules_controller.rb` / `promotion_actions_controller.rb` / `coupon_codes_controller.rb`（`ResourceController#model_class` → `authorize!`）、`lib/tasks/navigation.rake`（`validate_role_permissions`） | ⚠️ 控制器授权依赖 registry 覆盖（D1） |
| Storefront | `storefront/src/` | — | 无权限消费点 | 不涉及 |
| Platform | `platform/packages/` | permissions | Admin SDK 无权限矩阵类型 | 不涉及 |

---

## 7. 技术影响

- **修改**：`pallastrade_core/app/models/pallastrade/permission_registry.rb`（Entry + validate!）、`ability.rb`（多目标应用）、`permission_sets/base.rb`（派生助手）、`permission_sets/promotion_management.rb`（改为派生）、宿主 `config/initializers/pallastrade_permission_registry.rb`（`models` + 新资源）、`pallastrade_admin/lib/tasks/navigation.rake`（覆盖断言）、`lib/tasks/permissions.rake`（新 rake，若不存在则新增）。
- **新增**：`spec/models/pallastrade/permission_registry_spec.rb`、`spec/models/pallastrade/permission_sets/promotion_management_spec.rb`、`spec/requests/pallastrade/admin/promotion_permission_spec.rb`、`spec/lib/pallastrade/tasks/permission_registry_validator_spec.rb`。
- **不改**：Admin API v3 授权、SuperUser 行为、业务模型/迁移、导航结构（仅新增校验）、Roles 矩阵 UI 结构。

---

## 8. 测试计划

| 文件 | 类型 | 覆盖 AC |
|---|---|---|
| `spec/models/pallastrade/permission_registry_spec.rb`（新） | model | AC-001 / AC-004 / AC-006 |
| `spec/models/pallastrade/permission_sets/promotion_management_spec.rb`（新） | model | AC-005 |
| `spec/models/pallastrade/ability_db_spec.rb`（扩展） | model | AC-002 |
| `spec/requests/pallastrade/admin/promotion_permission_spec.rb`（新） | request | AC-003 / AC-004 |
| `spec/lib/pallastrade/tasks/permission_registry_validator_spec.rb`（新） | rake | AC-006 |
| `spec/models/pallastrade/ability_db_spec.rb` + `navigation_consistency_spec.rb` + promotions 回归 | 回归 | AC-007 / AC-008 |

---

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-admin/SKILL.md`：权限注册表节补「多模型覆盖 + 新资源 + 校验命令」。
- [x] `ai/skills/pallastrade-security/SKILL.md`：capability 单源原则（资源 → 覆盖模型；不新起 registry）。
- [x] `ai/skills/pallastrade-promotions/SKILL.md`：促销权限映射表指针 + `coupon_codes` capability。
- [x] `harness/scenarios/scenarios.json`：GS-089。
- [x] `docs/prd/README.md`：本 PRD 行。
- [x] 接口契约：无端点变更 → 不重生成（实施后 `generated:check` 确认）。

---

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-11 | 0.1 | 初稿：PR-P8-1 盘点（4 处事实来源 + D1..D5）+ 收敛方案（models 覆盖 + 权限集派生 + 校验） | AI |
| 2026-09-11 | 1.0 | 用户明确选择「批次 5b：PR-P8 权限单源」授权实施；FR/AC（AC-001..008）与测试映射锁定 | AI |
| 2026-09-11 | 1.1 | 按实施盘点校正：`:coupon_codes` 新增注册（数据范围经 promotion 上卷）、`PromotionCategory` 无后台入口不入矩阵、`:customers` 去掉不可执行的 `store_id` 声明（D6）、校验码表与分级锁定 | AI |
| 2026-09-11 | 1.2 | 实施完成：注册表多模型覆盖 + Ability 多目标（含数据范围按模型上卷与列类型转换）+ 权限集派生 + `permissions:validate`/nav 覆盖断言 + spec ×5；回归 170 examples 绿 | AI |

## 11. 实施记录

| 文件 | 变更 |
|---|---|
| `pallastrade_core/.../permission_registry.rb` | `Entry` 增 `models`；`register` 接受 `models:`（默认 `[model_class]`）；新增 `resources_for_model` / `validate!` / `valid?` / `snapshot` / `replace_entries!` + 7 类校验码 |
| `pallastrade_core/.../ability.rb` | `apply_function_permission` 对 capability 的全部覆盖模型应用 grant；`resolve_permission_targets`；`data_condition_for(resource, model)` 按模型派生（`scope_condition_for` 上卷 + `cast_column_value` 类型转换） |
| `pallastrade_core/.../permission_sets/base.rb` | 新增 `grants_registry_resource` / `registry_grants` / `apply_registry_grants`；`activate!` 默认展开注册表授权（无声明时保持 `NotImplementedError`） |
| `pallastrade_core/.../permission_sets/promotion_management.rb` | 改为从注册表派生（promotions/coupon_codes manage + promotion_redemptions read），仅保留 PromotionCategory/Metafield 显式行 |
| `backend/config/initializers/pallastrade_permission_registry.rb` | `:promotions` 覆盖 3 模型；新增 `:coupon_codes`；`:customers` 去除不可执行的 `store_id`（D6） |
| `pallastrade_core/lib/tasks/permissions.rake`（新） | `pallastrade:permissions:validate`（`STRICT=1` 失败非零退出）+ `Tasks::PermissionRegistryValidator` |
| `pallastrade_admin/lib/tasks/navigation.rake` | `validate_promotion_surface_coverage`（促销后台模型必须被 capability 覆盖，+29 行纯新增） |
| spec ×5 | 注册表（AC-001/004/006/007）、权限集（AC-005）、Ability 多模型与数据范围上卷（AC-002）、后台请求（AC-003/004）、rake 校验（AC-006） |

**实测**：`pallastrade:permissions:validate` → `resources=14 models=13 errors=0 warnings=3`（reports/emails/developers 无模型的 UI-only 资源）；`nav:validate` OK；回归 170 examples / 0 failures；rubocop 新文件 0 offenses。

> 范围控制：`rubocop -a` 在 `navigation.rake` 上产生过无关格式化，已 `git checkout HEAD` 回退后改为纯手工新增（+29/-0），保持改动面最小（STD-SCOPE-001）。

## 12. 知识同步评估（sync-check 逐项结论）

| 触发组 | 资产 | 结论 | 依据 |
|---|---|---|---|
| Model / DB 变更 | 领域 Skill（promotions） | ✅ updated | 新增「促销权限（capability 单源）」映射表 + 注册/校验步骤 |
| Model / DB 变更 | pallastrade-data-model Skill | ➖ reviewed-no-change | 无模型/表/迁移变更 |
| Model / DB 变更 | 测试 | ✅ updated | 新增 5 个 spec（注册表/权限集/Ability/后台请求/rake） |
| Model / DB 变更 · API 端点变更 | 场景库 / scenarios.json | ✅ updated | 新增 GS-089 |
| API 端点变更 | `backend/public/api-docs/{store,admin}.yaml` | ➖ reviewed-no-change | 无端点/响应结构变更 |
| API 端点变更 | pallastrade-api-v3 Skill | ➖ reviewed-no-change | v3 授权（scope）未变（R7） |
| API 端点变更 | SDK 类型(generated:check) | ✅ updated（复跑无漂移） | 批内未改 serializer；`generated:check` 通过 |
| UI 组件 / 页面 | pallastrade-storefront Skill / 组件测试 | ➖ reviewed-no-change | 无 storefront 变更 |
| 事件 / 订阅者 | pallastrade-events-webhooks Skill | ➖ reviewed-no-change | 无订阅者/事件变更 |
| 包 / SDK 能力 | pallastrade-typescript-sdk Skill / platform/packages/README.md / 根 README | ➖ reviewed-no-change | 无平台包变更（命中来自并行批次文件） |
| 安全策略 | pallastrade-security Skill | ✅ updated | 新增 capability 单源原则（失权/越权、上卷与类型转换、不回退无条件放行） |
| 安全策略 | AGENTS.md §8 危险操作 | ➖ reviewed-no-change | 权限变更不触碰危险操作清单 |
| Skill / PRD 机制 | pallastrade-prd Skill / AGENTS.md / copilot-instructions.md | ➖ reviewed-no-change | 治理规则未变 |
