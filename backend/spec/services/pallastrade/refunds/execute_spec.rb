# frozen_string_literal: true

require 'rails_helper'

# PRD-REV-P6-1 AC-R61-01/02/03/04/06/08/17 —— Refunds::Execute（durable-first / 三态 / 幂等 / capacity）
# 注：Execute 服务内部经 refund.payment.payment_method 重新加载 provider 实例，故统一用
# allow_any_instance_of 打桩（单测内唯一 provider 类型为 Bogus）。
RSpec.describe PallasTrade::Refunds::Execute, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: 100,
                     state: 'completed', source: nil, skip_source_requirement: true)
  end

  def response_double(success: true, authorization: 're_provider_1')
    double(success?: success, authorization: authorization,
           params: { 'message' => 'declined' }, message: 'declined')
  end

  def stub_credit(&block)
    allow_any_instance_of(PallasTrade::Gateway::Bogus).to receive(:credit, &block)
  end

  def requested_refund(amount: 60)
    create(:refund, payment: payment, amount: amount, transaction_id: nil, state: 'requested')
  end

  it 'AC-R61-01 durable-first: only a persisted requested refund triggers provider, then succeeds' do
    stub_credit { |*_args| response_double(authorization: 're_provider_1') }
    refund = requested_refund
    expect(refund).to be_persisted
    expect(refund.state).to eq('requested')

    result = described_class.call(refund: refund)
    expect(result.success?).to be(true)
    refund.reload
    expect(refund).to be_succeeded
    expect(refund.transaction_id).to eq('re_provider_1')
    expect(refund.provider_idempotency_key).to eq("refund:#{refund.prefixed_id}:execute")
    expect(refund.attempt_count).to eq(1)
    expect(refund.succeeded_at).to be_present
  end

  it 'AC-R61-04 idempotent: repeated Execute on succeeded refund does not call provider again' do
    calls = 0
    stub_credit do |*_args|
      calls += 1
      response_double(authorization: 're_provider_1')
    end
    refund = requested_refund

    described_class.call(refund: refund)
    described_class.call(refund: refund.reload)

    expect(calls).to eq(1)
    expect(refund.reload).to be_succeeded
  end

  it 'definite provider rejection → failed durable row (no raise by default, no provider reference)' do
    stub_credit { |*_args| response_double(success: false) }
    refund = requested_refund

    expect { described_class.call(refund: refund) }.not_to raise_error
    refund.reload
    expect(refund).to be_failed
    expect(refund.last_error_code).to eq('PROVIDER_REJECTED')
    expect(refund.transaction_id).to be_nil
    expect(PallasTrade::Refund.exists?(refund.id)).to be(true)
  end

  it 'timeout/unknown → ambiguous (no auto second refund)' do
    stub_credit do |*_args|
      raise PallasTrade::Core::GatewayError, 'Connection timed out while calling provider'
    end
    refund = requested_refund

    expect { described_class.call(refund: refund) }.not_to raise_error
    refund.reload
    expect(refund).to be_ambiguous
    expect(refund.last_error_code).to eq('PROVIDER_AMBIGUOUS')
  end

  it 'raise_on_failure keeps legacy semantics (reimbursement/gateway-cancel)' do
    stub_credit { |*_args| response_double(success: false) }
    refund = requested_refund

    expect { described_class.call(refund: refund, raise_on_failure: true) }
      .to raise_error(PallasTrade::Core::GatewayError)
    refund.reload
    expect(refund).to be_failed
  end

  it 'AC-R61-08 claim-time capacity guard: over-capacity in-flight refund fails without PSP' do
    expect_any_instance_of(PallasTrade::Gateway::Bogus).not_to receive(:credit)
    create(:refund, payment: payment, amount: 80, transaction_id: 're_taken') # succeeded → capacity 20
    # 模拟两笔并发都通过 create 校验后的竞态：第二笔绕过 create 校验直接落库 requested
    refund = build(:refund, payment: payment, amount: 30, transaction_id: nil, state: 'requested')
    refund.save!(validate: false)

    described_class.call(refund: refund)
    refund.reload
    expect(refund).to be_failed
    expect(refund.last_error_code).to eq('CAPACITY_EXCEEDED')
  end

  it 'AC-R61-06 durable: local projection failure leaves durable row, never a phantom success' do
    stub_credit { |*_args| response_double(authorization: 're_provider_1') }
    refund = requested_refund

    allow_any_instance_of(PallasTrade::OrderUpdater).to receive(:update).and_raise('boom')
    expect { described_class.call(refund: refund) }.to raise_error(StandardError)

    expect(PallasTrade::Refund.exists?(refund.id)).to be(true)
    expect(refund.reload.state).to be_in(%w[processing requested ambiguous])
    expect(refund.reload).not_to be_succeeded
  end
end
