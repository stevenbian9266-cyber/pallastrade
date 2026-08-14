# REQ-20260814-config-center-developers-tab — 配置中心入口改为 Developers 第 4 选项卡

> 需求标题：优化：配置中心入口从侧边栏独立项改为 Developers 第 4 选项卡
> 关联 PRD：PRD-20260814-admin-管理后台新增安全配置管理模块-oss-key-secret-值托管.md（v0.5）
> 任务类型：feature（优化）

---

## Step 0：跨层搜索（已执行）

| 层 | 搜索路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | config_items、config_center | 无（在 gem 层） | 不涉及 |
| Admin | `pallastrade_admin/config/initializers/pallastrade_admin_navigation.rb` | settings_nav.add :config_center、developers_tabs_nav | line 337-343（settings_nav 独立项，本次移除）；line 477-495（developers_tabs：api_keys/webhook/allowed_origins，本次新增 config_center） | 是——本次修改 |
| Admin views | `pallastrade_admin/app/views/.../config_items/index.html.erb` | developers_nav | line 1 渲染 `shared/developers_nav`（保留——标题将与选项卡一致） | 无需改 |
| Admin views | `pallastrade_admin/app/views/.../shared/_developers_nav.html.erb` | developers | 标题 `PallasTrade.t(:developers)` + `render_tab_navigation(:developers_tabs)` | 无需改 |
| Storefront | `storefront/src/` | config | 无 | 不涉及 |
| Platform | `platform/packages/` | configItems | 无 | 不涉及 |

**搜索结论**：仅需改 `pallastrade_admin_navigation.rb` 一处——移除 `settings_nav.add :config_center` 独立项，在 `developers_tabs_nav` 新增 `config_center` 选项卡。`_developers_nav` partial 与 index 视图保留即可（顶部标题与选项卡将一致）。无新增文件。

---

## Step 1：Skill 文件咨询（已执行）

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | "Add a menu item / nav entry to the admin → `PallasTrade.admin.navigation.sidebar.add` / tab 导航" —— 本次调整导航注册（settings_nav → developers_tabs） |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | "Config Center lives under Settings (`settings_nav.add :config_center`, `ConfigItemsController` with `SettingsConcern`)" —— 本次将入口从 settings_nav 移到 developers_tabs 第 4 项 |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | "命中相似 PRD → `harness prd update` 回写原 PRD（优化迭代），不新建" —— 已回写 PRD v0.5 |

---

## 需求内容

### 背景

配置中心页面顶部复用了 `developers_nav`（Developers 标题 + API Keys/Webhook/Allowed Origins 三个选项卡），但自身注册在 Settings 侧边栏独立菜单（`settings_nav.add :config_center`），导致"侧边栏叫 Config Center、页面顶部叫 Developers"的不一致。用户澄清：配置中心（集成参数/密钥）本就属开发者类目，应融合为 Developers 第 4 个选项卡。

### 变更点

1. **`pallastrade_admin_navigation.rb`**：
   - 移除 `settings_nav.add :config_center`（line 337-343）
   - 在 `developers_tabs_nav` 新增 `config_center` 选项卡（position 40，`url: :admin_config_items_path`，active 匹配 `controller_name == 'config_items'`，权限 `if: can?(:manage, PallasTrade::ConfigItem)`）
2. 页面 `index.html.erb` 保留 `developers_nav`（标题与选项卡现一致，无需改）
3. 无需迁移/数据变更

### 验收（AC）

- AC-010：Settings 侧边栏**不再**显示独立 "Config Center" 菜单项；Developers 选项卡包含第 4 项 "Config Center"（`/admin/config_items`）
- AC-003（回归）：`GET /admin/config_items` 正常渲染，页面顶部 Developers 标题 + 4 个选项卡
- 回归：admin config_items spec 全绿
