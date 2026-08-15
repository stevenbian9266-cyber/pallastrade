# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PallasTrade::BackInStockSubscription, type: :model do
  let(:store) { create(:store, code: 'bis_model_test') }
  let(:product) { create(:product, store: store) }

  describe 'validations' do
    it 'is valid with a product, email and store' do
      expect(build(:back_in_stock_subscription, store: store, product: product)).to be_valid
    end

    it 'rejects a duplicate (product, email) subscription' do
      create(:back_in_stock_subscription, store: store, product: product, email: 'a@b.com')
      expect(build(:back_in_stock_subscription, store: store, product: product, email: 'a@b.com')).to be_invalid
    end

    it 'allows the same email on different products' do
      other = create(:product, store: store, name: 'Other')
      create(:back_in_stock_subscription, store: store, product: product, email: 'a@b.com')
      expect(build(:back_in_stock_subscription, store: store, product: other, email: 'a@b.com')).to be_valid
    end

    it 'rejects an invalid email' do
      expect(build(:back_in_stock_subscription, store: store, product: product, email: 'nope')).to be_invalid
    end

    it 'rejects an unknown status' do
      expect(build(:back_in_stock_subscription, store: store, product: product, status: 'bogus')).to be_invalid
    end
  end

  describe '#mark_notified!' do
    it 'flips the status to notified' do
      sub = create(:back_in_stock_subscription, store: store, product: product)
      expect { sub.mark_notified! }.to change { sub.reload.status }.from('active').to('notified')
    end
  end
end
