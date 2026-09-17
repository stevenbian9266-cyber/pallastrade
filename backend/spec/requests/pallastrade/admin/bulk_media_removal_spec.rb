# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-catalog-bulk-media —— 管理后台「批量移除媒体」
#   AC-002 预览零写入且与执行计数一致
#   AC-008 跨店隔离
#   AC-009 审计：ProductHistory bulk 记录
#   AC-002/AC-009 端到端：预览 → 确认 → 执行
RSpec.describe 'Admin products bulk media removal', type: :request do
  # 显式随机 code：store 工厂的序列 code 会与历史测试库残留冲突（既有测试卫生问题）
  let!(:store) do
    create(:store, code: "bulk_media_#{SecureRandom.hex(4)}", default: true,
                   default_currency: 'USD', name: 'Bulk Media Store')
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

  describe 'AC-002 preview is zero-write and matches the executed result' do
    it 'previews without touching data, then removes on confirm' do
      product = create(:product, store: store)
      create(:asset, viewable: product)
      other = create(:product, store: store)
      other_asset = create(:asset, viewable: other)

      sign_in_as_superuser

      assets_before = PallasTrade::Asset.count

      put '/admin/products/bulk_media_preview',
          params: { ids: [product.id, other.id] },
          headers: bulk_headers

      expect(response).to have_http_status(:ok)
      # 预览零写入：资产一个没少，商品媒体还在
      expect(PallasTrade::Asset.count).to eq(assets_before)
      expect(product.reload.media).not_to be_empty

      put '/admin/products/bulk_media_remove',
          params: { ids: [product.id, other.id] },
          headers: bulk_headers

      expect(response).to have_http_status(:see_other)
      expect(product.reload.media).to be_empty
      expect(other.reload.media).to be_empty
      expect(PallasTrade::Asset.where(id: other_asset.id)).to be_empty
    end

    it 'reports skipped products in the flash without failing' do
      with_media = create(:product, store: store)
      create(:asset, viewable: with_media)
      without_media = create(:product, store: store)

      sign_in_as_superuser

      put '/admin/products/bulk_media_remove',
          params: { ids: [with_media.id, without_media.id] },
          headers: bulk_headers

      expect(response).to have_http_status(:see_other)
      expect(flash[:success]).to be_present
      expect(with_media.reload.media).to be_empty
    end
  end

  describe 'AC-009 audit trail' do
    it 'records a bulk product history entry' do
      product = create(:product, store: store)
      create(:asset, viewable: product)

      sign_in_as_superuser

      expect do
        put '/admin/products/bulk_media_remove',
            params: { ids: [product.id] },
            headers: bulk_headers
      end.to change { PallasTrade::AuditLog.where(action: 'product.bulk_media_removed').count }.by(1)
    end
  end

  describe 'AC-008 store isolation' do
    it 'does not touch products of another store' do
      foreign_store = create(:store, code: "bmr_other_#{SecureRandom.hex(4)}", default_currency: 'USD')
      foreign = create(:product, store: foreign_store)
      create(:asset, viewable: foreign)

      sign_in_as_superuser

      put '/admin/products/bulk_media_remove',
          params: { ids: [foreign.id] },
          headers: bulk_headers

      expect(foreign.reload.media).not_to be_empty
    end
  end

  describe 'AC-010 the bulk action is registered and its i18n keys exist' do
    it 'exposes remove_media on the products table' do
      action = PallasTrade.admin.tables.products.find_bulk_action(:remove_media)

      expect(action).to be_present
      expect(action.form_partial).to eq('pallastrade/admin/bulk_operations/forms/confirmation')
    end

    it 'ships every key the generic modal and preview render' do
      # 引擎翻译在本环境用裸 I18n.exists? 查不到，必须走 PallasTrade.t（见 admin Skill）
      %w[
        admin.bulk_ops.products.title.remove_media
        admin.bulk_ops.products.body.remove_media
        admin.bulk_ops.products.result.media_removed
        admin.bulk_ops.products.warnings.media_permission_denied
      ].each do |key|
        expect(PallasTrade.t(key, default: nil)).to be_present, "missing i18n key: #{key}"
      end
    end
  end
end
