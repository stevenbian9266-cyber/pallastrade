# frozen_string_literal: true

require 'rails_helper'

# PRD-REV-P6-2 AC-R62-04/06 —— Refunds::ExecuteJob（async 执行 / 幂等 / nil 安全 / durable）
RSpec.describe PallasTrade::Refunds::ExecuteJob, type: :job do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'paid')
  end
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: 100,
                     state: 'completed', source: nil, skip_source_requirement: true)
  end

  def stub_credit(&block)
    allow_any_instance_of(PallasTrade::Gateway::Bogus).to receive(:credit, &block)
  end

  it 'executes a requested refund to succeeded via provider' do
    stub_credit { |*_args| double(success?: true, authorization: 're_job_1', params: {}) }
    refund = create(:refund, payment: payment, amount: 40, transaction_id: nil, state: 'requested')

    described_class.perform_now(refund.id)

    refund.reload
    expect(refund).to be_succeeded
    expect(refund.transaction_id).to eq('re_job_1')
  end

  it 'is idempotent: terminal refund does not call provider again' do
    calls = 0
    stub_credit do |*_args|
      calls += 1
      double(success?: true, authorization: 're_job_2', params: {})
    end
    refund = create(:refund, payment: payment, amount: 40, transaction_id: nil, state: 'requested')

    described_class.perform_now(refund.id)
    described_class.perform_now(refund.id) # already succeeded

    expect(calls).to eq(1)
  end

  it 'records ambiguous outcome durably and does not raise' do
    stub_credit do |*_args|
      raise PallasTrade::Core::GatewayError, 'Connection timed out while calling provider'
    end
    refund = create(:refund, payment: payment, amount: 40, transaction_id: nil, state: 'requested')

    expect { described_class.perform_now(refund.id) }.not_to raise_error
    refund.reload
    expect(refund).to be_ambiguous
    expect(PallasTrade::Refund.exists?(refund.id)).to be(true)
  end

  it 'is a safe no-op for a missing refund' do
    expect { described_class.perform_now(9_999_999) }.not_to raise_error
  end

  it 'keeps the durable row when an unexpected local error occurs (no phantom success)' do
    stub_credit { |*_args| double(success?: true, authorization: 're_job_3', params: {}) }
    allow_any_instance_of(PallasTrade::OrderUpdater).to receive(:update).and_raise('boom')
    refund = create(:refund, payment: payment, amount: 40, transaction_id: nil, state: 'requested')

    expect { described_class.perform_now(refund.id) }.not_to raise_error
    expect(PallasTrade::Refund.exists?(refund.id)).to be(true)
    expect(refund.reload).not_to be_succeeded
  end
end
