# frozen_string_literal: true

require 'rails_helper'

# PRD-20260911-promotions-promo-batch5b-permission-single-source AC-003 AC-004
# 后台：DB 驱动角色（非 SuperUser）授予 promotions/coupon_codes 后应能访问促销
# 规则/动作入口；未授权资源仍被拒绝。
RSpec.describe 'Admin promotion permissions', type: :request do
  let!(:store) { create(:store, code: 'promo_permission_store', default: true) }
  let(:admin) do
    create(:admin_user, email: 'promo_perm_admin@example.com', password: 'secret',
                        password_confirmation: 'secret', without_admin_role: true)
  end

  def grant_role(**permissions)
    role = create(:role, name: "promo_perm_#{SecureRandom.hex(3)}")
    permissions.each do |resource, actions|
      actions.each do |action|
        role.role_permissions.create!(permission_type: 'function', resource: resource.to_s, action: action.to_s, allowed: true)
      end
    end
    role.role_permissions.create!(permission_type: 'data', resource: 'promotions', scope: 'store',
                                  scope_value: store.id, allowed: true)
    create(:role_user, user: admin, role: role, resource: store, store: store)
    sign_in admin
    allow_any_instance_of(PallasTrade::Admin::PromotionsController).to receive(:current_store).and_return(store)
    allow_any_instance_of(PallasTrade::Admin::CouponCodesController).to receive(:current_store).and_return(store)
  end

  let(:promotion) { create(:promotion, store: store, code: 'PERM1') }

  describe 'promotions 授权（AC-003）' do
    it '规则/动作入口可访问（capability 覆盖多模型）' do
      grant_role(promotions: %w[read create update])

      get PallasTrade.new_admin_promotion_rule_path(promotion)
      expect(response).to have_http_status(:ok)

      get PallasTrade.new_admin_promotion_action_path(promotion)
      expect(response).to have_http_status(:ok)
    end
  end

  describe '未授权资源仍被拒绝（AC-003）' do
    it 'products 未授权时不可访问' do
      grant_role(promotions: %w[read update])

      get PallasTrade.admin_products_path
      expect(response).not_to have_http_status(:ok)
    end
  end

  describe 'coupon_codes 独立 capability（AC-004）' do
    it '未授予 coupon_codes 时券码列表被拒绝，授予后可访问' do
      grant_role(promotions: %w[read update])

      get PallasTrade.admin_promotion_coupon_codes_path(promotion)
      expect(response).not_to have_http_status(:ok)

      role = PallasTrade::RolePermission.joins(:role).where(PallasTrade::Role.arel_table[:name].matches('promo_perm_%')).last&.role
      role.role_permissions.create!(permission_type: 'function', resource: 'coupon_codes', action: 'read', allowed: true)

      get PallasTrade.admin_promotion_coupon_codes_path(promotion)
      expect(response).to have_http_status(:ok)
    end
  end
end
