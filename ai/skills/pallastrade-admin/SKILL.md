---
name: pallastrade-admin
description: Use when the user is customizing the PallasTrade admin (the `pallastrade_admin` gem) — adding a new resource page, registering a sidebar item, customizing a column in an admin table, overriding a view, scaffolding a new admin section. Common phrasings include "add admin page", "Rails admin", "pallastrade_admin", "scaffold admin resource", "admin sidebar", "override admin view", "Hotwire admin", "Turbo admin".
---

# PallasTrade Legacy Rails Admin (`pallastrade_admin`)

> Commands below use the PallasTrade CLI form (`pallastrade …`, Docker). On a classic Rails app without the CLI (typical pre-5.4), use the native mapping in the `pallastrade-project` skill — `bin/rails` / `bundle exec rake` from the app root, paths without the `backend/` prefix.

The admin is a Rails engine — server-rendered ERB views, Stimulus + Turbo for interactivity, Tailwind for styling. (PallasTrade 6.0 will introduce a new React-based admin; on PallasTrade 5.x, `pallastrade_admin` is the admin.)

## Project layout

The Rails admin lives in the `pallastrade_admin` gem, mounted at `/admin`. View it as a normal Rails app:

```
pallastrade_admin gem
├── app/
│   ├── controllers/pallastrade/admin/         # admin controllers
│   ├── views/pallastrade/admin/<resource>/    # ERB views per resource
│   ├── helpers/pallastrade/admin/             # view helpers
│   ├── presenters/pallastrade/admin/          # presenter pattern for complex views
│   ├── javascript/pallastrade/admin/          # Stimulus controllers, importmap-managed
│   └── models/pallastrade/admin/navigation*   # nav + nav builder
└── lib/generators/pallastrade/admin/
    ├── install/                         # bin/rails g pallastrade:admin:install
    └── scaffold/                        # bin/rails g pallastrade:admin:scaffold
```

In a host app (`backend/`), you customize by overriding files at the same paths under `backend/app/`. Rails view path resolution prefers the host app's files over the gem's.

## Adding a new admin resource (the one-command path)

PallasTrade ships an admin scaffold generator that produces the full CRUD admin for any model. After the model + migration exist (use `pallastrade:api_resource` or `pallastrade:model`):

```bash
pallastrade rails g pallastrade:admin:scaffold PallasTrade::Brand
```

This emits:

| File | Purpose |
|---|---|
| `backend/app/controllers/pallastrade/admin/brands_controller.rb` | Controller inheriting `PallasTrade::Admin::ResourceController` |
| `backend/app/views/pallastrade/admin/brands/index.html.erb` | Listing page (renders `render_table @collection, :brands`; columns come from the table registry) |
| `backend/app/views/pallastrade/admin/brands/new.html.erb` | Create form page |
| `backend/app/views/pallastrade/admin/brands/edit.html.erb` | Edit form page |
| `backend/app/views/pallastrade/admin/brands/_form.html.erb` | Shared form partial |
| `backend/config/initializers/pallastrade_admin_brands_table.rb` | Table column registration |
| `backend/config/initializers/pallastrade_admin_brands_navigation.rb` | Sidebar nav registration |
| `backend/config/routes.rb` | `namespace :admin { resources :brands }` injected into the `add_routes` block |

The generator also injects routes into `backend/config/routes.rb`, inside the `PallasTrade::Core::Engine.add_routes do` block (present in the pallastrade-starter template). If your routes.rb lacks that block, add the routes manually:

```ruby
# backend/config/routes.rb
Rails.application.routes.draw do
  PallasTrade::Core::Engine.add_routes do
    namespace :admin do
      resources :brands
    end
  end

  mount PallasTrade::Core::Engine, at: '/'
end
```

`add_routes` (not raw `PallasTrade::Core::Engine.routes.append`) is the supported mechanism — it guards against routes being drawn twice when the app reloads.

(If you're using `pallastrade:api_resource` for the API, the routes for the API are separate from the admin routes — they live in different namespaces.)

Restart Rails to pick up the new initializers and routes:

```bash
pallastrade restart
```

### Developers tools resources (API Keys / Webhooks / Allowed Origins / Redirects)

Developer-tool resources are registered on the **Developers navigation tabs**
(`developers_tabs_nav`, `pallastrade_admin_navigation.rb`) with a `SettingsConcern`
controller, a table in `pallastrade_admin_tables.rb`, and a v3 Admin API controller +
serializer + `PallasTrade::PermittedAttributes` entry.

- **SEO 301 redirects** (`PallasTrade::Redirect`, `/admin/redirects`, Developers tab):
  `from_path` → `to_path`, status 301/302, `active` toggle. Paths are normalized on save
  (leading slash, strip trailing slash; `from_path` also strips a pasted origin;
  `to_path` must be internal). Consumed by the storefront `middleware.ts` via the Store
  API `redirects/resolve` endpoint.
  - **页面级功能说明**（2026-08）：index 页用 `content_for(:page_alerts)` + `alert-info`
    显示通俗易懂的功能介绍（`admin.redirects.intro_help`）；new/edit 共用 `_form.html.erb`，
    顶部同样放 `alert-info` 说明（`admin.redirects.form_intro`）。文案必须通俗（旧链接→新链接、
    防 404、保 SEO 排名），并走 `PallasTrade.t` locale（含 `: `/`→`/`"` 等特殊字符的值须用单引号包裹）。
    该模式同样适用于其他 settings 列表页（参照 `option_types` 的 `intro_help` 先例）。
  - **URL 变更商品清单**（2026-08）：index 页在 intro 下方展示「Products with changed URLs」
    表格（`@url_changes = PallasTrade::ProductUrlChange.call(current_store)`，数据源为 friendly_id
    `friendly_id_slugs` 历史，无新表）。每行「Create redirect」链接用
    `new_object_url(from_path: ..., to_path: ...)` 预填 new 页；`RedirectsController#new` 从
    `params[:from_path]/[:to_path]` 预填 @object。已存在 from_path 重定向的商品标 `handled`。
  - **业务标题/描述**（2026-08）：`PallasTrade::Redirect` 有可选 `title`（string）与 `description`
    （text）列（迁移 `20260815000002_add_title_description_to_pallastrade_redirects`）。列表
    `pallastrade_admin_tables.rb` 的 `:title` 列 `position: 5`（默认显示、可排序/筛选），让用户
    一眼看出「这条重定向对应什么业务」；`_form.html.erb` 顶部提供 Title/Description 输入（可选）。
    Admin API 的 `permitted_params` 与 admin `redirect_serializer` 均含 title/description。

## Customizing the sidebar

> Note (2026-08): The sidebar **Enterprise Edition upgrade notice was removed** — the admin sidebar renders navigation + user menu only, with no upgrade/Community-Edition prompt. Do not reintroduce upgrade marketing blocks.

Sidebar entries are registered in initializers. Pattern:

```ruby
# backend/config/initializers/pallastrade_admin_brands_navigation.rb
Rails.application.config.after_initialize do
  PallasTrade.admin.navigation.sidebar.add :brands,
    label: :brands,                                       # i18n key or string
    url: :admin_brands_path,                              # symbol → route helper, or string
    icon: 'list',                                         # Tabler icon name (https://tabler.io/icons)
    position: 55,                                         # lower = earlier in sidebar
    active: -> { controller_name == 'brands' },           # when to highlight
    if: -> { can?(:manage, PallasTrade::Brand) }                # CanCanCan visibility check
end
```

Common nav patterns:

```ruby
# Top-level item that opens a sub-menu
PallasTrade.admin.navigation.sidebar.add :marketing, label: :marketing, position: 30 do |nav|
  nav.add :promotions, label: :promotions, url: :admin_promotions_path, position: 10
  nav.add :coupon_codes, label: :coupon_codes, url: :admin_coupon_codes_path, position: 20
end

# Remove an existing entry
PallasTrade.admin.navigation.sidebar.remove :reports

# Reorder an existing entry
PallasTrade.admin.navigation.sidebar.update :products, position: 5
```

The full nav API is in `pallastrade/admin/app/models/pallastrade/admin/navigation.rb` if you need to read the source.

## Breadcrumbs & page headers（统一单一侧边栏规范，2026-08，P6 起）

**2026-08（P3 起）面包屑由导航配置自动推导，P6 起主区/设置区统一为单一 sidebar 树，
不再区分 Settings 模式。** 请求路径 → 导航项（`Navigation#find_breadcrumb_nodes`）→
自动 `图标 + 一级 + 二级(+tab)` 面包屑。手写 concern 已删除（`ProductsBreadcrumbConcern` /
`OrderBreadcrumbConcern` / `PromotionsBreadcrumbConcern` / `EmailsBreadcrumbConcern` /
`PostsBreadcrumbConcern` 均已移除）。

**自动推导规则（P3/P5/P6）：**

1. **统一推导**：`BreadcrumbConcern#derive_sidebar_breadcrumb` 用当前 `request.path`
   在 `PallasTrade.admin.navigation.sidebar` 中做**最深匹配**（URL 匹配为主 + active
   条件兜底），命中项沿父链生成面包屑（`/admin/emails` → `Emails > Email Settings`；
   `/admin/orders` → `Orders > All Orders`；`/admin/api_keys` → `Developers > API Keys`）。
   图标取顶级导航项 `icon`。**设置模块不再有 Settings 前缀。**
2. **顶级落地（landing）**：带子菜单的一级项声明 `landing: :first_child`，点击一级项
   落到 landing 子项页并默认高亮（缺省 = 第一个子项）。**新增带子菜单模块必须声明
   `landing`。**
3. **query 感知**：带 query 的项（如 `orders_to_fulfill` 的 `q[shipment_state_not_in]`）
   仅在 path+query 都相等时命中，绝不落入 path-only 兜底，避免与同路径兄弟项
   （All Orders）混淆。
4. **tab 节点**：声明 `tabs: :stock_tabs` 的项，其 tab 注册表命中当前路径时追加末级
   crumb（`Products > Stock > Stock Movements`）。已存在项自动去重。
5. **对象页**：控制器用 `before_action` 追加对象 crumb（如 products_controller 的
   `add_breadcrumb_for_product` → `Products > Products List > 产品名`）。**不要**在
   action 内手写模块/子页 crumb（已自动推导）；只有对象/特殊上下文（gift_cards 用户
   上下文、webhook_deliveries 父级、stock_transfers 单号）才追加。
6. **新增模块页面**：只需在 `pallastrade_admin_navigation.rb` 声明导航项（`label`/
   `url`/`icon`/`position`/`landing`），面包屑 + 图标 + 子菜单自动出现，**零控制器
   导航代码**。

   ```ruby
   sidebar_nav.add :emails, label: :emails, url: :admin_emails_path, icon: 'send', position: 70,
                   landing: :email_settings do |emails|
     emails.add :email_settings, label: 'admin.emails.settings', url: :admin_emails_path, position: 10
   end
   ```

7. **skip_breadcrumb_derivation 例外（2026-08-17 教训）**：若控制器声明了
   `self.skip_breadcrumb_derivation = true`（如 `stores_controller` 的 section 级、
   `webhook_deliveries` 的父级+本页），则该控制器**所有 action 都不会自动推导面包屑**。
   在此类控制器**新增任何 action（index/new/create 等）都必须手写 `add_breadcrumb`
   （含 `add_breadcrumb_icon`），并加面包屑回归断言**；否则新页面面包屑为空。
   新增页面验证清单（浏览器）：**页面标题 + 面包屑 + 图标** 三要素必查。

8. **页面头（page_title）**：列表/详情/表单页必须写 `content_for :page_title`（渲染页面
   头部 h3 标题）；否则 `shared/_content_header` 不渲染 header，且 `page_actions`
   （操作按钮：新建/返回/标记解决等）会被**整体丢弃**；无 `:page_title` 时自动 fallback
   到最深导航项 label（P4 `@navigation_page_title`）：

   ```erb
   <%= content_for(:title, PallasTrade.t('admin.emails.templates')) %>   <%# 浏览器标签页标题 %>
   <% content_for :page_title do %>                                     <%# 页面头（必须） %>
     <%= PallasTrade.t('admin.emails.templates') %>
   <% end %>
   <% content_for :page_actions do %>                                    <%# 操作按钮区 %>
     <%= link_to PallasTrade.t('admin.emails.new_template'), ..., class: 'btn btn-primary' %>
   <% end %>
   ```

### 统一单一侧边栏（P6）

后台只有**一棵**侧边栏树（`PallasTrade.admin.navigation.sidebar`）：

| 要素 | 要求 |
|---|---|
| 结构 | 主区模块（Orders/Products/Customers/...）+ 设置模块（Developers/Users/Tax/Shipping/Audit/Return Settings/...）全部为一级项；多页面模块带子菜单（可收拉，激活时展开），单页面模块为叶子项；`settings_section` 仅视觉分隔 |
| 落地 | 有子项的顶级必须 `landing: <第一个子项>`；顶级点击 → 落地子项页 |
| 面包屑 | `一级 > 二级`（Orders > All Orders）；设置模块 `Developers > API Keys`（无 Settings 前缀）；tab 页 `Products > Stock > Stock Movements`；深层页 `Products > Products List > 产品名` |
| 页面头 + section/tabs | 设置模块页面仍可渲染 `shared/_section_nav`（section: :developers 等），标题/tabs 来自 `Navigation::SETTINGS_SECTIONS`；禁止手写 4 个 banner partial |
| 例外 | 特殊 crumb 控制器声明 `self.skip_breadcrumb_derivation = true` 保留手写（stores 的 section 级、webhook_deliveries 的父级+本页）；对象 crumb 用 before_action 追加 |
| i18n | 新增 String 型 label（含 `.`）必须 en + zh-CN 双语（gem en.yml + `backend/config/locales/admin_nav.zh-CN.yml`） |
| 校验 | `harness nav:validate` 强制：landing 存在性、tabs 已注册、i18n 双语、permission-only `if:`、常显原则 |

```ruby
# 设置模块示例（Developers）
sidebar_nav.add :developers, label: :developers, url: :admin_api_keys_path, icon: 'terminal',
                position: 165, landing: :api_keys do |developers|
  developers.add :api_keys, label: :api_keys, url: :admin_api_keys_path, position: 5
  developers.add :webhook_endpoints, label: :webhook_endpoints, url: :admin_webhook_endpoints_path, position: 10
end
```

```erb
<%# 设置模块页面 section banner（统一 partial）—— api_keys/webhook_endpoints/... index 页 %>
<%= render 'pallastrade/admin/shared/section_nav', section: :developers %>
```

```ruby
# 注册表：PallasTrade::Admin::Navigation::SETTINGS_SECTIONS
# developers: { title: :developers, tabs: :developers_tabs }
# team: { title: :users, tabs: :team_tabs, page_actions: '.../team_nav_actions', nav_partials: :team_nav_partials }
# audit: { title: 'admin.audit_log', tabs: :audit_tabs }
# returns: { title: -> { "... & ..." }, tabs: :returns_tabs, nav_partials: :returns_and_refunds_nav_partials }
```

⚠️ 通用禁忌：不要在 action 方法内手写 `add_breadcrumb` 拼模块/子页 crumb（已自动推导）；
所有页面都必须有页面头（否则 `page_actions` 丢失）。回归断言见
`navigation_consistency_spec.rb`（AC-006~AC-011 用例）。

## 权限体系 + 可视化菜单配置（2026-08-16，P1-P6 权限体系重构）

后台权限由 DB 驱动（取代代码级 `PallasTrade.permissions.assign`），核心模型：

- **`PallasTrade::RolePermission`**：角色权限行，`permission_type` ∈ `set`（引用权限集类，保留复杂块逻辑，如 admin SuperUser）/ `function`（resource × action: read/create/update/destroy/export/manage）/ `menu`（nav_key 可见性）/ `data`（resource × scope: all/self/store/channel/custom）。
- **`PallasTrade::MenuConfig`**：~~可视化菜单配置覆盖层（显隐/改名/排序/自定义菜单项）~~。**2026-08-17 方向收敛**：菜单结构归代码定义，MenuConfig 只保留模型/表（历史兼容，不删），**写入入口与渲染覆盖合并已移除**——侧边栏严格按代码导航配置渲染。
- **`PallasTrade::PermissionRegistry`**：功能/数据权限矩阵可配置资源的注册表（resource → **models（覆盖模型集合）** + model_class（主模型，= models.first）+ actions + data_fields）。新增可授权资源须在 `backend/config/initializers/pallastrade_permission_registry.rb` 登记。

  **capability 可覆盖多个模型**（PRD-20260911-promo-batch5b）：后台控制器按各自的模型类 `authorize!`，因此一个资源必须列出它涵盖的全部模型——例如 `:promotions` 覆盖 `Promotion + PromotionRule + PromotionAction`（否则 DB 角色拿到 `promotions.update` 仍改不了规则/动作），`:coupon_codes` 单独覆盖 `CouponCode`。数据字段无列时可经 `belongs_to` 上卷（CouponCode → `promotion.store_id`）。

  自洽校验：`bundle exec rake pallastrade:permissions:validate`（`STRICT=1` 有 error 非零退出）；`PermissionRegistry.validate!` 分级：error = 非 AR 模型 / model_class 与 models.first 不一致 / 非法 action / 数据字段无列且不可达（`belongs_to` 链深度 ≤ 2）/ 覆盖模型缺列且无上卷路径；warning = 同一模型被多资源覆盖、无模型的 UI-only 资源。

关键行为：

1. **Ability 由 DB 驱动**：`PallasTrade::Ability#apply_permissions_from_db` 读取用户角色的 role_permissions；`admin` 角色由 `Role.default_admin_role` 确保 `set: SuperUser`；无 DB 配置的角色回退代码权限集（storefront default）。
2. **功能权限 → 授权主体**：resource 经 PermissionRegistry 解析为**全部覆盖模型**（`orders` → `PallasTrade::Order`；`promotions` → Promotion/PromotionRule/PromotionAction），对每个模型授予同一 action，并自动附带 `:admin`（面板入口 gate）。read/index/show 授予时叠加数据范围条件（`accessible_by` 自动生效）；目标模型无该列时经 `belongs_to` 上卷（`{ promotion: { store_id: … } }`）并按列类型转换 scope_value。
3. **菜单权限过滤**：DB 驱动角色（`ability.menu_permissions` 非 nil）的侧边栏完全由菜单权限决定（跳过代码 `if:`）；未配置角色按代码 `if:` 向后兼容。
4. **菜单配置页 = 只读可视化（2026-08-17 起）**：`MenuConfigsController#index` 仅只读展示导航树（`PallasTrade.admin.navigation.sidebar.root_items`），无任何编辑控件/写路由；菜单结构由 `pallastrade_admin_navigation.rb` 定义。权限配置依据 = Roles 页「菜单权限」树状勾选（与配置页同一导航树）。
5. **角色权限 UI**：Roles 编辑页三 tab（菜单/功能/数据）；`Role#rebuild_role_permissions` 重建（set 类型保护）。
6. **校验**：`nav:validate` 校验 role_permissions 的 resource 必须注册于 PermissionRegistry，并要求促销后台模型（Promotion/PromotionRule/PromotionAction/CouponCode/PromotionRedemption）均被某个 capability 覆盖。

⚠️ 角色权限编辑只影响 menu/function/data；`set`（admin SuperUser）不受 UI 重建影响。
新增受控资源 = 注册 PermissionRegistry + 权限矩阵自动出现（零表单改动）。
菜单结构增删 = 改 `pallastrade_admin_navigation.rb`（代码评审），不开放 UI 结构编辑。

## 只读运维页范式（reference: Transactions / Refund Ops / Promotion Redemptions）

后台的「只读观测页」统一按以下四件套落位（以 **Promotions → Redemptions**（2026-09-10，PRD-20260910-promo-batch3c）为例）：

1. **控制器**：`pallastrade_admin/app/controllers/.../<resource>_controller.rb` 继承 `ResourceController`，覆写 `model_class` / `scope`（用 `current_store.<assoc>` 保证店铺隔离）/ `object_name` / `find_object`（`find_by_prefix_id!`）；只读页**不要**定义 new/create/edit/update/destroy。
2. **表格**：`config/initializers/pallastrade_admin_tables.rb` 里 `PallasTrade.admin.tables.register(:<key>, model_class:, link_to_action: :show, search_param:, row_actions: false, row_actions_edit: false, row_actions_delete: false, new_resource: false)` + 逐列 `.add`；视图只写 `<%= render_table @collection, :<key> %>`。
3. **导航**：`pallastrade_admin_navigation.rb` 在目标分组（如 `promotions.add`）加子项，`if: -> { can?(:read, <Model>) }` 守卫；**新增/删除子项必须同步 `spec/requests/pallastrade/admin/navigation_consistency_spec.rb` 的子项数组断言**（历史踩坑：Orders 加 `:transactions`、Promotions 加 `:promotion_redemptions` 都会让该断言失败）。
4. **权限**：`backend/config/initializers/pallastrade_permission_registry.rb` 注册 `<resource>`（model_class + actions + data_fields: store_id）；`nav:validate` 会校验 role_permissions 里的 resource 必须已注册。

对应 Admin API 只读端点（如 `GET /api/v3/admin/promotion_redemptions`）见 `pallastrade-api-v3` Skill：`ResourceController` 子类 + `scoped_resource`，列表返回 `{ data, meta }`，**JWT 管理员需显式 `authorize!(:read, Model)`**（read 动作没有全局钩子；API key 主体由 `ScopedAuthorization` 处理）。Ransack 过滤必须在模型上写 `whitelisted_ransackable_attributes`，否则过滤条件被静默忽略（返回全量）。

### Promotions → Categories 写路径 CRUD（PRD-20260911-promo-batch6 / PR-P9-2）

`PallasTrade::PromotionCategory`（促销分类）原先只有 Admin API，后台无入口；本批次补最小 CRUD：

- 控制器 `PallasTrade::Admin::PromotionCategoriesController`（`ResourceController` 子类，覆写 `model_class` / `object_name` / `permitted_resource_params`（`:name, :code`）/ `location_after_save|destroy → admin_promotion_categories_path`）；分类表**无 `store_id`**，所以**不**覆写 `scope`（默认 `model_class` + `accessible_by`）——写路径不要用 `current_store.<assoc>`。
- 视图 `promotion_categories/{index,new,edit,_form}.html.erb`（镜像 `posts` CRUD：`content_for(:page_actions)` + `render_table` + `form_with model:`）；表格注册 `:promotion_categories`（`search_param: :name_or_code_cont`，模型侧需声明 `whitelisted_ransackable_attributes = %w[name code]`，否则过滤被静默忽略）。
- 导航：`promotions.add :promotion_categories`（position 20，`if: -> { can?(:manage, PallasTrade::PromotionCategory) }`），en + zh-CN 双语；同步 `navigation_consistency_spec.rb` 子项数组断言。
- 权限：PermissionRegistry 注册 `:promotion_categories`（`PromotionCategory`，read/create/update/destroy，`data_fields: []`）。
- 促销编辑页分类选择器在 `promotions/form/_settings.html.erb`，数据由 `PromotionsController#load_form_data` 注入 `@promotion_categories`（**完整集合**，不按 ability 过滤——否则无分类权限的角色编辑促销会把已选分类静默清空）。

### 订单页展示读「成交快照」（PRD-20260910-promo-batch4a）

订单详情页的促销面板（`admin/orders/_promotions.html.erb` + `_order_promotion.html.erb`）**不再直接读 `order_promotion.promotion.name` / `promotion.coupon_code?`**：

- 名称用 `order_promotion.name`、类型徽章用 `order_promotion.coupon_code?`（内部读 `kind`）——两者都是「快照优先」读方法，成交订单（`frozen?`）返回冻结值，购物车/未回填订单回退实时促销定义；
- 已冻结行额外渲染一个锁形徽章（`title` 显示 `frozen_at`），便于运营区分「历史快照」与「实时定义」；
- 后台不得提供修改快照的写入口（快照只由成交/支付确认路径与回填 rake 写入）。

### 退款分摊预览卡片（PRD-20260910-promo-batch4b，架构 §101）

促销卡片下方追加**只读**「Refund allocation preview」区块（partial
`admin/orders/_refund_allocation_preview.html.erb`，由 `_promotions.html.erb` 渲染）：

- 数据源 `Promotions::Allocation::RefundPreview`：每行显示 原金额 / 分摊优惠 / 可退金额（`refundable_amount` 为
  `nil` 时渲染 `n/a`——该行无 inventory unit，绝不臆造金额），页脚为三列合计，下方逐促销显示「分摊 / 原折扣」；
- 可退金额由 `ReturnItem` 权威计算（内存对象，不写库）；区块内**无任何写操作**（无按钮/表单/写路由）；
- 无促销或无分摊时整块不渲染（`preview.available? && promotions.any?`）。

### 促销规则/动作定义发现收敛到 registry（PRD-20260910-promo-batch5a）

后台促销编辑器的「添加规则 / 添加动作」弹窗与表单 partial **不再各自解析类名**，统一读
`PallasTrade::Promotions::DefinitionRegistry`：

- 类型列表：`promotion_rule_entries(promotion)` / `promotion_action_entries(promotion)` 返回 registry 条目
  （`label` / `description` 来自 `promotion_rule_types.<api_type>.*` locale），已存在的类型自动排除；
  历史写法 `rule_type.demodulize.underscore` 会把 `Taxon` 解析成 `taxon`（真实 key 是 `category`），
  导致 Taxon/User 两类在弹窗里显示 translation missing —— 现已由 registry 的 `key` 单源解析；
- 表单 partial：`promotion_rule_form_partial(rule)` / `promotion_action_form_partial(action)` 走
  `entry.admin_partial`（`pallastrade/admin/promotion_rules/forms/<key>`），未注册类型回退旧命名约定；
- 控制器 allowlist：`allowed_rule_types` / `allowed_action_types` 读 `DefinitionRegistry.rule_classes` /
  `.action_classes`，与 Admin API `SubclassedResource` 的 `subclassed_via` 同一来源；
- 新增/修改规则或动作后跑 `bundle exec rake pallastrade:promotions:definitions`（`STRICT=1` 出错非零退出）
  校验「注册数组 / calculator 桶 / 表单 partial / locale」四件套是否齐全。

## 多店铺管理（2026-08-17）

数据/权限/API 层多店铺早已就绪（`PallasTrade::Store` 一等模型、`Current.store` 每请求上下文、`RoleUser` 用户→角色→店铺、`for_store(current_store)` 作用域、Store API `pk_` key 识别店铺）。2026-08-17 在 Rails 后台补齐管理 UI：

- **店铺列表**（`admin/stores` index）：Ransack 表格 + Pagy 分页，展示全部店铺（name/code/url/default/created_at）。导航项 `:stores`（Settings 区，`admin.stores.title`）。
- **新建店铺**（`admin/stores/new` + POST）：name/code/url 必填（code 空自动 `set_default_code`）；`mail_from_address` 为空自动按 url 生成 `no-reply@<host>`；`customer_support_email`/`new_order_notifications_email` 预填当前登录用户邮箱（可改）；`default_currency`/`supported_currencies` 复用 `PallasTrade::CurrencyHelper#currency_options`/`all_currency_options`（money gem ISO 4217，选项「代码 — 名称」）+ `data: { display_names_type: 'currency' }` 本地化显示（与 markets 表单一致，2026-08-17 迭代 2 统一）、`default_locale` 下拉 `PallasTrade::Locales::ALL` + `data: { display_names_type: 'language' }`；`supported_currencies` 多选提交数组 → 控制器 join 逗号分隔并自动并入 default_currency；创建后 `grant_store_access` 授予当前用户该店铺 admin RoleUser 并 `session[:admin_store_id]` 自动切换。
- **店铺切换器**（`sidebar/_store_dropdown`）：下拉列出 `admin_accessible_stores`（超管=全部，否则 RoleUser 店铺），当前高亮；POST `admin/switch_store` → 校验授权 → 超管对无 RoleUser 店铺自动授权 → 写 session。
- **current_store 解析**（`Admin::BaseController` 覆盖）：session 选中店铺（授权校验）→ 用户有 RoleUser 的店铺 → `Store.default`；并写入 `PallasTrade::Current.store`。⚠️ 判定超管用 `superuser?`（RolePermission set:SuperUser），**不要**在 current_store 解析里用 `can?`/`current_ability`（其构建回调 current_store → 无限递归）。
- **权限**：店铺管理入口 = `can?(:manage, PallasTrade::Store)`（超管）；切换 = `admin_accessible_stores.include?(store)`。

> 注意：`determine_role_names` 按 `role_users.where(store: @store)` 解析角色，因此切换到无 RoleUser 的店铺需先授权（超管自动授权），否则该店能力为空 → forbidden。

## 父订单批量售后（P7, 2026-08-28，flag 灰度）

订单详情页新增父订单批量售后能力（`pallastrade_admin` gem 直接修改）：

- **入口**：`views/.../orders/_header.html.erb` `page_actions_dropdown` 加「Parent Order Returns」链接（`PallasTrade.parent_order_returns_admin_order_path`），显示条件 `@order.parent_order? && returns_parent_order_handling? && can?(:create, PallasTrade::ReturnAuthorization)`。`returns_parent_order_handling?` 为 `orders_controller` helper_method（`store.preferred_returns_parent_order_handling.presence || Config[:returns_parent_order_handling]`）。
- **路由**：`resources :orders` member `get :parent_order_returns` + `post :parent_order_returns, action: :parent_order_returns_create`。
- **批量页**：`views/.../orders/parent_order_returns.html.erb`（各目标订单可退 shipped units 列表 + reason/stock_location 选择 + 确认）。`parent_order_returns_create` 调 `PallasTrade::Returns::ParentOrderReturns`，成功重定向父订单详情。`parent_order_returns_targets` helper 供视图计算可退 units（shipped 且未被既有 RA 关联）。
- **flag 关闭**：入口不显示；直接访问 → redirect 回订单页。

## 手动拆单 + 父子树 UI（P6, 2026-08-28，flag 灰度）
订单详情页新增手动拆单能力（`pallastrade_admin` gem 直接修改）：

- **入口**：`views/.../orders/_header.html.erb` `page_actions_dropdown` 加「Split Order」链接（`PallasTrade.split_admin_order_path`），显示条件 `order.completed? && manual_split_enabled? && can?(:update, order)`。`manual_split_enabled?` 为 `orders_controller` helper_method（`store.preferred_manual_split_enabled.presence || Config[:admin_manual_split_enabled]`）。
- **路由**：`resources :orders` member `get :split` + `post :split, action: :split_create`。
- **拆分页**：`views/.../orders/split.html.erb`（行项目 checkbox + Stimulus `order_split_controller.js` 实时预览已选数量/小计 + 提交 `line_item_ids[]`）。`split_create` 调 `PallasTrade::Orders::ManualSplit`，成功重定向父订单详情，失败 flash 错误回拆分页。
- **父子树**：`views/.../orders/_parent_child_tree.html.erb`——子订单显示父订单 banner；父订单显示 children 卡片（订单号/金额/支付/发货状态 + `display_combined_total`）。挂在 `show.html.erb` 主列顶部 + `split.html.erb` 侧栏。
- **列表父子过滤**：`pallastrade_admin_tables.rb` orders 表格 filter-only 列 `parent_filter`（`ransack_attribute: 'parent_id_null'`，select Parent orders/Child orders）。
- **权限**：split/split_create 授权映射 `:update`（兼容 function 权限只授 update 的角色）。
- **flag 关闭**：入口不显示；直接访问 split 页 → redirect 回订单页。

## 支付方式选项化：Provider 详情「支付方式」页签（D1 切片3, 2026-09-15，PRD-20260915-admin）

商家按 method（前台入口）配置一个支付商：`views/.../payment_methods/_options.html.erb` 挂在
`edit.html.erb` 的**主表单内**（随保存一起提交，勿再嵌套 `<form>`）；数据源 =
`PaymentMethod#payment_option_catalog`（provider 声明，Stripe = card/apple_pay/google_pay）∪ 已配置
`metadata['options']`（目录外条目保留，避免保存丢数据）。

- **写入口**：`Admin::PaymentMethodsController#permitted_resource_params` 归一表单参数
  `payment_method[payment_options][<kind>][active|display_name|position]` → `metadata['options']`。
  **勾选任一入口才置 `optionized=true`**；未选项化 provider 保持原语义（前台回落默认入口，零回归）；
  目录外 kind 一律忽略（防注入任意入口）。
- **Test connection**：member route `post :test_connection` → `PallasTrade::PaymentMethods::TestConnection`
  （core 服务：本地凭证体检 + provider 可选远端探测 `PaymentMethod#test_connection`）→ 报告写
  `metadata['last_test_connection'] = {ok, code, message, checked_at}` + `AuditLog`
  （action `payment_method_test_connection`）。按钮用
  `link_to …, data: { turbo_method: :post, turbo_frame: '_top' }`（Turbo 栈约定，非嵌套表单）。
- **落库细节**：`metadata` 只是 `private_metadata` 的 API 别名（`PallasTrade::Metadata`）——低层写入用
  `update_columns(private_metadata: …)`；`update_columns` 同时避免触发 provider 校验（Stripe 的
  `validate_secret_key` 会发远端请求）。
- **凭证脱敏（FR-006）**：`_form.html.erb` 在 preferences 下方回显 `masked_password_preferences(@object)`
  （`PallasTrade::Preferences::Masking`，`••••` + 后 4 位）；页面/日志不出明文（表单参数已被
  `filter_parameter_logging.rb` 的 `:secret`/`:_key` 过滤）。
- **回归**：`harness verify admin-payment-methods-rspec`（页签渲染/保存归一 + Test connection + 脱敏 +
  optionized 门控/Start 同源校验）。

## 支付凭据与环境：provider 详情页（D9 切片2, 2026-09-15，PRD-20260915-payments-d9）

- **环境控件**：显示设置卡增 `f.pallastrade_select :environment, environment_options`（helper 在 `PaymentsHelper#environment_options`）；控制器 `merge_environment_into` 从 **`params`** 读取（`environment` 不在 permit 名单内），白名单外的值忽略，切 `test` 时强制 `storefront_visible = false`。
- **归一链順序坑**：`permitted_resource_params` 必须 `merge_environment_into(merge_payment_options_into(attributes))` —— `merge_payment_options_into` **返回新 Hash**（`attributes.to_h.merge(metadata:)`），不接返回值会丢掉入口配置（实测回归：optionized/rule_set 全失效）。
- **「凭据健康」卡 + 「Webhook」卡**（`_credentials.html.erb`，在 `edit.html.erb` 的 options 之后 render）：分级/轮换/到期/告警行 + reveal 按钮（`data: { turbo_method: :post, turbo_confirm: … }`，命中 Turbo 栈约定）；值只回掩码（`masked_password_preferences`）；Webhook 卡展示 `/api/v3/webhooks/payments/<pm_prefixed_id>` 与签名密钥**只读掩码**（`masked_webhook_signing_key`）。
- **reveal 动作**：`POST /admin/payment_methods/:id/reveal_credential`（member route）——`authorize! :update` + `can?(:manage, PallasTrade::Role.default_admin_role)` 双重门禁；响应 `turbo_stream`（就地替换 `#credential_value_<key>`）或 `json`；审计只记 key。
- 回归：`harness verify d9-credentials-rspec`。

## 支付熔断与健康：provider 详情页（D11 切片1, 2026-09-16，PRD-20260916-payments-d11-circuit-breaker-health）

- **「熔断与健康」卡**（`_breaker.html.erb`，`edit.html.erb` 在 `_credentials` 之后 render；锚点 `#payment_method_breaker`）：
  上表 = 24h provider 级指标（尝试/失败/失败率/平均时长/主要错误）；下表 = 逐入口状态（正常/已软置灰 + 恢复时间）+ 动作。
  指标**只调** `Payments::Health::Metrics`（`PaymentsHelper#breaker_health_metrics`），页面不重算口径。
- **手动动作**（member route）：`POST /admin/payment_methods/:id/soft_disable`（**必填 reason**，缺原因 → `flash[:error]` 且不改状态）
  与 `POST /admin/payment_methods/:id/soft_enable`；权限 = `authorize! :update`；审计
  `payment_option_manually_soft_disabled` / `payment_option_manually_soft_enabled`（metadata 记 kind + reason）。
  手动置灰 = **粘性**（`manual: true`，巡检不会自动恢复）；自动置灰到期由 `Evaluate` 清理。
- **页面自洽**：入口状态经 `PaymentMethod#breaker_state(kind)` / `soft_disabled?(kind)`；逐入口名用 `option_display_name(kind)`
  （D16 读模型**扩参**，未传参行为不变）。
- ⚠️ 历史坑：admin 编辑页路径参数是 **`prefixed_id`**（`pm_xxx`），spec 里写 `payment_method.id` 会 404。
- **回归**：`harness verify d11-circuit-breaker-rspec`。

## 对账队列工作台（D13 切片1, 2026-09-16，PRD-20260916-payments-d13-reconciliation-cases）

- **新页面** `/admin/reconciliation_cases`（Orders → 对账队列，position **55**；导航项 `orders.add :reconciliation_cases`，
  `if: can?(:manage, PallasTrade::ReconciliationCase)`）；控制器 `ReconciliationCasesController < BaseController`（**不是** ResourceController——
  案例没有 CRUD 语义，只有队列筛选 + 运营动作）。
- **筛选口径唯一**：`ReconciliationCase.filter_by(store_id:, scope_filter:, kind:, difference_type:, severity:, provider:, assignee_id:, search:)`
  —— page / counts / CSV 导出三处共用；`@filters` 用 `filters` 备忘（index 与 export 都取同一份，**export 不设 @filters 会静默不过滤**）。
- **动作**（member route，全部 `authorize! :update` + `AuditLog`）：`assign`（`assignee_id=self` = 指派给自己）/ `note`（正文必填，
  写 `ReconciliationCaseNote` 留痕）/ `mark_investigating` / `mark_explained` / `mark_fixed` / `dismiss`（**原因必填**）/ `reopen`。
- **CSV**：`export` action → `send_data ::CSV.generate(...)`（控制器顶部 `require 'csv'`；上限 10k + 截断 warn）；口径 = 当前筛选。
- **降级**：`show` 的关联（交易/订单/审计）逐一 `safe_value` 降级 → 页面恒 200（对齐 disputes_ops / webhook_events 口径）。
- ⚠️ 导航一致性 spec 断言 Orders 子项**完整列表**（新增项必须同步 `spec/requests/pallastrade/admin/navigation_consistency_spec.rb`）。
- **回归**：`harness verify d13-reconciliation-cases-rspec`（+ `node scripts/nav-validate-static.mjs`）。

## 结算台账工作台（D13 切片2, 2026-09-16，PRD-20260916-payments-d13b-payout-ledger）

- **新页面** `/admin/payouts`（Orders → 结算台账，position **57**；导航项 `orders.add :payouts`，
  `if: can?(:manage, PallasTrade::Payout)`）；控制器 `PayoutsController < BaseController`（index / show / new / import / match）。
- **筛选口径唯一**：`Payout.filter_by(store_id:, provider:, status:, from:, to:)` —— 页面与汇总共用同一 scope；
  `@filters` 备忘 `filters`（避免 index 与其它 action 取到不同口径）；日期用 `parse_boundary`（纯日期 → `beginning_of_day` / `end_of_day`）。
- **汇总与计数**：`totals_for(scope)`（`SUM(gross_total/fee_total/net_total)` 一次 pick，nil → 0）；列表差异行计数用
  `PayoutLine.differences.where(payout_id: ids).group(:payout_id).count` **一次聚合**（避免逐行 `count` 的 N+1）。
- **动作**：`POST /admin/payouts/import`（粘贴 CSV 或上传文件；成功 → **自动** `Match` + `SyncCases` → flash 汇总
  `payouts/lines_created/lines_skipped/errors`）；`POST /admin/payouts/:id/match`（`authorize! :update` + 重匹配 + 差异重新入队）；
  两者都写 `AuditLog`（actor = `audit_actor`）。
- **金额展示**：helper `payout_amount` 用 `format('%.2f', …)`（确定性两位小数；不要依赖 `BigDecimal#to_s` 的格式差异）。
- **视图**：`payouts/{index,show,new}.html.erb`；「重新匹配」用 `data: { turbo_method: :post, turbo_confirm: … }`（**不是** `method: :post`）。
- ⚠️ 导航一致性 spec 断言 Orders 子项**完整列表**（新增项必须同步 `spec/requests/pallastrade/admin/navigation_consistency_spec.rb`）。
- **回归**：`harness verify d13b-payouts-rspec`。

## 退款审批工作台（D14 切片1, 2026-09-16，PRD-20260916-payments-d14-refund-approval）

- **新页面** `/admin/refund_approvals`（Orders → 退款审批，position **58**；导航项 `orders.add :refund_approvals`，
  `if: can?(:manage, PallasTrade::RefundApproval)`）；控制器 `RefundApprovalsController < BaseController`
  （index / policy / approve / reject —— 无 show：列表即工作台）。
- **筛选口径唯一**：`RefundApproval.filter_by(store_id:, scope_filter:, from:, to:)`（默认 `scope_filter: 'pending'`）；
  计数 `base_scope.group(:status).count`；列表 `recent_first` + 分页（`PER_PAGE = 50`）。
- **策略卡**（页内表单 `PATCH /admin/refund_approvals/policy`）：`enabled` / `auto_approve_limit` / `currency`；
  写 `Store#private_metadata['refund_policy']`（`update_columns`，不触发回调）+ 审计 `refund_policy_updated` + before/after 快照；
  归一化在控制器 `normalized_policy`（丢弃未知键；阈值空串 = 「全部需审批」）；权限 `can?(:update, PallasTrade::Store)`，拒绝时 flash 提示不炸页。
- **动作**：`POST :id/approve` / `POST :id/reject`（`authorize! :update, PallasTrade::Refund`）；
  **发起人本人行不渲染动作**（helper `same_actor?(approval)`）+ 服务层强制「不能自批」；拒绝原因 `required` + 服务层 `note_required`。
- **错误提示**：`decision_error_message` 把服务错误码映射到 `admin.refund_approvals.errors.<code>`（i18n 缺失 → 通用文案 + code，不泄露内部细节）。
- ⚠️ 导航一致性 spec 断言 Orders 子项**完整列表**（新增项必须同步 `spec/requests/pallastrade/admin/navigation_consistency_spec.rb`）。
- **回归**：`harness verify d14-refund-approval-rspec`（+ `node scripts/nav-validate-static.mjs`）。

## 争议期限看板与提醒历史（D14 切片2, 2026-09-16，PRD-20260916-payments-d14b-dispute-deadlines）

- **看板**（`disputes_ops#index` 顶部卡片）：T-3 / T-1 / 已超期**计数** + 台账提醒总数 + 当前策略摘要（`tiers_days` / auto-lose 开关）；
  计数与筛选**共用** `deadline_scope_for(tier)`（唯一口径，杜绝「计数与列表不一致」）；策略读取失败 → 整卡降级为 0 值（页面恒 200）。
- **筛选**：`?deadline=t3|t1|overdue`。⚠️ 必须**覆盖 `search_collection`**，而**不是**在 `index` 里改 `params[:q]` ——
  基类 `before_action :load_resource` **先**调用 `collection`（内部 memo `@collection` / `@search`），
  action 内再改 params 已经太晚（实测现象：筛选「看着生效」、实际返回全量 → 断言 `not_to include` 失败）。
- **列表列**：表格注册 `:deadline_tier`（position 27）；自定义列 partial 首行必须
  `<%# locals: (record:, column:, value:) %>` 且用 `record`（**不是** `dispute` —— 用错会在渲染时 `undefined local variable`）。
- **详情历史**：`/admin/disputes/:id` 的「提醒历史」卡片（`recent_first.limit(20)`，空态文案 `disputes_deadline_history_empty`）。
  ⚠️ `safe_value` 只适用于 **outcome**（内部调 `outcome.success?`）—— 传数组会被 `NoMethodError` 吞掉 → **静默降级为空列表**；
  取数组请用独立的 `rescue StandardError → []` 私有方法（或 `evidence_submissions_for` 那种既有写法）。
- **徽章**：`dispute_deadline_badge(dispute)` + `dispute_deadline_class(tier)`（`badge-danger` / `badge-warning` / `badge-info`）经 `helper_method` 暴露视图；颜色只用类名，**不写内联样式**（AP-001/AP-006）。
- **回归**：`harness verify d14b-dispute-deadlines-rspec`。

## 风控名单工作台（D15 切片1, 2026-09-16，PRD-20260916-payments-d15-risk-lists）

- **新页面** `/admin/risk_lists`（Orders → 风控名单，position **59**；导航项 `orders.add :risk_lists`，
  `if: can?(:manage, PallasTrade::PaymentRiskList)`）；控制器 `RiskListsController < BaseController`
  （index / create / revoke / import / export —— **无 edit**：续期 = 用同值再提交，upsert 就更新原行）。
- **筛选与计数同源**：`PaymentRiskList.filter_by(store:, list_type:, subject_type:, scope_filter:)`（`all/active/expired/revoked`）
  同时服务列表与四张状态卡（视图给 `<h3 data-count-scope="…">` 便于 spec 断言计数与筛选一致）。
- **写路径全部走服务**：`Risk::Lists::Upsert`（新增/续期/撤销，写审计 `risk_list_entry_changed`）与
  `Risk::Lists::ImportCSV`（逐行幂等 + 错误收集，审计 `risk_list_imported`）——控制器**不直接写模型**，避免口径分叉。
- **导入/导出**：`POST /admin/risk_lists/import`（粘贴 `csv` 或上传 `csv_file`，两者共用同一服务）
  与 `GET /admin/risk_lists/export`（`send_data`，列与导入同构，可再导入）。
- ⚠️ **审计 actor 要自己定义**：`audit_actor` **不在** BaseController 里（payouts / refunds_ops / disputes_ops 各自定义）→ 新控制器若不写就报 `NameError`。
- ⚠️ **订单页注入的 partial 必须以 `_` 开头**：`PallasTrade.admin.partials.order_page_body << 'pallastrade/admin/risk_lists/order_assessment_card'`
  而文件必须叫 `_order_assessment_card.html.erb`（否则 `ActionView::MissingTemplate`）。
- ⚠️ **订单页 request spec**：`OrdersController#scope` 用 `current_store.orders.accessible_by(...)` → 后台 spec 里需按既有范式固定店铺
  （`allow_any_instance_of(PallasTrade::Admin::OrdersController).to receive(:current_store).and_return(store)`），且用 `order.prefixed_id` 访问。
- **脱敏**：列表/卡片/审计一律 `PaymentRiskList#masked_value`；导出保留原值（权限 + 审计）。
- ⚠️ **导航一致性 spec 断言 Orders 子项完整列表**（本次新增 `:risk_lists` 已同步）。
- **回归**：`harness verify d15-risk-lists-rspec`。

## 支付成本域两页：成本报表 + 费率策略（D13 切片3, 2026-09-16；PRD-20260916-payments-d13c-fee-cost-report）

Orders 下新增两个子项（position 60/61，`if: -> { can?(:manage, PallasTrade::PaymentFeePolicy) }`）——同一权限域：

- **`/admin/payment_costs`（支付成本报表，只读）**：期间（默认近 30 天）+ provider／币种／入口筛选 → 汇总卡
  （`<h3 data-cost-metric="gross|fee|rate|average_order|orders|unpriced|actual|variance">`）+ **入口排名表**
  （`data-cost-table="by_entry"`，每行「下钻」链接带上 `method_key` 参数）+ 逐笔明细（`data-cost-table="detail"`，行带 `data-payment-id`）
  + 未定价原因卡 + CSV 导出（`GET /admin/payment_costs/export`，含 `entry_key`，**不含任何凭证/卡号**）。
  所有数字来自 `Payments::Costs::Report`（唯一口径），导出写审计 `payment_cost_report_exported`。
- **`/admin/payment_fee_policies`（费率策略维护）**：列表（适用范围／状态／币种筛选 + **与筛选同源**计数 `data-count-scope`）+ 分页
  + 新增／编辑（`_form` 局部，**只暴露 global／provider／method**，`store` 级留给平台侧）+ **软撤销**（`POST :revoke`，保留历史行）。
  审计 `payment_fee_policy_changed`（含 before/after 快照）/ `payment_fee_policy_revoked`。
- ⚠️ **`PallasTrade::CSV` 命名空间遮蔽标准库** → 导出必须写 `::CSV.generate`（否则 `NoMethodError: undefined method 'generate' for module PallasTrade::CSV`）。
- ⚠️ **页面断言要容忍模板换行**：汇总卡值在 `<h3 …>` 下一行 → 用 `match(/data-cost-metric="fee">\s*4\.0/)` 而不是 `include('…">4.0')`。
- ⚠️ **导航一致性 spec 断言 Orders 子项完整列表**（本次新增 `:payment_costs` / `:payment_fee_policies` 已同步）。
- **回归**：`harness verify d13c-cost-report-rspec`。

## 汇率域两页：汇率表 + 汇率快照（D13 切片4, 2026-09-16；PRD-20260916-payments-d13d-fx-snapshot）

Orders 下再新增两个子项（position 62/63，`if: -> { can?(:manage, PallasTrade::CurrencyRate) }`）：

- **`/admin/currency_rates`（汇率表）**：筛选（币种对/来源/状态/作用域）+ **与筛选同源**计数（`data-count-scope`）+ 分页 + 内联新增（**同一身份键 = 更新原行**，幂等）+ 软撤销（`POST :revoke`）；
  审计 `currency_rate_changed` / `currency_rate_revoked`。`priority` 留空 = 按来源默认。
- **`/admin/fx_snapshots`（汇率快照工作台）**：状态（pending/matched/mismatch/undetermined）+ 币种对 + 期间筛选 → 汇总卡（`data-fx-summary="average_bips"` + 开放案例数）+ 明细（`data-variance-bips` 行数据）；
  `POST :recompare`（对当前筛选集合**重新比对**，结算单修正后可把差异翻回一致并自动销案；审计 `fx_snapshots_recompared`）；`GET :export`（CSV，含结算汇率来源与 bips，**不含凭证/卡号**，审计 `fx_snapshots_exported`）；差异行可跳转对账队列（`kind=fx`）。
- ⚠️ **订单币种必须在店铺 `supported_currencies` 内**（否则 `Currency is not supported by this store`）→ 后台与 spec 的 fixture 要显式声明支持币种。
- ⚠️ **导航一致性 spec 断言 Orders 子项完整列表**（本次新增 `:currency_rates` / `:fx_snapshots` 已同步）。
- **回归**：`harness verify d13d-fx-snapshot-rspec`。

## 拒付率看板 `/admin/dispute_rates`（D14 切片3, 2026-09-16；PRD-20260916-payments-d14c-dispute-rate-board）

Orders 子项 `dispute_rates`（position 64，`if: -> { can?(:manage, PallasTrade::DisputeRateAlert) }`）：

- **页面**：口径说明（分子/分母/币种/unknown/BIN 不可得）+ 筛选（窗口 30/60/90、卡组织、维度、台账档位）+ 阈值设置表单 + 组织卡片（`data-rate-network` / `data-rate-status` / `data-rate-metric` / `data-rate-usage-value`）+ 下钻表（`data-bucket-masked`）+ 预警台账（`data-count-scope` 与 `data-alert-tier`）。
- **权限**：读/写均 `can?(:manage, PallasTrade::DisputeRateAlert)`（新增到 `configuration_management`）；**一键加黑另需** `can?(:manage, PallasTrade::PaymentRiskList)`。
- **一键加黑（掩码反解）**：页面**只提交脱敏值**（`masked_fingerprint`），服务端在**当前窗口下钻结果**里反解原始卡指纹，**必须唯一命中**才写 D15 名单（不唯一 → 友好报错）。这是「页面不出现原始卡指纹」与「能执行动作」的兼顾方案。
- ⚠️ **脱敏只用一个口径**：调用 `PallasTrade::Admin::DisputeRatesHelper.masked`（内部复用 D15 `PaymentRiskList#masked_value`），视图用实例方法 `mask_fingerprint`。
- ⚠️ **新增控制器必须自带 `audit_actor`**（`BaseController` 不提供；否则 `NameError`）。
- ⚠️ 导航一致性 spec 的子项数组已含 `:dispute_rates`（并行会话已同步）。
- **回归**：`harness verify d14c-dispute-rates-rspec`。

## 支付适用范围编辑：Provider 详情「支付方式」页签（D8 切片2, 2026-09-15，PRD-20260915-payments-d8）

同一页签每行新增「适用范围」编辑器 + 摘要列（改 `_options.html.erb`；**不新增页面**）：

- **表单**：`payment_method[payment_options][<kind>][rule_set][<dimension>][]`（4 组多选：market / country /
  zone / currency）+ 隐藏位 `[rule_set][present]=1`（标记「范围区已提交」——全空选择必须能**清空**规则，
  否则与「未提交」无法区分）。
- **归一（控制器 `merged_payment_option_rule_set`）**：prefix ID → 原始 ID（market 限**本店** `store.markets`、
  zone 全局表）；country 校验 ISO 存在；currency 走**店铺支持币种白名单**（`supported_currencies_list`，
  有 market 时按 market 币种推导）；非法值**静默丢弃**；无有效条件 → 删除 `rule_set`（= 不限）。
  **已有 `exclude` 条件原样保留**（v1 不做排除 UI，摘要列可见）。
- **回填/摘要**：`payment_option_scope_form_values` 把已存原始 ID 转回 prefix ID（前台可读）；
  摘要用 `PaymentMethod#payment_option_scope_summary(kind)`（维度名走 i18n：`pallastrade.payment_option_dimensions`）。
- **回归**：`harness verify d8-availability-rspec`（范围编辑/拒绝跨店 market/清空/未提交保留/摘要渲染）。

## Customizing admin tables

```ruby
# backend/config/initializers/pallastrade_admin_products_table_customization.rb
Rails.application.config.after_initialize do
  # Add a column to the existing Products table
  PallasTrade.admin.tables.products.add :brand_name,
    label: :brand,                                        # i18n key
    type: :string,                                        # :string | :number | :date | :datetime | :money | :status | :link | :boolean | :image | :custom | :association
    sortable: true,
    filterable: true,
    default: true,                                        # visible by default (vs opt-in via column toggle)
    position: 25

  # Remove a column
  PallasTrade.admin.tables.products.remove :sku

  # Update an existing column
  PallasTrade.admin.tables.products.update :name, label: :product_name
end
```

For tables you generate yourself (via `pallastrade:admin:scaffold`), the initializer is emitted with sensible defaults — `name`, `created_at`, `updated_at`. Add your domain-specific columns there.

Custom column rendering: when a column's value isn't a direct attribute, define a method on the model or a presenter/decorator. The column's key (the first argument to `add`) is used as the lookup method by default; pass `method:` to point at a different method name or a lambda that receives the record. For example, if you add a `brand_name` column to the Products table, define `brand_name` on the Product model or a presenter:

```ruby
# In your model or decorator
def brand_name
  brand&.name
end
```

Custom row actions: when a table needs member actions beyond the default
edit/delete (e.g. approve/reject moderation), register the table with a
`row_actions_partial` — the partial receives `record:` and `table:` locals and
renders before the delete button. Example (Reviews, P0-4):

```ruby
# pallastrade_admin_tables.rb
PallasTrade.admin.tables.register(:reviews, model_class: PallasTrade::Review,
  search_param: :title_or_body_or_user_email_cont,
  row_actions: true, row_actions_edit: false, row_actions_delete: true,
  new_resource: false, row_actions_partial: 'pallastrade/admin/reviews/row_actions')
```

```erb
<%# app/views/pallastrade/admin/reviews/_row_actions.html.erb %>
<% if record.pending? && can?(:update, record) %>
  <%= link_to PallasTrade.t('admin.reviews.statuses.approved'),
        PallasTrade.approve_admin_review_path(record),
        class: 'btn btn-sm btn-light text-success',
        data: { turbo_method: :patch, turbo_frame: '_top' } %>
  <%= link_to PallasTrade.t('admin.reviews.statuses.rejected'),
        PallasTrade.reject_admin_review_path(record),
        class: 'btn btn-sm btn-light text-danger',
        data: { turbo_method: :patch, turbo_frame: '_top' } %>
<% end %>
```

Member routes (`PATCH /admin/reviews/:id/approve` etc.) live in
`config/routes.rb`; the helper methods are exposed on `PallasTrade.` (e.g.
`PallasTrade.approve_admin_review_path(record)`). Turbo links need
`data: { turbo_method: :patch, turbo_frame: '_top' }`.

### Bulk operations — 批量运营 2.0（预览优先，2026-09-15，PRD-20260915-admin-bulk-operations-2）

批量动作由 `add_bulk_action(table, key, ...)` 注册（`pallastrade_admin_tables.rb`），框架渲染批量工具条并把选中 ids 交给动作。**破坏性批量（价格/库存/渠道）一律走"预览 → 确认 → 执行"三段式**，五个部件缺一不可：

| 部件 | 位置 | 要点 |
|---|---|---|
| 服务对象 | `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/products/bulk_operation.rb`（同目录另有 bulk_price_update / bulk_inventory_adjust / bulk_channel_assignment） | `preview = run(dry_run: true)`、`call = run(dry_run: false)`；返回 `Result = Struct.new(:selected_count, :updated_count, :skipped_count, :warnings)` |
| 预览路由 | `products_controller.rb` + `config/routes.rb` | `*_preview`（collection PUT）→ `render turbo_stream: turbo_stream.replace(:bulk_dialog, partial: 'pallastrade/admin/bulk_operations/preview')` |
| 表单 partial | `bulk_operations/forms/_price_form.html.erb` 等 | 通过 `add_bulk_action(..., form_partial_locals: { mode: ... })` 传参区分动作变体 |
| 预览 partial | `bulk_operations/_preview.html.erb` | 计数 dl + warnings 列表 + `form_tag(@preview_path, method: :put)` 隐藏字段 + `turbo_save_button_tag` |
| 执行路由 | `bulk_update_price` 等（collection PUT） | 复用同一服务实例调 `call` → flash → `handle_bulk_operation_response` |

不变量（回归规格 `admin-products-bulk-rspec` 强制）：

- **预览零写入**：dry-run 与执行走同一 `run`，预览前后数据库无变化且两面计数一致。
- **逐条跳过而非整体失败**：权限（`can? :manage`）与适用性在服务内逐条判定，拒绝原因进 `warnings`（`permission_denied` / `no_price` / `negative_result` / `above_maximum` / `clamped_at_zero` / `inventory_not_tracked` / `zero_delta` / `stock_location_missing` / `not_published` / `no_channels`），其余记录继续处理。
- **金额安全**：`Price.currency` 一律**大写**（`VND`/`USD`）；只写 base price（`prices` 默认 price list），**不碰** `price_list` 行；调价只作用于所选币种；百分比调价 `(amount * factor).round(2)`，负值/超上限跳过。
- **库存安全**：`find_or_initialize_by` + `set_count_on_hand`，下限 0 收敛（计入 `clamped_at_zero`）；不追踪库存的变体跳过。
- **i18n**：新增动作/表单/预览/结果/warning 必须补 `admin.bulk_ops.products.*` 键；规格断言用 `PallasTrade.t(key, default: nil)`（裸 `I18n.exists?` 在此环境查不到引擎翻译，含既有键）。
- 回归验证：`harness verify admin-products-bulk-rspec`。

### 批量移除媒体（Media，2026-09-17，PRD-20260917-catalog-bulk-media）

方案 §5.1「Bulk Operations 2.0」表的**最后一行**。动作 `remove_media`（products 表，position 130）、
服务 `PallasTrade::Products::BulkMediaRemoval`、控制器 `bulk_media_preview` / `bulk_media_remove`。
无配置项，所以 `form_partial` 用框架自带的**空确认 partial**（`bulk_operations/forms/confirmation`）——
`_preview.html.erb` 本身是通用的，**不需要新视图**。

- **范围**：选中商品的**全部媒体** —— ① 商品级 `product.media`；② **所有变体（含 master）**的 `variant.images`。
  口径与 Catalog Health 的 `missing_media`（「产品层与变体层都无资产」）对齐 ⇒ 清空后这些商品会
  **自然出现在 Catalog Health 待办里**，正是「先清掉错的、再从待办重传」的闭环。
- **级联不重建**：`Asset` 自带 `has_many :variant_media, dependent: :destroy`，删 Asset 会连带清关联
  并触发 `refresh_variant_thumbnail`；**手写第二套级联反而会漏掉缩略图刷新**。
- **指针必须手动清**：`Product#primary_media_id` 与 `Variant#primary_media_id` 都**没有** `dependent:`，
  删除后必须把受影响记录的该列置 `nil`，否则留下悬空外键。
- ⚠️ **`bulk_collection` 不做店铺作用域**（`model_class.accessible_by(ability, :update).where(id:)`），
  而 superuser 的 ability 是跨店的 ⇒ **其余 bulk 动作未收窄**（既有行为，本 PRD 未改）。
  媒体删除**不可逆**，所以 `bulk_media_removal` 额外 `merge(current_store.products)` 收窄：
  合法路径（ids 来自当前店铺列表）是 no-op，被篡改的请求多一道防线。要给别的动作也加，需单独评估其 spec。
- 权限：`can?(:manage, PallasTrade::Asset)` 不满足时**零写入**，原因走
  `warnings.media_permission_denied`（不复用 `permission_denied`，那条文案写的是「价格或库存」）。
- 回归：`harness verify bulk-media-rspec`；改动 locale 时另跑 `harness verify admin-i18n-rspec`。

### Catalog Health —— 商品健康待办中心（2026-09-15，PRD-20260915-admin-catalog-health-v1）

Products → **Catalog Health**（`/admin/catalog_health`）是商品运营的「待办中心」：不是报表，直接给 **7 类 Actionable Issue 计数 + 一键下钻**，并在其上给出**覆盖率**与**可解释健康分**（见下文两节）。

| issue key | 口径（一律排除 archived） | 下钻目标 |
|---|---|---|
| `missing_media` | 产品层与变体层（含 master）**都没有资产**（读 `pallastrade_assets` 事实表，`Asset` 无 counter_cache 时不要信 `media_count`） | `/admin/products?health_issue=missing_media` |
| `missing_description` | **默认语言**有效 `description` 为空（翻译行优先，回退模型列——Mobility `column_fallback`） | 同上（`health_issue=missing_description`） |
| `missing_seo` | 默认语言 `meta_title` **或** `meta_description` 为空 | 同上（`health_issue=missing_seo`） |
| `missing_translations` | 非默认受支持语言的 (产品 × 语言) 缺 `name` 对数（与翻译页同口径 `where.not(name: [nil,''])`） | `/admin/product_translations` |
| `active_zero_stock` | active 且**无任何可卖变体**：不存在 `track_inventory=false`、`preorderable=true`、`count_on_hand>0` 或 `backorderable=true` 的未删除变体 | 同上（`health_issue=active_zero_stock`） |
| `redirect_unresolved` | `ProductUrlChange.call(store)` 中 `handled=false` 的 URL 变更条数 | `/admin/redirects` |
| `old_drafts` | `draft` 且 `updated_at` 早于 30 天前 | 同上（`health_issue=old_drafts`） |

接线定式（四件套，已沉淀为可复制范式）：

1. **口径单一权威**：`PallasTrade::CatalogHealth::Issues`（`PRODUCT_FILTER_KEYS` 的 scope 构造器 + 两个专页计数），计数与过滤列表**共用同一构造器**——规格断言「计数 == 列表条数」；`Report` 逐项 `safe_count` 降级（单项异常记日志、页面恒 200）。
2. **过滤接线**：`ProductsController#scope` 覆写（`super` 之后按合法 `health_issue` 追加过滤），**不新增列表页**；非法 key 静默忽略。
3. **横幅注入**：注册到 `products_header_partials`（`PallasTrade.admin.partials.products_header << '...'`，初始器 `pallastrade_admin_partials.rb`），**零 gem 视图覆盖**。
4. **导航与权限**：`products.add :catalog_health`（`if: -> { can?(:read, PallasTrade::Product) }`）；控制器 `BaseController` + `model_class = PallasTrade::Product` 把授权锚定到商品权限（`ProductDisplay` 已授予 `[:read, :admin, :index]`），**必须同步 `navigation_consistency_spec.rb` 子项数组**。

回归验证：`harness verify admin-catalog-health-rspec`（含导航一致性回归）。

### AI Runs 的 Acceptance 列（三态，2026-09-17；PRD-20260917-catalog-ai-edited-before-save）

`/admin/ai/runs` 的「采纳情况」列显示 `acceptance_state`：`accepted` / `discarded` / **`edited`**
（最后一个是“采纳后、保存前又被改过”）。键：`ai.run.acceptance` / `ai.run.acceptance_pending` /
`ai.run.acceptance_state.<state>`；视图用 `default:` 兜底所以**不会** missing，但中文要补在
`admin_ai.zh-CN.yml` 的 **`pallastrade.ai.run.*`** 下。

> ⚠️ 该文件里历史遗留的 `zh-CN.admin.ai.*` / `zh-CN.ai_tools` 等键**取不到** ——
> `PallasTrade.t` 会 prepend `:pallastrade`。真实中文覆盖率比表面低，详见
> `docs/research/RESEARCH-20260917-admin-i18n-gap.md`。

### Catalog Health 覆盖率区（Coverage，2026-09-17；PRD-20260917-catalog-health-coverage-ratios + PRD-20260917-catalog-health-score）

`/admin/catalog_health` 顶部「覆盖率」卡覆盖**全部 7 类 issue**（原先只有 SEO 与翻译两项）：

- 控制器注入 `@coverage = PallasTrade::CatalogHealth::Coverage.call(current_store)`。
- **每个 key 的分母与它自己的分子同单位**，由 `Coverage::DENOMINATORS` **一处**定义：
  内容三类 = 未归档商品数；`active_zero_stock` = 未归档**且 active** 的商品数；
  `old_drafts` = 未归档**且 draft** 的商品数；`missing_translations` = `Issues.translation_slots`
  （商品 × 其它语言）；`redirect_unresolved` = `ProductUrlChange` 总条数。
  这五套分母**互不相同** —— 共用一个会算出一个很像对的**错**比率。
- ⚠️ 一个既存事实：`Issues.translation_slots` 走 `store.product_ids`（**含已归档**），
  而内容三类走 `not_archived`。两套集合不同是既有口径（本改动不动它）——
  关键是**分子与分母必须同一套**，否则比率才是错的。
- 每项显示 **覆盖率百分比 + 分子/分母**（例：`97.4%` / `38 中缺 1`）；
  分母为 0 → 「暂无数据」（既不是 0% 也不是 100%，两者都是编造）。
- 单项计数抛错 → 该维标 `failed`、不计算，**也不计入健康分** ——
  绝不能把降级返回的 `0` 当成「这一类全好」。
- 文案键：`admin.catalog_health.coverage.{heading,unknown,unknown_hint,missing_of_total,metrics.*}`
  （**7 个** metrics 键，en + 宿主 zh-CN 双向必须都存在）。
- 只读；不动导航，不动 7 类 issue 的计数与下钻链接。

### Catalog Health 健康分（Score，2026-09-17；PRD-20260917-catalog-health-score）

在覆盖率之下再给一个 **0–100 总分**，并**把算法完整摊开**——分数的全部价值在于商家能拿计算器复算。

- `PallasTrade::CatalogHealth::Score.call(store)` → `Result#out_of_100` / `#dimensions` /
  `#counted_count` / `#dimension_count`；控制器注入 `@score`。
- **总分 = 可计算维度的加权平均**（`Σ 权重 × 覆盖率 ÷ Σ 权重`），`Score::WEIGHTS` 为常量、默认**等权**（权重越复杂越难解释）。
- **不可计算的维度既不按 0 也不按 1 计入**：分母为 0（新店 / 单语言 / 无 URL 变更）
  或计数器报错 → 排除并在表里逐行标注 `Score::Dimension#excluded_reason`：
  `:no_denominator`（还没有可衡量的对象）或 `:count_failed`（系统问题）—— 两者处理方式不同，必须分开说。
- **全部维度都不可计算 → 总分为 `nil`**，页面显示空态文案而不是编一个数字。
- 页面同时渲染：总分、`%{counted}/%{total}`、每维的分子/分母/覆盖率/权重/是否计入。
- 文案键：`admin.catalog_health.score.{heading,out_of_100,weighting,unknown,unknown_hint,coverage,weight,excluded.{no_denominator,count_failed}}`
  （en + 宿主 zh-CN 双向）。
- ⚠️ **页面里有两张表**：给「issue 清单」那张加了 `data-testid="catalog-health-issues"`。
  写与健康相关的渲染断言时**必须限定在这张表内**（`doc.css('tbody')` 会把健康分明细表也数进去，
  既有 AI 建议 spec 就因此失败过一次）。
- 回归：`harness verify admin-catalog-health-rspec`（2026-09-17 起已把覆盖率与健康分 spec 纳入）。

### Catalog Health 趋势列（Trend，2026-09-16；PRD-20260916-catalog-health-trend-snapshot；审计 G-7）

`/admin/catalog_health` 每行新增**趋势列**（计数与下钻链接原样保留）：

- 控制器注入 `@trend = PallasTrade::CatalogHealth::Trend.call(current_store)`（只读快照表，不动导航）。
- 视图：`@trend.row_for(issue.key)` → `improving` 绿 / `worsening` 红 / `flat` 灰，前缀显示 delta（负数 = 待办变少）。
- **空态必须诚实**：`unknown`（无快照或只有一条）显示 “No trend yet”，**不得**渲染成“持平 0”——
  那是在编造结论。文案键：`admin.catalog_health.trend.{heading,unknown,directions.*}`。
- 采集由 `CatalogHealth::SnapshotSweeperJob` 每日 02:00 完成；工作台只读，**不触发采集**。

### Product History —— 商品级时间线（2026-09-15，PRD-20260915-catalog-batch-d1-product-history）

商品编辑页右栏的「历史时间线」定式是 **审计表即时间线**（零迁移）：写侧统一走 `PallasTrade::ProductHistory::Recorder`，读侧 `PallasTrade::ProductHistory::Timeline` 把审计条目与改价历史合并倒序。

| 关注点 | 做法 |
|---|---|
| 存储 | 复用 `pallastrade_audit_logs`（`resource_type='PallasTrade::Product'`），**不新增表/迁移**；`before`/`after` 只存**真正变化的受跟踪字段**（`name/slug/status/description/meta_title/meta_description/available_on/discontinue_on`） |
| 写侧（单商品） | `Recorder.snapshot(product)` 在 `update` 前取快照 → 成功后 `record_product(product:, action:, actor:, before:, metadata:)`；**无变化且无 `metadata` 直接跳过**（避免空保存刷屏） |
| 写侧（批量） | `record_bulk`：**每个受影响商品一条**，`metadata['source']='bulk'` 携带 `updated_count`/`skipped_count`——时间线既能回答「谁改的」也能回答「这批影响了几条」 |
| actor 归一 | `{type, id, label}`（label 取 email/name/full_name，回退 `#id`）；`nil` → `'system'`，视图直接用 label |
| 嵌套区块 | 改变体/媒体/分类不落在受跟踪列 → 用 `metadata['sections']`（`variants`/`media`/`categories`）标注，面板显示「改过哪些区块」 |
| 读侧 | `Timeline.call(product:, limit: 20)` 合并 `AuditLog.for_resource` + `PriceHistory.where(variant_id: ...)`，按 `occurred_at` 倒序截断；价格条目的 `before` 由**同 `price_id` 的下一条更旧记录**推导（`metadata` 带 `variant_sku`/`variant_id`） |
| 注入点 | 注册到 `product_form_sidebar_partials`：`PallasTrade.admin.partials.product_form_sidebar << 'pallastrade/admin/products/history'`（初始器 `pallastrade_admin_partials.rb`），**零 gem 表单覆盖** |
| i18n | `admin.product_history.*`：`title`/`empty`/`system_actor`/`sku` + `kinds`（created/updated/price/bulk_*）+ `fields`（每个受跟踪字段 + `price`/`currency`） |

接线位置：`ProductsController#update`（快照 + 记录）、`bulk_status_update`、`run_bulk_operation(..., history_action:)` 包办三个批量入口。

回归验证：`harness verify product-history-rspec`。

### Duplicate Detection —— 重复商品候选（2026-09-15，PRD-20260915-catalog-batch-d2-duplicate-detection）

Products → **Duplicate Products**（`/admin/duplicate_products`）是商品治理第三步：列出**看起来重复**的商品候选，并给你并排对比。候选发现是只读的；**合并商品（Merge）已由 D-3 提供**（变体 / 评论 / 媒体 / 分类 / 促销迁移 + Redirect + 台账 + 撤销），入口就在同一页，见下节。

| 信号 | 口径（一律：同店 + 商品未删除 + 非 archived + 变体未删除） |
|---|---|
| `duplicate_barcode` | 变体 `LOWER(TRIM(barcode))` 相同且非空，且组内**商品数 > 1** |
| `duplicate_sku` | 变体 `LOWER(TRIM(sku))` 相同且非空 |
| `duplicate_name` | 商品 `LOWER(TRIM(name))` 相同且非空 |

为什么这三个信号真实存在：`Variant#sku` 的唯一性校验**可被 `disable_sku_validation` 关闭且允许为空**；`variants.barcode` **有列有索引但没有任何唯一性校验**；商品 `name` 无约束。
`slug` **不是**信号——`Product::Slugs` 冲突时自动补 uuid，看不到重复。

实现定式（校验过自的两次踩坑）：

1. **口径单一权威**：`PallasTrade::Products::DuplicateCandidates`（`SIGNALS` + `call(store, signal:)` + `counts(store)`）；`counts` 从**同一份 groups** 派生 → 计数与列表**构造上不可能不一致**；页面过滤在同一数组上 `select`（不重跑查询）。
2. **聚合零插值**：分组表达式用 `Arel::Nodes::NamedFunction`（`LOWER(TRIM(col))`）+ `having(table[:id].count(true).gt(1))`，**类内不拼任何 SQL 字符串**（B-2 的 Brakeman 教训）。
3. **变量无店铺列**：`pallastrade_variants` 无 `store_id` → 必须 `joins(:product).merge(product_scope)` 才能把别店的 SKU/条码挡在组外。
4. **空白值靠分组后剔键**，**不要** `where.not(col: [nil, ''])`：那会生成 `NOT (col = NULL OR col IS NULL)` —— 对真实行恒为 NULL（永不命中）；Mobility 翻译属性上 `not_eq('')` 还会被转成 `!= NULL`。现写法：分组 → `keys.reject(&:blank?)` → `where(expr.in(keys))`。
5. **导航与权限**：`products.add :duplicate_products`（`if: -> { can?(:read, PallasTrade::Product) }`）+ `BaseController` + `model_class`；**必同步 `navigation_consistency_spec.rb` 子项数组**（现为 `products_list catalog_health duplicate_products price_lists …`）。

页面：概览（三信号计数 → 带 `?signal=` 链接）+ 候选表（组键 / 商品链接 / `+N more`）+ 对比页 `compare?product_ids[]=…`（名称/slug/状态/变体·SKU/条码/基础价/库存/渠道/分类/时间，缺失值占位）。

回归验证：`harness verify duplicate-products-rspec`。

### Merge Product —— 重复商品合并与撤销（2026-09-16，PRD-20260916-catalog-d3-product-merge）

同一工作台的第四步（也是方案 §十二 的收官项）：候选与对比页现在能直接**合并**——对比页底部“合并入口”卡片把 `product_ids[]` 带进预检页；预检页把“会发生什么”摊开（每段迁移/跳过计数、跳过原因、旧 URL 301 计划、历史引用计数），确认后 POST 执行；工作台顶部“最近合并”卡片可**撤销**。

| 关注点 | 做法 |
|---|---|
| 预检与执行同源 | 都调 `Products::MergePreview`：预检零写入，执行复用同一份结果，**口径不可能不一致** |
| 冲突不覆盖 | SKU / 评论 / 库存位置 / 分类 / 促销 冲突 → 跳过 + 在预检页列出原因，原记录**留在原处** |
| 历史不可改写 | 预检页显式声明历史订单/支付/流水**零改写**（只统计引用数） |
| 撤销 | “最近合并”行内 `button_to` + `data: { turbo_confirm: }`；被占用（清单项缺失/易主）则**整体拒绝**并提示原因 |
| 权限 | 与工作台一致：`can?(:read, PallasTrade::Product)` 读预检；执行/撤销需 `can?(:update, …)` / `can?(:destroy, …)`，控制器逐项检查 |
| 路由 helper | `PallasTrade.admin_merge_duplicate_products_path` / `PallasTrade.admin_undo_merge_duplicate_products_path`（gem 内路由必须带 `admin_` 前缀） |
| 硬约束 | 弃用商品用 `update_columns(deleted_at:)` **纯软删**；`destroy` 会触发 `dependent: :destroy` 把被跳过的评论真删（spec 已钉死） |

回归验证：`harness verify d3-product-merge-rspec`。

### Catalog Operations —— 商品运营报表（只读聚合，2026-09-16；PRD-20260916-catalog-operations-report；审计 G-6）

Products → **Catalog Operations**（`/admin/catalog_operations`）把 D-1 已在写的商品审计流水读成两个可决策的数字：**批量 vs 单条操作规模**（条目数 + 去重商品数）与**商品维护频次**（`product.updated` 条目 ÷ 被动过的商品数），外加操作者榜。**只读** —— 没有 create/update/destroy，需要动手时把人送回商品列表。

1. **服务**：`PallasTrade::Catalog::Operations::Report.call(window_days: 7)` —— 除铁律「零写库」外，两条容易踩的口径：
   - 批量/单条看**条目**的 `metadata['source'] == 'bulk'`（`ProductHistory::Recorder.record_bulk` 写的），**不是**按 action 名分 —— 同一 action 两种来源都可能；批次本身没有 id，所以报表给「条目数」与「去重商品数」两个数字。
   - **全库口径**：`pallastrade_audit_logs` 没有 store 维度 → 返回 `scope_note: 'all_stores'`，页面如实标注；**不要**假装按店过滤（多店作用域是审计 G-8）。
   - 分母为 0 时比率为 `0.0`（不是 NaN）；三个聚合都在 DB 完成。
2. **窗口**：`?window=7|30`，其他值回落默认（`Report::ALLOWED_WINDOW_DAYS`），不报错、不猜测。
3. **视图**：`card-lg` + `table` 三段（批量 vs 单条 / 维护频次 / 操作者榜）+ 窗口切换 + 空态；文案走 `PallasTrade.t('admin.catalog_operations.*')`（含 `window_days` 复数键）。
4. **导航与权限**：`products.add :catalog_operations`（`position: 9.5`，在 `duplicate_products` 之后；`if: -> { can?(:read, PallasTrade::Product) }`）+ `BaseController` + `model_class = PallasTrade::Product`；**必同步 `navigation_consistency_spec.rb` 子项数组**（现为 `products_list catalog_health duplicate_products catalog_operations price_lists …`）。
5. **回归**：`harness verify catalog-operations-rspec`。

### AI Product Copilot —— 商品编辑页 AI 助手（2026-09-15，PRD-20260915-catalog-batch-e1-ai-copilot）

商品编辑页的描述与 SEO 卡片接入 AI：`[Generate with AI]` / `[Rewrite]` / `[Generate SEO]`。**安全边界是硬要求**（方案 §7.2）：`Generate → Preview → Accept → Save` —— AI 只出草稿，Accept 才写入表单控件，保存仍由商家点 Save；AI 不得改价格/库存/渠道/上架。

| 关注点 | 做法 |
|---|---|
| 能力定义 | 代码级注册（`pallastrade_ai/config/initializers/catalog_capabilities.rb`，**全环境生效**；`test_capabilities.rb` 才是 dev/test 专用）：`catalog.product_description` / `catalog.product_seo`，`execution: :sync`、`data_classification: 'internal'`、`authorization: { action: :update, subject: 'PallasTrade::Product' }` |
| 提示词组装 | 在**业务服务**里（`PallasTrade::AI::Catalog::ProductCopy`）拼 `messages` + `system_instructions`，Gateway 不会调 handler 的 `build_messages`（它直接用 `input[:messages]`）；handler 只保留契约壳 |
| 审计 | 每次生成自动落 `PallasTrade::AI::Run`（actor/能力/模型/用量）；只存 `input_digest`，**提示词与响应正文不落库** |
| 端点 | 宿主 app `PallasTrade::Admin::AIController#product_description/product_seo`（JSON，422 + `error.code`）；商品用 **前缀 id**（`current_store.products.find_by_prefix_id!`），且要自行处理 404（`ResourceController#resource_not_found` 在 `skip_before_action :load_resource` 的控制器上会爆） |
| 按钮状态 | helper `ai_assist_state(capability)` 调 `AvailabilityService.check`（零副作用）→ 未配置就 `disabled + title=<原因>`；**AI 引擎未安装时返回 nil，页面保持原样**（admin 引擎不硬依赖 AI 引擎） |
| 前端 | `ai-assist` Stimulus（fetch → 预览 → Accept/Discard）；Accept 写值后要 `dispatchEvent(new Event('input'))` 并同步 TinyMCE（`tinymce.get(id).setContent`），否则描述框与 SEO 预览不同步 |
| Zeitwerk 坑 | admin 引擎注册了 `inflect.acronym 'AI'` → `ai_assist_helper.rb` 必须定义 `AIAssistHelper`（写成 `AiAssistHelper` 会启动即炸） |

回归验证：`harness verify ai-copilot-rspec`。

### AI Translate Missing —— 翻译抽屉的缺失字段补全（2026-09-15，PRD-20260915-catalog-batch-e2-ai-translate-missing）

商品编辑页 → 翻译抽屉（`/admin/translations/PallasTrade::Product/:slug/edit`，语言 tab）里有 `[AI Translate Missing]`：以**店铺默认语言**为源，只补当前 tab 语言下**仍为空**的字段 `name / description / meta_title / meta_description`（**不含 slug**），预览后 Accept 填入表单，保存仍走抽屉自己的 `PUT admin_translation_path`。

| 关注点 | 做法 |
|---|---|
| 缺失口径 | **必须 `get_field_with_locale(locale, field, fallback: false)`**——请求上下文里 Mobility 会回退到店铺默认语言，缺翻译看起来「已翻译」（`pallastrade-i18n` 明说 `fallback: false` 才是检测缺失的官方方式） |
| 语言两种写法 | 抽屉表单字段后缀是**归一化**的（`normalized_locale`：downcase + `-`→`_`，如 `name_zh_cn`），Mobility 读写用**语言代码**（`zh-CN`，`zh_cn` 会抛 `Mobility::InvalidLocale`）。服务端要按店铺 `supported_locales_list` 把后缀映射回代码（`resolve_locale`），映射不到 → `unsupported_locale` |
| 能力/服务 | `catalog.product_translation`（同一 `catalog_capabilities.rb`，幂等）+ `PallasTrade::AI::Catalog::ProductTranslation`：只读商品、只补缺失；**无缺失直接 `no_missing_fields`，不发请求不建 Run** |
| 端点 | `POST /admin/ai/product_translation`（`product_id` 前缀 id + `target_locale`）；成功 200 `{ translations, locale, fields, run_id }`，失败 422 `{ error: { code } }`（沿用 `find_copilot_product` / `render_copilot_result`） |
| 抽屉接线 | `translations/products/_form.html.erb` 里每个字段行包 `data-ai-translation-row="<field>"`（**不动共享的 `translation_rows/*` partial**，其它可翻译资源不受影响）；`ai-assist` Stimulus 的 `translation` 分支按字段写行内输入（`description` 同步 TinyMCE） |
| 绝不覆盖 | 目标语言已有值 → 不进缺失列表（回归断言：请求前后翻译值逐字段一致） |

回归验证：`harness verify ai-translate-rspec`。

### Catalog Health → AI Fix Suggestion —— 只读修复建议（2026-09-16，PRD-20260916-catalog-batch-e3-ai-fix-suggestion）

两处入口、同一能力 `catalog.health_fix_suggestion`：**工作台**（`/admin/catalog_health` 每行 `[AI Fix Suggestion]` → 行内折叠面板）与**商品编辑页侧栏卡片**（`product_form_sidebar` 注入点，列出该商品命中的健康问题 + 建议）。

| 关注点 | 做法 |
|---|---|
| 只读语义 | 能力授权面是 `{ action: :read, subject: 'PallasTrade::Product' }`（生成类能力才是 `update`）；端点/服务**无写路径**，UI 也**没有 Accept 按钮**（没有可写入目标） |
| 计数同源 | 建议里的 `count` 必须来自 `CatalogHealth::Report#count_for`（与工作台同一口径）；商品级命中判定复用 `CatalogHealth::Issues.product_relation(Product.where(id:), key, store:).exists?` |
| 采样最小化 | 工作台级只取该 issue 作用域前 5 个商品，事实字段仅 `name/status/price/stock_on_hand`（不含客户/订单/成本/供应商） |
| 入口白名单 | 步骤里的 `entry` 只能是 `product_edit_ai` / `translations_drawer` / `product_media` / `variant_inventory` / `redirects` / `publishing`；模型给了别的值 → **只丢 entry，保留步骤**（不让建议指向不存在的入口） |
| 两种粒度 | 同一端点 `POST /admin/ai/catalog_health_suggestion`：`issue_key`（工作台）或 `product_id`（商品级，前缀 id → 跨店 404）；无命中/计数 0 → `422 nothing_to_fix` 且**不建 Run** |
| 注入点坑 | 侧栏 partial 必须声明 `<%# locals: (product:, f: nil) %>`——`render_admin_partials` 会同时传 `f:`，strict locals 下多传一个就 `ArgumentError` |

回归验证：`harness verify ai-health-suggestion-rspec`。

## Overriding views

Drop the same-pathed file in the host app and Rails uses it. The gem ships `pallastrade/admin/app/views/pallastrade/admin/products/index.html.erb`; you override it at `backend/app/views/pallastrade/admin/products/index.html.erb`.

Two real gotchas:

1. **Copy the full file first**, then edit. Partial overrides don't work — Rails picks the host app's file entirely. Use `bundle show pallastrade_admin` to find the gem's view source.

2. **View files have a `data-controller` Stimulus binding** for interactive behavior. If you delete a `data-controller="…"` attribute, the related JS stops working. Keep the bindings unless you're explicitly replacing them.

For lighter overrides, use the admin's named injection points instead of overriding whole views. Views render registered partial lists (e.g. `head`, `body_end`, `products_header`, `product_form`) via `render_admin_partials`. Create your partial (e.g. `backend/app/views/pallastrade/admin/shared/_my_banner.html.erb`) and register it in an initializer:

```ruby
Rails.application.config.after_initialize do
  PallasTrade.admin.partials.body_end << 'pallastrade/admin/shared/my_banner'
end
```

List all injection points with `PallasTrade.admin.partials.keys` in a console.

## Building admin UI — the form builder, components, and helpers

When you write admin views or partials (a scaffolded resource form, an injected `product_form` section, an overridden view), use the admin's own UI vocabulary instead of raw Rails helpers — you get consistent styling, labels, error display, and i18n for free.

### Form builder (the important one)

Every admin `form_with` automatically uses `PallasTrade::Admin::FormBuilder` (`default_form_builder` in the admin's BaseController) — no setup needed:

```erb
<%= form_with model: [:admin, @brand] do |f| %>
  <%= f.pallastrade_text_field :name, required: true %>
  <%= f.pallastrade_text_field :code, help: "Leave blank to auto-generate" %>
  <%= f.pallastrade_money_field :price, currency: current_store.default_currency %>
  <%= f.pallastrade_collection_select :tax_category_id, PallasTrade::TaxCategory.all, :id, :name,
        { include_blank: true, autocomplete: true }, {} %>
  <%= f.pallastrade_check_box :active %>
  <%= f.pallastrade_file_field :logo, width: 240, height: 240 %>
<% end %>
```

The full method set: `pallastrade_text_field`, `pallastrade_number_field`, `pallastrade_money_field` (locale-aware separators, normalizes to decimal on submit, appends the currency symbol), `pallastrade_email_field`, `pallastrade_date_field`, `pallastrade_datetime_field`, `pallastrade_text_area` (auto-grows), `pallastrade_rich_text_area` (Trix), `pallastrade_select` / `pallastrade_collection_select` (pass `autocomplete: true` for a searchable dropdown — use it on any select with 20+ options), `pallastrade_check_box`, `pallastrade_radio_button` (pass an explicit `:id` to bind the label to a specific radio; otherwise the label is matched by value), `pallastrade_file_field` (drag-and-drop, preview, `crop: true`, `allowed_file_types:`).

Common options on every method: `label:` (string, or `false` to hide), `required:` (renders the asterisk), `help:` (text under the field), `help_bubble:` (tooltip icon next to the label), `class:`. Validation errors render under the field automatically; labels resolve via i18n (`pallastrade.<attribute>` then `activerecord.attributes.pallastrade/<model>.<attribute>`).

### UI components

Helper-rendered components matching the admin's design system — use these instead of hand-rolled markup:

| Component | Helpers |
|---|---|
| Dropdown | `dropdown { dropdown_toggle + dropdown_menu }` |
| Dialog (modal) / Drawer (side panel) | `dialog_header`, `dialog_close_button`, `dialog_discard_button`; `drawer_header`, `drawer_close_button` |
| Icon | `icon('plus')` — Tabler icon names |
| Image with fallback | `pallastrade_image_tag` |
| Tooltips | `tooltip`, `help_bubble` |
| Status badge | `active_badge(condition)` |
| Avatar, clipboard-copy, progress bar | `render_avatar`, `clipboard_component` / `clipboard_button`, `progress_bar_component` |
| Dates in store timezone | `pallastrade_date`, `pallastrade_time`, `pallastrade_time_ago`, `local_time` |

### View helpers worth knowing

- **Navigation/links:** `link_to_with_icon`, `link_to_edit`, `link_to_delete` (Turbo confirm built in), `button`, `external_link_to`, `page_header_back_button`
- **Turbo:** `turbo_save_button_tag` (submit with saving state), `turbo_render_alerts`, `turbo_close_dialog`
- **Context:** `current_store`, `current_currency`, `try_pallastrade_current_user`, `supported_currencies`
- **Model preferences:** `preference_fields` / `preference_field_for` — render form inputs for a model's `preference :x` declarations automatically (this is how payment-method and store settings forms are built)

Full references ship in the local docs: `node_modules/@pallastrade/docs/dist/developer/admin/form-builder.md`, `components.md`, and `helper-methods.md`.

## Decorating admin controllers

The PallasTrade admin controllers are normal Rails controllers — you can decorate them like any other. Scaffold the file with `pallastrade generate controller_decorator PallasTrade::Admin::ProductsController` — it emits `backend/app/controllers/pallastrade/admin/products_controller_decorator.rb` with the `prepended` hook and the `prepend` wiring (the generator nests the modules and puts the fully-qualified `prepend` line outside; this equivalent hand-written form is more compact):

```ruby
# backend/app/controllers/pallastrade/admin/products_controller_decorator.rb
module PallasTrade::Admin::ProductsControllerDecorator
  def self.prepended(base)
    base.before_action :my_custom_check, only: [:create, :update]
  end

  private

  def my_custom_check
    # ...
  end
end

PallasTrade::Admin::ProductsController.prepend PallasTrade::Admin::ProductsControllerDecorator
```

This is more invasive than nav/table customization — only reach for it when the action's behavior needs to change. Check whether a subscriber (for side effects) or a service swap (for business logic) would work first. See the `pallastrade-project` skill for the full customization decision tree.

## Stimulus controllers — admin interactivity

The Rails admin uses Stimulus + Turbo for client-side interactivity. Existing controllers live at `pallastrade_admin/app/javascript/pallastrade/admin/controllers/`:

| Controller | What it does |
|---|---|
| `sidebar_controller.js` | Sidebar toggle + persistence |
| `variants_form_controller.js` | Variant management on product edit |
| `page_builder_controller.js` | Drag-and-drop CMS page builder |
| `bulk_editor_controller.js` | Multi-row table editing |
| `dropdown_controller.js` | Dropdown menus |

To add your own Stimulus controller, drop it at `backend/app/javascript/controllers/` and register it via the importmap (`backend/config/importmap.rb`). Reference it from a view with `data-controller="my-controller"`.

For Turbo Streams (server-pushed UI updates), the same patterns apply as any Rails 7+ Hotwire app — render `turbo_stream.*` from the controller, target frames by ID.

## Design tokens & density（B6-1，PRD-20260915-admin-…-b6-1，2026-09-15）

后台的观感只有两个杠杆：**token** 与 **密度档位**。改颜色/面/文字/间距前先看这里，不要逐组件找硬编码值。

- **token 定义在 gem**：`pallastrade_admin/app/assets/tailwind/pallastrade/admin/base/_theme.css`（`@theme static`）：
  - 品牌色阶：`--color-primary-{50…950}`（navy `#0A2540` 派生，**-600 为主色档**，白底对比 5.87:1）、`--color-accent-{50…950}`（teal `#0F9D94`；B6-1 **只定义不启用**，强调态场景在 B6-2/B6-3 落地）；
  - 语义 token：`--color-surface` / `-surface-muted` / `-background` / `-border` / `-border-strong` / `-text` / `-text-muted` / `-text-subtle` / `-focus-ring`；
  - 密度变量：`--admin-density-{row-padding-y,row-padding-x,control-height,control-padding-x,label-gap,section-gap,font-size-base,line-height-base}`。
- **`@theme static` 不能去掉**：Tailwind v4 默认会把“仅定义、尚未被任何 utility 引用”的主题变量摇树掉，宿主覆盖与后续批次会引用到不存在的变量（产物里 grep 不到即为此因）。
- **组件层禁止直引 Tailwind 调色板**（`bg-zinc-950` / `bg-blue-50` …）：主色/语义一律走 token（例：`.btn-primary` = `bg-primary-600` + hover `-700`；`.nav-pills .nav-link.active` = `bg-primary-50 text-primary-900`）。中性色与状态色的全面 token 化在 B6-2。
- **密度档位**：`<html data-admin-density="compact|comfortable">`（三个 layout 已输出 **compact** 默认；UI 切换入口在 B6-2）。未设属性时由 `:root` 的 compact 默认值兜底。
- **宿主覆盖**：`backend/app/assets/tailwind/pallastrade_admin.css`（`@theme` 覆盖 + `[data-admin-density]` 覆盖示例已就位）——宿主改品牌只改这里，**不要改 gem 组件**。
- **守护**：`harness verify admin-theme-rspec`（`backend/spec/design/admin_theme_tokens_spec.rb`：token 集合、组件零直引、三 layout 属性、WCAG AA 对比度 ≥4.5/≥3）。
- **构建与验证**：`bin/rails pallastrade:admin:tailwindcss:build`（dev 由 `pallastrade-admin-css-1` watcher 自动重建；`assets:precompile` 已挂钩）。改完 CSS/布局后必须**重建 + 重新加载页面**确认——Rails 进程会缓存模板与资产清单，本地容器需 `docker restart pallastrade-web-1` 才会反映布局改动与新的资产 digest。

## Decision tree: what kind of admin change is this?

| Want to... | Use |
|---|---|
| Add a sidebar item linking to your own page | `PallasTrade.admin.navigation.sidebar.add` in an initializer |
| Add a column to an admin table | `PallasTrade.admin.tables.<name>.add` in an initializer |
| Add a new resource CRUD section | `bin/rails g pallastrade:admin:scaffold PallasTrade::YourModel` |
| Write or edit a form | `f.pallastrade_*` form-builder methods — see "Building admin UI" above |
| Add a modal / dropdown / badge / tooltip | The component helpers — see "Building admin UI" above |
| Change how an existing page looks | Override the view in `backend/app/views/pallastrade/admin/...` |
| Add a new action to a controller | Decorator (last resort — see `pallastrade-project` skill first) |
| Make a form field interactive | Stimulus controller + `data-controller="..."` in the view |
| Push real-time updates to the UI | Turbo Stream broadcasts from a subscriber or service |
| Change admin styling globally | Edit `backend/app/assets/tailwind/pallastrade_admin.css` (created by the installer) — it imports the gem's base styles from `app/assets/tailwind/pallastrade/admin/index.css`; add `@theme` overrides and custom Tailwind there |
| Change a colour, surface or spacing **for the whole product** | Edit the gem's tokens: `pallastrade_admin/app/assets/tailwind/pallastrade/admin/base/_theme.css` (`@theme static`) — see “Design tokens & density” below |


## Webhook events console（D12, 2026-09-15；PRD-20260915-payments-d12-webhook-governance）

- 新页面 `/admin/webhook_events`（Developers 区，position 15；导航与 tabs 两处都要注册）：
  入站 provider 事件流（筛选：支付商/动作/状态/订单号/日期）+ 详情（payload/关联/审计/耗时）+ 三个动作。
- 动作均用 `button_to`（后台**无 rails-ujs**，`link_to method:` 无效）+ `turbo_confirm`；权限锚点 `can?(:manage, PallasTrade::PaymentWebhookEvent)`。
- 自定义 console 的授权：`BaseController#authorize_admin` 用 `model_class` + `authorize! action, model_class`；
  自定义动作（replay/quarantine/mark_processed）靠 `can :manage, …` 覆盖（`:manage` = 任意动作）。
- 只读聚合（健康/清单）**逐个降级**（异常 → nil → 区块不渲染），页面恒 200（同 disputes_ops 口径）。
- ⚠️ i18n 命名：导航 `label:` 用**点号字符串**（`'admin.webhook_events.title'`），因为
  `admin.webhook_events` 本身是一个哈希（含 title/intro/…），不能当 label 用。

## Bulk actions（B-1 框架 · F-3 评论审核，2026-09-16）

后台列表的批量操作**走统一框架**，不要另写弹窗：

1. 在 `pallastrade_admin/config/initializers/pallastrade_admin_tables.rb` 给表注册动作：
   `PallasTrade.admin.tables.<key>.add_bulk_action :event, label: 'i18n.key', icon:, action_path: ->(vc) { vc.pallastrade.<path> }, body: 'i18n.key', position:, condition: -> { can?(:x, Model) }`
2. 通用模态由 `Admin::BulkOperationsController#new`（`GET /admin/bulk_operations/new?kind=&table_key=`）按注册渲染 —— **无需新视图**；列表只需 `render_table @collection, :<key>`。
3. 执行端点由各资源自己实现，但有三条铁律：
   - **逐条走状态机/服务**（`Review#approve!` / `#reject!` 之类），**禁止** `update_all` 直改状态列 —— 否则审计与副作用全丢；
   - **逐条鉴权**（`authorize! :action, record`，捕 `CanCan::AccessDenied` 计入「无权跳过」），批量不得放宽权限；
   - 返回**可解释报告**（成功 / 无权 / 状态不允许 / 不存在四计数），部分失败**不回滚**已成功项；设**单次上限**（评论为 50）并拒绝越界请求。

范例：`Admin::ReviewsController#bulk`（F-3，`POST /admin/reviews/bulk`，参数 `event` + `ids[]`，四计数写进 flash）。

> ⚠️ 改 `pallastrade_admin_tables.rb` 后**必须** `ruby -c` 校验：整个文件包在一个 `do … end` 块里，插入位置不对会把块尾 `end` 吞掉，表现为应用启动 `SyntaxError`（F-3 实测踩过）。

## Where to read further

- **Admin source:** `bundle show pallastrade_admin` to find the installed gem path. The README at the root of the gem covers the philosophy.
- **Customization docs:** `node_modules/@pallastrade/docs/dist/developer/admin/` covers patterns.
- **Navigation API:** `PallasTrade::Admin::Navigation` source — the full method surface for nav customization.
- **Table API:** `PallasTrade::Admin::Table` (`app/models/pallastrade/admin/table.rb`) and `PallasTrade::Admin::Table::Column` (`app/models/pallastrade/admin/table/column.rb`) inside the gem — column types, options, sorting/filtering details. The registry behind `PallasTrade.admin.tables` is `PallasTrade::Admin::Engine::TablesEnvironment` in `lib/pallastrade/admin/engine.rb`.
- **Scaffold generator:** `bundle show pallastrade_admin`/lib/generators/pallastrade/admin/scaffold/ has the template files you can copy for advanced customization.
- **Form builder / components / helpers:** `node_modules/@pallastrade/docs/dist/developer/admin/form-builder.md`, `components.md`, `helper-methods.md` — the full option tables for everything in "Building admin UI" above.

## 3DS / SCA 策略编辑（D15 切片3, 2026-09-17；PRD-20260917-checkout-d15-切片3）

- **入口**：门店编辑页「结账」区块 → 新增 **3DS / SCA 策略** 小卡（`stores/form/_checkout.html.erb`）。
- **字段**：模式 `always` / `risk_based`（默认）/ `off` + 低金额阈值 + 国家白名单（ISO-2，逗号或数组）+ 入口白名单（kind）。
- **校验与落库**：写完只经 `Payments::ThreeDSecure::Policy.storable`（**写路径**：非法 mode / 负阈值 / 非法国家码 → `errors`，**不落库不静默**）；读路径 `normalize` 永不抛错（运营写坏键不能让结账 500）。落 `store.private_metadata['three_d_secure_policy']`，**零迁移**；保存写审计 `store_three_d_secure_policy_updated`。
- **零影响**：未提交该键 → `private_metadata` 其它键**原样保留**；未配置门店 = 默认 `risk_based`（与今天行为一致）。
- **入口能力列**：支付方式（Provider 详情「支付方式」页签）入口表新增**只读**「可强制认证」列（来自 provider `payment_option_catalog[i]['three_d_secure']`，未声明 = 不支持）；不读不写规则集，无新权限资源（沿用 `can :manage, PallasTrade::Store`）。
- **规则动作文案**：`/admin/risk_rules` 的动作词汇与试算展示含 `force_3ds`（i18n en + zh-CN **键集相等**，与 D15 切片2 同表）。

## 风控规则工作台 `/admin/risk_rules`（D15 切片2, 2026-09-17；PRD-20260917-payments-d15b-risk-rules）

Orders 子项 `risk_rules`（position **59.5**，紧跟「风控名单」59，同权限域）：

- **页面**：`index`（规则集筛选/与筛选同源计数 `data-count-scope` / 建集表单）+ `show`（生效规则表 `data-active-rules` + 金丝雀卡片 + **版本历史** `data-version-history` + 发草稿/发布/金丝雀/回滚）+ `preview`（订单试算）。
- **动作**（均 `authorize! :manage, PallasTrade::RiskRuleSet` + 审计 + confirm）：`create_version` / `publish` / `canary` / `rollback`（**原因必填**）/ `toggle`。
  全部写路径经唯一服务 `Risk::Rules::Versioning`（控制器不直接写版本，避免口径分叉）。
- **试算（preview）**：`data-preview-result` / `-version` / `-canary` / `-bucket` / `-rule` / `-action` / `-skipped`；**只读**：不写留痕、不改订单状态，找不到订单显示 `data-preview-error`（用 `data-*` 断言，**不要**整页文本断言）。
- ⚠️ **金丝雀下拉必须列草稿（可达性）**：候选集 = `@versions.reject(&:archived?)`（**草稿 + 已发布**，归档版不可复活），标签 = `version_label + state_*`。若只列 `published?`，运营侧永远只有生效版可选 → 灰度功能**存在但用不了**（`publish` 会归档其它已发布版，不存在「已发布且不生效」的版本）。草稿被选中时以金丝雀身份发布但**不改**生效版（语义见 `pallastrade-security`）。
- **权限**：`can :manage, PallasTrade::RiskRuleSet`（覆盖全部自定义动作）+ `can :manage, PallasTrade::RiskRuleVersion`；已在 `backend/config/initializers/pallastrade_permission_registry.rb` 登记 `:risk_rules`（新增授权资源必须登记，否则 `nav:validate` 难过）。
- ⚠️ **新增 Orders 子项必须同步 `navigation_consistency_spec.rb` 的 orders 子项数组**（本次加 `:risk_rules`）。
- ⚠️ **多态 `created_by` 不要赋字符串**：actor 归一在服务层（只有 AR 记录才落多态列，`'admin'` / `{type:,id:,label:}` 交给审计），否则会撞 `PrefixedId#assign_attributes` 报 `undefined method 'has_query_constraints?' for String`。
- **回归**：`harness verify d15b-risk-rules-rspec`。

## 风控看板 `/admin/payment_risk`（D3, 2026-09-17；PRD-20260917-payments-d3）

Orders 子项 `payment_risk`（position **64.5**，紧跟「拒付率」之后，同 `PaymentRiskAssessment` 权限域）：

- **页面**：窗口选择（7/30/60/90 天）+ 5 行指标表（`data-testid="payment-risk-metrics"`，每行 `payment-risk-metric-<key>` + `data-metric-status`）+ 下钻链接 + 阈值策略表单（`payment-risk-policy`；每指标 enabled + 两档阈值，未勾选时 hidden `enabled=0`）+ 告警历史（`payment-risk-alerts`，最近 20 条审计）。
- **动作**（均经服务层，控制器**不自算**）：`patch /admin/payment_risk/policy`（唯一写路径走 `DashboardPolicy.storable`：非法**不落库** + flash 错误；成功写审计 `store_payment_risk_dashboard_policy_updated`）/ `post /admin/payment_risk/reevaluate`（手动立即求值，复用同一个 `DashboardAlert` 判定）。
- ⚠️ **路由写法**：用显式 `get/patch/post`（helper：`admin_payment_risk_path` / `_policy_path` / `_reevaluate_path`）。**不要**写 `resources :payment_risk, only: [:index]` —— 会自动复数化成 `admin_payment_risk_index_path`，与视图不符。
- ⚠️ **新增 Orders 子项必须同步两处**：`navigation_consistency_spec.rb` 的 orders 子项数组 + `backend/config/initializers/pallastrade_permission_registry.rb`（本次登记 `:payment_risk`，`PaymentRiskAssessment`，`read update`）。
- **i18n**：新域 → 新文件 `backend/config/locales/admin_payment_risk.zh-CN.yml` + gem `en.yml` 的 `admin.payment_risk.*`（en↔zh-CN **键集相等**，跑 `harness verify admin-i18n-rspec`）。
- **「不可判定不猜」在 UI 的体现**：`unavailable` 行显示 `reason` 文案而非 `0`；`unconfigured` 行显示「未配置阈值」而非「正常」。
- **回归**：`harness verify d3-risk-dashboard-rspec`（含导航一致性）。

## 交易排障台复核卡 `/admin/transactions/:id`（D2, 2026-09-17；PRD-20260917-payments-d2）

`manual_review` 交易的人工出口（此前只能 console 改状态）。**动作与状态机细节见 `pallastrade-payments` SKILL**，此处只记后台接线约定：

- **两个动作**（member POST，与既有 `recover` 同一资源）：`approve_and_capture` / `release_and_cancel`。授权沿用控制器级映射 —— `authorize_admin` 把 `%i[recover approve_and_capture release_and_cancel]` 统一按 `:update` 授权（CanCan 只到 `update/manage`）。
- **复核卡只看状态**：`@object.state == 'manual_review'` 才渲染两表单（各含**必填原因** + `data: { turbo_confirm: ... }` 双重确认）；其它状态只给一句说明、**不给按钮**（自动恢复属于 `recover`）。
- ⚠️ **按钮 label 含 `&`**（"Approve & capture"）→ ERB 转义成 `&amp;`，spec 断言要用 `CGI.escapeHTML(PallasTrade.t(...))`，别直接比对原文。
- **失败码 → i18n 显式映射**（`REVIEW_ERROR_KEYS`）：`reason_required` / `not_reviewable` / `no_pending_authorization` / `capture_failed` / `finalize_failed` / `paid_payment_present` / `release_failed`，未知码回落 `generic`。**不要用「翻译不存在就回落」的探测式写法**（`PallasTrade.t` 对缺键的返回形式不稳定）。
- **复核历史**：读同资源的 `AuditLog`（`action IN (transaction_review_captured|released|failed)`，倒序 limit 10）——**不新建台账表**，审计即历史。
- **文案位置**：键加到既有 `pallastrade.admin.orders.*`（gem `en.yml` + 宿主 `config/locales/admin_orders.zh-CN.yml`），**不要**为此新建 locale 文件（同域键必须同文件，否则键集相等校验与加载顺序都会出问题）。
- **回归**：`harness verify d2-manual-review-rspec`。
