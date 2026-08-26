# frozen_string_literal: true

require 'rails_helper'

# PRD-20260826-payments-实施-p1-数据模型与语义方法
# AC-003/007：PaymentCombination 模型字段 + 状态机 + 非法迁移转业务错误
RSpec.describe PallasTrade::PaymentCombination, type: :model do
  let!(:store) { create(:store, code: 'pcom_store') }
  let(:user) { create(:user) }

  it 'persists with default pending status and prefixed id (AC-003)' do
    combination = create(:payment_combination, store: store, customer: user, amount: 100.0)
    expect(combination).to be_persisted
    expect(combination.status).to eq('pending')
    expect(combination.prefixed_id).to start_with('pcom_')
    expect(combination).to be_valid
  end

  it 'transitions pending -> processing -> succeeded (AC-003)' do
    combination = create(:payment_combination, store: store, customer: user, amount: 100.0)
    expect { combination.process! }.not_to raise_error
    expect(combination.status).to eq('processing')
    expect { combination.succeed! }.not_to raise_error
    expect(combination.status).to eq('succeeded')
  end

  it 'raises a business error (not StateMachines::InvalidTransition) on invalid transition (AC-007)' do
    combination = create(:payment_combination, store: store, customer: user, amount: 100.0)
    combination.process!
    combination.succeed!

    expect { combination.succeed! }
      .to raise_error(PallasTrade::PaymentCombination::InvalidTransitionError) do |e|
        expect(e.code).to eq('payment_combination_cannot_succeed')
      end
  end

  it 'supports fail / cancel / expire from pending or processing (AC-003)' do
    canceled = create(:payment_combination, store: store, customer: user, amount: 100.0)
    expect { canceled.cancel! }.not_to raise_error
    expect(canceled.status).to eq('canceled')

    failed = create(:payment_combination, store: store, customer: user, amount: 100.0)
    failed.process!
    expect { failed.fail! }.not_to raise_error
    expect(failed.status).to eq('failed')

    expired = create(:payment_combination, store: store, customer: user, amount: 100.0)
    expect { expired.expire! }.not_to raise_error
    expect(expired.status).to eq('expired')
  end

  it 'links member orders through payment_splits (AC-003)' do
    combination = create(:payment_combination, store: store, customer: user, amount: 100.0)
    order1 = create(:order, store: store, user: user, item_total: 100, total: 100)
    order2 = create(:order, store: store, user: user, item_total: 100, total: 100)

    create(:payment_split, payment_combination: combination, order: order1,
                           payment: create(:payment, order: order1, amount: 60.0))
    create(:payment_split, payment_combination: combination, order: order2,
                           payment: create(:payment, order: order2, amount: 40.0))

    expect(combination.orders).to include(order1, order2)
  end
end
