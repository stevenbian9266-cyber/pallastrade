# frozen_string_literal: true

require 'rails_helper'

# PRD-20260915-payments-d8-支付适用范围引擎-支付商-支付方式-市场-国家-zone-币种-前台入口过滤
#   AC-001：rule_set 归一（非法维度/算子/空值忽略；空规则 = 不限）
#   AC-002：求值语义（exclude 优先 / match all|any / 未知上下文 collapse 方向）
#   AC-008：能力目录收窄（Capability ∩ Policy）
#   AC-007：evaluate 逐入口原因（调试/解释）
RSpec.describe PallasTrade::Payments::Availability::Resolver do
  let(:store) { @default_store || create(:store, default: true, default_currency: 'USD') }
  let(:order) { create(:order_with_line_items, store: store) }

  def context(**attrs)
    PallasTrade::Payments::Availability::Context.new(**attrs)
  end

  # rules_by_kind: { 'card' => rule_set_or_nil, ... } → 选项化 provider
  def optionized_method(rules_by_kind, attributes = {})
    options = rules_by_kind.map.with_index(1) do |(kind, rule_set), index|
      option = { 'kind' => kind, 'active' => true, 'position' => index }
      option['rule_set'] = rule_set if rule_set
      option
    end

    create(:check_payment_method, store: store, active: true, display_on: 'front_end',
                                  metadata: { 'optionized' => true, 'options' => options }, **attributes)
  end

  def available_kinds(payment_method, **ctx)
    described_class.available_options(order: order, payment_method: payment_method, context: context(**ctx)).
      map { |option| option['kind'] }
  end

  describe 'RuleSet.normalize（AC-001）' do
    subject(:rule_set_module) { PallasTrade::Payments::Availability::RuleSet }

    it 'keeps valid conditions, drops unknown dimensions/operators and empty values' do
      normalized = rule_set_module.normalize(
        'match' => 'any',
        'include' => [
          { 'dimension' => 'market', 'operator' => 'in', 'values' => %w[1 2] },
          { 'dimension' => 'amount', 'operator' => 'in', 'values' => %w[10] },   # 未上线维度
          { 'dimension' => 'country', 'operator' => 'gt', 'values' => %w[US] },  # 未知算子
          { 'dimension' => 'currency', 'operator' => 'in', 'values' => [] },     # 空 values
          { 'dimension' => 'currency', 'operator' => 'eq', 'values' => %w[eur] } # 大小写归一
        ],
        'exclude' => 'bogus'
      )

      expect(normalized['match']).to eq('any')
      expect(normalized['include']).to eq(
        [
          { 'dimension' => 'market', 'operator' => 'in', 'values' => %w[1 2] },
          { 'dimension' => 'currency', 'operator' => 'eq', 'values' => %w[EUR] }
        ]
      )
      expect(normalized['exclude']).to eq([])
    end

    it 'returns nil when no valid condition remains (空规则 = 不限)' do
      expect(rule_set_module.normalize('include' => [{ 'dimension' => 'market' }])).to be_nil
      expect(rule_set_module.normalize('include' => [])).to be_nil
      expect(rule_set_module.normalize(nil)).to be_nil
    end

    it 'defaults match to all and drops eq conditions with several values' do
      normalized = rule_set_module.normalize(
        'include' => [{ 'dimension' => 'currency', 'operator' => 'eq', 'values' => %w[EUR USD] }]
      )

      expect(normalized).to be_nil

      defaulted = rule_set_module.normalize(
        'include' => [{ 'dimension' => 'currency', 'operator' => 'eq', 'values' => %w[EUR] }]
      )
      expect(defaulted['match']).to eq('all')
    end

    it 'summarizes configured scope' do
      rule_set = rule_set_module.normalize(
        'include' => [{ 'dimension' => 'currency', 'operator' => 'in', 'values' => %w[EUR] }],
        'exclude' => [{ 'dimension' => 'country', 'operator' => 'in', 'values' => %w[US] }]
      )

      expect(rule_set_module.summary(rule_set)).to include('EUR').and include('US')
      expect(rule_set_module.summary(nil)).to eq(I18n.t('pallastrade.payment_option_scope_all'))
    end
  end

  # PRD-20260915-payments-d8-支付适用范围引擎-支付商-支付方式-市场-国家-zone-币种-前台入口过滤 AC-002
  describe '求值语义（AC-002）' do
    it 'excludes even when include matches (否定优先)' do
      payment_method = optionized_method(
        'card' => {
          'match' => 'all',
          'include' => [{ 'dimension' => 'currency', 'operator' => 'in', 'values' => %w[EUR] }],
          'exclude' => [{ 'dimension' => 'country', 'operator' => 'in', 'values' => %w[US] }]
        }
      )

      expect(available_kinds(payment_method, currency: 'EUR', country_iso: 'US')).to eq([])
      expect(available_kinds(payment_method, currency: 'EUR', country_iso: 'DE')).to eq(%w[card])
    end

    it 'requires every include condition when match is all' do
      payment_method = optionized_method(
        'card' => {
          'match' => 'all',
          'include' => [
            { 'dimension' => 'currency', 'operator' => 'in', 'values' => %w[EUR] },
            { 'dimension' => 'country', 'operator' => 'in', 'values' => %w[DE] }
          ]
        }
      )

      expect(available_kinds(payment_method, currency: 'EUR', country_iso: 'DE')).to eq(%w[card])
      expect(available_kinds(payment_method, currency: 'EUR', country_iso: 'FR')).to eq([])
      expect(available_kinds(payment_method, currency: 'USD', country_iso: 'DE')).to eq([])
    end

    it 'passes when at least one include condition matches when match is any' do
      payment_method = optionized_method(
        'card' => {
          'match' => 'any',
          'include' => [
            { 'dimension' => 'currency', 'operator' => 'in', 'values' => %w[EUR] },
            { 'dimension' => 'country', 'operator' => 'in', 'values' => %w[DE] }
          ]
        }
      )

      expect(available_kinds(payment_method, currency: 'USD', country_iso: 'DE')).to eq(%w[card])
      expect(available_kinds(payment_method, currency: 'CHF', country_iso: 'FR')).to eq([])
    end

    it 'supports not_in (只在非该值可用)' do
      payment_method = optionized_method(
        'card' => { 'include' => [{ 'dimension' => 'currency', 'operator' => 'not_in', 'values' => %w[USD] }] }
      )

      expect(available_kinds(payment_method, currency: 'USD')).to eq([])
      expect(available_kinds(payment_method, currency: 'EUR')).to eq(%w[card])
    end

    it 'treats unknown context as not matched: include fails closed, exclude fails open' do
      include_rule = optionized_method('card' => {
                                         'include' => [{ 'dimension' => 'country', 'operator' => 'in', 'values' => %w[DE] }]
                                       })
      exclude_rule = optionized_method('apple_pay' => {
                                         'exclude' => [{ 'dimension' => 'country', 'operator' => 'in', 'values' => %w[US] }]
                                       })

      # 地址未填（country 未知）：include 不承诺 → 不出现；exclude 无正证据 → 不排除
      expect(available_kinds(include_rule, currency: 'EUR')).to eq([])
      expect(available_kinds(exclude_rule, currency: 'EUR')).to eq(%w[apple_pay])
    end

    it 'keeps providers without rules available in any context (零回归)' do
      payment_method = optionized_method('card' => nil)

      expect(available_kinds(payment_method, currency: 'USD', country_iso: 'US', market_id: 1)).to eq(%w[card])
      expect(available_kinds(payment_method)).to eq(%w[card])

      legacy = create(:check_payment_method, store: store, active: true, display_on: 'front_end')
      expect(available_kinds(legacy, currency: 'USD')).to eq([legacy.default_option_kind])
    end
  end

  describe '维度求值（AC-003 的求值侧）' do
    it 'evaluates market / country / zone / currency conditions' do
      payment_method = optionized_method(
        'card' => {
          'match' => 'all',
          'include' => [
            { 'dimension' => 'market', 'operator' => 'in', 'values' => %w[7] },
            { 'dimension' => 'zone', 'operator' => 'in', 'values' => %w[3] },
            { 'dimension' => 'currency', 'operator' => 'in', 'values' => %w[EUR] }
          ]
        }
      )

      expect(available_kinds(payment_method, market_id: '7', zone_ids: %w[3], currency: 'EUR')).to eq(%w[card])
      expect(available_kinds(payment_method, market_id: '8', zone_ids: %w[3], currency: 'EUR')).to eq([])
      expect(available_kinds(payment_method, market_id: '7', zone_ids: %w[4], currency: 'EUR')).to eq([])
      expect(available_kinds(payment_method, market_id: '7', zone_ids: %w[3], currency: 'USD')).to eq([])
    end
  end

  # PRD-20260915-payments-d8-支付适用范围引擎-支付商-支付方式-市场-国家-zone-币种-前台入口过滤 AC-008
  describe '能力目录收窄（AC-008）' do
    it 'rejects options whose catalog does not declare the current currency' do
      payment_method = optionized_method('card' => nil)
      allow(payment_method).to receive(:payment_option_catalog).and_return(
        [{ 'kind' => 'card', 'frontend_kind' => 'inline', 'currencies' => %w[EUR] }]
      )

      expect(available_kinds(payment_method, currency: 'EUR')).to eq(%w[card])
      expect(available_kinds(payment_method, currency: 'USD')).to eq([])
    end

    it 'does not narrow when the catalog declares nothing (默认不限制)' do
      payment_method = optionized_method('card' => nil)

      expect(available_kinds(payment_method, currency: 'USD')).to eq(%w[card])
    end
  end

  describe 'evaluate（AC-007）' do
    it 'returns per-kind decisions with reasons' do
      payment_method = optionized_method(
        'card' => { 'exclude' => [{ 'dimension' => 'country', 'operator' => 'in', 'values' => %w[US] }] },
        'apple_pay' => nil
      )

      result = described_class.evaluate(
        order: order, payment_method: payment_method, context: context(country_iso: 'US')
      )

      card = result.find { |entry| entry['kind'] == 'card' }
      expect(card['allowed']).to be(false)
      expect(card['reasons'].first).to include('dimension' => 'country', 'outcome' => 'excluded', 'observed' => %w[US])

      apple_pay = result.find { |entry| entry['kind'] == 'apple_pay' }
      expect(apple_pay['allowed']).to be(true)
      expect(apple_pay['reasons']).to eq([])
    end

    it 'explains unmet include conditions' do
      payment_method = optionized_method(
        'card' => { 'include' => [{ 'dimension' => 'currency', 'operator' => 'in', 'values' => %w[EUR] }] }
      )

      result = described_class.evaluate(
        order: order, payment_method: payment_method, context: context(currency: 'USD')
      )

      entry = result.find { |row| row['kind'] == 'card' }
      expect(entry['allowed']).to be(false)
      expect(entry['reasons'].first['outcome']).to eq('not_matched')
      expect(entry['reasons'].first['observed']).to eq(%w[USD])
    end
  end
end
