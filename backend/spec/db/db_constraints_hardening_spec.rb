# frozen_string_literal: true

# review 批3b-1 (2026-09-06): D1 —— payments.payment_session_id partial UNIQUE（FR-015
# 「1 session ≤ 1 payment」物理兜底）；D4 —— orders.payment_combination_id 死列已删。
require 'rails_helper'

RSpec.describe 'DB constraints hardening (P4 review 3b-1)', type: :model do
  let(:store) { @default_store }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 10, total: 10,
                   payment_state: 'balance_due')
  end
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }

  it 'D1: schema has a partial unique index on payments.payment_session_id' do
    index = ActiveRecord::Base.connection.indexes('pallastrade_payments')
                              .find { |i| i.name == 'idx_pallastrade_payments_session_unique' }
    expect(index).to be_present
    expect(index.unique).to be true
    expect(index.where).to match(/payment_session_id IS NOT NULL/i)
  end

  it 'D1: rejects a second payment linked to the same session (RecordNotUnique)' do
    session = create(:bogus_payment_session, order: order, payment_method: payment_method,
                                             amount: order.total)
    create(:payment, order: order, payment_method: payment_method, amount: order.total,
                     state: 'completed', payment_session: session,
                     source: nil, skip_source_requirement: true)

    # app 层 amount validation 会先拦（order 额度已占）——用 save(validate: false) 直测
    # DB partial unique 兜底（FR-015 物理层）。
    expect do
      payment = build(:payment, order: order, payment_method: payment_method, amount: order.total,
                                state: 'completed', payment_session: session,
                                source: nil, skip_source_requirement: true)
      payment.save(validate: false)
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'D4: orders no longer has the dead payment_combination_id column' do
    expect(PallasTrade::Order.column_names).not_to include('payment_combination_id')
    expect(PallasTrade::Order.reflect_on_all_associations.map(&:name)).not_to include(:payment_combination)
  end
end
