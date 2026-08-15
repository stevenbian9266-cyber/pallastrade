# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PallasTrade::BackInStockSubscriber, type: :job do
  let(:store) { create(:store, code: 'bis_sub_test') }
  let(:product) { create(:product, store: store) }
  let(:subscriber) { PallasTrade::BackInStockSubscriber.new }

  # Drive the subscriber directly (events run through Sidekiq in the test env,
  # so we call the handler with the same payload shape the event bus would).
  def fire_back_in_stock
    subscriber.send(:notify_subscribers, double(payload: { 'id' => product.prefixed_id }))
  end

  describe '#notify_subscribers (product.back_in_stock)' do
    it 'emails active subscriptions and marks them notified' do
      subscription = create(:back_in_stock_subscription, store: store, product: product)

      expect(PallasTrade::BackInStockMailer).to receive(:back_in_stock).with(subscription).and_return(double(deliver_later: true))

      fire_back_in_stock

      expect(subscription.reload.status).to eq('notified')
    end

    it 'does not email subscriptions that were already notified' do
      create(:back_in_stock_subscription, store: store, product: product, status: 'notified')

      expect(PallasTrade::BackInStockMailer).not_to receive(:back_in_stock)

      fire_back_in_stock
    end

    it 'emails each active subscription once' do
      subs = [create(:back_in_stock_subscription, store: store, product: product, email: 'customer1@example.com'),
              create(:back_in_stock_subscription, store: store, product: product, email: 'customer2@example.com')]

      subs.each do |sub|
        expect(PallasTrade::BackInStockMailer).to receive(:back_in_stock).with(sub).and_return(double(deliver_later: true))
      end

      fire_back_in_stock

      expect(subs.map { |s| s.reload.status }).to all(eq('notified'))
    end

    it 'does nothing for a product without subscriptions' do
      expect(PallasTrade::BackInStockMailer).not_to receive(:back_in_stock)

      fire_back_in_stock
    end
  end
end
