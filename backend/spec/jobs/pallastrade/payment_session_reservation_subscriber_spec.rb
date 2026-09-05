# frozen_string_literal: true

require 'rails_helper'

# INV-P3 审计收口 D3 (2026-09-05): payment_session.processing → 刷新订单 RESERVED TTL
# （FR-039/AC-3020：合法 active payment execution 不无保护地超过 reservation validity）。
# 事件在测试环境经 Sidekiq 异步执行 → 与 back_in_stock_subscriber_spec 一致，直接驱动 handler。
# AC-3020/FR-039：合法 active payment execution 不无保护地超过 reservation validity。
RSpec.describe PallasTrade::PaymentSessionReservationSubscriber, type: :job do
  let!(:store) { create(:store, code: 'psr_sub_store') }
  let!(:stock_location) { create(:stock_location, name: 'WH-R', active: true) }
  let(:variant) { create(:product, store: store).master }
  let!(:stock_item) { create(:stock_item, variant: variant, stock_location: stock_location) }
  let!(:order) do
    create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: 10,
                                   variants: [variant])
  end
  let(:line_item) { order.line_items.reload.first }
  let(:payment_method) { create(:bogus_payment_method, name: 'Card', store: store) }
  let(:subscriber) { described_class.new }

  before do
    variant.update_column(:track_inventory, true)
    stock_item.update_columns(count_on_hand: 5, backorderable: false)
  end

  def fire_processing(session)
    subscriber.send(:extend_reservations, double(payload: { 'id' => session.prefixed_id }))
  end

  it 'extends RESERVED TTL when the payment session enters processing (D3)' do
    reservation = create(:stock_reservation, order: order, line_item: line_item,
                                             stock_item: stock_item, quantity: 1,
                                             expires_at: 1.minute.from_now)
    session = payment_method.create_payment_session(order: order, amount: order.total)
    session.save!

    fire_processing(session)

    expect(reservation.reload.expires_at).to be > 5.minutes.from_now
    expect(reservation.reload.state).to eq('reserved')
  end

  it 'extends reservations scoped to the bound commerce_transaction when present' do
    tx = PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase',
                                                  currency: order.currency.to_s, amount: order.total)
    PallasTrade::TransactionOrder.create!(commerce_transaction: tx, order: order,
                                          role: 'primary', amount_snapshot: order.total)
    reservation = create(:stock_reservation, order: order, line_item: line_item,
                                             stock_item: stock_item, quantity: 1,
                                             expires_at: 1.minute.from_now,
                                             commerce_transaction: tx)
    session = create(:bogus_payment_session, order: order, payment_method: payment_method,
                                             status: 'pending', amount: order.total,
                                             currency: order.currency.to_s,
                                             commerce_transaction: tx)

    fire_processing(session)

    expect(reservation.reload.expires_at).to be > 5.minutes.from_now
  end

  it 'does not touch terminal rows (only RESERVED extended)' do
    committed = create(:stock_reservation, order: order, line_item: line_item,
                                           stock_item: stock_item, quantity: 1)
    committed.commit!
    session = payment_method.create_payment_session(order: order, amount: order.total)
    session.save!

    expect { fire_processing(session) }.not_to(change { committed.reload.expires_at })
  end

  it 'is a safe no-op for an unknown session id' do
    expect do
      subscriber.send(:extend_reservations, double(payload: { 'id' => 'ps_missing' }))
    end.not_to raise_error
  end
end
