# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13c-fee-cost-report（D13 切片3）
#   AC-4 ← FR-3：单笔计算（百分比 + 固定 + 平台 + 跨境 + 转换；保底/封顶作用域明确）
#   AC-5 ← FR-3：无策略 → 不计费并标记未定价（不臆造成本）
RSpec.describe PallasTrade::Payments::Fees::Calculate do
  let!(:store) { create(:store, code: "d13c_calc_#{SecureRandom.hex(4)}") }

  def policy(attrs = {})
    build(:payment_fee_policy, { store: store, name: 'calc' }.merge(attrs))
  end

  def calculate(amount:, policy:, **overrides)
    described_class.call({
      amount: amount, currency: 'USD', policy: policy
    }.merge(overrides)).value
  end

  describe 'components' do
    it 'computes percentage and fixed fees' do
      result = calculate(amount: 100, policy: policy(percent_fee: 2.9, fixed_fee: 0.3))

      expect(result[:percent_fee]).to eq(2.9.to_d)
      expect(result[:fixed_fee]).to eq(0.3.to_d)
      expect(result[:total_fee]).to eq(3.2.to_d)
      expect(result[:net_amount]).to eq(96.8.to_d)
      expect(result[:priced]).to be(true)
    end

    it 'adds the platform fee to the percentage part' do
      result = calculate(amount: 200, policy: policy(percent_fee: 1, fixed_fee: 0, platform_percent: 0.5))

      expect(result[:percent_fee]).to eq(2.to_d)
      expect(result[:platform_fee]).to eq(1.to_d)
      expect(result[:total_fee]).to eq(3.to_d)
    end

    it 'rounds to two decimals' do
      result = calculate(amount: 33.33, policy: policy(percent_fee: 2.9, fixed_fee: 0))

      expect(result[:percent_fee]).to eq(0.97.to_d)
      expect(result[:total_fee]).to eq(0.97.to_d)
      expect(result[:net_amount]).to eq(32.36.to_d)
    end
  end

  describe 'min / max clamp' do
    it 'applies min_fee to the variable part only (fixed fee added afterwards)' do
      result = calculate(amount: 10, policy: policy(percent_fee: 1, fixed_fee: 0.25, min_fee: 0.5))

      expect(result[:variable_fee]).to eq(0.1.to_d)
      expect(result[:clamped_fee]).to eq(0.5.to_d)
      expect(result[:adjustment]).to eq(0.4.to_d)
      expect(result[:total_fee]).to eq(0.75.to_d)
    end

    it 'applies max_fee to the variable part only' do
      result = calculate(amount: 10_000, policy: policy(percent_fee: 3, fixed_fee: 2, max_fee: 100))

      expect(result[:variable_fee]).to eq(300.to_d)
      expect(result[:clamped_fee]).to eq(100.to_d)
      expect(result[:adjustment]).to eq(-200.to_d)
      expect(result[:total_fee]).to eq(102.to_d)
    end
  end

  describe 'cross-border' do
    it 'charges the cross-border components only when the country differs' do
      policy = policy(percent_fee: 1, fixed_fee: 0, cross_border_percent: 2, cross_border_fixed: 0.5,
                      home_country: 'US')

      domestic = calculate(amount: 100, policy: policy, order_country: 'US')
      abroad = calculate(amount: 100, policy: policy, order_country: 'JP')

      expect(domestic[:cross_border_fee]).to eq(0.to_d)
      expect(domestic[:total_fee]).to eq(1.to_d)
      expect(abroad[:cross_border]).to be(true)
      expect(abroad[:cross_border_fee]).to eq(2.to_d)
      expect(abroad[:fixed_fee]).to eq(0.5.to_d)
      expect(abroad[:total_fee]).to eq(3.5.to_d)
    end

    it 'does not charge (and leaves a signal) when the basis cannot be determined' do
      result = calculate(amount: 100, policy: policy(percent_fee: 1, fixed_fee: 0, cross_border_percent: 2,
                                                     home_country: 'US'), order_country: nil)

      expect(result[:cross_border_fee]).to eq(0.to_d)
      expect(result[:signals]).to include('cross_border_undetermined')
    end

    it 'does not charge when the policy declares no home country' do
      result = calculate(amount: 100, policy: policy(percent_fee: 1, fixed_fee: 0, cross_border_percent: 2),
                         order_country: 'JP')

      expect(result[:cross_border_fee]).to eq(0.to_d)
      expect(result[:signals]).not_to include('cross_border_undetermined')
    end
  end

  describe 'currency conversion' do
    it 'charges only when the payment currency differs from the settlement currency' do
      policy = policy(percent_fee: 1, fixed_fee: 0, currency_conversion_percent: 1.5, settlement_currency: 'USD')

      same = calculate(amount: 100, policy: policy, currency: 'USD')
      different = calculate(amount: 100, policy: policy, currency: 'EUR')

      expect(same[:conversion_fee]).to eq(0.to_d)
      expect(different[:converted]).to be(true)
      expect(different[:conversion_fee]).to eq(1.5.to_d)
      expect(different[:total_fee]).to eq(2.5.to_d)
    end

    it 'leaves a signal when the currency is unknown locally' do
      result = calculate(amount: 100, policy: policy(percent_fee: 1, fixed_fee: 0, currency_conversion_percent: 1,
                                                     settlement_currency: 'USD'), currency: nil)

      expect(result[:signals]).to include('conversion_undetermined')
      expect(result[:total_fee]).to eq(1.to_d)
    end
  end

  describe 'no policy' do
    it 'is unpriced: zero fee, full net, explicit signal' do
      result = calculate(amount: 100, policy: nil)

      expect(result[:priced]).to be(false)
      expect(result[:total_fee]).to eq(0.to_d)
      expect(result[:net_amount]).to eq(100.to_d)
      expect(result[:signals]).to include('no_policy')
    end
  end

  describe 'purity' do
    it 'does not write anything and does not touch money tables' do
      p = policy(percent_fee: 2, fixed_fee: 0)

      expect do
        calculate(amount: 100, policy: p)
      end.not_to change { PallasTrade::PaymentFeePolicy.count + PallasTrade::Payment.count }
    end
  end
end
