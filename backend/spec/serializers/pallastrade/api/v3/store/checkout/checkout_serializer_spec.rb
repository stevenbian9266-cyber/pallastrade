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

    # B1 扩展（PRD-20260914-checkout B1）：credits / capabilities / billing_mode / payment。
    context 'B1 extensions (AC-001..AC-004, AC-008)' do
      it 'outputs credits / capabilities / billing_mode / payment blocks' do
        expect(data['credits']).to eq(gift_cards: [], store_credit: nil)
        expect(data['capabilities']).to eq(
          can_edit_address: true, can_change_shipping: true,
          can_apply_promotion: true, can_pay: true
        )
        expect(%w[same_as_shipping custom]).to include(data['billing_mode'])
        expect(data['payment'][:available_payment_methods]).to be_an(Array)
      end

      it 'serializes front-end payment methods with stable api_type + session flags (AC-008)' do
        pm = create(:check_payment_method, store: store, active: true, display_on: 'front_end')
        serialized = serialize(PallasTrade::OrderCheckout::View.call(order: order))

        entry = serialized['payment'][:available_payment_methods].find { |m| m[:id] == pm.prefixed_id }

        expect(entry).to be_present
        expect(entry[:type]).to eq('check')
        expect(entry[:session_required]).to be(false)
        # PALLAS-CUSTOM: PAY-OPT-1（PRD-20260915 切片2）—— 入口身份（kind）与前端形态 additive 新增
        expect(entry[:kind]).to eq('check')
        expect(entry[:frontend_kind]).to eq('manual')
        expect(entry.keys).to contain_exactly(:id, :name, :description, :type, :session_required, :source_required,
                                              :kind, :frontend_kind, :client_config,
                                              :option_id, :method_key, :display_name,
                                              :requires_authentication)
        # PRD-20260916-payments-d16-payment-method-presentation AC-003：D16 为 additive 变更 ——
        # 既有键集合只增不减（含 D10 的 client_config），且仍保持「每个 payment method 一行」的行基数
        # （视图口径 = order.payment_methods，不按入口 options 展开）。
        expect(serialized['payment'][:available_payment_methods].size).to eq(order.payment_methods.size)
      end

      # PALLAS-CUSTOM: D16 切片1（PRD-20260916-payments-d16-payment-method-presentation AC-001/002）——
      # 入口级展示元数据：运营在后台配置的「门店显示名」到得了前台；未配置回落 provider 名。
      it 'exposes entry-level presentation metadata with provider-name fallback (AC-001/AC-002)' do
        provider = create(:check_payment_method, store: store, active: true, display_on: 'front_end',
                                                 name: 'Check provider',
                                                 metadata: { 'optionized' => true,
                                                             'options' => [{ 'kind' => 'card', 'active' => true,
                                                                             'position' => 1,
                                                                             'display_name' => '信用卡' }] })
        plain = create(:check_payment_method, store: store, active: true, display_on: 'front_end',
                                              name: 'Plain provider')

        serialized = serialize(PallasTrade::OrderCheckout::View.call(order: order))
        entries = serialized['payment'][:available_payment_methods]

        branded = entries.find { |m| m[:id] == provider.prefixed_id }
        expect(branded[:display_name]).to eq('信用卡')
        expect(branded[:method_key]).to eq('card')
        expect(branded[:option_id]).to eq("#{provider.prefixed_id}:card")

        fallback = entries.find { |m| m[:id] == plain.prefixed_id }
        expect(fallback[:display_name]).to eq('Plain provider')
        expect(fallback[:option_id]).to eq("#{plain.prefixed_id}:#{plain.default_option_kind}")
      end

      # PALLAS-CUSTOM: D10（PRD-20260915-payments-d10-client-config AC-005 / FR-003）——
      # 前台密钥下发：契约 additive 新增 `client_config`（publishable 级凭据 + 环境），
      # 取代构建期 `NEXT_PUBLIC_*`；secret 级凭据永不出现在响应里。
      it 'exposes client_config with publishable credentials only (AC-005)' do
        gateway = create(:stripe_gateway, store: store, active: true, display_on: 'both')
        gateway.set_preference(:publishable_key, 'pk_test_d10_payload')
        gateway.set_preference(:secret_key, 'sk_test_d10_payload_secret')
        gateway.save!

        serialized = serialize(PallasTrade::OrderCheckout::View.call(order: order))
        entry = serialized['payment'][:available_payment_methods].find { |m| m[:id] == gateway.reload.prefixed_id }

        expect(entry).to be_present
        expect(entry[:client_config]).to eq(
          provider: 'stripe', environment: 'live',
          publishable: { 'publishable_key' => 'pk_test_d10_payload' }, session_token: nil
        )
        expect(serialized.to_s).not_to include('sk_test_d10_payload_secret')
      end

      # PALLAS-CUSTOM: PAY-OPT-1（切片2 / AC-002 / AC-006）—— 已选项化且零可用入口的 provider
      # 不出现在下单前的结账契约里（前台列表与 payload 同源）。
      it 'omits optionized providers with zero entries from the payment payload (AC-002/AC-006)' do
        hidden = create(:check_payment_method, store: store, active: true, display_on: 'front_end',
                                               metadata: { 'optionized' => true, 'options' => [] })
        serialized = serialize(PallasTrade::OrderCheckout::View.call(order: order))

        ids = serialized['payment'][:available_payment_methods].map { |m| m[:id] }

        expect(ids).not_to include(hidden.prefixed_id)
      end

      it 'projects credit amounts from the order (AC-001/AC-003)' do
        create(:store_credit_payment, order: order, amount: 2, state: 'checkout')
        serialized = serialize(PallasTrade::OrderCheckout::View.call(order: order.reload))

        order.reload
        expect(serialized['credits'][:store_credit][:amount]).to eq(order.total_applied_store_credit.to_s)
        expect(serialized['credits'][:store_credit][:display_amount]).to eq(order.display_total_applied_store_credit.to_s)
      end

      context 'hide_prices (AC-004)' do
        it 'nulls credit amounts but keeps the structure' do
          create(:store_credit_payment, order: order, amount: 2, state: 'checkout')
          serialized = serialize(PallasTrade::OrderCheckout::View.call(order: order.reload), hide_prices: true)

          expect(serialized['credits'][:store_credit]).to eq(amount: nil, display_amount: nil)
          expect(serialized['credits'][:gift_cards]).to eq([])
        end
      end
    end
  end
end
