# frozen_string_literal: true

require 'rails_helper'

# PRD-20260915-admin-bulk-operations-2 —— 管理后台商品批量运营 2.0
#（批量价格 / 库存 / 渠道 + 预览确认）
#
#   AC-001/002/003 ← FR-001/FR-006：批量 Set Price（创建/更新、price_list 不受影响、PriceHistory）
#   AC-004 ← FR-002：Adjust %
#   AC-005 ← FR-003：库存调整（创建/增减/clamp/不追踪跳过）
#   AC-006 ← FR-004：渠道批量上下架
#   AC-007 ← FR-005：preview 零写入 + 与执行计数一致
#   AC-008 ← FR-006：权限不足逐项跳过（service 级）
#   AC-009 ← FR-005：执行后 302 回列表 + flash 汇总
#   AC-010 ← FR-005：新增 i18n 键齐备
RSpec.describe 'Admin products bulk operations v2', type: :request do
  # 显式随机 code：store 工厂的序列 code 会与历史测试库残留冲突（已知测试卫生问题）
  let!(:store) do
    create(:store, code: "admin_bulk_#{SecureRandom.hex(4)}", default: true,
                   default_currency: 'USD', name: 'Bulk Store')
  end
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
  end

  def bulk_headers
    { 'HTTP_REFERER' => '/admin/products' }
  end

  def usd_price(variant)
    variant.prices.base_prices.find_by(currency: 'USD')
  end

  describe 'AC-001/AC-002/AC-003 批量 Set Price' do
    it 'overwrites the base price of the selected products (AC-001)' do
      product = create(:product, store: store, price: 10.0, currency: 'USD')
      expect(usd_price(product.master).amount).to eq(10.0)

      sign_in_as_superuser
      put '/admin/products/bulk_update_price',
          params: { ids: [product.id], mode: 'set', currency: 'USD', amount: '25.5' },
          headers: bulk_headers

      expect(response).to have_http_status(:see_other)
      expect(usd_price(product.master.reload).amount).to eq(25.5)
    end

    it 'creates the price row when the product has no price in that currency (AC-001)' do
      product = create(:product, store: store, price: 10.0, currency: 'USD')
      expect(product.master.prices.base_prices.find_by(currency: 'EUR')).to be_nil

      sign_in_as_superuser
      put '/admin/products/bulk_update_price',
          params: { ids: [product.id], mode: 'set', currency: 'EUR', amount: '12' },
          headers: bulk_headers

      expect(product.master.prices.base_prices.find_by(currency: 'EUR').amount).to eq(12)
    end

    it 'leaves price-list prices untouched (AC-002)' do
      product = create(:product, store: store, price: 10.0, currency: 'USD')
      price_list = create(:price_list, store: store)
      list_price = product.master.prices.create!(currency: 'USD', amount: 7, price_list: price_list)

      sign_in_as_superuser
      put '/admin/products/bulk_update_price',
          params: { ids: [product.id], mode: 'set', currency: 'USD', amount: '25' },
          headers: bulk_headers

      expect(list_price.reload.amount).to eq(7)
      expect(usd_price(product.master.reload).amount).to eq(25)
    end

    it 'records price history when the amount changes (AC-003)' do
      product = create(:product, store: store, price: 10.0, currency: 'USD')
      allow(PallasTrade::Config).to receive(:[]).and_call_original
      allow(PallasTrade::Config).to receive(:[]).with(:track_price_history).and_return(true)

      sign_in_as_superuser
      expect do
        put '/admin/products/bulk_update_price',
            params: { ids: [product.id], mode: 'set', currency: 'USD', amount: '33' },
            headers: bulk_headers
      end.to change { PallasTrade::PriceHistory.where(variant_id: product.master.id).count }.by(1)

      expect(PallasTrade::PriceHistory.where(variant_id: product.master.id).last.amount).to eq(33)
    end
  end

  describe 'AC-004 批量按百分比调价' do
    it 'applies the percentage to priced products (AC-004)' do
      product = create(:product, store: store, price: 100.0, currency: 'USD')

      sign_in_as_superuser
      put '/admin/products/bulk_update_price',
          params: { ids: [product.id], mode: 'adjust_percent', currency: 'USD', percent: '10' },
          headers: bulk_headers

      expect(usd_price(product.master.reload).amount).to eq(110.0)
    end

    it 'skips products without a price in the selected currency (AC-004)' do
      product = create(:product, store: store, price: 50.0, currency: 'USD')

      sign_in_as_superuser
      put '/admin/products/bulk_update_price',
          params: { ids: [product.id], mode: 'adjust_percent', currency: 'EUR', percent: '10' },
          headers: bulk_headers

      expect(usd_price(product.master.reload).amount).to eq(50.0)
      expect(flash[:success]).to include('1 skipped')
    end

    it 'skips variants whose adjusted price would be negative (AC-004)' do
      product = create(:product, store: store, price: 10.0, currency: 'USD')

      sign_in_as_superuser
      put '/admin/products/bulk_update_price',
          params: { ids: [product.id], mode: 'adjust_percent', currency: 'USD', percent: '-200' },
          headers: bulk_headers

      expect(usd_price(product.master.reload).amount).to eq(10.0)
      expect(flash[:success]).to include('1 skipped')
    end
  end

  describe 'AC-005 批量库存调整' do
    it 'creates stock items, clamps at zero and skips untracked products (AC-005)' do
      tracked = create(:product, store: store, price: 10.0, currency: 'USD')
      untracked = create(:product, store: store, price: 10.0, currency: 'USD', track_inventory: false)
      location = create(:stock_location)

      sign_in_as_superuser
      put '/admin/products/bulk_adjust_inventory',
          params: { ids: [tracked.id, untracked.id], stock_location_id: location.id, delta: '10' },
          headers: bulk_headers

      item = PallasTrade::StockItem.find_by(variant_id: tracked.master.id, stock_location_id: location.id)
      expect(item.count_on_hand).to eq(10)
      expect(PallasTrade::StockItem.find_by(variant_id: untracked.master.id,
                                            stock_location_id: location.id)).to be_nil
      expect(flash[:success]).to include('1 skipped')

      put '/admin/products/bulk_adjust_inventory',
          params: { ids: [tracked.id], stock_location_id: location.id, delta: '-25' },
          headers: bulk_headers

      expect(item.reload.count_on_hand).to eq(0)
    end
  end

  describe 'AC-006 批量渠道上下架' do
    it 'publishes and unpublishes the selected products (AC-006)' do
      product = create(:product, store: store, price: 10.0, currency: 'USD')
      channel = create(:channel, store: store)

      sign_in_as_superuser
      put '/admin/products/bulk_update_channels',
          params: { ids: [product.id], mode: 'add', channel_ids: [channel.id] },
          headers: bulk_headers

      expect(PallasTrade::ProductPublication.exists?(product_id: product.id, channel_id: channel.id)).to be(true)

      put '/admin/products/bulk_update_channels',
          params: { ids: [product.id], mode: 'remove', channel_ids: [channel.id] },
          headers: bulk_headers

      expect(PallasTrade::ProductPublication.exists?(product_id: product.id, channel_id: channel.id)).to be(false)
    end
  end

  describe 'AC-007 预览零写入与计数一致' do
    it 'does not write prices, stock or channels during preview (AC-007)' do
      product = create(:product, store: store, price: 10.0, currency: 'USD')
      location = create(:stock_location)
      channel = create(:channel, store: store)

      sign_in_as_superuser
      put '/admin/products/bulk_price_preview',
          params: { ids: [product.id], mode: 'set', currency: 'USD', amount: '99' },
          headers: bulk_headers
      expect(response).to have_http_status(:ok)
      expect(usd_price(product.master.reload).amount).to eq(10.0)

      put '/admin/products/bulk_inventory_preview',
          params: { ids: [product.id], stock_location_id: location.id, delta: '5' },
          headers: bulk_headers
      expect(response).to have_http_status(:ok)
      expect(PallasTrade::StockItem.find_by(variant_id: product.master.id,
                                            stock_location_id: location.id)).to be_nil

      put '/admin/products/bulk_channels_preview',
          params: { ids: [product.id], mode: 'add', channel_ids: [channel.id] },
          headers: bulk_headers
      expect(response).to have_http_status(:ok)
      expect(PallasTrade::ProductPublication.exists?(product_id: product.id, channel_id: channel.id)).to be(false)
    end

    it 'reports the same counts for preview and execution (AC-007)' do
      product_a = create(:product, store: store, price: 10.0, currency: 'USD')
      product_b = create(:product, store: store, price: 10.0, currency: 'USD')
      ability = instance_double(PallasTrade::Ability, can?: true)

      service = PallasTrade::Products::BulkPriceUpdate.new(
        products: PallasTrade::Product.where(id: [product_a.id, product_b.id]),
        ability: ability, currency: 'USD', mode: 'set', amount: '20'
      )

      preview = service.preview
      result = service.call

      expect(preview.updated_count).to eq(result.updated_count)
      expect(preview.skipped_count).to eq(result.skipped_count)
      expect(result.updated_count).to eq(2)
    end
  end

  describe 'AC-008 权限不足逐项跳过' do
    it 'skips products whose prices cannot be managed (AC-008)' do
      product = create(:product, store: store, price: 10.0, currency: 'USD')
      ability = instance_double(PallasTrade::Ability, can?: false)

      result = PallasTrade::Products::BulkPriceUpdate.new(
        products: PallasTrade::Product.where(id: product.id),
        ability: ability, currency: 'USD', mode: 'set', amount: '20'
      ).call

      expect(result.skipped_count).to eq(1)
      expect(result.warnings[:permission_denied]).to eq(1)
      expect(usd_price(product.master.reload).amount).to eq(10.0)
    end

    it 'skips products whose stock items cannot be managed (AC-008)' do
      product = create(:product, store: store, price: 10.0, currency: 'USD')
      location = create(:stock_location)
      ability = instance_double(PallasTrade::Ability, can?: false)

      result = PallasTrade::Products::BulkInventoryAdjust.new(
        products: PallasTrade::Product.where(id: product.id),
        ability: ability, stock_location: location, delta: 5
      ).call

      expect(result.skipped_count).to eq(1)
      expect(result.warnings[:permission_denied]).to eq(1)
    end
  end

  describe 'AC-009 结果反馈' do
    it 'redirects back with a summary flash (AC-009)' do
      product = create(:product, store: store, price: 10.0, currency: 'USD')

      sign_in_as_superuser
      put '/admin/products/bulk_update_price',
          params: { ids: [product.id], mode: 'set', currency: 'USD', amount: '20' },
          headers: bulk_headers

      expect(response).to redirect_to('/admin/products')
      expect(flash[:success]).to include('Updated 1 product(s)')
    end
  end

  describe 'AC-010 i18n 完整性' do
    it 'ships every bulk-ops key added by this PRD (AC-010)' do
      keys = %w[
        admin.bulk_ops.products.title.set_price
        admin.bulk_ops.products.title.adjust_price_percent
        admin.bulk_ops.products.title.adjust_inventory
        admin.bulk_ops.products.title.add_to_channels
        admin.bulk_ops.products.title.remove_from_channels
        admin.bulk_ops.products.body.set_price
        admin.bulk_ops.products.preview.title
        admin.bulk_ops.products.preview.confirm
        admin.bulk_ops.products.result.price_updated
        admin.bulk_ops.products.warnings.permission_denied
      ]

      # NOTE: assert through `PallasTrade.t` — the engine translations are
      # resolved via the app-level helper (raw I18n lookups miss them in this
      # environment, including pre-existing admin.bulk_ops keys).
      keys.each do |key|
        expect(PallasTrade.t(key, default: nil)).to be_present, "missing i18n key #{key}"
      end
    end
  end

  describe '批量模态接线（tables 注册 + 表单渲染）' do
    it 'serves the price form for both price actions' do
      sign_in_as_superuser

      %w[set_price adjust_price_percent].each do |kind|
        get '/admin/bulk_operations/new', params: { kind: kind, table_key: 'products' }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('name="mode"')
        expect(response.body).to include('name="currency"')
      end

      get '/admin/bulk_operations/new', params: { kind: 'set_price', table_key: 'products' }
      expect(response.body).to include('name="amount"')

      get '/admin/bulk_operations/new', params: { kind: 'adjust_price_percent', table_key: 'products' }
      expect(response.body).to include('name="percent"')
    end

    it 'serves the inventory and channel forms' do
      sign_in_as_superuser

      get '/admin/bulk_operations/new', params: { kind: 'adjust_inventory', table_key: 'products' }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="delta"')
      expect(response.body).to include('name="stock_location_id"')

      get '/admin/bulk_operations/new', params: { kind: 'add_to_channels', table_key: 'products' }
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/name="channel_ids(\[\])?"/)
      expect(response.body).to include('name="mode"')
    end
  end
end
