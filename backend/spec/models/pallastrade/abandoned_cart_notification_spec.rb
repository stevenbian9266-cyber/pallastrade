# frozen_string_literal: true

require 'rails_helper'

# PRD-20260818-other-p0-3-邮件自动化-弃单恢复
# AC-003 / AC-001：通知幂等（唯一约束）+ 发送标记
RSpec.describe PallasTrade::AbandonedCartNotification, type: :model do
  let!(:store) { create(:store, code: 'abn_model_store') }
  let!(:cart) { create(:order, store: store, email: 'buyer@example.com', state: 'cart') }

  it 'persists a notification and enforces (cart, email) uniqueness' do
    first = store.abandoned_cart_notifications.create!(cart: cart, email: cart.email)
    expect(first).to be_persisted
    expect(first.sent?).to be(false)

    expect {
      store.abandoned_cart_notifications.create!(cart: cart, email: cart.email)
    }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'marks a notification as sent idempotently' do
    notification = store.abandoned_cart_notifications.create!(cart: cart, email: cart.email)
    notification.mark_sent!
    expect(notification.sent?).to be(true)
    expect(store.abandoned_cart_notifications.sent).to include(notification)
  end
end
