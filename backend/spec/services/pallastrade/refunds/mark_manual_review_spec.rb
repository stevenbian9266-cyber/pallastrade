# frozen_string_literal: true

require 'rails_helper'

# PRD-REV-P6-8b AC-R68B-05 —— Refunds::MarkManualReview 人工标记复核
RSpec.describe PallasTrade::Refunds::MarkManualReview, type: :service do
  ActiveJob::Base.queue_adapter = :test

  let(:store) { create(:store, code: "mmr_store_#{SecureRandom.hex(4)}") }
  let(:reason) { create(:refund_reason) }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let!(:payment) do
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', source: nil, skip_source_requirement: true)
    create(:payment_capture_event, payment: payment, amount: 100.0)
    payment
  end

  def refund_in(state:)
    create(:refund, payment: payment, reason: reason, amount: 10, state: 'requested', transaction_id: nil)
      .tap do |r|
        r.update_columns(state: state, provider_idempotency_key: "refund:#{r.prefixed_id}:execute")
      end
  end

  it 'processing/ambiguous → manual_review（OPERATOR_REVIEW）+ Audit' do
    %w[processing ambiguous].each do |state|
      refund = refund_in(state: state)
      outcome = described_class.call(refund: refund, actor: 'operator@test')
      expect(outcome).to be_success
      expect(refund.reload.state).to eq('manual_review')
      expect(refund.last_error_code).to eq('OPERATOR_REVIEW')
    end
    expect(PallasTrade::AuditLog.where(action: 'refund_mark_review')).to exist
  end

  it 'requested/failed/succeeded/canceled/manual_review → failure 零副作用' do
    %w[requested failed succeeded canceled manual_review].each do |state|
      refund = refund_in(state: state)
      before_state = refund.state
      outcome = described_class.call(refund: refund, actor: 'operator@test')
      expect(outcome).to be_failure, "state=#{state} 应 failure"
      expect(refund.reload.state).to eq(before_state)
    end
    expect(PallasTrade::AuditLog.where(action: 'refund_mark_review')).not_to exist
  end
end
