# PRD-20260915-admin-管理后台-ui-b6-1-品牌色-token-语义-token-与密度变量基础层

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-15 |
| 来源 | 优化：管理后台 UI —— 配色token / 列表表单密度 / 面包屑导航 / 交易订单详情页信息层级（**B6-1 基础层**） |
| 分类 | admin（自动判定，见 `harness/policies/prd-categories.json`） |
| 关联 Skill | `pallastrade-admin`（主：§Styling / 决策树「Change admin styling globally」）、`pallastrade-project`（gem 直改约定） |
| 关联 REQ | REQ-20260915-admin-ui-b6-1-theme-tokens.md（实施时回填） |
| 关联 PRD | 本批为管理后台 UI 优化的 **B6-1/3**（B6-2 列表与表单密度、B6-3 面包屑导航与详情页信息层级，另批立项） |
| 需求类型 | UI 优化（设计 token 基础层 + 密度开关 + 主色品牌化），**零业务逻辑变更** |

---

## 1. 背景与目标

### 1.1 背景（现状核查 2026-09-15）

管理后台是本仓库的 **Rails engine**（`backend/pallastrade_gems/pallastrade_admin`），样式为 **Tailwind v4**，产物由 `bin/rails pallastrade:admin:tailwindcss:build`（`assets:precompile` 已挂钩；dev 由 `pallastrade-admin-css-1` watcher 实时构建）生成到 `app/assets/builds/pallastrade/admin/application.css`。

| 现状 | 事实 |
|---|---|
| 设计 token | `app/assets/tailwind/pallastrade/admin/base/_theme.css` 的 `@theme` 块：仅定义 `--color-primary: var(--color-zinc-950)`（**接近纯黑**）、状态色指向 Tailwind 深色档、字号/字重/阴影/布局尺寸；**没有品牌色阶、没有语义层（surface/border/text）、没有密度变量** |
| 颜色直引 | 组件层（`components/_*.css`，38 个文件）大量直接 `@apply` Tailwind 调色板（`zinc-950`/`gray-*`/`blue-*`/`red-*`/`green-*`），硬编码 hex 仅 4 处 → **token 化改造成本低、收益高** |
| 主色消费点 | `.btn-primary`（`bg-zinc-950`）、`.btn-secondary`（`blue-50/100/900`）、`.nav-link:hover`（`text-zinc-950`）、`--color-primary` 别名；**ERB 视图里 `primary-*` 工具类使用数 = 0** → 主色品牌化影响面**仅限于组件层**，可控 |
| 密度 | 无任何密度变量；行高/控件高度写在组件（`_tables.css` 195 行、`_forms.css` 267 行、`_filters.css` 83 行）里，改密度目前只能逐条改 `@apply` |
| 品牌色来源 | `pallastrade-brand-assets/pallastrade-logo.svg`：**navy `#0A2540`** + **teal `#0F9D94`**；前台 storefront token 用的是一套蓝色系（`#0077ff`），与后台目前无关联 |
| 宿主覆盖点 | `backend/app/assets/tailwind/pallastrade_admin.css`（官方指定入口：`@theme` 覆盖 + `@layer components`） |

**用户已确认的方向（2026-09-15）**：配色采用**品牌 navy + teal**；密度**默认 compact**（保留 comfortable 可切）；四块内容**分三批**，本批为 B6-1 基础层。

### 1.2 目标

1. 建立**品牌色阶 + 语义 token 层**，让后续所有后台视觉改动只依赖 token，不再直接引 Tailwind 调色板。
2. 建立**密度变量族 + 双档切换**（`data-admin-density="compact" | "comfortable"`，默认 compact），为 B6-2 的列表/表单密度改造提供唯一杠杆。
3. 主色消费点（主按钮、次按钮的主色语义、导航激活/悬停、焦点环）切换到品牌 token。
4. 用**机器可校验**的方式固定 token 契约与对比度（WCAG AA），避免后续改动悄悄退化。

### 1.3 成功指标

- `_theme.css` 提供 ≥ 22 个新 token（品牌双色阶 + 语义 + 密度），且**零 Tailwind 默认调色板直引**残留于主色/语义路径。
- `/admin_user/sign_in`（公开页）截图呈现品牌主色；`html[data-admin-density="compact"]` 生效，同一页面 body 字号/行高与 comfortable 档可区分。
- 新增 spec 对 token 集合 + 对比度做断言，纳入注册 verifier（秒级），后续回归自动拦截。

### 1.4 非目标（本批不做）

- **不动**表格/表单/筛选器的具体尺寸（B6-2：仅在本批提供变量与档位，B6-2 才替换到组件）。
- **不动**面包屑/侧边栏/详情页布局与信息层级（B6-3）。
- 不改任何控制器/模型/路由/权限/业务逻辑；不改 ERB 结构（仅 layout 增加一个 `data-` 属性）。
- 不引入新的 CSS 框架/构建步骤；不改变现有 class 名（向后兼容，扩展/插件视图继续可用）。

---

## 2. 用户故事与场景

| # | 角色 | 场景 | 期望 |
|---|---|---|---|
| U1 | 运营（日常） | 打开后台任意列表/详情页 | 主按钮/链接/激活态是品牌色，不再是纯黑；信息密度更紧凑（compact 默认） |
| U2 | 运营（偏好） | 觉得太紧或太松 | 可切到 comfortable 档（本批提供机制，切换入口在 B6-2 落 UI） |
| U3 | 前端/设计开发者 | 要改后台某处颜色或间距 | 只改 token（`_theme.css` 或宿主覆盖文件），不用逐组件找硬编码值 |
| U4 | 维护者 | 有人把品牌色改成低对比色 | spec 断言失败（对比度 < 4.5:1）→ 拦住 |

**边界/异常场景**

- S1：宿主（本仓库）通过 `backend/app/assets/tailwind/pallastrade_admin.css` 覆盖 token → 覆盖应优先生效（导入顺序 + `@theme` 合并语义需验证）。
- S2：未设置 `data-admin-density` 的页面（如 `admin_wizard`/`minimal` 布局、ActionText 内嵌）→ 必须回落到 compact 默认（`:root` 兜底），不得出现无样式错位。
- S3：RTL（`components/_rtl.css` 存在）→ 新 token 不得写方向相关值；密度变量为纯数值，天然安全。
- S4：暗色（后台当前无 dark mode 切换）→ 本批不引入 dark 模式，token 命名预留语义位但只定义亮色值。

---

## 3. 功能需求（FR）

- **FR-001 品牌色阶 token**：在 `base/_theme.css` 的 `@theme` 内新增
  - `--color-primary-50 … --color-primary-950`（基于 **navy `#0A2540`** 确定性派生：固定色相/饱和度插值，`-600/-700` 作为主色档，`-50/-100` 作为浅底，`-900/-950` 作为深底/文字）；
  - `--color-accent-50 … --color-accent-950`（基于 **teal `#0F9D94`**，同规则）；
  - 派生规则与色值表写入 PRD §9（可复核）；`--color-primary` 别名仍存在但指向品牌主色档（保持旧引用的可用性）。
- **FR-002 语义 token 层**：新增 `surface / surface-muted / background / border / border-strong / text / text-muted / text-subtle / focus-ring` 九个语义变量（值取品牌中性阶或灰阶），并注明「组件不得再直接引 Tailwind 调色板」的约定。
- **FR-003 密度变量族**：新增 `--admin-density-row-padding-y / -row-padding-x / -control-height / -control-padding-x / -label-gap / -section-gap / -font-size-base / -line-height-base`，默认值 = **compact** 档；`:root[data-admin-density="comfortable"]` 覆盖为宽松档（数值与现状接近）。
- **FR-004 密度属性默认注入**：`layouts/pallastrade/{admin,admin_wizard,minimal}.html.erb` 的 `<html>` 增加 `data-admin-density="compact"`（S2 兜底仍需 `:root` 默认值）；不改变其他 layout 结构与视图。
- **FR-005 主色消费点品牌化**：把「主色语义」的组件切换到品牌 token：
  - `.btn-primary`（含 hover/focus）→ `primary-600/700` + `focus-ring`；
  - `.btn-secondary`（当前蓝系浅底）→ `primary-50/100/900`；
  - `.nav-link:hover/focus` 与 `.nav-pills .nav-link.active` → `text-primary-700` / `bg-primary-50`；
  - `.btn-secondary .arrow`、`_cards.css`/`_tinymce.css`/`_page-builder.css` 中现有的 `primary`/`zinc-950` 语义引用 → 统一 token。
  （**范围限制**：本批只改「主色语义」；中性色与状态色的全面 token 化在 B6-2。）
- **FR-006 宿主覆盖入口完善**：`backend/app/assets/tailwind/pallastrade_admin.css` 增加**可直接启用的注释示例**：`@theme` 覆盖品牌档 + `[data-admin-density]` 覆盖示例 + 说明「宿主覆盖优先于 gem 默认」。
- **FR-007 对比度契约（WCAG AA）**：为 token 定义中「文字/背景」「边框/背景」「按钮前景/背景」五组组合计算对比度，正文 ≥ 4.5:1、大字与边框 ≥ 3:1；结果表写入 PRD §9，并由 spec 断言（防止后续改动退化）。
- **FR-008 机器校验 spec + 注册 verifier**：新增 `backend/spec/design/admin_theme_tokens_spec.rb`：
  - 断言 `_theme.css` 含全部必需 token 名（品牌双色阶 ≥ 20 个 + 语义 9 个 + 密度 8 个）与 `data-admin-density` 选择器块；
  - 断言组件层**不再**出现 `bg-zinc-950` / `text-zinc-950` / `bg-blue-50` 等被替换的直引（白名单外为零）；
  - 断言 3 个 layout 均输出 `data-admin-density`；
  - 内置对比度计算断言（≥ 上述阈值）。
  同时把该 spec 注册为 verifier `admin-theme-rspec`（`harness.config.mjs`），供 gate/CI 快速回归。
- **FR-009 构建与视觉验证**：容器内执行 `bin/rails pallastrade:admin:tailwindcss:build` 成功；构建产物含新 token；`/admin_user/sign_in` 页面加载新 CSS 且截图呈现品牌色与 compact 密度。
- **FR-010 回滚与兼容**：所有改动为**加法 + 有限替换**；class 名不变；回滚 = revert 提交（无数据/接口影响）。宿主的 `@theme` 覆盖能力保持（宿主可一键改回旧主色）。

---

## 4. 非功能需求（NFR）

- **性能**：仅新增 CSS 自定义属性与少量 `@apply` 替换，产物体积变化 < 5%，不引入运行时 JS。
- **可维护性**：token 命名遵循 Tailwind v4 `--color-<name>-<step>` 约定；语义 token 用 `--color-<semantic>` 命名，避免与色阶混淆。
- **可访问性**：FR-007 的对比度是硬门槛；焦点环在浅底/深底均可见（≥3:1）。
- **可测试性**：token 契约可在无浏览器环境断言（读文件）；视觉验证用截图 + 计算样式（DOM snapshot）。
- **可回滚性**：见 FR-010；不涉及 DB 迁移。

---

## 5. 验收标准（AC，与测试一一映射）

- **AC-001 ← FR-001**：`_theme.css` 同时包含 `--color-primary-{50,100,…,950}` 与 `--color-accent-{50,…,950}`，且 `--color-primary` 指向品牌主色档（spec 断言 + PRD §9 色值表）。
- **AC-002 ← FR-002**：九个语义 token 全部存在（spec 断言）。
- **AC-003 ← FR-003**：八个密度变量存在，默认档 = compact；`[data-admin-density="comfortable"]` 覆盖块存在且至少 5 个变量被覆盖（spec 断言）。
- **AC-004 ← FR-004**：3 个 layout 的 `<html>` 输出 `data-admin-density`（spec 断言 + curl 页面 HTML 片段）。
- **AC-005 ← FR-005**：`.btn-primary`/`.btn-secondary`/`.nav-link`/`.nav-pills .nav-link.active` 使用品牌 token；被替换的 Tailwind 直引（`zinc-950`/`blue-50/100/900` 在主色语义处）在组件层为 0（spec 断言）。
- **AC-006 ← FR-006**：宿主覆盖文件含 `@theme` 与 density 覆盖示例；`npm`/`rails` 构建仍成功（构建日志）。
- **AC-007 ← FR-007**：五组对比度均达标，且 spec 的对比度断言通过（阈值写死在 spec）。
- **AC-008 ← FR-008**：`harness verify admin-theme-rspec --task <id>` 全绿（spec 计数 ≥ 6 例）。
- **AC-009 ← FR-009**：构建命令 exit 0；产物 CSS 含 `--color-primary-600` 等新 token；`/admin_user/sign_in` 截图显示品牌主色 + compact 密度（截图证据 + DOM 计算样式 `line-height`）。
- **AC-010 ← FR-010/S2**：未设置密度的页面（`minimal` 布局或 ActionText 内嵌）渲染正常（无 token 未定义导致的样式崩坏）——以 `:root` 兜底断言 + 页面检索证据。

---

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `tailwind/pallastrade_admin.css` / `assets/tailwind` | 宿主覆盖入口 `app/assets/tailwind/pallastrade_admin.css`（`@import` gem base + `@source`）、`app/assets/builds/pallastrade/admin/application.css`（构建产物，未入库）、`app/assets/stylesheets/application.css` | ✅ 入口已就位 → 本批补充示例与注释 |
| App（视图） | `backend/app/views/` | `pallastrade/admin` | 仅 `ai/` 模块（net-new，AP-008 白名单） | ✅ 零改动 |
| Core | `pallastrade_core/app/` | `theme` / `tailwind` | 无样式资产（core 不承载 admin 样式） | ✅ 不涉及 |
| API | `pallastrade_api/app/` | `theme` / `assets` | 无样式资产 | ✅ 不涉及 |
| **Admin（主）** | `pallastrade_admin/app/assets/tailwind/pallastrade/admin/**` | `@theme` / `primary` / `density` / 硬编码色 | `base/_theme.css`（token 定义）、`base/_base.css`、`components/{_buttons,_navigation,_cards,_tables,_forms,_filters,_breadcrumbs,..}.css`（38 文件，硬编码 hex 仅 4）、`utilities/_bootstrap.css`、`config/tailwind.config.js`（扫描路径）、`lib/tasks/tailwind.rake`（构建任务）、`lib/pallastrade/admin/tailwind_helper.rb`（`$PALLASTRADE_ADMIN_PATH` 解析） | **否 → 本批实现**（无品牌色阶/语义层/密度变量） |
| Storefront | `storefront/src/` | token / tailwind config | `storefront/src/app/globals.css`（前台自有蓝色系 token，与后台无关） | ✅ 零改动（前台 token 体系独立） |
| Platform | `platform/packages/` | dashboard / tokens | `dashboard` / `dashboard-ui`（React SPA，**非本期 admin**） | ✅ 零改动 |

**结论**：本批是**纯后台样式基础层**改造，落点在 gem 的 `base/_theme.css` + 少量 `components/*.css`（主色语义）+ 3 个 layout 的 `<html>` 属性 + 宿主覆盖文件注释 + 1 个新 spec + 1 个新 verifier 注册。防重复判定：无既有 PRD 覆盖「后台设计 token / 密度」；`pallastrade-admin` Skill 有 §Styling 与决策树指引（本批即按「全局样式改 `pallastrade_admin.css` / gem base」的现行方式执行）。

---

## 7. 技术影响

- **gem（admin）**：`app/assets/tailwind/pallastrade/admin/base/_theme.css`（token 新增）、`components/{_buttons,_navigation,_cards}.css`（主色语义 token 化）、`app/views/layouts/pallastrade/{admin,admin_wizard,minimal}.html.erb`（`data-admin-density` 属性）。
- **宿主**：`backend/app/assets/tailwind/pallastrade_admin.css`（覆盖示例注释）。
- **harness**：`harness.config.mjs` 注册 `admin-theme-rspec`（新文件 `backend/spec/design/admin_theme_tokens_spec.rb`）。
- **文档**：`pallastrade-admin` Skill §Styling（token/密度契约与「先改 token」规则）、`docs/standards/`（如需登记设计 token 指针）、`platform/…` 无关。
- **不涉及**：路由、控制器、模型、序列化器、DB、API 文档、SDK、前台 storefront。

---

## 8. 测试计划

- **新增**：`backend/spec/design/admin_theme_tokens_spec.rb` → AC-001/002/003/004/005/007/010（读 CSS/ERB 文件 + 对比度计算；无需 DB）
- **注册**：`harness.config.mjs` → `admin-theme-rspec`（命令：`docker exec pallastrade-web-1 bash -c "cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/design/admin_theme_tokens_spec.rb"`）
- **构建**：`docker exec pallastrade-web-1 bash -lc "cd /rails && bin/rails pallastrade:admin:tailwindcss:build"` → AC-009（构建日志）
- **视觉/DOM**：`curl http://localhost:3000/admin_user/sign_in` + 抓取 `/assets/pallastrade/admin/application-*.css` grep 新 token；浏览器截图（登录页，公开可访问）+ 计算样式断言 → AC-004/009/010
- **回归**：`pnpm -C storefront test` 不涉及（前台零改动），但仍跑 `harness generated:check` 与 storefront 三绿确认无副作用；`pallastrade-admin` Skill 的 Eval 场景新增 GS-125
- **AC ↔ 测试映射**：测试文件内同行写 `# PRD-<本PRD-ID> AC-xxx` 供 `prd verify` 校验

---

## 9. 设计 token 规格（FR-001/002/003/007 的权威表）

> 色阶由基色确定性派生（固定 HSL 插值：L 从 97%（-50）到 12%（-950），S 保持基色饱和度 ±5%），色值表在实施时以脚本计算并复核对比度。

### 9.1 品牌色阶（实测值，由基色确定性派生）

| 档位 | primary（navy `#0A2540` 派生） | accent（teal `#0F9D94` 派生） |
|---|---|---|
| 50 | `#EEF5FB` | `#EDFCFB` |
| 100 | `#DDEBF8` | `#DBFAF8` |
| 200 | `#BED9F3` | `#BBF7F3` |
| 300 | `#95C2EE` | `#8FF4EE` |
| 400 | `#60A3E6` | `#57EFE5` |
| 500 | `#2B85DE` | `#20EADD` |
| **600（主色档）** | **`#1C66B0`** | `#12BAB0` |
| 700 | `#16528D` | `#0E958C` |
| 800 | `#11406E` | `#0B746E` |
| 900 | `#0D2E4F` | `#09534E` |
| 950 | `#0A2138` | `#073B38` |

`--color-primary` 别名指向 `--color-primary-600`（保留旧引用可用）。**accent 只定义不启用**（用户决策：强调/成功态场景在 B6-2/B6-3 落地）——spec 断言组件层 `accent-` 使用数为 0。

### 9.2 语义 token

`--color-surface: #FFFFFF`、`--color-surface-muted: #F9FAFB`、`--color-background: #FAFAFA`、`--color-border: #E5E7EB`、`--color-border-strong: #D1D5DB`、`--color-text: #111827`、`--color-text-muted: #4B5563`、`--color-text-subtle: #6B7280`、`--color-focus-ring: #2B85DE`。

### 9.3 密度变量

`--admin-density-*`：row-padding-y `0.375rem`、row-padding-x `0.75rem`、control-height `2rem`、control-padding-x `0.625rem`、label-gap `0.25rem`、section-gap `1rem`、font-size-base `0.813rem`、line-height-base `1.25rem`（共 8 项，均为 compact 默认）；`:root[data-admin-density="comfortable"]` 覆盖其中 8 项（row-padding-y `0.5rem`、control-height `2.25rem` …）。三个 layout 输出 `data-admin-density="compact"`。

> **重要实现发现（已写入 admin Skill）**：Tailwind v4 默认会把“仅定义、未被 utility 引用”的主题变量**摇树掉**——首轮构建后产物里 `--color-accent-950`/`--color-surface-muted` 均为 0 处；改用 `@theme static` 后全部 token 恒定输出（产物 247.1KB → 248.6KB）。否则宿主覆盖与 B6-2/B6-3 会引用到不存在的变量。

### 9.4 对比度实测（FR-007）

| 组合 | 前景 / 背景 | 阈值 | 实测 |
|---|---|---|---|
| 正文 | `--color-text` / `--color-surface` | ≥4.5 | **17.74** |
| 次要文字 | `--color-text-muted` / `--color-surface` | ≥4.5 | **7.56** |
| 弱化文字 | `--color-text-subtle` / `--color-surface` | ≥4.5 | **4.83** |
| 主按钮（白字 / 主色底） | `#FFFFFF` / `--color-primary-600` | ≥4.5 | **5.87** |
| 主按钮 hover（白字 / -700） | `#FFFFFF` / `--color-primary-700` | ≥4.5 | **8.00** |
| 链接主色 / 白底 | `--color-primary-600` / `--color-surface` | ≥4.5 | **5.87** |
| 焦点环 / 白底 | `--color-focus-ring` / `--color-surface` | ≥3.0 | **3.81** |
| 次要按钮文字 / 浅底 | `--color-primary-900` / `--color-primary-50` | ≥4.5 | **12.55** |

`--color-border` / `--color-border-strong` 为**装饰/分隔**用途（非控件边界的唯一识别手段），不计入对比度门槛；控件状态由焦点环（≥3）与主色承担。

### 9.5 运行期验证（DOM 计算样式，/admin_user/sign_in）

```json
{ "density": "compact", "densityControlHeight": "2rem", "densityLineHeight": "1.25rem",
  "primary600": "#1C66B0", "accent500": "#20EADD", "surfaceMuted": "#F9FAFB",
  "btnBg": "rgb(28, 102, 176)", "bodyFontSize": "14px", "bodyLineHeight": "21px" }
```

切换 `data-admin-density` → `comfortable` 时 `--admin-density-control-height` 由 `2rem` → `2.25rem`（机制生效）；控件实际高度未变（`input 34.6px`）——**B6-1 只提供机制，组件接线属 B6-2**（预期）。

---

## 10. 文档同步清单（知识同步门）

- [x] Skill：`pallastrade-admin`（新增「Design tokens & density（B6-1）」小节：token 层级 / `@theme static` 缘由 / 密度双档 / 宿主覆盖 / `admin-theme-rspec` / 构建与重启注意；决策树增一行）
- [x] `AGENTS.md` §6 验证表（新增：「Admin 样式 / 设计 token → `harness verify admin-theme-rspec`」）
- [x] 场景库：`harness/scenarios/scenarios.json` 新增 GS-125（后台 token/密度契约）
- [ ] 本 PRD 状态 + `docs/prd/README.md` 索引（`prd-status-sync --fix/--check`）
- [x] 已评估项：`docs/standards/README.md`（规范索引，无设计 token 条目 → 本批不新增指引文件）；`pallastrade-storefront`（前台零改动）；`pallastrade-api-v3`（无接口变更）

### 10.1 sync-check 逐项结论（2026-09-15）

| 触发组 | 需评估资产 | 结论 |
|---|---|---|
| 样式 / 设计 token | 样式规范（CLAUDE.md / Skill Style Guide 章节） | ✅ `pallastrade-admin` Skill 新增「Design tokens & density（B6-1）」+ 决策树增行；`storefront/CLAUDE.md` 管前台，与本批无关 |
| 样式 / 设计 token | AP-006 检查 | ✅ 已评估：AP-006 的 `fileGlob` 仅覆盖 `storefront/src/**`，后台 gem CSS 不在扫描面；且本批新增色值**只出现在 `_theme.css` token 定义**，组件层改走 `var()/utility`（spec 断言零直引） |
| 样式 / 设计 token | E2E 截图证据 | ✅ 已采集：`/admin_user/sign_in` 截图 + DOM 计算样式（§9.5）+ 构建产物 token grep + 被服务 CSS 校验 |
| Skill / PRD 机制 | `AGENTS.md` | ✅ 已更新（§6 验证表新增 `admin-theme-rspec` 行）；`copilot-instructions.md` / `pallastrade-prd` Skill 无机制变更 → 已评估无需更新 |
| Skill / PRD 机制 | 场景库 | ✅ GS-125（`eval-ai --scenarios` 126/126） |

## 11. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-15 | 0.1 | 初稿：用户已确认「分三批 / 品牌 navy+teal / 默认 compact」→ 本批为 B6-1 基础层（token + 密度变量 + 主色品牌化 + 对比度契约 + spec/verifier） | AI |
| 2026-09-15 | 0.2 | 实施完成：① 实测值回填（§9.1 色阶表 / §9.4 对比度 8 组 / §9.5 DOM 计算样式）；② 关键发现：Tailwind v4 对未使用主题变量**摇树** → 改用 `@theme static` 保证 token 恒定输出（否则宿主覆盖与 B6-2/3 引用到空值），已写入 admin Skill；③ 主色消费点范围：`.btn-primary`/`.btn-secondary`/`.nav-pills .nav-link{,.active}`/`.nav-link:hover` + 新增 `.btn:focus-visible` 焦点环；`badge-info`（info 状态色）与其余中性色归 B6-2；④ 新增 verifier `admin-theme-rspec`；⑤ 本地验证教训：Rails 进程缓存模板与资产清单 → 改 layout/主题后需重启 web 进程才生效 | AI |
