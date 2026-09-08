# frozen_string_literal: true

require 'rails_helper'

# PRD-REV-P6-7 Financial Convergence（源 §62）：
#   G1 纯 refund posting 缺失 → ReconcileTransaction JOURNAL_POSTING_MISSING（sweeper→Repair 闭环）
#   G2 ReconcileRefund 本地状态显式分类（failed/canceled 无噪音；ambiguous 专用 + provider 解决标记）
#   G3 provider「无此退款」→ PROVIDER_REFUND_MISSING（对称 PROVIDER_PAYMENT_MISSING）
RSpec.describe 'REV-P6-7 Financial Convergence', type: :service do
  let(:store) { @default_store }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end
  let(:pm) { create(:bogus_payment_method, store: store, active: true) }

  def completed_payment
    create(:payment, order: order, payment_method: pm, amount: 100, state: 'completed',
                     source: nil, skip_source_requirement: true)
  end

  describe PallasTrade::Reconciliations::ReconcileRefund do
    it 'G2: failed/canceled（无资金影响）→ NOT_APPLICABLE + NO_PROVIDER_REFUND（消除 completed txn 噪音）' do
      payment = completed_payment
      %w[failed canceled].each do |state|
        refund = create(:refund, payment: payment, amount: 5, state: state, transaction_id: nil)

        result = described_class.call(refund: refund)
        expect(result.value.status.to_s.downcase).to eq('not_applicable')
        expect(result.value.reasons).to eq(['NO_PROVIDER_REFUND'])
      end
    end

    it 'G2: ambiguous/manual_review 无引用 → NEEDS_ATTENTION + LOCAL_REFUND_AMBIGUOUS（非 legacy 错置）' do
      payment = completed_payment
      %w[ambiguous manual_review].each do |state|
        refund = create(:refund, payment: payment, amount: 5, state: state, transaction_id: nil)

        result = described_class.call(refund: refund)
        expect(result.value.status.to_s.downcase).to eq('needs_attention')
        expect(result.value.reasons).to eq(['LOCAL_REFUND_AMBIGUOUS'])
      end
    end

    it 'G2: ambiguous 有引用且 provider MATCHED → MATCHED + LOCAL_AMBIGUOUS_RESOLVED_BY_PROVIDER' do
      refund = create(:refund, payment: completed_payment, amount: 20,
                               state: 'ambiguous', transaction_id: 're_amb_1')

      result = described_class.call(refund: refund)
      expect(result.value.status.to_s.downcase).to eq('matched')
      expect(result.value.reasons).to include('LOCAL_AMBIGUOUS_RESOLVED_BY_PROVIDER')
    end

    it 'G3: provider 明确无此退款 → PROVIDER_REFUND_MISSING（非 PROVIDER_UNAVAILABLE）' do
      refund = create(:refund, payment: completed_payment, amount: 20, transaction_id: 're_missing_1')
      allow(pm).to receive(:fetch_refund_details)
                  .and_raise(Stripe::InvalidRequestError.new('No such refund: re_missing_1', 404))

      result = described_class.call(refund: refund)
      expect(result.value.status.to_s.downcase).to eq('needs_attention')
      expect(result.value.reasons).to eq(['PROVIDER_REFUND_MISSING'])
    end

    it 'G3: 一般 provider 异常 → PROVIDER_UNAVAILABLE（不误归为缺失）' do
      refund = create(:refund, payment: completed_payment, amount: 20, transaction_id: 're_err_1')
      allow(pm).to receive(:fetch_refund_details)
                  .and_raise(Stripe::APIConnectionError.new('connection reset'))

      result = described_class.call(refund: refund)
      expect(result.value.status.to_s.downcase).to eq('needs_attention')
      expect(result.value.reasons).to eq(['PROVIDER_UNAVAILABLE'])
    end
  end

  describe PallasTrade::Reconciliations::ReconcileTransaction do
    def make_txn
      PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: 100)
    end

    def captured_payment(txn)
      session = create(:bogus_payment_session, order: order, payment_method: pm, status: 'completed',
                                               amount: 100, currency: 'USD', commerce_transaction: txn)
      payment = create(:payment, order: order, payment_method: pm, amount: 100, state: 'completed',
                                 payment_session: session, source: nil, skip_source_requirement: true)
      create(:payment_capture_event, payment: payment, amount: 100.0)
      payment
    end

    def make_entry(txn:, type:, amount:, payment: nil, refund: nil)
      PallasTrade::FinancialLedgerEntry.create!(
        commerce_transaction: txn, entry_type: type, amount: amount, currency: 'USD',
        idempotency_key: "spec-p67-#{type}-#{txn.id}-#{SecureRandom.hex(6)}",
        effective_at: Time.current, payment: payment, refund: refund
      )
    end

    it 'G1: succeeded refund 缺 REFUND_SUCCEEDED posting → JOURNAL_POSTING_MISSING；补记后收敛' do
      txn = make_txn
      payment = captured_payment(txn)
      make_entry(txn: txn, type: 'CASH_CAPTURED', amount: 100.0, payment: payment)
      refund = create(:refund, payment: payment, amount: 20, transaction_id: 're_p67_1',
                               state: 'succeeded', succeeded_at: Time.current)

      result = described_class.call(transaction: txn)
      expect(result.value.reasons).to include('JOURNAL_POSTING_MISSING')

      # RepairTransaction 幂等补记后（模拟 entry 已建）→ reason 收敛
      make_entry(txn: txn, type: 'REFUND_SUCCEEDED', amount: -20.0, payment: payment, refund: refund)
      result2 = described_class.call(transaction: txn.reload)
      expect(result2.value.reasons).not_to include('JOURNAL_POSTING_MISSING')
    end
  end
end
