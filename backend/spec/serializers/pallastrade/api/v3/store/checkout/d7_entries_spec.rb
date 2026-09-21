# frozen_string_literal: true

require 'rails_helper'

# PRD-20260918-payments-d7-payment-section-express（切片1，checkout 投影）
#   AC-001 ← FR-001：`available_payment_methods[].entries[]` 携带入口级字段与顺序
#   AC-004 ← FR-001/NFR-001：入口集合来自 `Availability::Resolver`（与 Start 同源）——
#           范围规则挡掉的入口**不在 entries 里**（前台因此不可能「看得到、付不了」）
#   AC-005 ← FR-002：provider 级 group / position
RSpec.describe 'D7 checkout entries projection' do
  # 用**真实 Stripe 目录**（声明 card / apple_pay 能力）+ 独立门店
  # （`@default_store` 跨 example 共享，写 metadata 会泄漏到其它用例）。
  let(:store) do
    create(:store, code: "d7-proj-#{SecureRandom.hex(4)}", name: 'D7 Projection Store',
                   default: false, default_currency: 'USD', default_locale: 'en',
                   url: 'https://d7-proj.example.com', mail_from_address: 'no-reply@d7-proj.example.com')
  end
  let(:user) { create(:user) }

  def pending_order
    order = create(:order_with_line_items, store: store, user: user, line_items_price: 100, shipment_cost: 5)
    order.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current,
                         completed_at: nil, payment_state: 'balance_due', payment_total: 0)
    PallasTrade::OrderUpdater.new(order).update
    order.reload
  end

  def optionized_provider(options)
    create(:stripe_gateway, store: store, active: true, display_on: 'front_end',
                            name: 'Optionized provider',
                            metadata: { 'optionized' => true, 'options' => options })
  end

  def entry_for(order, provider)
    view = PallasTrade::OrderCheckout::View.call(order: order)
    data = PallasTrade::Api::V3::Store::Checkout::CheckoutSerializer.new(view).to_h
    data['payment'][:available_payment_methods].find { |m| m[:id] == provider.prefixed_id }
  end

  # PRD-20260918-payments-d7-payment-section-express AC-001
  it 'projects one entry per configured entry with group/position/frontend_kind' do
    provider = optionized_provider([
      { 'kind' => 'card', 'active' => true, 'position' => 1, 'frontend_kind' => 'inline',
        'display_name' => '信用卡' },
      { 'kind' => 'apple_pay', 'active' => true, 'position' => 2, 'frontend_kind' => 'express',
        'display_name' => 'Apple Pay' }
    ])
    order = pending_order

    entry = entry_for(order, provider)

    expect(entry).to be_present
    expect(entry[:entries].map { |e| e['method_key'] }).to eq(%w[card apple_pay])
    expect(entry[:entries].first).to include('option_id' => "#{provider.prefixed_id}:card",
                                             'method_key' => 'card', 'display_name' => '信用卡',
                                             'frontend_kind' => 'inline', 'group' => 'card',
                                             'position' => 1)
    expect(entry[:entries].last).to include('frontend_kind' => 'express', 'group' => 'wallet', 'position' => 2)
    expect(entry[:group]).to eq('card')
    expect(entry[:position]).to eq(1)
  end

  # PRD-20260918-payments-d7-payment-section-express AC-004
  #
  # ⚠️ 收敛切片 4（2026-09-21，payment-convergence-stripe-only §9.1）：入口「适用范围」
  #    （`rule_set` 的 include/exclude 规则）已随该特性下线，故本用例不再用范围规则造场景，
  #    改用**仍在生效**的收窄机制演示同一不变式（entries ⊆ Resolver）：
  #    本单要求 3DS/SCA 认证时，`Resolver` 只放行**声明可强制认证**的入口 ——
  #    Stripe 目录里 `card = supported`、`apple_pay = unsupported`，
  #    因此钱包入口被服务端挡掉（前台不可能「看得到、付不了」）。
  it 'drops entries rejected by the availability resolver (same source as Start)' do
    provider = optionized_provider([
      { 'kind' => 'card', 'active' => true, 'position' => 1, 'frontend_kind' => 'inline' },
      { 'kind' => 'apple_pay', 'active' => true, 'position' => 2, 'frontend_kind' => 'express' }
    ])
    order = pending_order
    # 门店策略：本单一律要求认证（`three_d_secure: unsupported` 的钱包入口因此不可用）
    store.update!(private_metadata: (store.private_metadata || {}).merge(
      PallasTrade::Payments::ThreeDSecure::Policy::STORE_METADATA_KEY => { 'mode' => 'always' }
    ))
    # ⚠️ 认证需求来自「策略 + 最新留痕」，且 `Required` 在**订单对象上做请求内记忆化** ——
    #    策略变更后必须显式刷新店铺关联与判定缓存（真实请求里每单是新对象，测试里需手动清）
    #    范式与 spec/services/pallastrade/payments/availability/d15c_authentication_gate_spec.rb 一致
    store.reload
    order.reload
    PallasTrade::Payments::ThreeDSecure::Required.reset_cache_for(order)

    entry = entry_for(order, provider)
    resolver_kinds = PallasTrade::Payments::Availability::Resolver.available_option_kinds(
      order: order, payment_method: provider
    )

    expect(entry[:entries].map { |e| e['method_key'] }).to eq(%w[card])
    expect(entry[:entries].map { |e| e['method_key'] }).to eq(resolver_kinds)
  end

  # PRD-20260918-payments-d7-payment-section-express AC-002
  it 'keeps a single entry for providers that were never optionized' do
    provider = create(:stripe_gateway, store: store, active: true, display_on: 'front_end',
                                       name: 'Plain provider')
    order = pending_order

    entry = entry_for(order, provider)

    expect(entry[:entries].size).to eq(1)
    expect(entry[:entries].first['method_key']).to eq(provider.default_option_kind)
  end

  # PRD-20260918-payments-d7-payment-section-express AC-006（cart 通道）
  # 购物车单页结账读 `cart.payment_methods`（store `PaymentMethodSerializer`）——
  # 该通道**没有订单上下文**，因此下发「已配置且启用」的入口集合（不过滤），
  # 前台据此才能显示 Apple Pay / Google Pay（可用性仍由 Start 带订单上下文复算）。
  describe 'store PaymentMethodSerializer (cart / order 通道)' do
    def serialized_provider(provider)
      PallasTrade::Api::V3::PaymentMethodSerializer.new(provider, params: { store: store }).to_h
    end

    it 'exposes the entry list so the cart checkout can render every entry' do
      provider = optionized_provider([
        { 'kind' => 'card', 'active' => true, 'position' => 1, 'frontend_kind' => 'inline',
          'display_name' => 'Card' },
        { 'kind' => 'apple_pay', 'active' => true, 'position' => 2, 'frontend_kind' => 'express',
          'display_name' => 'Apple Pay' }
      ])

      data = serialized_provider(provider)

      expect(data['entries'].map { |e| e['method_key'] }).to eq(%w[card apple_pay])
      expect(data['entries'].map { |e| e['frontend_kind'] }).to eq(%w[inline express])
      expect(data['entries'].first['option_id']).to eq("#{provider.prefixed_id}:card")
    end

    it 'keeps a single implicit entry for providers that were never optionized' do
      provider = create(:stripe_gateway, store: store, active: true, display_on: 'front_end',
                                         name: 'Plain cart provider')

      data = serialized_provider(provider)

      expect(data['entries'].size).to eq(1)
      expect(data['entries'].first['method_key']).to eq(provider.default_option_kind)
    end
  end
end
