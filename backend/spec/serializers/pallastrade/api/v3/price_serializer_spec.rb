# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-catalog-json-ld-phase2 AC-002 AC-007
#
# `price_list_ends_at` 是商品页结构化数据 `priceValidUntil` 的**唯一**数据源：
# 只把**实际命中**的那张价目表的时间窗报出来；未命中价目表（回落默认价格）就是 nil，
# 前台据此省略 `priceValidUntil` —— 不猜一个有效期。
RSpec.describe PallasTrade::Api::V3::PriceSerializer, type: :serializer do
  let(:variant) { create(:variant) }

  # 工厂已经给变体建好了基础价 —— 唯一索引是 (variant_id, currency)，
  # 再建一条同币种的价格会撞车，所以直接用现有的那条，需要时挂上价目表。
  let(:price) { variant.prices.first }

  def serialize(price)
    described_class.new(price, params: {}).to_h
  end

  describe 'price_list_ends_at' do
    it 'is nil for a price that did not come from a price list (AC-002)' do
      expect(price.price_list_id).to be_nil
      expect(serialize(price)['price_list_ends_at']).to be_nil
    end

    it 'is nil when the applied price list has no time window (AC-002)' do
      price.update!(price_list: create(:price_list, ends_at: nil))

      expect(serialize(price)['price_list_ends_at']).to be_nil
    end

    it 'reports the applied price list window as ISO8601 (AC-002)' do
      price_list = create(:price_list, ends_at: Time.zone.parse('2027-03-15 12:00:00'))
      price.update!(price_list: price_list)

      expect(serialize(price)['price_list_ends_at']).to eq(
        price_list.reload.ends_at.iso8601
      )
    end

    it 'does not let the validity date change the price itself (AC-002)' do
      # 它是纯展示派生：金额仍然来自 Price 记录，价目表有截止时间不会改金额。
      before_amount = price.amount
      price.update!(price_list: create(:price_list, ends_at: 1.week.from_now))

      expect(price.reload.amount).to eq(before_amount)
      expect(serialize(price)['amount'].to_s).to eq(before_amount.to_s)
    end
  end

  it 'keeps the pre-existing price fields untouched (AC-007 regression)' do
    payload = serialize(price)

    expect(payload.keys).to contain_exactly(
      'id', 'amount', 'amount_in_cents', 'compare_at_amount',
      'compare_at_amount_in_cents', 'currency', 'display_amount',
      'display_compare_at_amount', 'price_list_id', 'price_list_ends_at'
    )
    expect(payload['currency']).to eq(price.currency)
    expect(payload['price_list_id']).to be_nil
  end
end
