# frozen_string_literal: true

require 'spec_helper'

# PRD-20260914-checkout-cart-gift-cards-canonical AC-002 AC-003：
# 车阶段只承载意图（零资金副作用），校验口径与 legacy 端点一致。
RSpec.describe PallasTrade::Carts::ApplyGiftCard do
  let(:store) { @default_store }
  let(:cart) { store.shopping_carts.create!(currency: 'USD', locale: 'en') }

  def metadata_code
    (cart.reload.private_metadata || {})[described_class::METADATA_KEY]
  end

  describe '.call' do
    # AC-002
    it 'stores the normalized code as cart intent' do
      gift_card = create(:gift_card, store: store)

      result = described_class.call(cart: cart, code: "  #{gift_card.code.upcase}  ")

      expect(result).to be_success
      expect(metadata_code).to eq(gift_card.code.downcase)
    end

    # AC-002
    it 'rejects unknown codes without persisting anything' do
      result = described_class.call(cart: cart, code: 'NOPE')

      expect(result).not_to be_success
      expect(result.error.to_s).to eq('gift_card_not_found')
      expect(metadata_code).to be_nil
    end

    # AC-002
    it 'rejects expired and already-redeemed cards' do
      expired = create(:gift_card, :expired, store: store)
      redeemed = create(:gift_card, :redeemed, store: store)

      expect(described_class.call(cart: cart, code: expired.code).error.to_s).to eq('gift_card_expired')
      expect(described_class.call(cart: cart, code: redeemed.code).error.to_s).to eq('gift_card_already_redeemed')
      expect(metadata_code).to be_nil
    end

    # NFR-1：车阶段零资金副作用（不建 payment、不占用余额）
    it 'does not touch money in the cart stage' do
      gift_card = create(:gift_card, store: store)

      expect { described_class.call(cart: cart, code: gift_card.code) }
        .not_to change { PallasTrade::Payment.count }
      expect(gift_card.reload.amount_used).to eq(0)
    end
  end
  # AC-006（切片 2）：与店铺余额意图互斥（镜像 GiftCards::Apply 的权威约束
  # `gift_card_using_store_credit_error`，在意图层就拦住，避免提交才失败）。
  it 'refuses to coexist with a store credit intent' do
    gift_card = create(:gift_card, store: store)
    cart.update!(private_metadata: { 'store_credit_amount' => '10.0' })

    result = described_class.call(cart: cart, code: gift_card.code)

    expect(result.error.to_s).to eq('gift_card_store_credit_conflict')
    expect(metadata_code).to be_nil
  end
  describe 'removal (AC-003)' do
    it 'clears the intent and is idempotent' do
      gift_card = create(:gift_card, store: store)
      described_class.call(cart: cart, code: gift_card.code)

      expect(PallasTrade::Carts::RemoveGiftCard.call(cart: cart)).to be_success
      expect(metadata_code).to be_nil
      # 幂等：无卡时再移除仍成功
      expect(PallasTrade::Carts::RemoveGiftCard.call(cart: cart)).to be_success
    end
  end
end
