# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-catalog-d3-product-merge AC-010 AC-011 AC-012 AC-016
#
#   AC-010 ← FR-006：无权限 → 拒绝且零写入
#   AC-011 ← FR-007：确认页展示预检结果；执行后回显报告
#   AC-012 ← FR-007/FR-008：合并入口可用（比较页 → 预检 → 执行）
#   AC-016 ← FR-010：工作台可撤销合并
RSpec.describe 'Admin product merges', type: :request do
  let!(:store) { create(:store, code: 'd3_merge_store', name: 'D3 Store', default: true) }
  let(:admin) { create(:admin_user, without_admin_role: true) }
  let!(:survivor) { create(:product, store: store, name: 'D3 Keep me', slug: 'd3-keep-me') }
  let!(:absorbed) { create(:product, store: store, name: 'D3 Merge me', slug: 'd3-merge-me') }

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::DuplicateProductsController).to receive(:current_store).and_return(store)
    allow_any_instance_of(PallasTrade::Admin::DuplicateProductsController)
      .to receive(:try_pallastrade_current_user).and_return(admin)
  end

  describe 'GET /admin/duplicate_products/merge (AC-011)' do
    it 'shows the preview and writes nothing' do
      sign_in_as_superuser
      create(:variant, product: absorbed, sku: 'D3-ADMIN-PREVIEW')

      expect do
        get '/admin/duplicate_products/merge',
            params: { survivor_id: survivor.prefixed_id, absorbed_id: absorbed.prefixed_id }
      end.not_to change(PallasTrade::ProductMerge, :count)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('merge-impact')
      expect(response.body).to include('merge-redirects')
      expect(response.body).to include(PallasTrade.t('admin.duplicate_products.merge.impact_heading'))
      # 商品尚未被改动
      expect(absorbed.reload.deleted?).to be(false)
    end

    it 'refuses a selection of the same product' do
      sign_in_as_superuser

      get '/admin/duplicate_products/merge',
          params: { survivor_id: survivor.prefixed_id, absorbed_id: survivor.prefixed_id }

      expect(response).to have_http_status(:redirect)
      expect(PallasTrade::ProductMerge.count).to eq(0)
    end
  end

  describe 'POST /admin/duplicate_products/merge (AC-011 / AC-012)' do
    it 'merges, reports it in the worklist and can be undone (AC-016)' do
      sign_in_as_superuser
      variant = create(:variant, product: absorbed, sku: 'D3-ADMIN-MERGE')

      post '/admin/duplicate_products/merge',
           params: { survivor_id: survivor.prefixed_id, absorbed_id: absorbed.prefixed_id }

      expect(response).to have_http_status(:redirect)
      ledger = PallasTrade::ProductMerge.last
      expect(ledger.survivor_id).to eq(survivor.id)
      expect(variant.reload.product_id).to eq(survivor.id)

      follow_redirect!
      expect(response.body).to include('recent-merge-row')
      expect(response.body).to include('merge-undo-form')

      post '/admin/duplicate_products/undo_merge', params: { merge_id: ledger.prefixed_id }

      expect(response).to have_http_status(:redirect)
      expect(ledger.reload.undone?).to be(true)
      expect(variant.reload.product_id).to eq(absorbed.id)
    end
  end

  describe 'authorization (AC-010)' do
    it 'redirects an anonymous visitor and writes nothing' do
      expect do
        post '/admin/duplicate_products/merge',
             params: { survivor_id: survivor.prefixed_id, absorbed_id: absorbed.prefixed_id }
      end.not_to change(PallasTrade::ProductMerge, :count)

      expect(response).to have_http_status(:redirect)
      expect(absorbed.reload.deleted?).to be(false)
    end
  end
end
