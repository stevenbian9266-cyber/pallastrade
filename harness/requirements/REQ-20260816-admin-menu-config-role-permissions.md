# REQ-20260816-admin-menu-config-role-permissions — 后台可视化菜单配置模块 + 角色权限体系（菜单/数据/功能权限）

> 任务类型：feature | 任务：`TASK-20260816133510-b00daee4` | Gate：`GATE-2026-08-16T13-35-27`
> 分支：dev | 基线：`d7203d9` | 关联 PRD：`docs/prd/admin/PRD-20260816-admin-后台可视化菜单配置模块-角色权限体系-菜单-数据-功能权限.md`（approved）
> 用户已确认决策：全局+店铺覆盖 / 支持自定义菜单项 / 数据权限完整版 / DB 完全取代代码权限

---

## Step 0：跨层搜索（已执行，详见 PRD §6）

| 层 | 搜索路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | nav/permission | `ai_controller.rb`（导航注册） | 不涉及 |
| Core | `pallastrade_core/app/` | Ability/Role/PermissionSets | `ability.rb`、`role.rb`、`role_user.rb`、`permission_sets/*`、`permission_configuration.rb` | **本次改造对象（权限引擎）** |
| API | `pallastrade_api/app/` | permission | 无 | 不涉及 |
| Admin | `pallastrade_admin/app/` | navigation/roles | 导航配置/Item/Navigation/BreadcrumbConcern、`roles_controller.rb` + `roles/_form.html.erb`（仅 name）、`admin_users_controller.rb` | **本次改造对象（菜单配置 UI + 角色权限 UI + 导航渲染集成）** |
| Storefront | `storefront/src/` | 无 | 无 | 不涉及 |
| Platform | `platform/packages/` | 无 | 无 | 不涉及 |

## Step 1：Skill 文件咨询（已执行）

| Skill | 状态 | 关键结论 |
|---|---|---|
| `pallastrade-customization/SKILL.md` | ✅ | 导航自定义 → `pallastrade-admin`；权限/能力 → `pallastrade-security`；运行时行为 → 配置 |
| `pallastrade-security/SKILL.md` | ✅ | CanCanCan abilities/scope 是权威权限机制；数据权限须参数化防注入 |
| `pallastrade-prd/SKILL.md` | ✅ | PRD 驱动闭环：approved → task/gate → REQ → 实施 → 测试 → 知识同步 |

---

## 需求标题：后台可视化菜单配置模块 + 角色权限体系（菜单/数据/功能权限）

### 背景 / 已确认决策

- 现状：菜单仅配置文件声明、Role 无权限 UI（仅 name 字段）、权限仅代码级 PermissionSets
- 已确认 4 项决策：
  1. 菜单配置作用域 = 全局默认 + 店铺覆盖
  2. 菜单配置支持新增自定义菜单项
  3. 数据权限 MVP = 完整版（all/self/store/channel/custom）
  4. DB 权限完全取代代码权限（迁移 + 零回归）

### 改动清单（分阶段实施）

- **P1**：数据模型 + 迁移 + Ability DB 读取
  1. 新建 `PallasTrade::MenuConfig`（store_id 可空=全局、nav_key、visible/label/position 覆盖、自定义项字段）
  2. 新建 `PallasTrade::RolePermission`（role_id、permission_type=menu/function/data、resource、action、nav_key、scope、scope_value、custom_condition JSON）
  3. `Role` 加 `has_many :role_permissions`；迁移建 2 张表
  4. seed：现有 `admin`→SuperUser 全量、`default`→DefaultCustomer 迁移为 DB 记录
  5. `Ability#apply_permissions_from_sets` → 从 DB `role_permissions` 构建（保留 `pallastrade_admin?` 兼容）
  6. 新增 `PermissionRegistry`（resource 注册表 + 可用操作 + 数据字段）
- **P2**：Roles 权限矩阵 UI（菜单/功能/数据 三 tab）→ 修复"无法设置 permission"
- **P3**：菜单权限 + 导航渲染集成（Navigation 合并 MenuConfig 覆盖层 + 角色菜单权限过滤）
- **P4**：可视化菜单配置模块（全局+店铺覆盖 + 自定义菜单项）
- **P5**：数据权限 accessible_by 集成（self/store/channel/custom）
- **P6**：nav:validate 升级 + 全量测试 + 知识同步（SKILL/GS/scenarios）

### 验收标准（PRD §5 AC-001~010，标注 `# PRD-xxx AC-x`）

- AC-001~003：菜单配置页（导航树 + 全局/店铺切换 + 显隐/改名/排序/自定义项 + 即时生效 + 覆盖层不破坏 landing/tabs/面包屑）
- AC-004~006：Roles 权限三 tab + 持久化 + 菜单权限过滤 + 功能权限 `orders:read`
- AC-007：数据权限 self/custom 生效 + 非法表达式拒绝
- AC-008：迁移后 admin/default 零回归（代码 PermissionSets 移除）
- AC-009：nav:validate 覆盖 key + 权限 resource 校验
- AC-010：菜单配置隐藏 + 角色菜单权限双条件生效

### 测试计划

- 新增：`role_permission_spec.rb`、`menu_config_spec.rb`、`ability_db_spec.rb`、`menu_config_spec.rb`（request）、`roles_permissions_spec.rb`（request）
- 更新：`navigation_consistency_spec.rb`（菜单权限过滤 + 覆盖层回归）
- 每阶段：容器 rspec + quick check + 浏览器验证
