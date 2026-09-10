# frozen_string_literal: true

require 'spec_helper'

# PRD-20260910-promotions-promo-batch4b-refund-allocation AC-005 AC-006 AC-007
# 只读退款计算预览端点：原金额 / 分摊优惠 / 可退金额；quantities 参数；只读与鉴权。
RSpec.describe '/api/v3/admin/orders/:order_id/refund_calculation', type: :request do
  include_context 'API v3 Admin authenticated'

  let(:store) { @default_store }

  let(:promotion) do
    create(:promotion_with_order_adjustment, store: store, code: 'ALLOCAPI', name: 'Allocation API Promo',
                                             weighted_order_adjustment_amount: 30)
  end

  let(:order) do
    order = create(:order_with_line_items, store: store, line_items_count: 2, line_items_price: 100,
                                           shipment_cost: 50)
    order.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current)
    order.coupon_code = promotion.code
    PallasTrade::PromotionHandler::Coupon.new(order).apply
    order.update_with_updater!
    order.pay!
    order.reload
  end

  def get_calculation(params = {})
    get "/api/v3/admin/orders/#{order.prefixed_id}/refund_calculation", params: params, headers: headers
  end

  def authority_refundable(line_item, quantity)
    return_item = PallasTrade::ReturnItem.new(inventory_unit: line_item.inventory_units.order(:id).first)
    return_item.return_quantity = quantity
    return_item.set_default_pre_tax_amount
    return_item.pre_tax_amount.to_d
  end

  describe 'GET（AC-005）' do
    it 'returns original / allocated / refundable per line and per promotion' do
      get_calculation

      expect(response).to have_http_status(:ok)
      body = response.parsed_body['data']

      expect(body['order_id']).to eq(order.prefixed_id)
      expect(body['available']).to be true
      expect(body['line_items'].size).to eq(2)

      line = order.line_items.order(:id).first
      payload = body['line_items'].find { |row| row['line_item_id'] == line.prefixed_id }

      expect(payload['original_amount'].to_f).to eq(100.0)
      expect(payload['allocated_discount'].to_f).to eq(15.0) # 30 元订单级折扣按 50/50 分摊
      expect(payload['allocated_discount_breakdown']['order_prorata'].to_f).to eq(15.0)
      expect(payload['return_quantity']).to eq(line.quantity)

      # 可退金额 == ReturnItem 权威（同一输入）
      expect(payload['refundable_amount'].to_f).to eq(authority_refundable(line, line.quantity).to_f)

      expect(body['promotions'].first['promotion_id']).to eq(promotion.prefixed_id)
      expect(body['promotions'].first['original_discount'].to_f).to eq(30.0)
      expect(body['promotions'].first['allocated_discount'].to_f).to eq(30.0)
      expect(body['promotions'].first['balanced']).to be true
      expect(body['totals']['allocated_discount'].to_f).to eq(30.0)
    end

    it 'honours quantities[...] for partial returns（AC-005）' do
      line = order.line_items.order(:id).first

      get_calculation(quantities: { line.prefixed_id => 1 })

      body = response.parsed_body['data']
      payload = body['line_items'].find { |row| row['line_item_id'] == line.prefixed_id }

      expect(payload['return_quantity']).to eq(1)
      expect(payload['refundable_amount'].to_f).to eq(authority_refundable(line, 1).to_f)
    end

    it 'returns a zero refundable amount for quantity 0（AC-005）' do
      line = order.line_items.order(:id).first

      get_calculation(quantities: { line.prefixed_id => 0 })

      payload = response.parsed_body['data']['line_items'].find { |row| row['line_item_id'] == line.prefixed_id }
      expect(payload['return_quantity']).to eq(0)
      expect(payload['refundable_amount'].to_f).to eq(0.0)
      expect(payload['refundable_source']).to eq('zero')
    end

    it 'ignores unrelated query params' do
      get_calculation(foo: 'bar')

      expect(response).to have_http_status(:ok)
    end
  end

  describe '只读（AC-006）' do
    it 'creates no Refund / ReturnItem and is idempotent' do
      expect { get_calculation }.not_to change(PallasTrade::Refund, :count)
      expect { get_calculation }.not_to change(PallasTrade::ReturnItem, :count)
      first = response.parsed_body
      get_calculation
      expect(response.parsed_body).to eq(first)
    end

    it 'does not modify the order snapshot' do
      frozen_before = order.order_promotions.map(&:attributes)

      get_calculation

      expect(order.order_promotions.reload.map(&:attributes)).to eq(frozen_before)
    end
  end

  describe '鉴权与参数校验（AC-007）' do
    it 'returns 404 for an unknown order' do
      get '/api/v3/admin/orders/order_doesnotexist/refund_calculation', headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for an order from another store' do
      other_store = create(:store, code: "other_#{SecureRandom.hex(4)}")
      other_order = create(:order_with_line_items, store: other_store, line_items_count: 1, line_items_price: 10)

      get "/api/v3/admin/orders/#{other_order.prefixed_id}/refund_calculation", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 422 for an unknown line_item_id' do
      get_calculation(quantities: { 'li_doesnotexist' => 1 })

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns 422 when the quantity exceeds the line quantity' do
      line = order.line_items.order(:id).first

      get_calculation(quantities: { line.prefixed_id => line.quantity + 1 })

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns 422 for a non-numeric quantity' do
      line = order.line_items.order(:id).first

      get_calculation(quantities: { line.prefixed_id => 'abc' })

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'requires authentication' do
      get "/api/v3/admin/orders/#{order.prefixed_id}/refund_calculation"

      expect(response).to have_http_status(:unauthorized)
    end

    context 'with a limited role' do
      include_context 'API v3 Admin with custom permissions'

      let(:custom_permission_set) do
        Class.new(PallasTrade::PermissionSets::Base) do
          def activate!
            can :read, PallasTrade::Promotion
          end
        end
      end

      it 'forbids reading the calculation without an order read capability' do
        get_calculation

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
