# frozen_string_literal: true

require 'spec_helper'

# PRD-20260914-checkout-cart-store-credits-canonical AC-001..AC-004、AC-006：
# 车阶段只承载意图（零资金副作用），与礼品卡互斥，金额可省略（= 用尽可用余额）。
RSpec.describe PallasTrade::Carts::ApplyStoreCredit do
  let(:store) { @default_store }
  let(:user) { create(:user) }
  let(:cart) { store.shopping_carts.create!(currency: 'USD', locale: 'en', user: user) }

  def metadata_amount
    (cart.reload.private_metadata || {})[described_class::METADATA_KEY]
  end

  describe '.call' do
    # PRD-20260914-checkout-cart-store-credits-canonical AC-001
    it 'stores the requested amount as cart intent without touching money' do
      credit = create(:store_credit, store: store, user: user, amount: 50.0, currency: 'USD')

      expect { described_class.call(cart: cart, amount: '25') }
        .not_to change { PallasTrade::Payment.count }

      expect(metadata_amount).to eq('25.0')
      expect(credit.reload.amount_used).to eq(0)
      expect(credit.amount_authorized).to eq(0)
    end

    # PRD-20260914-checkout-cart-store-credits-canonical AC-003：省略金额 → 意图 = 当前可用余额合计
    it 'defaults to the available credit total when no amount is given' do
      create(:store_credit, store: store, user: user, amount: 30.0, currency: 'USD')
      create(:store_credit, store: store, user: user, amount: 20.0, currency: 'USD')

      expect(described_class.call(cart: cart)).to be_success
      expect(metadata_amount).to eq('50.0')
    end

    # PRD-20260914-checkout-cart-store-credits-canonical AC-002
    it 'rejects guests, customers without credit, and invalid amounts' do
      guest_cart = store.shopping_carts.create!(currency: 'USD', locale: 'en')
      expect(described_class.call(cart: guest_cart, amount: '10').error.to_s).to eq('store_credit_requires_login')

      expect(described_class.call(cart: cart, amount: '10').error.to_s).to eq('store_credit_not_available')

      create(:store_credit, store: store, user: user, amount: 50.0, currency: 'USD')
      expect(described_class.call(cart: cart, amount: '0').error.to_s).to eq('store_credit_invalid_amount')
      expect(described_class.call(cart: cart, amount: '-5').error.to_s).to eq('store_credit_invalid_amount')
      expect(described_class.call(cart: cart, amount: 'abc').error.to_s).to eq('store_credit_invalid_amount')
      expect(metadata_amount).to be_nil
    end

    # PRD-20260914-checkout-cart-store-credits-canonical AC-002：只用同币种余额（避免 USD 订单吃到 EUR 余额）
    it 'ignores credits in another currency' do
      create(:store_credit, store: store, user: user, amount: 50.0, currency: 'EUR')

      expect(described_class.call(cart: cart, amount: '10').error.to_s).to eq('store_credit_not_available')
    end

    # PRD-20260914-checkout-cart-store-credits-canonical AC-006：与礼品卡意图互斥（镜像 GiftCards::Apply 的权威约束）
    it 'refuses to coexist with a gift card intent' do
      create(:store_credit, store: store, user: user, amount: 50.0, currency: 'USD')
      cart.update!(private_metadata: { 'gift_card_code' => 'some-code' })

      expect(described_class.call(cart: cart, amount: '10').error.to_s).to eq('store_credit_gift_card_conflict')
    end
  end

  # PRD-20260914-checkout-cart-store-credits-canonical AC-004
  describe 'removal' do
    it 'clears the intent and is idempotent' do
      create(:store_credit, store: store, user: user, amount: 50.0, currency: 'USD')
      described_class.call(cart: cart, amount: '10')

      expect(PallasTrade::Carts::RemoveStoreCredit.call(cart: cart)).to be_success
      expect(metadata_amount).to be_nil
      expect(PallasTrade::Carts::RemoveStoreCredit.call(cart: cart)).to be_success
    end
  end
end
