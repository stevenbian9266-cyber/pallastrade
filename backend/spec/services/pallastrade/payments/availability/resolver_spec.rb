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

  # PRD-20260915-payments-d8-支付适用范围引擎-支付商-支付方式-市场-国家-zone-币种-前台入口过滤 AC-002
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

end
