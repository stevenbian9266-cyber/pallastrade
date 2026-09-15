# frozen_string_literal: true

require 'rails_helper'

# PRD-20260915-catalog-batch-d1-product-history —— 后台接入（记录点 + 时间线渲染）
RSpec.describe 'Admin product history timeline', type: :request do
  let(:store) { create(:store, code: 'product_history_admin') }
  let(:admin) do
    create(:admin_user, email: 'merchant@example.com', password: 'secret',
                        password_confirmation: 'secret', without_admin_role: true)
  end

  before do
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::ProductsController).to receive(:current_store).and_return(store)
    # ResourceController#update 的 location_after_save 是绝对 URL（test 环境 host 不同会触发 OpenRedirectError）
    allow_any_instance_of(PallasTrade::Admin::ProductsController)
      .to receive(:location_after_save).and_return('/admin/products')
  end

  describe 'PATCH /admin/products/:id' do
    it 'records the changed attributes with the acting admin' do
      product = create(:product, store: store, name: 'Old Blender', slug: 'old-blender')

      patch "/admin/products/#{product.slug}", params: { product: { name: 'New Blender' } }

      expect(response).to have_http_status(:found)
      log = PallasTrade::AuditLog.where(action: 'product.updated', resource_id: product.id).last
      expect(log).to be_present
      expect(log.after['name']).to eq('New Blender')
      expect(log.metadata['changed']).to include('name')
      expect(log.actor_label).to eq('merchant@example.com')
    end
  end

  describe 'PUT /admin/products/bulk_update_channels' do
    it 'records a bulk entry for every selected product' do
      product = create(:product, store: store, name: 'Bulk Blender')
      channel = create(:channel, store: store)

      put '/admin/products/bulk_update_channels',
          params: { ids: [product.id], mode: 'add', channel_ids: [channel.id] },
          headers: { 'HTTP_REFERER' => '/admin/products' }

      log = PallasTrade::AuditLog.where(action: 'product.bulk_channels_updated', resource_id: product.id).last
      expect(log).to be_present
      expect(log.metadata['source']).to eq('bulk')
      expect(log.metadata['updated_count']).to eq(1)
    end
  end

  describe 'GET /admin/products/:id/edit' do
    it 'renders the timeline with the recorded change' do
      product = create(:product, store: store, name: 'Timeline Blender', slug: 'timeline-blender')
      PallasTrade::Audit.record(
        action: 'product.updated',
        actor: { type: admin.class.name, id: admin.id, label: admin.email },
        resource: product,
        before: { 'name' => 'Before Blender' },
        after: { 'name' => 'Timeline Blender' }
      )
      create(:price_history, variant: product.default_variant,
                             price: product.default_variant.prices.base_prices.first,
                             amount: 42, currency: 'USD', recorded_at: 1.hour.ago)

      get "/admin/products/#{product.slug}/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t('admin.product_history.title'))
      expect(response.body).to include(PallasTrade.t('admin.product_history.kinds.price'))
      expect(response.body).to include('merchant@example.com')
    end

    it 'shows the empty state when nothing happened yet' do
      product = create(:product, store: store, name: 'Fresh Blender', slug: 'fresh-blender')
      # 工厂建价时的 price_history 会出现在时间线，先清掉再验证空态。
      PallasTrade::PriceHistory.where(variant_id: product.variants_including_master.select(:id)).delete_all

      get "/admin/products/#{product.slug}/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t('admin.product_history.title'))
      expect(response.body).to include(PallasTrade.t('admin.product_history.empty'))
    end
  end
end
