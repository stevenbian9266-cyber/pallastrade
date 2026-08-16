# REQ-20260816-admin-nav-architecture — 管理后台导航架构统一重构（P4 单一布局 + 设置区统一）

> 任务类型：feature | 任务：`TASK-20260816105616-d4fa3758` | Gate：`GATE-2026-08-16T10-56-33`
> 分支：dev | 基线：`e58beca` | 方案文档：`docs/research/admin-navigation-refactor-plan.md`
> 关联 PRD：`docs/prd/admin/PRD-20260816-admin-管理后台导航架构统一重构-常显原则-面包屑自动推导-单一布局.md`（approved）

---

## Step 0：跨层搜索（已执行）

| 层 | 搜索路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | breadcrumb/nav | `ai_controller.rb`（Pattern B） | 不涉及 |
| Core | `pallastrade_core/app/` | nav/breadcrumb | 无 | 不涉及 |
| API | `pallastrade_api/app/` | nav | 无 | 不涉及 |
| Admin | `pallastrade_admin/app/` | navigation/add_breadcrumb/settings-header/if: | 导航配置、helper、Item、布局、25+控制器 | **本次修改对象** |
| Storefront | `storefront/src/` | breadcrumb | 前台组件 | 不涉及 |
| Platform | `platform/packages/` | nav | 无 | 不涉及 |

## Step 1：Skill 文件咨询（已执行）

| Skill | 状态 | 关键结论 |
|---|---|---|
| `pallastrade-customization/SKILL.md` | ✅ | 导航自定义 → `pallastrade-admin` |
| `pallastrade-admin/SKILL.md` | ✅ | 已有「两套布局统一规范」章节（GS-031/032）；本重构将其升级为 Schema 权威章节 |
| `pallastrade-prd/SKILL.md` | ✅ | AC→测试注解 `# PRD-xxx AC-x` |

---

## 需求标题：管理后台导航架构统一重构（P1-P5）

### 背景 / 已确认决策

- 决策 1：顶级落地 = 模块主页面（Email 模式）
- 决策 2：getting_started 保留 wizard 完成后隐藏
- 决策 3：translations 常显 + 空态引导

### 改动清单（按阶段）

- **P1** ✅（已提交 24220a6）：`_layout.css` 的 `#settings-header` 高度自适应，修复面包屑溢出。
- **P2** ✅（已提交 24220a6）：`orders_to_fulfill`/`translations` 常显 + badge/空态。
- **P3**（本次）：面包屑自动推导 ——
  1. `Navigation::Item` 加 `match_path?`（URL 精确/前缀匹配）；`Navigation` 加 `find_breadcrumb_chain(path, context)`（最深匹配 + 祖先链）。
  2. `BreadcrumbConcern` 加 `before_action :derive_breadcrumbs_from_navigation`：**主区(sidebar)** 自动按 请求路径→导航项→ 图标 + 父+子面包屑；设置区保留现有机制（settings nav 为 section 级，crumb 移除归 P4）。
  3. 新增对象页 hook：`breadcrumb_object` / `breadcrumb_object_name` / `breadcrumb_object_url`（控制器可覆盖，products/promotions 迁移）。
  4. 删除 5 个手写 concern：`emails/posts/order/products/promotions_breadcrumb_concern`；清理主区控制器 `include` + `add_breadcrumb` + `add_breadcrumb_icon`（设置区控制器保留，归 P4）。
  5. 保留宿主应用 `ai_controller.rb` 手写面包屑（AI 模块不在导航配置，属宿主自定义）。
- **P4**（本次）：单一布局 + 设置区统一 ——
  1. **单一布局**：`SettingsConcern`/`admin_users`/`invitations` 的 `choose_layout` 改为 `admin`；删除 `admin_settings` 布局文件。设置页复用主布局渲染管线（顶部 header 面包屑 + main 内 content_header + tabs）。
  2. **page_title fallback**：`derive_breadcrumbs_from_navigation` 记录 `@navigation_page_title`（最深匹配项 label）；`_content_header` 无 `content_for :page_title` 时回退到它，保证每个主区页面有页面头。
  3. **设置区 section/tabs 统一**：`Navigation::SETTINGS_SECTIONS` 注册表（developers/team/audit/returns → title + tabs + 可选 page_actions/nav_partials）；新建 `shared/_section_nav` 统一 partial；11 个设置 index 视图改渲染 `_section_nav`；删除 `_developers_nav/_team_nav/_audit_nav/_returns_and_refunds_nav` 4 个 banner partial（team 邀请按钮拆 `_team_nav_actions`）。
  4. **设置区 crumb 保留**：settings nav 为 section 级（developers 覆盖 api_keys 等），每页 crumb label ≠ section label，自动推导归 P5 schema 迁移。
- **P5**（本次）：schema 校验器 + 设置区 crumb 自动推导 + 知识沉淀 ——
  1. **`nav:validate` 校验器**：`pallastrade:admin:nav_validate` rake task（顶级 icon/URL、子项常显、业务 if: 关键字检测）+ harness 插件 `harness/plugins/nav-validate.mjs`（docker-rake，降级静态扫描 `scripts/nav-validate-static.mjs`）+ 接入 quick profile + lefthook pre-commit。
  2. **设置区 crumb 自动推导**：`Navigation::SETTINGS_TAB_MAP`（developers→developers_tabs 等 6 组）→ `derive_settings_breadcrumb` 按 active 命中 section + tab map 取页面级 label（Settings > 页面）；移除 27 个设置控制器手写 page crumb；`skip_breadcrumb_derivation` 例外（stores section crumb、webhook_deliveries 父级 crumb）。
  3. **知识沉淀**：SKILL.md 设置区自动推导章节 + GS-032 更新 + 方案文档 v1.4。
- **P6**（本次）：统一单一侧边栏（设置区融入主区 + landing + tab 面包屑 + 全配置化）——
  1. **模型层**：`Item` 加 `landing`/`tabs` 属性 + `landing_item`；`Item#match_path?` query 感知（带 query 项仅 path+query 都相等才命中，绝不落入 path-only 兜底）；`Navigation` 加 `find_breadcrumb_nodes`（chain + active 兜底 `find_active_breadcrumb_chain` + tab 节点去重）、`find_landing`、`self.tab_context`；删除 `SETTINGS_TAB_MAP`。
  2. **推导层**：`BreadcrumbConcern` 统一为单一推导 `derive_sidebar_breadcrumb`（`find_breadcrumb_nodes(request.path, self, query: request.query_string)`），删除 settings 分支。
  3. **渲染层**：`render_navigation_item` 顶级链接落地到 landing 子项 URL；`_store_nav` 恒渲染 `:sidebar`；`_sidebar/_header/_breadcrumbs/render_breadcrumb_icon` 删除 `settings_area?` 分支（无 Settings 前缀）。
  4. **配置迁移**：settings_nav 全部并入 sidebar_nav（Developers/Users/Tax/Shipping/Audit/Return Settings 等为顶级可收拉项，带子菜单 + landing）；主区模块补次级菜单（All Orders★/Products List★/Customers List★/Promotions List★/Reports List★/Blog List★/Customer Returns★/AI 子菜单）；Stock 声明 `tabs: :stock_tabs`；Taxonomies 改 label Categories。
  5. **i18n**：新增 label 双语 —— gem en.yml + 宿主 `admin_nav.en.yml`/`admin_nav.zh-CN.yml`（`pallastrade:` 命名空间）。
  6. **控制器清理**：Stock 三个控制器删手写 index crumb（tab 推导覆盖，保留对象 crumb）；`ai_controller` 删子页手写 crumb（子菜单推导覆盖，保留 provider 名 crumb）。
  7. **校验器升级**：`nav:validate` 加 landing 存在性、tabs 已注册、String label 双语 en/zh-CN；tab 上下文轻量校验。
  8. **测试**：`navigation_consistency_spec` 重写为 AC-006~011（landing 面包屑、tab 面包屑、无 Settings 前缀、双语、子菜单完整）。
  9. **知识沉淀**：SKILL.md 统一单一侧边栏章节 + GS-034 + 方案文档 v1.5。

### 验收标准（P6 部分）

- AC-006：顶级落地 —— /admin/orders 面包屑 Orders > All Orders；Orders to Fulfill query 页面包屑 Orders > Orders to Fulfill；顶级链接 href 指向 landing。
- AC-007：全模块子菜单完整 + 每个有子项顶级声明 landing 且为第一个子项。
- AC-008：Stock 三 tab 页面包屑 Products > Stock > {Stock Items|Stock Movements|Stock Transfers} + 页面头。
- AC-009：设置模块三段式面包屑无 Settings 前缀（Developers > API Keys / Users > Roles / Tax > Tax Rates）。
- AC-010：深层页面包屑完整路径（Products > Products List > 产品名）。
- AC-011：新增 label en + zh-CN 双语存在；nav:validate 通过（landing/tabs/i18n）。

### 验收标准（P5 部分）

- AC-005：设置区 crumb 自动推导 —— /admin/webhook_endpoints → Settings > Webhook Endpoints（非 Developers）；/admin/tax_rates → Settings > Tax Rates；/admin/roles → Settings > Roles；/admin/storefront → Settings > Storefront。
- AC-006：`nav:validate` 通过（rake + harness 插件 + 静态扫描）；引入业务 `if:` 会被阻断（负向用例）。
- AC-007：`navigation_consistency_spec`（21 examples）+ 全量 admin（74 examples）全绿。

### 测试计划

- `navigation_consistency_spec` 扩展（AC-001~004，标注 `# PRD-xxx AC-x`）
- 浏览器 e2e：面包屑 top>=0、子项恒显、顶级点击
- 每阶段：容器 rspec + quick check + 部署 dev + 浏览器抽查
