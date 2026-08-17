# 需求文档：菜单配置收敛-结构代码化-可视化只读展示-权限配置依据

- 关联 PRD：PRD-20260817-admin-菜单配置收敛-结构代码化-可视化只读展示-权限配置依据（approved）
- 任务：TASK-20260817040252-c47eb99a
- 分支：dev

---

## Step 0：跨层搜索（6 层，gate 强制）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | menu_config / MenuConfig / custom_item / url_picker / 删除菜单 / 添加二级 | 无 | 不涉及 |
| App — views/decorators | `backend/app/` | 同上 | 无 | 不涉及 |
| Core Gem — models | `backend/pallastrade_gems/pallastrade_core/app/models/` | MenuConfig | `pallastrade/menu_config.rb`（P4 覆盖层模型，含 visible/parent_key/url） | **停用写入/渲染引用（保留模型与表）** |
| Core Gem — services | `backend/pallastrade_gems/pallastrade_core/app/services/` | 同上 | 无 | 不涉及 |
| API Gem — controllers | `backend/pallastrade_gems/pallastrade_api/app/controllers/` | menu_config | 无 | 不涉及 |
| Admin Gem — controllers | `backend/pallastrade_gems/pallastrade_admin/app/controllers/` | menu_configs | `menu_configs_controller.rb`（index + update/rebuild_configs） | **本次改造对象（只留 index 只读）** |
| Admin Gem — views | `backend/pallastrade_gems/pallastrade_admin/app/views/` | menu_configs | `views/menu_configs/index.html.erb`、`_custom_item_fields.html.erb`；`roles/_form.html.erb`（菜单权限树） | **改造对象**（index 只读化 + 删 custom partial；Roles 权限树保留） |
| Storefront | `storefront/src/` | menu_config / url_picker | 无 | 不涉及 |
| Platform | `platform/packages/` | menu_config / url_picker | 无 | 不涉及 |

### 搜索结论

- 无现存"只读菜单可视化"页面；无"删除/添加二级菜单/URL 选择器"能力（已确认无重复）。
- 改造核心在 **Admin 层**：`menu_configs` 只读化 + 移除写路由/写参数 + 导航渲染层停用覆盖合并；Core 层仅停用引用；Roles 菜单权限树（P2）已满足"权限配置依据"，复用。

---

## Step 1：Skill 文件咨询

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | "Add a menu item / nav entry to the admin → `PallasTrade.admin.navigation.sidebar.add` → **pallastrade-admin**"——菜单结构由代码导航配置定义；本次"结构归代码"与决策树一致。 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | "The admin is a Rails engine — server-rendered ERB views, Stimulus + Turbo for interactivity, Tailwind for styling"；导航/视图定制直接改 `pallastrade_admin` gem 源码（加 `# PALLAS-CUSTOM:` 注释）。 |
| `ai/skills/pallastrade-catalog/SKILL.md` | ⬜ 不涉及 | 本次为 admin 菜单配置，非商品目录。 |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ⬜ 不涉及 | ⬜ | 无接口变更（内部 admin 页面路由） |
| `pallastrade-decorators` | ⬜ 不涉及 | ⬜ | |
| `pallastrade-dependencies` | ⬜ 不涉及 | ⬜ | |
| `pallastrade-events-webhooks` | ⬜ 不涉及 | ⬜ | |
| `pallastrade-storefront` | ⬜ 不涉及 | ⬜ | |
| `pallastrade-testing` | ⬜ 不涉及 | ⬜ | |
| `pallastrade-i18n` | ⬜ 不涉及 | ⬜ | 文案修改沿用现有 `PallasTrade.t('admin.menu_configs.*')` 模式（en.yml + zh-CN） |

---

## 需求标题

菜单配置模块方向收敛：结构归代码、配置页只读可视化、权限配置依据。

## 任务类型

功能优化（方向收敛 / 移除可编辑能力）

## 需求描述

1. 菜单树结构（一级/二级、URL、landing、图标）完全由代码导航配置定义，UI 不再提供结构编辑（移除 显隐/改名/排序/自定义菜单项/删除/添加二级菜单 全部可编辑能力）。
2. 「菜单配置」页改为只读导航树展示，让用户直观感受后台菜单结构。
3. 角色「菜单权限」保持树状勾选（与配置页同一棵树），作为权限配置依据。
4. 历史 MenuConfig 覆盖数据不再影响渲染（表/模型保留不删）。

## 影响范围（harness affected 输出）

实施时运行 `harness affected --base origin/main` 输出；预期涉及：
- `pallastrade_admin`：menu_configs_controller / views / routes / navigation_helper / locales
- `backend/spec/requests/pallastrade/admin/menu_config_spec.rb`
- `ai/skills/pallastrade-admin/SKILL.md`（知识同步）

## 技术方案（初步）

- `menu_configs_controller.rb`：删除 `update`/`rebuild_configs`/`items_params`/`custom_items_params`，仅保留 `index`（只读展示）。
- `config/routes.rb`：移除 `post 'menu_configs'`（仅保留 GET index）。
- `views/menu_configs/index.html.erb`：改为只读树渲染（去掉 form/checkbox/输入/排序/自定义区块/保存按钮）。
- 删除 `views/menu_configs/_custom_item_fields.html.erb`。
- `navigation_helper.rb`：`build_effective_nav` 移除覆盖层合并（直接返回原 nav），删除 `apply_menu_config_overrides`/`find_nav_item`（若不再引用）。
- `locales`：`admin.menu_configs.*` 收敛为只读说明文案（en + zh-CN）。
- `menu_config_spec.rb`：改为只读断言（GET 200 + 无编辑控件 + 覆盖不生效 + POST 404）。

## 风险点

- 最高风险：渲染层移除覆盖合并后，历史已保存配置（如隐藏 Blog）突然恢复显示——预期行为（结构归代码），需在 PRD/REQ 明确并在浏览器验证。
- 回滚难度：低（单次提交，可 revert）。

## 决策节点

✅ 用户已确认（"实施"）：完全去掉自定义菜单项 / 配置页全部只读 / 按新方向重写 PRD。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| Ruby 视图/控制器 | `pallastrade_admin/app/views/pallastrade/admin/menu_configs/**`、`menu_configs_controller.rb` | `rspec menu_config_spec.rb` + admin 回归 | | ⬜ |
| 渲染层 | `navigation_helper.rb` | admin 回归（默认树渲染） | | ⬜ |
| 权限回归 | `roles_permissions_spec.rb` | 菜单权限树勾选 + 过滤 | | ⬜ |
| 全部 | — | `harness check --profile quick` | | ⬜ |
| UI | 配置页只读 | 浏览器 E2E（dev 部署后） | | ⬜ |

### 验证结论

（实施后填写）
