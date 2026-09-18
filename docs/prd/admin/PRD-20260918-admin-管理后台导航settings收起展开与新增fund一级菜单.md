# PRD-20260918-admin-管理后台导航settings收起展开与新增fund一级菜单

| 元数据 | 值 |
|---|---|
| 状态 | implementing |
| 创建日期 | 2026-09-18 |
| 来源 | 优化：管理后台导航Settings收起展开与新增Fund一级菜单 |
| 分类 | admin（自动判定，关键词命中 3） |
| 关联 Skill | pallastrade-admin |
| 关联 REQ | `harness/requirements/REQ-20260918-admin-nav-fund.md` |
| 关联 PRD | N/A —— 查重命中 2 个**已 done** 的导航类 PRD（20260816 导航一致性 / 20260816 P6 导航架构重构），均属已收口历史交付；本需求是**新增能力**（分区折叠交互 + 信息架构调整），非其 AC 的回写，故 `--force` 新建 |
| 需求类型 | 优化迭代 |

## 1. 背景与目标

### 1.1 一句话需求原文

1、管理后台settings菜单，做收起、展开交互操作，点击收起将settings下的子菜单全部收起，点击展开将settings菜单下的子菜单全部展开
2、管理后台新增一级菜单Fund，将order菜单中和资金有关的子菜单移到Fund菜单下

### 1.2 背景（现状核查，2026-09-18 代码走查）

- 侧边栏为**单一导航树**（P6 重构后主区/设置区已统一）：`PallasTrade.admin.navigation.sidebar`，渲染入口 `render_navigation(:sidebar)`（`shared/sidebar/_store_nav.html.erb`）。
- `Settings` 目前只是**分区标题**：`sidebar_nav.add :settings_section, section_label: 'Settings', position: 90`，渲染为 `<li class="nav-item nav-section-header">…</li>`；其下条目（Store Details / Users / Policies / Storefront / Channels / Payment Methods / Markets / Zones / Shipping / Tax / Return Settings / Stock Locations / Metafield Definitions / Audit Log / Developers / Back-in-stock / Abandoned carts / Reviews / Menu Configs / Edit Profile，position 94~200）都是它的**同级兄弟项**，**没有任何折叠能力**。
  - 副作用：设置区条目多（20 项）且不可收起，日常操作主区菜单时噪音大。
- `Orders` 已膨胀到 **19 个子项**：3 个订单作业（All Orders / Orders to Fulfill / Draft Orders）+ **16 个资金/支付/风控工作台**（D2/D12/D13/D13b/D13c/D13d/D14/D14b/D14c/D15/D15b/D16/D3 系列交付物）。
  - 问题：把「订单作业」与「资金核算 / 支付成本 / 汇率 / 争议 / 风控」混在同一一级菜单，子项长度已超出浏览耐受度，且与「订单」心智模型不符。

### 1.3 目标

1. `Settings` 分区支持**一键收起 / 展开**：点击收起 → 该分区下所有条目（含带子菜单项的二级菜单与 hover 下拉）全部隐藏；点击展开 → 全部显示。
2. 新增一级菜单 **Fund**，承载 16 个资金 / 支付 / 风控子项；`Orders` 回归纯订单作业（3 项）。
3. 面包屑随导航层级**自动推导**（`Orders > X` → `Fund > X`），不新增控制器手写 crumb。
4. en / zh-CN 双语文案齐备（Fund 标题 + 折叠开关无障碍文案）。

### 1.4 成功指标

- `Orders` 子项数 19 → 3；`Fund` 子项数 = 16，顺序符合资金生命周期。
- Settings 收起 / 展开为**点击一次即可生效**，刷新后状态保持；无 JS 时默认全展开（渐进增强）。
- 引用 `spec/requests/pallastrade/admin/navigation_consistency_spec.rb` 的 **12 个 harness 验证器**保持全绿。
- zh-CN 后台无 `translation missing`（Fund 标题、折叠开关文案）。

### 1.5 非目标（本批不做）

- 不改导航权限模型（`menu_permissions` 键位不变）；不改菜单配置页逻辑（只读，自动跟随）。
- 不改任何业务控制器行为；不改 Admin API / DB / 迁移。
- 不改「侧边栏整体折叠（icon-only）」既有交互与其 hover 下拉逻辑。
- 不重排 Settings 分区内的条目顺序（仅新增折叠能力）。

## 2. 用户故事 / 场景

- 作为运营管理员，我希望一键收起 Settings 分区，以便在长侧边栏中快速聚焦主区菜单（Orders / Products / …）。
- 作为运营管理员，我希望资金相关工作台（对账、结算、退款审批、费率、汇率、争议、风控…）集中在 Fund 下，以便按「资金」心智模型找到入口。
- **正常流 1**：进入后台 → Settings 默认展开 → 点击 Settings 行 → 分区内条目全部收起，箭头与 `aria-expanded` 同步为收起态。
- **正常流 2**：再次点击 → 全部展开；刷新页面后保持上次状态（localStorage）。
- **正常流 3**：点击 Fund → 落到 landing 子项（默认第一个可见子项 = 交易）；进入任一子页，面包屑显示「Fund > 支付成本」。
- **边界 1**：当前页位于 Settings 分区内（如 Policies）→ 即使记忆为「已收起」，也强制展开并保持当前项高亮。
- **边界 2**：无 JS（或 JS 异常）→ 分区保持展开，功能不受影响（渐进增强）。
- **边界 3**：DB 菜单权限驱动的角色 → Fund 顶级项仅在其任一子项被授权时出现；子项按原权限键过滤（键位不变）。
- **边界 4**：移动端（`sidebar-mobile`）渲染同一导航树 → 折叠交互同样生效（两份 DOM 各自维护状态）。
- **异常**：localStorage 不可用（隐私模式 / 配额异常）→ 忽略持久化，交互可用，默认展开。

## 3. 功能需求（FR）

- **FR-001**：`Settings` 分区标题渲染为**可折叠开关**：`<li class="nav-item nav-section-header" data-nav-section-toggle="settings">` 内为 `<button type="button" aria-expanded="true|false">`（chevron 图标 + 文案），保留原有视觉（分区分隔线、大写标签）。键盘可达（原生 button）。
- **FR-002**：折叠作用域 = **该分区标题之后、直到下一个分区标题（或列表结束）的全部同级导航元素**，包含带子菜单项产生的 `<ul class="nav-submenu">` / `<ul class="nav-submenu-dropdown">` 兄弟节点。实现不得依赖「逐项打标」（避免漏掉 submenu/dropdown 兄弟节点）。
- **FR-003**：状态持久化于 localStorage（键 `pallastrade_admin_nav_section_settings`，与既有 `pallastrade_admin_sidebar_open` 约定一致），缺省为展开。
- **FR-004**：若当前页命中该分区内任一条目（DOM 内存在激活的 `.nav-link.active`），**强制展开**（优先于记忆状态），并同步 `aria-expanded="true"`。
- **FR-005**：新增一级菜单 `fund`：`label: 'admin.fund.title'`、`icon: 'wallet'`（Tabler webfont CDN）、`position: 22`（紧跟 `orders`=20 之后、`returns`=25 之前）、`landing` 未指定（= 第一个可见子项）、`if:` 与子项权限一致（任一子项可见即顶级项可见）。
- **FR-006**：将下列 **16 个子项**从 `orders` 迁移到 `fund`（**键位保持不变**，权限与 active 条件一并平移）：`transactions`、`payments_ops`、`payment_combinations`、`refunds`、`refund_approvals`、`disputes_ops`、`dispute_rates`、`reconciliation_cases`、`payouts`、`currency_rates`、`fx_snapshots`、`payment_costs`、`payment_fee_policies`、`risk_lists`、`risk_rules`、`payment_risk`；`orders` 仅保留 `all_orders` / `orders_to_fulfill` / `draft_orders`。
- **FR-007**：Fund 内子项顺序（资金生命周期序）：交易 → 支付 → 组合支付 → 退款 → 退款审批 → 争议 → 拒付率 → 对账队列 → 结算台账 → 汇率表 → 汇率快照 → 支付成本 → 费率策略 → 风控名单 → 风控规则 → 风控看板。
- **FR-008**：面包屑随层级自动推导为「Fund > 子项」；**不得**在任何控制器内手写 Fund 层级 crumb（延续 2026-09-18 面包屑单一推导契约）。
- **FR-009**：i18n：`pallastrade.admin.fund.title`（en: `Fund` / zh-CN: `资金`）在 **en 与 zh-CN 两侧**新增；折叠开关无障碍文案新增键（en + zh-CN）。
- **FR-010**：新增/改动样式走**语义 token**（不得直引 Tailwind 调色板，遵循 `admin-theme-rspec` 契约）。
- **FR-011**：`/admin/menu_configs`（只读菜单配置页，由 `PallasTrade.admin.navigation.sidebar` + `PallasTrade::MenuConfig` 生成）自动反映 Fund 结构，无需改代码，但需回归断言。

## 4. 非功能需求（NFR）

- **兼容**：不破坏 `render_navigation_item` / `render_nav_item_with_children`、icon-only 折叠态、hover dropdown、移动端侧栏。
- **性能**：无新增 DB 查询（导航树初始化时构建；折叠为纯前端 DOM 操作）。
- **可维护性**：分区折叠能力由导航模型声明（`collapsible`），渲染层与 JS 单一职责；不引入逐项标记。
- **可测试**：服务端渲染可断言（button / aria / data 属性 + Fund 结构）；交互行为以浏览器 DOM 证据验证。
- **安全 / 权限**：权限键位不变；不新增接口；不改 `if:` 语义。
- **国际化**：en / zh-CN 双侧键集齐备。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001** ← FR-001/FR-010：Settings 分区标题渲染为 button（含 `data-nav-section-toggle="settings"`、`aria-expanded`），样式走语义 token，无直引调色板。
- **AC-002** ← FR-005/FR-006/FR-007：`sidebar.root_items` 含 `:fund`，`fund.children` 精确等于 16 项且顺序符合 FR-007；`orders.children` 精确等于 3 项。
- **AC-003** ← FR-005：Fund 渲染为可展开父项（含 `nav-submenu` 容器，顶级链接指向第一个可见子项），位置在 Orders 之后、Returns 之前。
- **AC-004** ← FR-008：Fund 子页面包屑为「Fund > 子项」且无重复层级（沿用 AC-012 修复后的单一契约；**payment_risk 暂列矩阵之外**，原因见 §7.1）。
- **AC-005** ← FR-009：`pallastrade.admin.fund.title` en / zh-CN 双侧存在且非空；相关页面无 `translation missing`。
- **AC-006** ← FR-011：`/admin/menu_configs` 页面展示 Fund 及其子项（与导航配置同源）。
- **AC-007** ← 权限：菜单权限仅授权 Fund 子集时，Fund 顶级项可见且仅显示被授权子项。
- **AC-008** ← FR-002/FR-003/FR-004（交互）：浏览器实测——点击收起 → 分区内条目与子菜单全部隐藏；刷新后保持；进入分区内页面自动展开（DOM 证据 + 截图）。
- **AC-009**：既有回归——`navigation_consistency_spec` 全绿（Orders / Products / Customers / Promotions / Reports / Blog / Returns 结构断言不回归）；`menu_config_spec` 全绿。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `admin.navigation` / `sidebar_nav` / `add_nav_item` | 无命中（宿主不注册侧边栏项） | 无需改动 |
| Core | `pallastrade_gems/pallastrade_core/app/` | `admin.navigation` | `app/models/pallastrade/menu_config.rb`（读 sidebar 树生成只读菜单配置） | 自动跟随，无需改动 |
| API | `pallastrade_gems/pallastrade_api/app/` | `navigation` / `sidebar` | 无命中 | 无需改动 |
| Admin | `pallastrade_gems/pallastrade_admin/` | `section_label` / `render_navigation` / `nav-submenu` / `sidebar` | ① `config/initializers/pallastrade_admin_navigation.rb`（导航权威）② `app/helpers/pallastrade/admin/navigation_helper.rb`（渲染器）③ `app/models/pallastrade/admin/navigation/{navigation,item,builder}.rb` ④ `app/javascript/pallastrade/admin/controllers/sidebar_controller.js`（挂在 `<body>`）⑤ `app/assets/tailwind/.../components/{_navigation,_layout}.css` ⑥ 宿主 `backend/config/locales/admin_nav.{en,zh-CN}.yml` | **本需求主战场** |
| Storefront | `storefront/src/` | `sidebar` / `Settings` | 仅站点自身布局侧栏（结账摘要、账户中心） | 不适用（非管理后台） |
| Platform | `platform/packages/` | `sidebar` / `Orders` | `dashboard`（React SPA，独立路由）、`cli` 模板与文档（`sidebarTitle` 为文档 frontmatter） | 不适用（本次范围仅 Rails 管理后台） |

**结论**：管理后台侧边栏导航的**唯一权威**是 `pallastrade_admin_navigation.rb`；渲染器与 Stimulus 控制器为唯二改动点；Core `MenuConfig` 与 `/admin/menu_configs` 自动跟随。宿主 App / API / Storefront / Platform 无同构能力，无重复实现风险。

## 7. 技术影响

**改动文件**

| 文件 | 变更 |
|---|---|
| `backend/pallastrade_gems/pallastrade_admin/config/initializers/pallastrade_admin_navigation.rb` | 新增 `fund` 一级菜单（16 子项迁移）；`settings_section` 声明 `collapsible: true` |
| `.../app/models/pallastrade/admin/navigation/item.rb` | 新增 `collapsible` 属性（attr + initialize + `to_h`） |
| `.../app/helpers/pallastrade/admin/navigation_helper.rb` | `render_nav_section_header` → 可折叠开关（button + data + aria）；语义 token |
| `.../app/javascript/pallastrade/admin/controllers/sidebar_controller.js` | 分区折叠/记忆/激活自动展开（connect 时恢复，含 no-transition 窗口内应用） |
| `.../app/assets/tailwind/pallastrade/admin/components/_layout.css` | 分区标题开关样式（含 hover/focus、折叠态） |
| `pallastrade_admin/config/locales/en.yml` + `backend/config/locales/admin_nav.{en,zh-CN}.yml` | `admin.fund.title` + 折叠开关文案（双语） |
| `backend/spec/requests/pallastrade/admin/navigation_consistency_spec.rb` | Orders→Fund 结构断言 + 面包屑期望 |
| `backend/spec/requests/pallastrade/admin/nav_collapsible_fund_spec.rb`（新增） | 见 §8 |

**影响面**：无 DB / 无 API / 无迁移；12 个 harness 验证器引用导航 spec，须同步跑通。

### 7.1 已知风险与并行会话冲突（重要）

- 工作区存在**并行会话未提交改动**：`navigation_consistency_spec.rb`（删 AC-012 面包屑块，-82 行）、`payment_risk_controller.rb`（**改回手写面包屑** `add_breadcrumb :orders`）、`ai/skills/pallastrade-admin/SKILL.md`（-19 行）等；疑似「旧编辑器快照静默回退」（见仓库记忆 `pallastrade-concurrent-session-hazards` §5c）。
- 若对方的**手写面包屑**落地，`/admin/payment_risk` 将显示「Orders > Payment Risk」，与 Fund 层级冲突。
- **处置（实际执行）**：本任务不触碰对方文件；采用「提交我自己的版本（HEAD + 我的改动）、事后把对方的未提交增量还原到工作区」的方式，双方工作均不丢失。
- **AC-004 边界**：Fund 面包屑矩阵**暂不含 `/admin/payment_risk`**（对方 worktree 版控制器会叠加「Orders > Payment risk」，实测得到 `Fund > Payment risk > Orders > Payment risk`），spec 内已注释原因；**遗留项**：待对方收尾后把该页补回矩阵。
- **实现细节补充**：`Fund` 的 `landing` 显式声明为 `:transactions`（导航校验器要求“有子项的顶级必须声明 landing”）。

## 8. 测试计划

| AC | 测试 | 说明 |
|---|---|---|
| AC-001 | `spec/requests/pallastrade/admin/nav_collapsible_fund_spec.rb` | 断言 section header 为 button + `data-nav-section-toggle` + `aria-expanded` + 语义 token class |
| AC-002/003/009 | `nav_collapsible_fund_spec.rb` + `navigation_consistency_spec.rb` | `fund.children` == 16 项顺序；`orders.children` == 3 项；渲染含 `nav-submenu` |
| AC-004 | `navigation_consistency_spec.rb` | 15 个 Fund 子页面包屑 == [Fund, 子项]（payment_risk 暂除外） |
| AC-005 | `nav_collapsible_fund_spec.rb` | en / zh-CN 双侧键存在；页面无 `translation missing` |
| AC-006 | `nav_collapsible_fund_spec.rb` | `/admin/menu_configs` 渲染含 Fund 标题与子项 |
| AC-007 | `nav_collapsible_fund_spec.rb` | 菜单权限子集 → Fund 可见但仅显示授权子项 |
| AC-008 | 浏览器实测（本地 dev 后台） | 收起/展开 + 刷新保持 + 分区内页面自动展开（DOM/截图证据） |

**回归**：`harness verify admin-catalog-health-rspec`（引用导航 spec 的代表性验证器）、`admin-theme-rspec`、`admin-i18n-rspec`；`harness check --profile quick`。

**AC-008 实证方式（实施期调整，局限已标注）**：本地 dev 后台需管理员登录（凭证与文档默认值不符，密码不经手模型），仓库无 system/JS 测试基建 ⇒ 改用「**应用真实下发的控制器 JS + 真实构建 CSS + 与渲染同构的 DOM**」的临时探针页验证并已删除探针：
收起 → 分区内 5/5 同级元素（含 `ul.nav-submenu` / `ul.nav-submenu-dropdown`）全部隐藏、aria-expanded=false、状态写入 localStorage；刷新后保持收起；当前页在分区内时强制展开；分区外 Orders 不受影响。证据：`artifacts/harness-evidence/20260918-admin-nav-collapse-fund.md`。

## 9. 文档同步清单（知识同步门）

- [ ] 不涉及 API → 无需 OpenAPI / SDK 文档同步
- [ ] `ai/skills/pallastrade-admin/SKILL.md`：补「侧边栏分区折叠（collapsible section）」+「Fund 一级菜单 IA」章节（⚠️ 与并行会话同文件，提交策略见 §7.1）
- [ ] `harness/scenarios/scenarios.json`：Skill 变更需同步 Eval 场景（doc-impact 规则）
- [ ] `docs/prd/README.md`：登记本 PRD 索引
- [ ] `harness sync-check --id <PRD-ID>` → `--ack`

## 11. 行为修正 v1.1（2026-09-18，用户实测反馈）

> 背景：v1.0 交付后用户反馈「Settings 展开时出现菜单浮层」「默认应为收起」「展开后应先只显示二级」。
> 本节覆盖 v1.0 中与之冲突的表述（FR-003 / FR-004 / AC-008）。

**修正后的目标行为（用户答复原文为准）**

| # | 行为 |
|---|---|
| A | Settings **默认收起**（首次进入不显示分区内条目）；分区行有**方向图标**，点击切换展开/收起 |
| B | 展开后**只显示二级菜单**；三级保持收起（不出现 hover 浮层） |
| C | 点击二级菜单 = **导航到落地页（即第一个三级）并展开其三级菜单**（默认显示第一个三级）；**分区内不出现任何箭头 icon** |
| D | 多个二级项的三级可**同时展开**（互不影响，不做手风琴） |
| E | 当前页在 Settings 内 → **自动展开到当前页**（分区展开 + 当前子树展开 + 当前项高亮） |
| F | **适用范围仅 Settings 分区**；主区菜单（Orders / Fund / Products / …）行为不变 |
| G | 任何情况下**不得出现 `.nav-submenu-dropdown` 浮层**（该容器只服务 icon-only 模式的 hover 下拉，必须始终 `hidden`） |

**根因（v1.0 缺陷）**：`sidebar_controller.js#applySectionState` 对分区内全部同级元素做
`classList.toggle("hidden", collapsed)` —— 展开时（`collapsed=false`）把 `hidden` 从
`ul.nav-submenu`（三级）与 `ul.nav-submenu-dropdown`（`.dropdown-container`：`position:absolute`
+ 白底 + 阴影 + `popIn` 动画）上**摘掉**，于是三级全部展开且 hover 浮层显形。

**修复要点**：分区显隐只作用于二级 `<li>`；三级 `ul.nav-submenu` 仅在收起时隐藏并记录原状态、
展开时**按原状态恢复**；`ul.nav-submenu-dropdown` 永不被显性化；默认值反转（服务端
`aria-expanded="false"`，且分区内条目在「无激活项」时服务端即渲染 `hidden`，避免首屏闪烁）；
控件与交互范围限在 Settings 分区。

**AC-010** ← A/B/E/G：`/admin/orders` 首次渲染 Settings 收起（`aria-expanded="false"` + 分区内 `<li>` 带 `hidden`），页面内**无可见** `.dropdown-container`；`/admin/policies` 渲染时分区自动展开且仅二级可见。
**AC-011** ← C/D/F：二级项（Users）点击 = 导航到其首个三级且该三级展开；主区菜单 DOM/行为与 v1.0 一致（分区开关不作用于主区）。

**验证记录（真机，2026-09-18）**

| 阶段 | 实测（localhost:3000，真实登录 + 真实资源） |
|---|---|
| 首访 `/admin/orders` | `data-nav-section-collapsed=true`、`aria-expanded=false`、chevron `rotate:-90deg`、二级可见 0/19、浮层可见 **0** |
| 点击展开 | 二级可见 19/19、**三级可见 0**、`.dropdown-container` 可见 **0**、绝对定位 `ul` 可见 **0**（截图核对无浮层） |
| 点击二级 Users | 跳转 `/admin/admin_users`；分区自动展开；`nav-submenu-users` 可见且首项 `nav_link-admin_users` 为 `.active`；其余子树保持收起；浮层仍为 0 |

验证过程中发现并修复了两个仅真机可见的问题（服务端 spec 无法覆盖）：
1. **JS 默认值分支写反**：包含激活项时反而把分区收起（与 AC-010 的"自动展开到当前页"相反）；
2. **资源管线缓存旧 JS**：修改 `app/javascript/**` 后不重启容器，验证会拿到旧控制器 → 结论失真（已写入 Skill 的验证提醒）。

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-18 | 0.1 | 初稿：需求拆解 + 现状核查 + 6 层跨层搜索 + AC/测试映射 + 并行冲突评估 | AI |
| 2026-09-18 | 0.2 | 用户确认（approved）；实施完成：nav 配置/Item/渲染器/JS/CSS/i18n/两个 spec；新增场景 GS-186；补充 AC-008 实证方式与支付页面包屑遗留项 | AI |
| 2026-09-18 | 1.0 | done：提交 c3458b5a（14 files, +803/-100）；门禁 GATE-2026-09-18T14-42-22 完结（三个注册验证器 + 知识评估 12/10 + 证据验证通过）；知识同步门 sync-check --ack 已确认 | AI |
| 2026-09-18 | 1.1 | 行为修正（用户实测反馈）：默认收起；展开仅二级；消除 hover 浮层；分区内无箭头 icon；仅 Settings 生效；手风琴关闭 | AI |
