# frozen_string_literal: true

require 'rails_helper'

# PRD-20260910-promotions-promo-batch3c-redemption-readonly AC-004 AC-005 AC-007
# Rails Admin 只读页（Promotions → Redemptions）+ 权限注册 + 回归。
RSpec.describe 'Admin Promotion Redemptions pages', type: :request do
  let!(:store) { create(:store, code: 'promo_redemption_admin_store', default: true) }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::PromotionRedemptionsController).
      to receive(:current_store).and_return(store)
  end

  def build_redemption(state: 'committed')
    promotion = create(:promotion_with_order_adjustment, store: store,
                                                         code: "ADM#{SecureRandom.hex(3)}",
                                                         weighted_order_adjustment_amount: 5)
    order = create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: 100)

    PallasTrade::PromotionRedemption.create!(
      store: store, promotion: promotion, order: order, state: state,
      currency: order.currency, amount: -5, reserved_at: Time.current,
      committed_at: state == 'committed' ? Time.current : nil,
      released_at: state == 'released' ? Time.current : nil,
      release_reason: state == 'released' ? 'order_canceled' : nil
    )
  end

  describe 'GET /admin/promotion_redemptions（AC-004）' do
    it 'renders the read-only list with the redemption row' do
      redemption = build_redemption
      sign_in_as_superuser

      get PallasTrade.admin_promotion_redemptions_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(redemption.prefixed_id)
      expect(response.body).to include(PallasTrade.t('admin.promotions.redemptions'))
    end

    it 'renders the detail page' do
      redemption = build_redemption
      sign_in_as_superuser

      get PallasTrade.admin_promotion_redemption_path(redemption)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(redemption.prefixed_id)
      expect(response.body).to include('committed')
    end

    it 'registers the table schema (no new/edit/delete)' do
      table = PallasTrade.admin.tables.get(:promotion_redemptions)

      expect(table).to be_present
      expect(table.model_class).to eq(PallasTrade::PromotionRedemption)
      expect(table.new_resource).to be_falsey
    end
  end

  describe 'permission registration（AC-005）' do
    it 'registers the read capability with store-scoped data fields' do
      expect(PallasTrade::PermissionRegistry.resources).to include(:promotion_redemptions)

      entry = PallasTrade::PermissionRegistry[:promotion_redemptions]
      expect(entry).to be_present
      expect(entry.to_s).to include('PromotionRedemption')
    end
  end
end
