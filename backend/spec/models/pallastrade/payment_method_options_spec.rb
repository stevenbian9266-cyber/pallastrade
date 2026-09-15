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

      expect(pm.options.map { |option| option['kind'] }).to eq(%w[card apple_pay])
    end

    it 'returns [] when metadata is absent or not an array' do
      expect(method_with({}).options).to eq([])
      expect(method_with('options' => 'nope').options).to eq([])
    end

    it 'sorts available options by position and drops disabled ones' do
      pm = method_with(
        'options' => [
          { 'kind' => 'card', 'active' => true, 'position' => 2 },
          { 'kind' => 'apple_pay', 'active' => false, 'position' => 1 },
          { 'kind' => 'google_pay', 'active' => true, 'position' => 3 }
        ]
      )

      expect(pm.available_options.map { |option| option['kind'] }).to eq(%w[card google_pay])
      expect(pm.option_for('apple_pay')['active']).to be(false)
      expect(pm.option_for('missing')).to be_nil
    end
  end

  describe 'optionized 门控（AC-006）' do
    it 'falls back to a single default option when not optionized' do
      pm = method_with({})

      expect(pm.optionized?).to be(false)
      expect(pm.frontend_visible?).to be(true)
      expect(pm.effective_options.size).to eq(1)
      expect(pm.effective_options.first['kind']).to be_present
      expect(pm.effective_options.first['active']).to be(true)
    end

    it 'falls back to the default option when not optionized but all options disabled' do
      pm = method_with('options' => [{ 'kind' => 'card', 'active' => false }])

      expect(pm.frontend_visible?).to be(true)
      expect(pm.effective_options.size).to eq(1)
    end

    it 'yields zero entries when optionized without any available option' do
      pm = method_with('optionized' => true, 'options' => [{ 'kind' => 'card', 'active' => false }])

      expect(pm.optionized?).to be(true)
      expect(pm.frontend_visible?).to be(false)
      expect(pm.effective_options).to eq([])
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
      expect(pm.effective_options.map { |option| option['kind'] }).to eq(%w[card klarna])
    end
  end

  describe 'order projections（AC-002/AC-007）' do
    let(:order) { create(:order_with_line_items, store: store) }

    it 'hides optionized providers with zero entries, keeps legacy providers visible' do
      legacy = create(:check_payment_method, store: store, active: true, display_on: 'front_end')
      hidden = create(:check_payment_method, store: store, active: true, display_on: 'front_end',
                                             metadata: { 'optionized' => true, 'options' => [] })

      expect(order.payment_methods).to include(legacy)
      expect(order.payment_methods).not_to include(hidden)
      expect(order.collect_frontend_payment_methods).not_to include(hidden)
    end
  end
end
