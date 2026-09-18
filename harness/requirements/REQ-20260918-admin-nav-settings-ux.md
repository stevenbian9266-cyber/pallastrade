# REQ-20260918-admin-nav-settings-ux — Settings 分区收起/展开交互修正（v1.1）

> 类型：功能优化（feature gate）｜父 PRD：`docs/prd/admin/PRD-20260918-admin-管理后台导航settings收起展开与新增fund一级菜单.md`（v1.1 行为修正，§11）
> 父任务：TASK-20260918134623-fb1c3519（v1.0 已完结，提交 `c3458b5a` + 文档 `90eb58b1`）
> 触发方式：用户实测反馈（v1.0 已部署 dev）

## 1. 需求描述（用户原话为准）

> 「你的实现有问题：1、当前管理后台菜单，如果 settings 展开，菜单面板会出现菜单弹窗浮层，这不该出现
> 2、期望实现的目标的是，settings 菜单默认收起，展开后默认显示二级菜单，点击二级菜单再展开三级菜单，settings 展开和收起都要有 icon 交互」

**用户对 4 个澄清问题的答复（逐字）**

| 问题 | 答复 |
|---|---|
| 二级标签点击行为 | 导航+展开三级，默认显示第一个三级；**settings 分区内菜单不需要箭头 icon，只有 settings 需要** |
| 是否手风琴 | 否：各二级项互不影响 |
| 适用范围 | 只改 Settings 分区，主区保持现状 |
| 当前页自动展开 | 自动展开到当前页（推荐） |

## 2. Step 0 跨层搜索（delta）

v1.0 已完成 6 层搜索；本批为同一能力的交互修正，权威文件不变，逐层复核结论：

| 层 | 相关文件 | 结论 |
|---|---|---|
| `backend/app/` | — | 无 admin 导航渲染逻辑（Host App 不持有侧边栏） |
| `pallastrade_core/app/` | — | 无导航渲染 |
| `pallastrade_api/app/` | — | 无关 |
| `pallastrade_admin/app/` | `helpers/pallastrade/admin/navigation_helper.rb`、`models/pallastrade/admin/navigation/item.rb`、`config/initializers/pallastrade_admin_navigation.rb`、`app/javascript/.../controllers/sidebar_controller.js`、`app/assets/tailwind/pallastrade/admin/components/{_layout,_navigation,_dropdowns}.css` | **唯一权威**，本批全部改动集中于此 |
| `storefront/src/` | — | 无关 |
| `platform/packages/` | — | 无关 |

**能改已有 → 不新建**：本批**不新增任何前端文件/组件**，只修正既有渲染器 + Stimulus 控制器 + 样式。

## 3. Step 1 Skill 咨询证据（本会话已读，结论复用并补充本批新增）

| Skill | 关键结论（对本需求的约束） |
|---|---|
| `pallastrade-admin` | 侧边栏唯一数据源 `PallasTrade.admin.navigation.sidebar`；分区标题是 root item；渲染链路 helper → Stimulus `sidebar`；样式走语义 token、禁止内联样式 |
| `pallastrade-storefront`（样式规范） | 组件类样式落在 `pallastrade_admin/app/assets/tailwind/**`，用设计 token（AP-001/AP-006 约束） |
| `pallastrade-api-v3` | 无接口变更 → 不涉及 `api-docs` / `generated:check` |
| `pallastrade-testing` | 服务端渲染 spec 用请求级断言（`render_views` + Nokogiri）；**客户端行为缺陷需另配真实 CSS 的交互验证**（本批的验证纠偏点） |

## 4. 目标行为（= PRD §11 FR 表）

A 默认收起（Settings 行有方向图标）｜B 展开仅二级｜C 点击二级 = 导航 + 展开三级（首个三级为落地页）
D 三级互不影响（无手风琴）｜E 当前页在分区内 → 自动展开到当前页｜F 仅 Settings 生效｜G 永不显形 hover 浮层

## 5. 技术方案

1. **根因**：`applySectionState` 的 `classList.toggle('hidden', collapsed)` 覆盖分区内**全部**同级元素，
   展开时摘掉 `ul.nav-submenu`（三级）与 `ul.nav-submenu-dropdown`（`.dropdown-container`：absolute + 阴影 = 浮层）的 `hidden`。
2. **渲染器**：`render_nav_section_header` 默认 `aria-expanded="false"`；分区内条目在「分区内无激活项」时
   服务端直接渲染 `hidden`（避免首屏闪烁）；**不新增 icon**（分区内保持一致，只有分区行有 chevron）。
3. **控制器**：分区显隐只切二级 `<li>`；
   - 收起：对可见的三级 `ul.nav-submenu` 打 `data-nav-section-hidden="1"` 再隐藏；
   - 展开：只恢复带该标记的三级（其余保持服务端状态 = 非激活即收起）；
   - `ul.nav-submenu-dropdown` **永不被显性化**（防御式断言 + 单测）；
   - 默认值反转：`collapsed = stored !== 'false'`，含激活项时强制展开并同步 `aria-expanded`。
4. **不触碰**：主区菜单、hover 下拉（icon-only 模式）、`Fund` 结构、权限过滤、面包屑。

## 6. 验证方案（AC ↔ 证据）

| AC | 验证手段 |
|---|---|
| AC-010（默认收起 / 展开仅二级 / 无浮层可见） | 更新后的 `nav_collapsible_fund_spec`（服务端渲染断言）+ 真实 CSS 交互探针（无可见 `.dropdown-container`） |
| AC-011（点击二级 = 导航 + 展开首个三级；主区不变） | 请求级 spec（`/admin/admin_users` 渲染 Users 子树展开且首项 active）+ 主区菜单渲染快照对比 |
| 回归 | `harness verify admin-catalog-health-rspec`（含导航一致性）、`admin-theme-rspec`、`admin-i18n-rspec`、`harness check --profile quick`、`nav:validate` |

## 7. 影响面 / 风险

- 行为变更（默认展开 → 默认收起）属**已交付行为修订**，已在 PRD §10 v1.1 留痕，无历史数据/接口影响。
- 风险点：服务端 `hidden` 与 localStorage 状态竞争 → 由「服务端默认 + JS 首帧同步 + 无过渡」规避。
