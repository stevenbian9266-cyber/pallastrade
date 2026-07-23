# PallasTrade Admin

[![Gem Version](https://badge.fury.io/rb/pallastrade_admin.svg)](https://badge.fury.io/rb/pallastrade_admin)

PallasTrade Admin provides a modern, fully-featured admin dashboard for managing your PallasTrade application.

## Overview

This gem includes:

- **Dashboard** - Analytics and KPI overview
- **Product Management** - Products, variants, properties, option types
- **Order Management** - Orders, payments, shipments, refunds
- **Customer Management** - Customer accounts and order history
- **Inventory Management** - Stock locations, stock items, transfers
- **Promotions** - Discounts, coupon codes, promotion rules
- **Content Management** - Pages, menus, navigation
- **Settings** - Store configuration, payment methods, shipping methods, taxes

## Installation

```bash
bundle add pallastrade_admin
bin/rails g pallastrade:admin:install
```

You will need to restart your web server and run `bin/dev` to start the development server for the admin dashboard.

## Features

### Dynamic Tables

Register customizable tables for your resources:

```ruby
# config/initializers/pallastrade_admin_tables.rb
Rails.application.config.after_initialize do
  PallasTrade.admin.tables.register(:gift_cards, model_class: PallasTrade::GiftCard)

  PallasTrade.admin.tables.gift_cards.add :code,
    label: :code,
    type: :string,
    sortable: true,
    filterable: true,
    default: true,
    position: 10
end
```

Column types: `:string`, `:currency`, `:date`, `:datetime`, `:boolean`, `:custom`

### Navigation

Configure sidebar and settings navigation:

```ruby
# config/initializers/pallastrade_admin_navigation.rb
Rails.application.config.after_initialize do
  PallasTrade.admin.navigation.sidebar.add :reports,
    label: :reports,
    url: :admin_reports_path,
    icon: 'chart-bar',
    position: 60,
    if: -> { can?(:manage, PallasTrade::Report) }
end
```

### Partial Hooks

Extend the admin interface with partial hooks (100+ available):

```erb
<%# app/views/pallastrade/admin/orders/_show_sidebar.html.erb %>
<div class="card">
  <div class="card-body">
    Custom order sidebar content
  </div>
</div>
```

### Controllers

Admin controllers inherit from `PallasTrade::Admin::ResourceController` for consistent CRUD:

```ruby
module PallasTrade
  module Admin
    class GiftCardsController < ResourceController
      private

      def model_class
        PallasTrade::GiftCard
      end

      def permitted_resource_params
        params.require(:gift_card).permit(
          PallasTrade::PermittedAttributes.gift_card_attributes
        )
      end
    end
  end
end
```

### Form Builder

Use the PallasTrade admin form builder for consistent styling:

```erb
<%= f.pallastrade_text_field :name %>
<%= f.pallastrade_text_area :description %>
<%= f.pallastrade_check_box :active %>
<%= f.pallastrade_select :status, options_for_status %>
```

## Technology Stack

- **Tailwind CSS** - Utility-first CSS framework
- **Turbo/Hotwire** - SPA-like interactions without JavaScript frameworks
- **Stimulus** - Modest JavaScript framework for controllers

## Testing

```bash
cd admin
bundle exec rake test_app  # First time only
bundle exec rspec
```

For controller specs, use `stub_authorization!` for authentication:

```ruby
RSpec.describe PallasTrade::Admin::ProductsController, type: :controller do
  stub_authorization!
  render_views

  describe 'GET #index' do
    it 'renders the index template' do
      get :index
      expect(response).to render_template(:index)
    end
  end
end
```

## Documentation

- [Admin Customization Guide](https://pallastrade.cn/docs/developer/customization/admin)
- [Navigation Configuration](https://pallastrade.cn/docs/developer/customization/admin-navigation)
- [Permissions Guide](https://pallastrade.cn/docs/developer/customization/permissions)
