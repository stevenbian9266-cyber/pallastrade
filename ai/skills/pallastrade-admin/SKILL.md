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

## Breadcrumbs & page headers（子菜单统一规范，2026-08）

**每个带子菜单的模块必须有专属 breadcrumb concern，且每个页面必须渲染页面头（page_title）。**
参考 `ProductsBreadcrumbConcern` / `OrderBreadcrumbConcern` / `PromotionsBreadcrumbConcern` /
`EmailsBreadcrumbConcern`（都在 `pallastrade_admin/app/controllers/concerns/pallastrade/admin/`）。

1. **面包屑 concern**：父级 crumb + 图标在 concern 里用类级声明，各子页控制器 include 后再加自己的子页 crumb：

   ```ruby
   # concerns/pallastrade/admin/emails_breadcrumb_concern.rb
   module PallasTrade::Admin::EmailsBreadcrumbConcern
     extend ActiveSupport::Concern
     included do
       add_breadcrumb_icon 'send'                                   # Tabler 图标名
       add_breadcrumb PallasTrade.t(:emails), :admin_emails_path    # 父级 crumb（symbol URL）
     end
   end

   # 子页控制器：include + 类级子页 crumb（+ 需要时对象 crumb）
   class EmailTemplatesController < ResourceController
     include PallasTrade::Admin::EmailsBreadcrumbConcern
     add_breadcrumb PallasTrade.t('admin.emails.templates'), :admin_email_templates_path
     before_action :add_breadcrumb_for_template, only: [:show, :edit, :update]
     # ...
   end
   ```

   ⚠️ **不要在 action 方法内手工 `add_breadcrumb`**（Email 菜单曾经的坑）——用类级
   `add_breadcrumb` + `before_action`，保证所有子页面包屑结构一致、带图标。

2. **页面头（page_title）**：列表/详情/表单页必须写 `content_for :page_title`（渲染页面
   头部 h3 标题）；否则 `shared/_content_header` 不渲染 header，且 `page_actions`
   （操作按钮：新建/返回/标记解决等）会被**整体丢弃**：

   ```erb
   <%= content_for(:title, PallasTrade.t('admin.emails.templates')) %>   <%# 浏览器标签页标题 %>
   <% content_for :page_title do %>                                     <%# 页面头（必须） %>
     <%= PallasTrade.t('admin.emails.templates') %>
   <% end %>
   <% content_for :page_actions do %>                                    <%# 操作按钮区 %>
     <%= link_to PallasTrade.t('admin.emails.new_template'), ..., class: 'btn btn-primary' %>
   <% end %>
   ```

   ⚠️ 只写 `content_for(:title)` 不写 `:page_title` → 页面头消失 + 操作按钮不显示
   （2026-08 Email 菜单统一化修复前的状态；回归断言见 `emails_spec.rb` 的
   `unified email menu structure` describe：校验 `id="page-header"`、`aria-label="breadcrumb"`
   与 `page_actions` 内容）。

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
