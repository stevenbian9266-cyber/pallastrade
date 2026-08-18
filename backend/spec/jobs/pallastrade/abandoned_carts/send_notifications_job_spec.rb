# frozen_string_literal: true

require 'rails_helper'

ActiveJob::Base.queue_adapter = :test

# PRD-20260818-other-p0-3-邮件自动化-弃单恢复
# AC-002 / AC-003 / AC-006：扫描条件 + 幂等 + 场景开关
RSpec.describe PallasTrade::AbandonedCarts::SendNotificationsJob, type: :job do
  let!(:store) { create(:store, code: 'abn_job_store') }
  let!(:variant) { create(:variant) }

  # abandoned eligible cart: incomplete + email + line items + old last_activity
  let!(:old_cart) do
    create(:order, store: store, email: 'buyer@example.com', state: 'cart', user: nil, last_activity_at: 3.days.ago)
      .tap { |o| create(:line_item, order: o, variant: variant, quantity: 1) }
  end

  it 'sends a recovery email and records a notification for eligible carts' do
    expect {
      described_class.perform_now(threshold_hours: 24, store_id: store.id)
    }.to change(store.abandoned_cart_notifications, :count).by(1)
       .and have_enqueued_mail(PallasTrade::AbandonedCartMailer, :recovery_email)
    expect(store.abandoned_cart_notifications.first.email).to eq(old_cart.email)
  end

  it 'does not re-notify a cart that already has a notification (idempotent)' do
    store.abandoned_cart_notifications.create!(cart: old_cart, email: old_cart.email)
    expect {
      described_class.perform_now(threshold_hours: 24, store_id: store.id)
    }.not_to change(store.abandoned_cart_notifications, :count)
  end

  it 'skips carts without an email, with no line items, or recently active' do
    no_email = create(:order, store: store, state: 'cart', user: nil, last_activity_at: 3.days.ago)
    empty = create(:order, store: store, email: 'empty@example.com', state: 'cart', user: nil, last_activity_at: 3.days.ago)
    fresh = create(:order, store: store, email: 'fresh@example.com', state: 'cart', user: nil, last_activity_at: 1.hour.ago)
      .tap { |o| create(:line_item, order: o, variant: variant, quantity: 1) }

    described_class.perform_now(threshold_hours: 24, store_id: store.id)
    expect(store.abandoned_cart_notifications.exists?(cart_id: no_email.id)).to be(false)
    expect(store.abandoned_cart_notifications.exists?(cart_id: empty.id)).to be(false)
    expect(store.abandoned_cart_notifications.exists?(cart_id: fresh.id)).to be(false)
    # 共享的 old_cart 仍符合条件会被通知（隔离验证三例外项不受影响）
    expect(store.abandoned_cart_notifications.exists?(cart_id: old_cart.id)).to be(true)
  end

  it 'respects the abandoned_cart scenario switch (disabled → no emails)' do
    store.preferences['email_scenario_abandoned_cart.recovery_email'] = false
    store.save!
    expect {
      described_class.perform_now(threshold_hours: 24, store_id: store.id)
    }.not_to change(store.abandoned_cart_notifications, :count)
  end
end
