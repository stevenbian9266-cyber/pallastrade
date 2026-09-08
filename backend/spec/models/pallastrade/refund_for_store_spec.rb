# frozen_string_literal: true

require 'rails_helper'

# PRD-REV-P6-8a AC-R68A-01/02 —— Refund.for_store（单订单 ∪ 组合退款 store 归属）+ journal_entries 关联
RSpec.describe PallasTrade::Refund, type: :model do
  let(:store) { create(:store, code: "ref_for_store_#{SecureRandom.hex(4)}") }
  let(:other_store) { create(:store, code: "ref_other_#{SecureRandom.hex(4)}") }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:reason) { create(:refund_reason) }

  def completed_payment(order:)
    pm = create(:bogus_payment_method, store: order.store, active: true)
    payment = create(:payment, order: order, payment_method: pm, amount: 100,
                               state: 'completed', source: nil, skip_source_requirement: true)
    create(:payment_capture_event, payment: payment, amount: 100.0)
    payment
  end

  def order_in(store)
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end

  describe '.for_store' do
    it 'AC-R68A-01: 单订单退款经 payment.order 归属当前 store' do
      order = order_in(store)
      refund = create(:refund, payment: completed_payment(order: order), reason: reason,
                               amount: 10, state: 'succeeded', transaction_id: 're_store_a',
                               succeeded_at: Time.current)

      other_refund = create(:refund,
                            payment: completed_payment(order: order_in(other_store)),
                            reason: reason, amount: 10)

      expect(PallasTrade::Refund.for_store(store)).to include(refund)
      expect(PallasTrade::Refund.for_store(store)).not_to include(other_refund)
      expect(PallasTrade::Refund.for_store(store).count).to eq(1)
    end

    it 'AC-R68A-01: 组合支付退款经 payment.payment_combination 归属（payment.order 为 nil）' do
      combo = create(:payment_combination, store: store)
      payment = create(:payment, order: nil, payment_combination: combo,
                                 payment_method: payment_method, amount: 100,
                                 state: 'completed', source: nil, skip_source_requirement: true)
      refund = create(:refund, payment: payment, reason: reason, amount: 10,
                               state: 'requested', transaction_id: nil)

      expect(PallasTrade::Refund.for_store(store)).to include(refund)
      expect(PallasTrade::Refund.for_store(store).count).to eq(1)
    end

    it 'AC-R68A-01: 排除其它 store 退款（隔离）' do
      other_refund = create(:refund,
                            payment: completed_payment(order: order_in(other_store)),
                            reason: reason, amount: 10)

      expect(PallasTrade::Refund.for_store(store)).not_to include(other_refund)
      expect(PallasTrade::Refund.for_store(store)).to be_empty
    end
  end

  describe '#journal_entries' do
    it 'AC-R68A-02: 未 posting 时返回空关联（不报错）' do
      order = order_in(store)
      refund = create(:refund, payment: completed_payment(order: order), reason: reason,
                               amount: 10, state: 'requested', transaction_id: nil)

      expect(refund.journal_entries).to be_an(ActiveRecord::Associations::CollectionProxy)
      expect(refund.journal_entries.to_a).to eq([])
    end

    it 'AC-R68A-02: journal_entries 关联映射到 FinancialLedgerEntry(refund_id)（posting 链 P4-3 覆盖）' do
      order = order_in(store)
      refund = create(:refund, payment: completed_payment(order: order), reason: reason,
                               amount: 10, state: 'succeeded', transaction_id: 're_ledger',
                               succeeded_at: Time.current)

      reflection = PallasTrade::Refund.reflect_on_association(:journal_entries)
      expect(reflection.klass).to eq(PallasTrade::FinancialLedgerEntry)
      expect(reflection.foreign_key.to_s).to eq('refund_id')
      # posting 链路由 P4-3 spec 覆盖；此处验证关联可查询（无 posting → 空）
      expect(refund.journal_entries.where(entry_type: 'REFUND_SUCCEEDED').count).to eq(0)
    end
  end
end
