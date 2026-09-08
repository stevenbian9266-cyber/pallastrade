# frozen_string_literal: true

require 'rails_helper'

# PRD-REV-P6-8c AC-R68C-02 —— Reimbursement covering（initiated）记账 helper
RSpec.describe PallasTrade::Reimbursement, type: :model do
  let(:store) { create(:store, code: "reimb_cov_#{SecureRandom.hex(4)}") }
  let(:reason) { create(:refund_reason) }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let!(:payment) do
    p = create(:payment, order: order, payment_method: payment_method, amount: 100,
                         state: 'completed', source: nil, skip_source_requirement: true)
    create(:payment_capture_event, payment: p, amount: 100.0)
    p
  end
  let!(:reimbursement) do
    PallasTrade::Reimbursement.create!(order: order).tap do |r|
      r.update_columns(total: 20)
    end
  end

  def attach_refund(amount:, state:, tx: nil)
    create(:refund, payment: payment, reason: reason, amount: amount, state: 'requested', transaction_id: nil)
      .tap do |r|
        r.update_columns(state: state, transaction_id: tx, reimbursement_id: reimbursement.id,
                         provider_idempotency_key: "refund:#{r.prefixed_id}:execute",
                         succeeded_at: state == 'succeeded' ? Time.current : nil)
      end
  end

  describe 'covering（initiated）记账' do
    it 'refund_coverage_amount 含 requested/processing/ambiguous/succeeded，排除 failed/canceled' do
      attach_refund(amount: 10, state: 'requested')
      attach_refund(amount: 5, state: 'succeeded', tx: 're_ok')
      attach_refund(amount: 7, state: 'failed')

      expect(reimbursement.refund_coverage_amount.to_f).to eq(15.0)
    end

    it 'initiated_amount = coverage + credits；uninitiated = total − initiated' do
      attach_refund(amount: 10, state: 'requested')
      expect(reimbursement.initiated_amount.to_f).to eq(10.0)
      expect(reimbursement.uninitiated_amount.to_f).to eq(10.0)

      attach_refund(amount: 10, state: 'succeeded', tx: 're_ok2')
      expect(reimbursement.reload.initiated_amount.to_f).to eq(20.0)
      expect(reimbursement.uninitiated_amount.to_f).to eq(0.0)
    end

    it 'refund 后续 failed 从 covering 退出（reimbursement 保持已发起状态；资金事实看 refund 行）' do
      attach_refund(amount: 10, state: 'requested')
      reimbursement.update_columns(reimbursement_status: 'reimbursed')
      # 模拟 async 后 provider 拒绝 → refund failed
      reimbursement.refunds.first.update_columns(state: 'failed')

      expect(reimbursement.refund_coverage_amount.to_f).to eq(0.0)
      expect(reimbursement.reload).to be_reimbursed # initiated 语义：reimbursement 不随单笔 refund 翻转
    end
  end
end
