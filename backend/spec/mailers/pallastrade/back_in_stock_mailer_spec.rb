# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PallasTrade::BackInStockMailer, type: :mailer do
  let(:store) { create(:store, code: 'bis_mailer_test') }
  let(:product) { create(:product, store: store, name: 'Copper Kettle') }
  let(:subscription) { create(:back_in_stock_subscription, store: store, product: product, email: 'waiting@example.com') }

  describe '#back_in_stock' do
    it 'delivers to the subscriber email with the product name' do
      mail = described_class.back_in_stock(subscription).deliver_now

      expect(mail.to).to eq(['waiting@example.com'])
      expect(mail.subject).to include('Copper Kettle')
      expect(mail.body.encoded).to include('Copper Kettle')
    end
  end
end
