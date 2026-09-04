# frozen_string_literal: true

require 'rails_helper'

# CHK-P1-1A: Store CheckoutSerializer（只读格式化）。
RSpec.describe PallasTrade::Api::V3::Store::Checkout::CheckoutSerializer, type: :model do
  # 复用 testing_support 全局 default store（before(:all) 已创建），避免重复建 store。
  let(:store) { @default_store || create(:store, default: true, default_currency: 'USD') }
  let(:user) { create(:user) }

  def pending_order
    order = create(:order_with_line_items, store: store, user: user,
                                           line_items_price: 100, shipment_cost: 5)
    order.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current,
                         completed_at: nil, payment_state: 'balance_due', payment_total: 0)
    PallasTrade::OrderUpdater.new(order).update
    order.reload
  end

  def serialize(view, params = {})
    described_class.new(view, params: params).to_h
  end

  describe '#to_h (AC-103)' do
    subject(:data) { serialize(view) }

    let(:order) { pending_order }
    let(:view) { PallasTrade::OrderCheckout::View.new.call(order: order) }

    it 'uses prefixed order id' do
      expect(data['id']).to eq(order.prefixed_id)
    end

    it 'outputs order state/status/contact' do
      expect(data['state']).to eq('pending')
      expect(data['status']).to eq('placed')
      expect(data['email']).to eq(order.email)
      expect(data['currency']).to eq(order.currency)
    end

    it 'outputs authoritative money as decimal strings (no minor units, no new contract)' do
      expect(data['item_total'].to_s).to eq(order.item_total.to_s)
      expect(data['delivery_total'].to_s).to eq(order.shipment_total.to_s)
      expect(data['total'].to_s).to eq(order.total.to_s)
      expect(data['amount_due'].to_s).to eq(order.amount_due.to_s)
      expect(data['display_total'].to_s).to eq(order.display_total.to_s)
    end

    it 'outputs items/fulfillments via existing resource serializers' do
      expect(data['items']).to be_an(Array)
      expect(data['items'].first['id']).to eq(order.line_items.first.prefixed_id)
      expect(data['fulfillments']).to be_an(Array)
    end

    it 'outputs shipping/billing address objects when present' do
      expect(data['shipping_address']).to be_a(Hash)
      expect(data['billing_address']).to be_a(Hash)
    end

    it 'outputs discount/tax detail lines (empty arrays by default)' do
      expect(data['discounts']).to eq([])
      expect(data['taxes']).to eq([])
    end

    context 'with adjustments' do
      before do
        create(:adjustment, adjustable: order, order: order, source: create(:tax_rate),
                            amount: 5, label: 'VAT', eligible: true)
      end

      it 'projects tax detail lines and empty discounts' do
        expect(data['taxes']).to be_an(Array)
        # 自定义明细 hash 使用 symbol 键（与 cart express_payment 内联结构一致）。
        expect(data['taxes'].first.keys).to contain_exactly(:id, :amount, :currency)
        expect(data['discounts']).to eq([])
      end
    end

    context 'hide_prices (AC-103 / FR-107)' do
      subject(:data) { serialize(view, hide_prices: true) }

      it 'nulls money fields and detail lines for gated guests' do
        expect(data['total']).to be_nil
        expect(data['display_total']).to be_nil
        expect(data['item_total']).to be_nil
        expect(data['discounts']).to be_nil
        expect(data['taxes']).to be_nil
        # 非金额字段保持可见
        expect(data['state']).to eq('pending')
        expect(data['email']).to eq(order.email)
      end
    end

    context 'version fields (CHK-P1-2)' do
      it 'outputs checkout_version, price_version and expires_at' do
        expect(data['version']).to eq(order.checkout_version)
        expect(data['price_version']).to eq(order.price_version)
        expect(data['expires_at']).to eq(order.checkout_expires_at&.iso8601)
      end

      it 'outputs a persisted price_version and expires_at after Recalculate' do
        PallasTrade::OrderCheckout::Recalculate.call(order: order)
        order.reload
        data = serialize(PallasTrade::OrderCheckout::View.call(order: order))

        expect(data['price_version']).to be_present
        expect(data['expires_at']).to be_present
        expect(data['version']).to eq(order.checkout_version)
      end
    end

    context 'readiness fields (CHK-P1-3)' do
      it 'outputs ready + missing_requirements for a canonical pending order' do
        expect(data['ready']).to be true
        expect(data['missing_requirements']).to eq([])
      end

      it 'outputs ready=false and the missing codes when email is blank' do
        order.update_columns(email: nil)
        data = serialize(PallasTrade::OrderCheckout::View.call(order: order))

        expect(data['ready']).to be false
        expect(data['missing_requirements']).to include('contact')
      end
    end
  end
end
