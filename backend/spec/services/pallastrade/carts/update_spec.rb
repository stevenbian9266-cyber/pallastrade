# frozen_string_literal: true

require 'spec_helper'

# PRD-20260913-checkout-billing-mode AC-001..AC-003：
# 账单地址「同配送 / 独立」语义在购物车层显式建模（`billing_mode` + legacy `use_shipping`）。
RSpec.describe PallasTrade::Carts::Update, type: :service do
  let(:store) { @default_store }
  let(:cart) { store.shopping_carts.create!(currency: 'USD', locale: 'en') }

  before do
    # 账单地址校验要求 country 记录存在（Address belongs_to country via country_iso）
    PallasTrade::Country.find_by(iso: 'GB') || create(:country, iso: 'GB', name: 'United Kingdom')
  end

  def complete_billing(**overrides)
    {
      first_name: 'Ada',
      last_name: 'Lovelace',
      address1: '1 Analytical Way',
      city: 'London',
      postal_code: 'N1 1AA',
      country_iso: 'GB'
    }.merge(overrides)
  end

  describe 'billing_mode' do
    # PRD-20260913-checkout-billing-mode AC-001
    it 'clears an existing billing address when billing_mode is same_as_shipping' do
      cart.update!(billing_address: create(:address, user: nil))

      result = described_class.call(cart: cart, params: { billing_mode: 'same_as_shipping' })

      expect(result).to be_success
      expect(cart.reload.billing_address_id).to be_nil
    end

    # PRD-20260913-checkout-billing-mode AC-001
    it 'stores the explicit billing address when billing_mode is custom' do
      result = described_class.call(cart: cart, params: { billing_mode: 'custom', billing_address: complete_billing })

      expect(result).to be_success
      expect(cart.reload.billing_address).to be_present
      expect(cart.billing_address.city).to eq('London')
      expect(cart.billing_address.first_name).to eq('Ada')
    end

    # PRD-20260913-checkout-billing-mode AC-002：legacy `use_shipping` 兼容映射
    it 'maps legacy use_shipping true to same_as_shipping' do
      cart.update!(billing_address: create(:address, user: nil))

      result = described_class.call(cart: cart, params: { use_shipping: true })

      expect(result).to be_success
      expect(cart.reload.billing_address_id).to be_nil
    end

    # PRD-20260913-checkout-billing-mode AC-002：`use_shipping: false` 不创建地址、不清除既有地址
    it 'keeps the existing billing address when use_shipping is false' do
      existing = create(:address, user: nil)
      cart.update!(billing_address: existing)

      result = described_class.call(cart: cart, params: { use_shipping: false })

      expect(result).to be_success
      expect(cart.reload.billing_address_id).to eq(existing.id)
    end

    # PRD-20260913-checkout-billing-mode AC-003：自定义账单地址不完整 → 失败且不落库半空地址
    it 'rejects an incomplete custom billing address without persisting it' do
      result = described_class.call(
        cart: cart,
        params: { billing_mode: 'custom', billing_address: { city: 'London' } }
      )

      expect(result).to be_failure
      expect(result.error.to_s).to match(/incomplete/i)
      expect(cart.reload.billing_address_id).to be_nil
    end

    # PRD-20260913-checkout-billing-mode AC-001：非法枚举值忽略（不猜测语义）
    it 'ignores an unknown billing_mode value' do
      existing = create(:address, user: nil)
      cart.update!(billing_address: existing)

      result = described_class.call(cart: cart, params: { billing_mode: 'whatever' })

      expect(result).to be_success
      expect(cart.reload.billing_address_id).to eq(existing.id)
    end
  end
end
