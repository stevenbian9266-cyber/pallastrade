# REQ-20260918-admin-nav-fund

> **类型**：功能优化（`feature` gate）｜**任务**：`TASK-20260918134623-fb1c3519`
> **PRD**：`docs/prd/admin/PRD-20260918-admin-管理后台导航settings收起展开与新增fund一级菜单.md`
> **一句话需求原文**：
> 1、管理后台settings菜单，做收起、展开交互操作，点击收起将settings下的子菜单全部收起，点击展开将settings菜单下的子菜单全部展开
> 2、管理后台新增一级菜单Fund，将order菜单中和资金有关的子菜单移到Fund菜单下

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | `admin.navigation` / `sidebar_nav` / `add_nav_item` | 无命中 | 宿主不注册侧边栏项 → 无需改动 |
| App — views/decorators | `backend/app/` | `sidebar` / `data-controller="sidebar"` | 无命中（布局与侧边栏 partial 均在 gem 内） | 无需改动 |
| Core Gem — models | `backend/pallastrade_gems/pallastrade_core/app/models/` | `admin.navigation` | `pallastrade/menu_config.rb`（读 `PallasTrade.admin.navigation.sidebar` 生成只读菜单配置） | 已有能力，**自动跟随**结构变化 |
| Core Gem — services | `backend/pallastrade_gems/pallastrade_core/app/services/` | `navigation` / `sidebar` | 无命中 | 无需改动 |
| API Gem — controllers | `backend/pallastrade_gems/pallastrade_api/app/controllers/` | `navigation` | 无命中 | 无需改动 |
| Admin Gem — controllers | `backend/pallastrade_gems/pallastrade_admin/app/controllers/` | `breadcrumb` / `skip_breadcrumb_derivation` | `payment_risk_controller.rb`（**并行会话未提交版本**含手写 crumb；HEAD 为自动推导） | 本任务不新增面包屑代码（自动推导）；冲突见「风险点」 |
| Admin Gem — views | `backend/pallastrade_gems/pallastrade_admin/app/views/` | `section_label` / `render_navigation` / `sidebar` / `nav-section-header` | `shared/_sidebar.html.erb`、`shared/sidebar/_store_nav.html.erb`、`shared/_header.html.erb`（整体折叠按钮）、`menu_configs/index.html.erb`（只读菜单树） | 已有能力 + **需扩展**：分区标题目前无折叠交互 |
| Admin Gem — 导航权威/渲染/JS | 同上（config/helpers/models/javascript/assets） | `collapsible` / `nav-submenu` / `sidebar_controller` | ① `config/initializers/pallastrade_admin_navigation.rb` ② `app/helpers/pallastrade/admin/navigation_helper.rb`（`render_nav_section_header` L454）③ `app/models/pallastrade/admin/navigation/{navigation,item,builder}.rb` ④ `app/javascript/pallastrade/admin/controllers/sidebar_controller.js`（挂 `<body>`）⑤ `assets/tailwind/.../components/{_navigation,_layout}.css` | **本需求主战场**（需新建：分区折叠能力 + Fund 一级菜单） |
| Storefront | `storefront/src/` | `sidebar` / `Settings` | 仅站点自身布局侧栏（结账摘要 / 账户中心） | 不适用（非管理后台） |
| Platform | `platform/packages/` | `sidebar` / `Orders` | `dashboard`（React SPA，独立路由与菜单）、`cli`（文档 frontmatter 的 `sidebarTitle`） | 不适用（本次范围仅 Rails 管理后台） |

### 搜索结论

- 管理后台侧边栏导航的**唯一权威**是 `pallastrade_admin_navigation.rb`；渲染链为
  `sidebar_nav`（配置树）→ `NavigationHelper#render_navigation(:sidebar)`（`nav_item` / `render_nav_item_with_children` / `render_nav_section_header`）
  → `sidebar_controller.js`（Stimulus，挂在 `<body data-controller="admin sidebar …">`）。
- `Settings` 现状 = **分区标题（section_label）**，其下条目是**同级兄弟项**（position 94~200），
  因此折叠必须作用于「标题之后的同级元素集合」，而非「children」。
- 已有能力：① 侧边栏**整体**折叠（icon-only，`sidebar#toggle` + localStorage `pallastrade_admin_sidebar_open`）；
  ② 带子菜单项的「激活时展开」；③ 面包屑自动推导（`find_breadcrumb_nodes`，沿 `parent_key` 回溯）。
- 需要新建：① 分区级收起/展开（服务端声明 + 前端交互 + 状态记忆 + 激活自动展开）；
  ② `Fund` 一级菜单（16 个子项从 `orders` 平移，键位不变）。
- **防重复判定**：不新增侧边栏渲染器、不新增权限模型、不新增路由/接口；仅扩展导航模型（`collapsible`）、
  渲染器（section header 渲染为开关）与既有 Stimulus 控制器。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：「Add a menu item / nav entry to the admin → `PallasTrade.admin.navigation.sidebar.add` → **pallastrade-admin**」；优先级顺序 Settings → Configuration → Events → Dependencies → **Admin / Ransack APIs** → Generators → Decorators → Extensions ⇒ 本需求落在「Admin API」层（改导航配置 + 渲染层），**不得**使用 decorator / 复制视图到宿主。 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | 「统一单一侧边栏（P6）」表：**落地**「有子项的顶级必须 `landing: <第一个子项>`；顶级点击 → 落地子项页」+「**新增带子菜单模块必须声明 landing**」；**i18n**「新增 String 型 label（含 `.`）必须 en + zh-CN 双语（gem `en.yml` + `backend/config/locales/admin_nav.zh-CN.yml`）」；**校验**「`harness nav:validate` 强制：landing 存在性、tabs 已注册、i18n 双语、permission-only `if:`、常显原则」；禁忌「不要在 action 内手写 `add_breadcrumb` 拼模块/子页 crumb（已自动推导）」。 |
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已读 | 目录域（Product/Variant/分类/搜索）本需求不触碰；仅确认 `catalog_health` / `duplicate_products` 的导航断言位于 **products 子树**（`sidebar.find(:products)`），Orders→Fund 迁移不影响它们。 |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-testing` | ✅ 是 | ✅ 已读 | 技术栈 RSpec + Factory Bot + Capybara；「**Always use factories — never call `Model.create` directly in tests**」；admin request spec 惯例：`sign_in admin` + 对控制器 `allow_any_instance_of(Klass).to receive(:current_store)`（本仓库 `navigation_consistency_spec.rb` 既有写法）。 |
| `pallastrade-i18n` | ✅ 是（新增键） | ✅ 已读（仓库记忆 `pallastrade-admin-i18n-gotcha`） | admin UI 语言 = `current_store.preferred_admin_locale`；gem 仅提供 **en**，zh-CN 在宿主 `backend/config/locales/admin_*.zh-CN.yml`。**只加 en 时所有 spec 也不会红**，中文后台会静默整页 `Translation missing` ⇒ 新键必须 **en + zh-CN 双侧**并做双向键集断言。 |
| `pallastrade-api-v3` | ⬜ 否 | — | 不涉及接口/序列化/Ransack。 |
| `pallastrade-decorators` | ⬜ 否 | — | 不改 PallasTrade 模型/控制器结构（导航为配置驱动）。 |
| `pallastrade-dependencies` | ⬜ 否 | — | 不替换核心服务。 |
| `pallastrade-events-webhooks` | ⬜ 否 | — | 无副作用/事件。 |
| `pallastrade-storefront` | ⬜ 否 | — | 前台不受影响。 |

---

## 需求标题

管理后台导航：Settings 分区收起/展开 + 新增 Fund 一级菜单（迁移 16 个资金类子项）

## 任务类型

功能优化（前端交互 + 信息架构调整）

## 需求描述

1. 侧边栏 `Settings` 分区支持一键收起 / 展开：点击收起 → 该分区下所有条目（含带子菜单项的二级菜单与 hover 下拉）全部隐藏；再点击 → 全部展开；刷新后保持上次状态；当前页位于该分区内时强制展开。
2. 新增一级菜单 `Fund`，把 `Orders` 下 **16 个**资金 / 支付 / 风控子项移入（键位不变），`Orders` 只保留 3 个订单作业子项（All Orders / Orders to Fulfill / Draft Orders）。

## 影响范围（`harness affected --base origin/dev` 输出）

```json
{ "filesChanged": 15, "affectedComponents": ["ai", "backend", "harness", "storefront"], "errors": [], "estimatedTests": 45 }
```

> 注：`filesChanged: 15` 包含**并行会话未提交文件**（storefront wallet / TS serializer / payment_risk 控制器 / admin SKILL）。
> 本任务自身改动面见 §技术方案（8 个文件，全部在 `pallastrade_admin` gem + 宿主 locale + spec）。

## 技术方案（初步）

| # | 变更 | 说明 |
|---|---|---|
| 1 | `pallastrade_admin_navigation.rb` | 新增 `fund`（`label: 'admin.fund.title'`、`icon: 'wallet'`、`position: 22`、`landing: :transactions`，子项 16 个按资金生命周期排序）；`orders` 移除 16 子项；`settings_section` 增 `collapsible: true` |
| 2 | `navigation/item.rb` | 新增 `collapsible` 属性（attr_accessor + initialize + `to_h`）与 `collapsible?` |
| 3 | `navigation_helper.rb` | `render_nav_section_header`：`collapsible` 分区渲染为 `<li data-nav-section-toggle="settings">` + `<button type="button" aria-expanded>`（chevron + 文案）；颜色走语义 token |
| 4 | `sidebar_controller.js` | 新增 `toggleSection(event)`；`connect()` 内恢复状态（localStorage `pallastrade_admin_nav_section_settings`，默认展开）；存在激活项 → 强制展开；作用域 = 同级元素直到下一个 `[data-nav-section-toggle]` |
| 5 | `_layout.css` | 分区标题开关样式（hover / focus-visible / 收起态 chevron 旋转） |
| 6 | `en.yml` + `admin_nav.zh-CN.yml` | `pallastrade.admin.fund.title`（Fund / 资金）+ 折叠开关无障碍文案（双语） |
| 7 | `navigation_consistency_spec.rb` | Orders children 断言 → 3 项；新增 Fund 16 项断言；面包屑 Orders→Fund |
| 8 | `nav_collapsible_fund_spec.rb`（新增） | AC-001/003/005/006/007 的服务端渲染与结构断言 |

**面包屑**：`find_breadcrumb_nodes` 沿 `parent_key` 自动推导 ⇒ 迁移后自动变为「Fund > 子项」，控制器零改动（符合 Skill 禁忌条款）。

## 风险点

| 风险 | 影响 | 处置 |
|---|---|---|
| **并行会话未提交改动**（`navigation_consistency_spec.rb` 删 82 行、`payment_risk_controller.rb` 改回手写 crumb、`ai/skills/pallastrade-admin/SKILL.md` -19 行） | ① 若其手写 crumb 落地，`/admin/payment_risk` 会显示「Orders > Payment Risk」，与 Fund 层级冲突；② 同文件提交可能「顺带提交」对方工作 | 不触碰对方文件；AC-004 面包屑矩阵暂排除 `payment_risk` 并在 spec 注释说明；提交时用「HEAD 版本 + 我的 hunk」策略，事后把对方版本还原到工作区（见仓库记忆 `pallastrade-concurrent-session-hazards`） |
| 折叠作用域 DOM 结构（带子菜单项会额外产生 `nav-submenu` / `nav-submenu-dropdown` **同级**节点） | 只隐藏 `<li>` 会残留子菜单 | 作用域按「下一个分区标题之前的全部同级元素」计算；spec 断言同一 `<ul>` 内三者均被标记/隐藏 |
| 12 个 harness 验证器引用导航 spec | 迁移后旧断言失败 | 同步更新 spec；跑代表性验证器（`admin-catalog-health-rspec`、`admin-i18n-rspec`、`admin-theme-rspec`） |
| 中文后台静默缺译文 | 中文门店出现 `Translation missing` | 新键 en + zh-CN 双侧新增 + spec 断言 |

## 决策节点

> ⏸️ **请确认以上理解是否正确（含 Fund 的 16 个子项清单与排序、Settings 折叠行为）。确认后进入实施。**

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| 导航配置 / 渲染器 / 模型（Ruby） | 见 §技术方案 1-3、7、8 | `harness check --profile quick`（含 nav-validate 插件） | | ⬜ |
| 导航行为回归 | `navigation_consistency_spec.rb` | `harness verify admin-catalog-health-rspec`（含导航 spec） | | ⬜ |
| 新增结构断言 | `nav_collapsible_fund_spec.rb` | docker rspec（两文件合跑） | ✅ **43 examples, 0 failures**（nav_collapsible_fund 10 + navigation_consistency 33） | ✅ |
| 导航 schema（权威校验器） | `pallastrade_admin_navigation.rb` | `bin/rails pallastrade:admin:nav_validate` | ✅ 改动前后均 `nav:validate OK — 0 warning(s)`（landing/双语/permission-only if/常显） | ✅ |
| 样式（css） | `_layout.css` | `harness verify admin-theme-rspec` + 构建产物断言 | ✅ 构建产物含 `.nav-section-toggle-btn`(L5604) `:hover`(5626) `:focus-visible`(5629) `.nav-section-chevron`(5637) 折叠旋转(5644) icon-only 隐藏(5647)；验证器结果见下 | ⬜ |
| i18n | `en.yml` / `admin_nav.zh-CN.yml` | `harness verify admin-i18n-rspec` | | ⬜ |
| 前端交互（JS） | `sidebar_controller.js` | DOM 级交互验证（真实下发 JS + 真实构建 CSS + 与渲染同构 DOM） | ✅ 收起 → 分区内 5/5 同级元素（含 `ul.nav-submenu`/`ul.nav-submenu-dropdown`）隐藏、aria-expanded=false、写入 localStorage；刷新保持；分区内页面强制展开；分区外 Orders 不受影响。证据：`artifacts/harness-evidence/20260918-admin-nav-collapse-fund.md`（**局限**：非登录态真实页面点击） | ✅ |

### 新增 admin 页面三要素检查（固定检查项）

> 本任务**不新增页面**（仅调整导航与侧边栏交互），故「页面标题 / 面包屑 / 操作按钮」三要素沿用既有页面；
> 但迁移会使 16 个既有页面的**面包屑层级**变化（Orders → Fund），必须逐项核对。

| 检查项 | 页面（路径） | 是否符合 | 备注 |
|---|---|---|---|
| ① 页面标题（page_title / 页面头 h3） | `/admin/payouts` 等 16 页 | ⬜ | 不涉及改动，抽查确认未受影响 |
| ② 面包屑（自动推导） | `/admin/payment_costs`、`/admin/payouts`、`/admin/reconciliation_cases`… | ⬜ | 期望「Fund > 子项」；`payment_risk` 暂列外（并行冲突） |
| ③ 页面操作按钮（page_actions）与返回路径 | 同上 | ⬜ | 不涉及改动，抽查确认未受影响 |
| ④ POST/PATCH/DELETE 用 `data: { turbo_method: }` | — | ⬜ | 不涉及（无新增表单/动作） |

### 验证结论

<!-- 实施后填写：命令 + 结果 + 结论 -->
