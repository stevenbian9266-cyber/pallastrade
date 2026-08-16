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
- **P5**：`harness nav:validate` + 全量迁移 + SKILL/GS 沉淀。

### 验收标准（P4 部分）

- AC-004：设置页使用主布局（body 无 `admin-settings` 类），面包屑仍在顶部 header（Settings > 页面），页面头 + tabs 正常渲染。
- AC-004b：/admin/api_keys 等设置页渲染「Developers」section banner（标题 + API Keys/Webhook/Allowed Origins/Redirects tabs）。
- AC-004c：主区无 page_title 的页面（如 orders show）自动 fallback 页面头（导航项 label）。
- AC-004d：`navigation_consistency_spec` + `emails_spec` 全绿（43+ examples）。

### 测试计划

- `navigation_consistency_spec` 扩展（AC-001~004，标注 `# PRD-xxx AC-x`）
- 浏览器 e2e：面包屑 top>=0、子项恒显、顶级点击
- 每阶段：容器 rspec + quick check + 部署 dev + 浏览器抽查
