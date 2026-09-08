# frozen_string_literal: true

require 'rails_helper'

# PRD-REV-P6-8b AC-R68B-01~04 —— Refunds::ManualRetry 人工同键确定性重试
RSpec.describe PallasTrade::Refunds::ManualRetry, type: :service do
  ActiveJob::Base.queue_adapter = :test

  let(:store) { create(:store, code: "mr_store_#{SecureRandom.hex(4)}") }
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

  def refund_in(state:, key: :auto)
    create(:refund, payment: payment, reason: reason, amount: 10, state: 'requested', transaction_id: nil)
      .tap do |r|
        resolved = key == :auto ? "refund:#{r.prefixed_id}:execute" : key
        r.update_columns(state: state, provider_idempotency_key: resolved)
      end
  end

  describe 'AC-R68B-01 retry_execution 事件覆盖三态' do
    it 'failed/ambiguous/manual_review → can retry_execution; requested 不可' do
      %w[failed ambiguous manual_review].each do |state|
        expect(refund_in(state: state)).to be_can_retry_execution
      end
      expect(refund_in(state: 'requested')).not_to be_can_retry_execution
      expect(refund_in(state: 'processing')).not_to be_can_retry_execution
    end
  end

  describe 'AC-R68B-02 eligible 重试' do
    it 'failed → processing + attempt+1 + ExecuteJob enqueue + Audit（无同步 Execute）' do
      refund = refund_in(state: 'failed')

      expect do
        outcome = described_class.call(refund: refund, actor: 'operator@test')
        expect(outcome).to be_success
      end.to have_enqueued_job(PallasTrade::Refunds::ExecuteJob).with(refund.id)

      refund.reload
      expect(refund.state).to eq('processing')
      expect(refund.attempt_count).to eq(1)
      expect(PallasTrade::AuditLog.where(action: 'refund_manual_retry',
                                         resource_type: 'PallasTrade::Refund',
                                         resource_id: refund.id)).to exist
    end

    it 'ambiguous 与 manual_review 同样可确定性重试' do
      %w[ambiguous manual_review].each do |state|
        refund = refund_in(state: state)
        described_class.call(refund: refund, actor: 'operator@test')
        refund.reload
        expect(refund.state).to eq('processing'), "state=#{state} 应进入 processing"
      end
    end
  end

  describe 'AC-R68B-03 ineligible 零副作用' do
    it 'requested/succeeded/canceled/processing → failure 不入队不审计不改状态' do
      %w[requested succeeded canceled processing].each do |state|
        refund = refund_in(state: state, key: state == 'processing' ? nil : "refund:inelig_#{SecureRandom.hex(4)}:execute")
        before_state = refund.state

        expect do
          outcome = described_class.call(refund: refund, actor: 'operator@test')
          expect(outcome).to be_failure
        end.not_to have_enqueued_job(PallasTrade::Refunds::ExecuteJob)

        refund.reload
        expect(refund.state).to eq(before_state)
      end
      expect(PallasTrade::AuditLog.where(action: 'refund_manual_retry')).not_to exist
    end

    it 'provider_idempotency_key 缺失 → failure（无法同键确定解决）' do
      refund = refund_in(state: 'ambiguous', key: nil)
      expect do
        outcome = described_class.call(refund: refund, actor: 'operator@test')
        expect(outcome).to be_failure
      end.not_to have_enqueued_job(PallasTrade::Refunds::ExecuteJob)
      expect(refund.reload.state).to eq('ambiguous')
    end
  end

  describe 'AC-R68B-04 并发/重复幂等' do
    it '已 processing（前次重试进行中）再次 retry → failure 且只入队一次' do
      refund = refund_in(state: 'failed')
      described_class.call(refund: refund, actor: 'operator@test')
      # 现在 processing；第二次调用于模拟并发窗口
      expect do
        outcome = described_class.call(refund: refund, actor: 'operator@test')
        expect(outcome).to be_failure
      end.not_to have_enqueued_job(PallasTrade::Refunds::ExecuteJob)
    end
  end
end
