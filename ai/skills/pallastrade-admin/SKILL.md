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
- **`PallasTrade::PermissionRegistry`**：功能/数据权限矩阵可配置资源的注册表（resource → model_class + actions + data_fields）。新增可授权资源须在 `backend/config/initializers/pallastrade_permission_registry.rb` 登记。

关键行为：

1. **Ability 由 DB 驱动**：`PallasTrade::Ability#apply_permissions_from_db` 读取用户角色的 role_permissions；`admin` 角色由 `Role.default_admin_role` 确保 `set: SuperUser`；无 DB 配置的角色回退代码权限集（storefront default）。
2. **功能权限 → 授权主体**：resource 经 PermissionRegistry 解析为模型类（`orders` → `PallasTrade::Order`），授予时自动附带 `:admin`（面板入口 gate）。read/index/show 授予时叠加数据范围条件（`accessible_by` 自动生效）。
3. **菜单权限过滤**：DB 驱动角色（`ability.menu_permissions` 非 nil）的侧边栏完全由菜单权限决定（跳过代码 `if:`）；未配置角色按代码 `if:` 向后兼容。
4. **菜单配置页 = 只读可视化（2026-08-17 起）**：`MenuConfigsController#index` 仅只读展示导航树（`PallasTrade.admin.navigation.sidebar.root_items`），无任何编辑控件/写路由；菜单结构由 `pallastrade_admin_navigation.rb` 定义。权限配置依据 = Roles 页「菜单权限」树状勾选（与配置页同一导航树）。
5. **角色权限 UI**：Roles 编辑页三 tab（菜单/功能/数据）；`Role#rebuild_role_permissions` 重建（set 类型保护）。
6. **校验**：`nav:validate` 校验 role_permissions 的 resource 必须注册于 PermissionRegistry。

⚠️ 角色权限编辑只影响 menu/function/data；`set`（admin SuperUser）不受 UI 重建影响。
新增受控资源 = 注册 PermissionRegistry + 权限矩阵自动出现（零表单改动）。
菜单结构增删 = 改 `pallastrade_admin_navigation.rb`（代码评审），不开放 UI 结构编辑。

## 多店铺管理（2026-08-17）

数据/权限/API 层多店铺早已就绪（`PallasTrade::Store` 一等模型、`Current.store` 每请求上下文、`RoleUser` 用户→角色→店铺、`for_store(current_store)` 作用域、Store API `pk_` key 识别店铺）。2026-08-17 在 Rails 后台补齐管理 UI：

- **店铺列表**（`admin/stores` index）：Ransack 表格 + Pagy 分页，展示全部店铺（name/code/url/default/created_at）。导航项 `:stores`（Settings 区，`admin.stores.title`）。
- **新建店铺**（`admin/stores/new` + POST）：name/code/url 必填（code 空自动 `set_default_code`）；`mail_from_address` 为空自动按 url 生成 `no-reply@<host>`；`customer_support_email`/`new_order_notifications_email` 预填当前登录用户邮箱（可改）；`default_currency`/`default_locale` 为下拉选择（`::Money::Currency.all` / `PallasTrade::Locales::ALL`）、`supported_currencies` 多选（提交数组 → 控制器 join 逗号分隔，并自动并入 default_currency）；创建后 `grant_store_access` 授予当前用户该店铺 admin RoleUser 并 `session[:admin_store_id]` 自动切换。
- **店铺切换器**（`sidebar/_store_dropdown`）：下拉列出 `admin_accessible_stores`（超管=全部，否则 RoleUser 店铺），当前高亮；POST `admin/switch_store` → 校验授权 → 超管对无 RoleUser 店铺自动授权 → 写 session。
- **current_store 解析**（`Admin::BaseController` 覆盖）：session 选中店铺（授权校验）→ 用户有 RoleUser 的店铺 → `Store.default`；并写入 `PallasTrade::Current.store`。⚠️ 判定超管用 `superuser?`（RolePermission set:SuperUser），**不要**在 current_store 解析里用 `can?`/`current_ability`（其构建回调 current_store → 无限递归）。
- **权限**：店铺管理入口 = `can?(:manage, PallasTrade::Store)`（超管）；切换 = `admin_accessible_stores.include?(store)`。

> 注意：`determine_role_names` 按 `role_users.where(store: @store)` 解析角色，因此切换到无 RoleUser 的店铺需先授权（超管自动授权），否则该店能力为空 → forbidden。

## Customizing admin tables

Most admin listing pages (Products, Orders, Promotions, etc.) use a registered table definition — see the gem's `config/initializers/pallastrade_admin_tables.rb` for the registered keys (note: the Customers page is registered as `:users`; a few pages like Payment Methods don't use the table registry). Add, remove, or reorder columns from an initializer:

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


## Where to read further

- **Admin source:** `bundle show pallastrade_admin` to find the installed gem path. The README at the root of the gem covers the philosophy.
- **Customization docs:** `node_modules/@pallastrade/docs/dist/developer/admin/` covers patterns.
- **Navigation API:** `PallasTrade::Admin::Navigation` source — the full method surface for nav customization.
- **Table API:** `PallasTrade::Admin::Table` (`app/models/pallastrade/admin/table.rb`) and `PallasTrade::Admin::Table::Column` (`app/models/pallastrade/admin/table/column.rb`) inside the gem — column types, options, sorting/filtering details. The registry behind `PallasTrade.admin.tables` is `PallasTrade::Admin::Engine::TablesEnvironment` in `lib/pallastrade/admin/engine.rb`.
- **Scaffold generator:** `bundle show pallastrade_admin`/lib/generators/pallastrade/admin/scaffold/ has the template files you can copy for advanced customization.
- **Form builder / components / helpers:** `node_modules/@pallastrade/docs/dist/developer/admin/form-builder.md`, `components.md`, `helper-methods.md` — the full option tables for everything in "Building admin UI" above.
