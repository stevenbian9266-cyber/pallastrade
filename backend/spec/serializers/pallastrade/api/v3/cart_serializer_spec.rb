# frozen_string_literal: true

require 'rails_helper'

# P0-4 (PRD FR-040/FR-041): CartSerializer#express_payment —— Express 金额服务端权威负载。
#   amount/currency = 资金权威（order.amount_due 子单位）
#   display_total   = 展示
#   line_items      = 仅供钱包/UI 展示（Subtotal/Discount/Tax；运费由 shippingRates 单独处理）
# 价格门控（hide_prices）下与其余金额字段一致返回 null。
RSpec.describe PallasTrade::Api::V3::CartSerializer, type: :serializer do
  let(:store) { @default_store }

  def legacy_cart_order
    order = create(:order_with_line_items, store: store, user: create(:user),
                                           shipment_cost: 0, line_items_price: 100)
    order.update_columns(state: 'cart', completed_at: nil, submitted_at: nil,
                         payment_state: nil, payment_total: 0)
    PallasTrade::OrderUpdater.new(order).update
    order.reload
  end

  def serialize(order, params = {})
    described_class.new(order, params: params).to_h
  end

  it 'exposes an express_payment payload with authoritative minor-unit amount and currency' do
    order = legacy_cart_order
    payload = serialize(order)['express_payment']

    expect(payload).not_to be_nil
    expect(payload[:currency]).to eq(order.currency)
    # amount = order.amount_due 子单位（即会话创建金额）
    expect(payload[:amount]).to eq(PallasTrade::Money.new(order.amount_due, currency: order.currency).cents)
    expect(payload[:display_total]).to eq(order.display_amount_due.to_s)
    expect(payload[:line_items]).to include(name: 'Subtotal', amount: 10_000)
  end

  it 'reflects discount and tax line items (display-only, never authoritative)' do
    order = legacy_cart_order
    order.update_columns(
      item_total: 100, additional_tax_total: 8, discount_total: -10,
      total: 98, payment_total: 0
    )
    order.reload

    items = serialize(order)['express_payment'][:line_items]
    names = items.map { |item| item[:name] }
    expect(names).to contain_exactly('Subtotal', 'Discount', 'Tax')
    expect(items.find { |item| item[:name] == 'Discount' }[:amount]).to eq(-1000)
    expect(items.find { |item| item[:name] == 'Tax' }[:amount]).to eq(800)
  end

  it 'returns null when prices are hidden' do
    order = legacy_cart_order

    expect(serialize(order, hide_prices: true)['express_payment']).to be_nil
  end

  # PRD-20260916-payments-d16-payment-method-presentation AC-004：cart 通道（`payment_methods` 走 store
  # `PallasTrade::Api::V3::PaymentMethodSerializer`）与 checkout 通道同源下发入口级展示元数据。
  it 'exposes entry-level presentation metadata on the cart payment_methods payload (D16 AC-004)' do
    # 先建支付方式再建订单：Order#payment_methods 有 @payment_methods 缓存，订单先建会缓存空列表。
    provider = create(:check_payment_method, store: store, active: true, display_on: 'front_end',
                                             name: 'Check provider',
                                             metadata: { 'optionized' => true,
                                                         'options' => [{ 'kind' => 'card', 'active' => true,
                                                                         'position' => 1,
                                                                         'display_name' => '信用卡' }] })
    order = legacy_cart_order

    # 注意：cart 通道经 store `PaymentMethodSerializer`（AMS）序列化 → 键为**字符串**
    # （checkout 通道是手写 hash → 符号键，两处口径不同）。
    entry = serialize(order)['payment_methods'].find { |m| m['id'] == provider.prefixed_id }

    expect(entry).to be_present
    expect(entry['option_id']).to eq("#{provider.prefixed_id}:card")
    expect(entry['method_key']).to eq('card')
    expect(entry['display_name']).to eq('信用卡')
    # 既有字段语义不变（additive）；行基数 = payment method 数（不按入口展开）
    expect(entry['name']).to eq('Check provider')
    expect(entry['type']).to eq('check')
    expect(serialize(order)['payment_methods'].size).to eq(order.payment_methods.size)
  end
end
