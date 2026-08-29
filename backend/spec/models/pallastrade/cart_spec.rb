# frozen_string_literal: true

require 'spec_helper'

# PRD-20260829-checkout-订单流程标准电商改造 AC-002（Cart 状态机）/ AC-004（分表）
RSpec.describe PallasTrade::Cart, type: :model do
  let(:store) { @default_store }
  let(:cart) { store.shopping_carts.create!(currency: 'USD', locale: 'en') }
  let(:variant) { create(:variant, product: create(:product, store: store)) }

  describe 'associations' do
    it 'is store-scoped' do
      expect(cart.store).to eq(store)
      expect(cart.prefixed_id).to start_with('cart_')
    end

    it 'has a unique token' do
      other = store.shopping_carts.create!(currency: 'USD', locale: 'en')
      expect(cart.token).to be_present
      expect(cart.token).not_to eq(other.token)
    end

    it 'destroys cart_items on destroy' do
      cart.cart_items.create!(variant: variant, quantity: 2, selected: true)
      expect { cart.destroy }.to change(PallasTrade::CartItem, :count).by(-1)
    end
  end

  describe 'state machine' do
    it 'starts active' do
      expect(cart).to be_active
    end

    it 'converts active → converted and stamps converted_at' do
      cart.convert!
      expect(cart).to be_converted
      expect(cart.converted_at).to be_present
    end

    it 'abandons active → abandoned' do
      cart.abandon!
      expect(cart).to be_abandoned
    end

    it 'cannot convert a converted cart' do
      cart.convert!
      expect(cart.convert).to be(false)
    end
  end

  describe 'selection helpers' do
    it 'selected_items returns only selected rows' do
      selected = cart.cart_items.create!(variant: variant, quantity: 1, selected: true)
      cart.cart_items.create!(variant: create(:variant, product: create(:product, store: store)), quantity: 1, selected: false)

      expect(cart.selected_items).to contain_exactly(selected)
    end

    it 'item_count sums quantities' do
      cart.cart_items.create!(variant: variant, quantity: 2, selected: true)
      expect(cart.item_count).to eq(2)
    end

    it 'item_total sums selected item amounts from live variant prices' do
      cart.cart_items.create!(variant: variant, quantity: 2, selected: true)
      expect(cart.item_total).to eq(variant.amount_in('USD') * 2)
    end
  end
end
