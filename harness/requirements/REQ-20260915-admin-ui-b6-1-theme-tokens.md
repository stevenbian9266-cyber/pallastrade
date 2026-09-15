# REQ-20260915-admin-ui-b6-1-theme-tokens — 管理后台 UI B6-1（品牌色 token / 语义 token / 密度变量基础层）

> 关联 PRD：`docs/prd/admin/PRD-20260915-admin-管理后台-ui-b6-1-品牌色-token-语义-token-与密度变量基础层.md`
> Harness 任务：`TASK-20260915024436-6d81b866` ｜ Gate：`GATE-2026-09-15T02-44-46`

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | `theme` / `tailwind` / `admin` | 无业务代码命中（样式入口见下） | ✅ 零改动 |
| App — views/decorators | `backend/app/` | `pallastrade/admin` | 仅 `app/views/pallastrade/admin/ai/**`（net-new 模块，AP-008 白名单） | ✅ 零改动 |
| App — 样式入口 | `backend/app/assets/` | `pallastrade_admin.css` / `builds` | `assets/tailwind/pallastrade_admin.css`（宿主覆盖入口，`@import "$PALLASTRADE_ADMIN_PATH/…/index.css"` + `@source`）、`assets/builds/pallastrade/admin/application.css`（构建产物，**未入库**）、`assets/tailwind/application.css`（空占位） | ✅ 入口齐备 → 本批补覆盖示例 |
| Core Gem | `pallastrade_core/app/` | `tailwind` / `theme` | 无样式资产（core 不承载 admin 样式） | ✅ 不涉及 |
| API Gem | `pallastrade_api/app/` | `assets` / `theme` | 无样式资产 | ✅ 不涉及 |
| **Admin Gem（主）** | `pallastrade_admin/app/assets/tailwind/pallastrade/admin/**` | `@theme` / `primary` / `density` / `#[0-9a-f]{6}` | `base/_theme.css`（token，仅 `--color-primary: zinc-950`）、`base/{_base,_utilities,_animations}.css`、`components/*.css` 25 个（`_layout` 566 行、`_forms` 267、`_tables` 195、`_buttons` 114…）、`views/_dashboard.css`、`plugins/*.css`；硬编码 hex **仅 4 处**；**无任何 density 变量**；ERB 视图 `primary-*` 工具类使用数 **0** | **否 → 本批实现** |
| Admin Gem — 布局 | `pallastrade_admin/app/views/layouts/pallastrade/` | `<html` | `admin.html.erb` / `admin_wizard.html.erb` / `minimal.html.erb`（三处 `<html>`） | **否 → 本批加 `data-admin-density`** |
| Admin Gem — 构建 | `pallastrade_admin/lib/` | `tailwind.rake` / `PALLASTRADE_ADMIN_PATH` | `tasks/tailwind.rake`（`pallastrade:admin:tailwindcss:{build,watch}`，`assets:precompile` 已 enhance）、`admin/tailwind_helper.rb`（路径替换）、`config/tailwind.config.js`（扫描 gem 视图/助手/JS） | ✅ 构建链成熟 → 直接复用 |
| Storefront | `storefront/src/` | token / tailwind | `src/app/globals.css`（前台自有蓝色系 token）、`tailwind.config.*` | ✅ 零改动（两套 token 体系互不影响） |
| Platform | `platform/packages/` | dashboard / tokens | `dashboard`、`dashboard-ui`（React SPA，**非本期 Rails admin**） | ✅ 零改动 |

### 搜索结论

- **能力层**：admin 样式体系（Tailwind v4 + `@theme` token + 组件 `@layer components`）与构建链（rake + watcher 容器）**已齐备**；本轮不引入任何新框架/新构建步骤。
- **缺口**：① 无品牌色阶（`--color-primary` 直接是 `zinc-950`）；② 无语义 token 层（surface/border/text）；③ 无密度变量与档位；④ 无 token 契约的机器校验（spec/verifier 缺失）。
- **落点**：`base/_theme.css` + 三个组件文件的主色语义 + 三个 layout 的 `<html>` 属性 + 宿主覆盖注释 + 新 spec + 新 verifier。ERB `primary-*` 使用数为 0 → **主色品牌化的影响面完全可控**。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树优先级「… → Generators → Decorators → Extensions」，本仓库 AGENTS §1 明确 gem 属**团队产品**、可直改（「Modify gem files directly. Git tracks all changes; upgrades are merges」）→ 样式基础层改动落 gem 是**最低风险层**，无需 decorator/宿主覆盖兜底 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | ①「The admin is a Rails engine — server-rendered ERB views, Stimulus + Turbo for interactivity, **Tailwind for styling**」；② 决策树「**Change admin styling globally** → Edit `backend/app/assets/tailwind/pallastrade_admin.css` … add `@theme` overrides and custom Tailwind there」（宿主覆盖是官方路径，本批补充可启用示例）；③ §Breadcrumbs「统一推导 + `skip_breadcrumb_derivation` 例外」（B6-3 用，本批不动） |
| `ai/skills/pallastrade-project/SKILL.md` | ✅ 已评估 | 项目结构与 gem 边界（`pallastrade_gems/*` 为本地框架源；Host App 仅 net-new 模块）→ 与本批落点一致 |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-testing` | ✅ | ✅ 已读 | spec 位置约定 `backend/spec/{models,requests,services,features}/`；本批落 `spec/design/`（无 DB、纯文件/计算断言），并复用容器 `pallastrade-web-1` 执行路径 |
| `pallastrade-storefront` | ⬜ 不涉及 | — | 前台 token 体系独立，本批零改动（仅回归确认） |
| `pallastrade-api-v3` | ⬜ 不涉及 | — | 无接口/序列化器/路由变更 |
| `pallastrade-events-webhooks` | ⬜ 不涉及 | — | 无事件订阅 |
| `pallastrade-i18n` | ⬜ 不涉及 | — | 无文案键变更 |
| `pallastrade-data-model` | ⬜ 不涉及 | — | 无 DB 变更 |

---

## 需求标题

管理后台（Rails `/admin`）**B6-1 基础层**：建立品牌色 token（navy + teal 双色阶）、语义 token 层（surface/border/text/focus）与密度变量双档（默认 compact，可切 comfortable），并把主色消费点（主/次按钮、导航激活与悬停、焦点环）切换到品牌 token；同步建立 WCAG AA 对比度契约与机器校验 spec/verifier。

## 任务类型

功能优化（UI 基础层 / 设计系统）——**零业务逻辑变更**：加法 token + 有限组件替换 + layout 属性 + 测试与文档。

## 需求描述

后台现在的令牌只有「`--color-primary` = 近纯黑」这一条主色，其余全靠组件里直接引 Tailwind 调色板（`zinc-950`/`gray-*`/`blue-*`），既没有品牌感，也没有能统一调节密度的地方；改一处观感要逐个组件翻。

本批先把**基础层**立起来：品牌双色阶 + 语义 token + 密度变量与档位（默认紧凑，保留舒适档），让后续「列表/表单密度」（B6-2）与「面包屑/导航/详情页信息层级」（B6-3）都只改 token 与组件映射，不再散落硬编码值；同时用 spec 把 token 集合与对比度钉住，防止后续退化。

## 影响范围（harness affected 输出）

```json
{
  "filesChanged": 101,
  "affectedComponents": ["ai", "backend", "harness", "platform", "storefront"],
  "errors": [],
  "estimatedTests": 252
}
```

（含 B1–B5 已提交内容；本批预计触及：admin gem `_theme.css` + 3 个组件 CSS + 3 个 layout + 宿主覆盖文件 + 1 新 spec + `harness.config.mjs` + Skill/场景库/PRD。）

## 技术方案（初步）

1. **token 定义**：在 gem `base/_theme.css` 的 `@theme` 内新增品牌双色阶（navy/teal，确定性派生）、九个语义 token、八个密度变量；`:root[data-admin-density="comfortable"]` 覆盖密度变量（默认 compact 写在 `:root`）。
2. **默认注入**：三个 layout 的 `<html>` 加 `data-admin-density="compact"`（S2 兜底由 `:root` 默认值保证）。
3. **主色消费点**：`.btn-primary` / `.btn-secondary` / `.nav-link:hover` / `.nav-pills .nav-link.active` / `.arrow` 等切到品牌 token（范围受控，B6-2 再处理中性色与状态色）。
4. **宿主覆盖示例**：`backend/app/assets/tailwind/pallastrade_admin.css` 增可启用注释（`@theme` 覆盖 + density 覆盖）。
5. **机器校验**：`backend/spec/design/admin_theme_tokens_spec.rb`（token 存在性 + 组件零直引 + layout 属性 + 对比度 ≥ 阈值）→ 注册 `admin-theme-rspec`。
6. **视觉验证**：容器内构建 + `/admin_user/sign_in` 截图与计算样式（DOM snapshot）。

## 风险点

| 风险 | 等级 | 缓解 |
|---|---|---|
| 主色由近黑改品牌 navy 属**可见观感变化**（越权决策风险） | 中 | 用户已明确选择品牌 navy+teal；PRD §1.1 记录决策来源；宿主可一键覆盖回旧色（FR-006/FR-010） |
| 密度默认 compact 在宽屏/大数据量页面上信息过密 | 中 | 变量化 + 双档切换；仅在本批生效默认值，B6-2 落切换入口时可验证实际阅读性 |
| Tailwind v4 `@theme` 与宿主覆盖的优先级语义（S1） | 中 | 实现后以「宿主覆盖值胜出」做断言/截图验证；必要时改用 `:root` 变量覆盖 |
| 旧视图/插件（page-builder、tinymce、uppy）依赖被替换的颜色类 | 中 | 只替换主色语义引用，保留 class 名；构建后全量页面抽查（列表/详情/表单各一页） |
| 对比度计算实现错误（自信满满地错） | 低 | 对比度断言用独立公式实现并与手算样例比对（spec 内固定样例） |
| 新 verifier 注册触发 harness 配置知识同步 | 低 | 已登记在 PRD §10（AGENTS.md §6 表 + 场景库 GS-125） |

**回滚难度**：低——纯样式与测试改动，无数据/接口影响；revert 即恢复。

## 决策节点（需用户确认）

1. **B6-1 范围**：仅基础层（token + 密度变量 + 主色品牌化 + 契约 spec/verifier），表格/表单密度替换留 B6-2、面包屑/详情页留 B6-3 —— 是否确认？
2. **主色档位**：主按钮用 `primary-600`（hover `-700`）、深色文字/底用 `-900/-950`、浅底用 `-50/-100` —— 是否有指定偏好？
3. **accent（teal）首期用途**：仅用于「强调态/成功提示/链接 hover 点缀」，还是本批先**只定义不启用**（B6-2 再落具体场景）？
4. **密度切换入口**：本批只提供机制（属性 + 变量），UI 切换按钮放 B6-2 —— 是否同意？

> ⏸️ **请确认以上理解与决策。确认后进入实施（清 prep → 改 token/组件/layout → 构建 + 截图 + spec → 证据 → 提交）。**
