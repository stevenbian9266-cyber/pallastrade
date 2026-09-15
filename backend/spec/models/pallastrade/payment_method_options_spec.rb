# frozen_string_literal: true

# PRD-20260915-admin-管理后台支付配置选项化（切片1）
#   AC-006：optionized 门控 —— 未选项化回落默认入口 / 已选项化且 0 可用入口 = 0 入口
#   AC-007：停用语义在 core 层的表现 —— provider 不再出现在前台/后台列表
#
# 入口（PaymentOption）过渡期存 `metadata["options"]`，不建表（业务方案 §65/§74 阶段一）。
require 'rails_helper'

RSpec.describe PallasTrade::PaymentMethod do
  let(:store) { @default_store || create(:store, default: true, default_currency: 'USD') }

  def method_with(metadata)
    create(:check_payment_method, store: store, metadata: metadata)
  end

  describe 'option API（归一化与只读安全）' do
    it 'normalizes entries and ignores malformed ones' do
      pm = method_with(
        'options' => [
          { 'kind' => 'card', 'active' => true, 'position' => 2 },
          { kind: :apple_pay, 'active' => true, 'position' => 1 },
          'bogus',
          { 'active' => true }
        ]
      )

      expect(pm.payment_options.map { |option| option['kind'] }).to eq(%w[card apple_pay])
    end

    it 'returns [] when metadata is absent or not an array' do
      expect(method_with({}).payment_options).to eq([])
      expect(method_with('options' => 'nope').payment_options).to eq([])
    end

    it 'sorts available options by position and drops disabled ones' do
      pm = method_with(
        'options' => [
          { 'kind' => 'card', 'active' => true, 'position' => 2 },
          { 'kind' => 'apple_pay', 'active' => false, 'position' => 1 },
          { 'kind' => 'google_pay', 'active' => true, 'position' => 3 }
        ]
      )

      expect(pm.available_payment_options.map { |option| option['kind'] }).to eq(%w[card google_pay])
      expect(pm.payment_option_for('apple_pay')['active']).to be(false)
      expect(pm.payment_option_for('missing')).to be_nil
    end
  end

  describe 'optionized 门控（AC-006）' do
    # PRD-20260915-admin-管理后台支付配置选项化-支付商-支付方式-前台入口 AC-006
    it 'falls back to a single default option when not optionized' do
      pm = method_with({})

      expect(pm.optionized?).to be(false)
      expect(pm.frontend_visible?).to be(true)
      expect(pm.effective_payment_options.size).to eq(1)
      expect(pm.effective_payment_options.first['kind']).to be_present
      expect(pm.effective_payment_options.first['active']).to be(true)
    end

    it 'falls back to the default option when not optionized but all options disabled' do
      pm = method_with('options' => [{ 'kind' => 'card', 'active' => false }])

      expect(pm.frontend_visible?).to be(true)
      expect(pm.effective_payment_options.size).to eq(1)
    end

    it 'yields zero entries when optionized without any available option' do
      pm = method_with('optionized' => true, 'options' => [{ 'kind' => 'card', 'active' => false }])

      expect(pm.optionized?).to be(true)
      expect(pm.frontend_visible?).to be(false)
      expect(pm.effective_payment_options).to eq([])
    end

    it 'uses configured options when optionized with active options' do
      pm = method_with(
        'optionized' => true,
        'options' => [
          { 'kind' => 'card', 'active' => true, 'position' => 1 },
          { 'kind' => 'klarna', 'active' => true, 'position' => 2 }
        ]
      )

      expect(pm.frontend_visible?).to be(true)
      expect(pm.effective_payment_options.map { |option| option['kind'] }).to eq(%w[card klarna])
    end
  end

  describe 'order projections（AC-002/AC-007）' do
    let(:order) { create(:order_with_line_items, store: store) }

    # PRD-20260915-admin-管理后台支付配置选项化-支付商-支付方式-前台入口 AC-007
    it 'hides optionized providers with zero entries, keeps legacy providers visible' do
      legacy = create(:check_payment_method, store: store, active: true, display_on: 'front_end')
      hidden = create(:check_payment_method, store: store, active: true, display_on: 'front_end',
                                             metadata: { 'optionized' => true, 'options' => [] })

      expect(order.payment_methods).to include(legacy)
      expect(order.payment_methods).not_to include(hidden)
      expect(order.collect_frontend_payment_methods).not_to include(hidden)
    end
  end

  # D8（PRD-20260915-payments-d8 切片1）：入口级「适用范围」（market / country / zone / currency）
  describe '适用范围规则（AC-001 / AC-003 / AC-006）' do
    def optionized_provider_for(kind, rule_set)
      option = { 'kind' => kind, 'active' => true, 'position' => 1 }
      option['rule_set'] = rule_set if rule_set
      create(:check_payment_method, store: store, active: true, display_on: 'front_end',
                                    metadata: { 'optionized' => true, 'options' => [option] })
    end

    def currency_rule(*values)
      { 'include' => [{ 'dimension' => 'currency', 'operator' => 'in', 'values' => values }] }
    end

    # PRD-20260915-payments-d8-支付适用范围引擎-支付商-支付方式-市场-国家-zone-币种-前台入口过滤 AC-001
    it 'normalizes the stored rule_set, drops invalid entries and summarizes the scope' do
      pm = method_with(
        'options' => [
          { 'kind' => 'card', 'active' => true, 'rule_set' => {
            'include' => [
              { 'dimension' => 'currency', 'operator' => 'in', 'values' => %w[eur] },
              { 'dimension' => 'amount', 'operator' => 'in', 'values' => %w[50] }
            ]
          } }
        ]
      )

      rule_set = pm.payment_option_rule_set('card')
      expect(rule_set['include']).to eq(
        [{ 'dimension' => 'currency', 'operator' => 'in', 'values' => %w[EUR] }]
      )
      expect(pm.payment_option_scope_summary('card')).to include('EUR')
      expect(pm.payment_option_rule_set('missing')).to be_nil
      expect(pm.payment_option_scope_summary('missing')).to eq(I18n.t('pallastrade.payment_option_scope_all'))
    end

    # PRD-20260915-payments-d8-支付适用范围引擎-支付商-支付方式-市场-国家-zone-币种-前台入口过滤 AC-003
    it 'filters frontend providers by order currency' do
      eur_only = optionized_provider_for('card', currency_rule('EUR'))
      usd_order = create(:order_with_line_items, store: store)
      eur_order = create(:order_with_line_items, store: store, currency: 'EUR')

      expect(usd_order.collect_frontend_payment_methods).not_to include(eur_only)
      expect(eur_order.collect_frontend_payment_methods).to include(eur_only)
    end

    # PRD-20260915-payments-d8-支付适用范围引擎-支付商-支付方式-市场-国家-zone-币种-前台入口过滤 AC-003
    it 'filters frontend providers by shipping country and zone membership' do
      de = create(:country, iso: 'DE')
      fr = create(:country, iso: 'FR')

      zone = create(:zone, name: "EU zone #{SecureRandom.hex(3)}")
      zone.zone_members.create!(zoneable: de)

      de_only = optionized_provider_for(
        'card', 'include' => [{ 'dimension' => 'country', 'operator' => 'in', 'values' => %w[DE] }]
      )
      zone_only = optionized_provider_for(
        'apple_pay', 'include' => [{ 'dimension' => 'zone', 'operator' => 'in', 'values' => [zone.id.to_s] }]
      )

      de_order = create(:order_with_line_items, store: store)
      de_order.update!(ship_address: create(:address, country: de))
      fr_order = create(:order_with_line_items, store: store)
      fr_order.update!(ship_address: create(:address, country: fr))

      expect(de_order.collect_frontend_payment_methods).to include(de_only).and include(zone_only)
      expect(fr_order.collect_frontend_payment_methods).not_to include(de_only)
      expect(fr_order.collect_frontend_payment_methods).not_to include(zone_only)
    end

    # PRD-20260915-payments-d8-支付适用范围引擎-支付商-支付方式-市场-国家-zone-币种-前台入口过滤 AC-003
    it 'filters frontend providers by order market' do
      default_market = create(:market, store: store, countries: [create(:country, iso: 'CA')], default: true)
      target_market = create(:market, store: store, countries: [create(:country, iso: 'AT')])
      market_only = optionized_provider_for(
        'card', 'include' => [{ 'dimension' => 'market', 'operator' => 'in', 'values' => [target_market.id.to_s] }]
      )

      other_order = create(:order_with_line_items, store: store, market: default_market)
      market_order = create(:order_with_line_items, store: store, market: target_market)

      expect(other_order.collect_frontend_payment_methods).not_to include(market_only)
      expect(market_order.collect_frontend_payment_methods).to include(market_only)
    end

    # PRD-20260915-payments-d8-支付适用范围引擎-支付商-支付方式-市场-国家-zone-币种-前台入口过滤 AC-006
    it 'keeps rule-less providers available in every context (零回归)' do
      plain = optionized_provider_for('card', nil)
      exotic_order = create(:order_with_line_items, store: store, currency: 'GBP')

      expect(exotic_order.collect_frontend_payment_methods).to include(plain)
      expect(exotic_order.payment_methods).to include(plain)
      expect(exotic_order.collect_backend_payment_methods).to be_a(Array)
    end
  end
end
