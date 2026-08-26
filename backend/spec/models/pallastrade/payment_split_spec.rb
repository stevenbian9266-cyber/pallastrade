# frozen_string_literal: true

require 'rails_helper'

# PRD-20260826-payments-实施-p1-数据模型与语义方法
# AC-004：PaymentSplit 关联 + 唯一性 + 金额字段
RSpec.describe PallasTrade::PaymentSplit, type: :model do
  let!(:store) { create(:store, code: 'psplit_store') }
  let(:user) { create(:user) }
  let(:order) { create(:order, store: store, user: user, item_total: 100, total: 100) }
  let(:payment) { create(:payment, order: order, amount: 10) }
  let(:combination) { create(:payment_combination, store: store, customer: user) }

  it 'persists a split with amounts defaulting to zero (AC-004)' do
    split = create(:payment_split, payment_combination: combination, order: order, payment: payment)
    expect(split).to be_persisted
    expect(split.authorized_amount).to eq(0)
    expect(split.captured_amount).to eq(0)
    expect(split.refunded_amount).to eq(0)
    expect(split.prefixed_id).to start_with('psplit_')
  end

  it 'enforces one split per (combination, order) (AC-004)' do
    create(:payment_split, payment_combination: combination, order: order, payment: payment)
    duplicate = build(:payment_split, payment_combination: combination, order: order, payment: payment)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:order_id]).to be_present
  end

  it 'computes credit_allowed from captured minus refunded (AC-004)' do
    split = create(:payment_split, payment_combination: combination, order: order, payment: payment,
                                   captured_amount: 100, refunded_amount: 30)
    expect(split.credit_allowed).to eq(70)
  end

  it 'rejects negative amounts (AC-004)' do
    split = build(:payment_split, payment_combination: combination, order: order, payment: payment,
                                  refunded_amount: -5)
    expect(split).not_to be_valid
  end
end
