# frozen_string_literal: true

require 'spec_helper'

# PRD-20260910-promotions-promo-batch3c-redemption-readonly AC-001 AC-002 AC-003 AC-006
# 只读端点：
#   GET /api/v3/admin/promotion_redemptions      列表（store 隔离 + order_id/promotion_id/state 过滤 + 分页）
#   GET /api/v3/admin/promotion_redemptions/:id  详情（prefixed id；404）
RSpec.describe '/api/v3/admin promotion_redemptions (read-only)', type: :request do
  include_context 'API v3 Admin authenticated'

  let(:store) { @default_store }

  def build_redemption(state: 'committed', target_store: nil, order: nil)
    redemption_store = target_store || store
    promotion = create(:promotion_with_order_adjustment, store: redemption_store,
                                                         code: "R#{SecureRandom.hex(3)}",
                                                         weighted_order_adjustment_amount: 5)
    order ||= create(:order_with_line_items, store: redemption_store, line_items_count: 1, line_items_price: 100)

    PallasTrade::PromotionRedemption.create!(
      store: redemption_store, promotion: promotion, order: order, state: state,
      currency: order.currency, amount: -5, reserved_at: Time.current,
      committed_at: state == 'committed' ? Time.current : nil,
      released_at: state == 'released' ? Time.current : nil,
      release_reason: state == 'released' ? 'order_canceled' : nil
    )
  end

  describe 'GET /api/v3/admin/promotion_redemptions（AC-001）' do
    it 'returns store-scoped rows with pagination meta, newest first' do
      older = build_redemption
      newer = build_redemption
      other_store = create(:store, code: "other_#{SecureRandom.hex(4)}")
      build_redemption(target_store: other_store)

      get '/api/v3/admin/promotion_redemptions', headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      ids = body['data'].map { |row| row['id'] }

      expect(ids).to contain_exactly(older.prefixed_id, newer.prefixed_id)
      expect(ids.first).to eq(newer.prefixed_id)
      expect(body['meta']).to include('count' => 2)
      expect(body['data'].first).to include('state' => 'committed')
      expect(body['data'].first['promotion_id']).to eq(newer.promotion.prefixed_id)
      expect(body['data'].first['order_id']).to eq(newer.order.prefixed_id)
    end
  end

  describe 'filters + show（AC-002）' do
    it 'filters by order_id / promotion_id / state' do
      target = build_redemption
      released = build_redemption(state: 'released')

      get '/api/v3/admin/promotion_redemptions', params: { order_id: target.order.prefixed_id }, headers: headers
      expect(response.parsed_body['data'].map { |row| row['id'] }).to eq([target.prefixed_id])

      get '/api/v3/admin/promotion_redemptions', params: { promotion_id: released.promotion.prefixed_id },
                                                 headers: headers
      expect(response.parsed_body['data'].map { |row| row['id'] }).to eq([released.prefixed_id])

      get '/api/v3/admin/promotion_redemptions', params: { state: 'released' }, headers: headers
      expect(response.parsed_body['data'].map { |row| row['id'] }).to eq([released.prefixed_id])
    end

    it 'returns an empty set (not an error) for an unknown filter value' do
      build_redemption

      get '/api/v3/admin/promotion_redemptions', params: { order_id: 'order_missing' }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['data']).to eq([])
    end

    it 'shows one redemption and 404s on an unknown id' do
      redemption = build_redemption

      get "/api/v3/admin/promotion_redemptions/#{redemption.prefixed_id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['id']).to eq(redemption.prefixed_id)
      expect(response.parsed_body['state']).to eq('committed')

      get '/api/v3/admin/promotion_redemptions/redemption_missing', headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'authorization（AC-003）' do
    it 'requires authentication' do
      get '/api/v3/admin/promotion_redemptions'

      expect(response).to have_http_status(:unauthorized)
    end

    context 'with a limited role' do
      include_context 'API v3 Admin with custom permissions'

      let(:custom_permission_set) do
        Class.new(PallasTrade::PermissionSets::Base) do
          def activate!
            can :read, PallasTrade::Order
          end
        end
      end

      it 'forbids reading redemptions without the read capability' do
        build_redemption

        get '/api/v3/admin/promotion_redemptions', headers: headers

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
