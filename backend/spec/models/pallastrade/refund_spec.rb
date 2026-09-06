# frozen_string_literal: true

# REV-P6-1 (PRD-20260906-payments-rev-p6-1-durable-refund-lifecycle-foundation):
# 并发防双退由「Refund create 校验（amount <= refundable_capacity，含 in-flight）+
# Refunds::Execute claim 的 payment 锁内重校验」共同保证（AC-R61-08，替代原 bugfix A6 的
# after_create perform! raise-回滚语义——失败不再回滚，改持久化 FAILED durable 行）。
require 'rails_helper'

RSpec.describe PallasTrade::Refund, type: :model do
  let(:store) { @default_store }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'paid')
  end

  def captured_payment(amount: 100)
    pm = create(:bogus_payment_method, store: store, active: true)
    session = create(:bogus_payment_session, order: order, payment_method: pm, status: 'completed',
                                             amount: amount, currency: 'USD')
    create(:payment, order: order, payment_method: pm, amount: amount, state: 'completed',
                     payment_session: session, source: nil, skip_source_requirement: true)
  end

  it 'REV-P6-1: claim re-validates capacity under the payment lock (blocks double refund)' do
    payment = captured_payment(amount: 100)
    r1 = create(:refund, payment: payment, amount: 60, transaction_id: nil, state: 'requested')
    PallasTrade::Refunds::Execute.call(refund: r1, raise_on_failure: true)
    r1.reload
    expect(r1.transaction_id).to be_present
    expect(r1).to be_succeeded
    expect(payment.reload.credit_allowed.to_f).to eq(40.0)

    # 模拟并发竞态窗口：第二条 refund 绕过 create 校验直接落库（requested），
    # Execute claim 在 payment 锁内重校验发现额度已被 r1 占用 → CAPACITY_EXCEEDED →
    # FAILED durable 行（raise_on_failure 保留旧调用方 raise 语义）。
    r2 = build(:refund, payment: payment, amount: 60, transaction_id: nil, state: 'requested')
    r2.save!(validate: false)

    expect { PallasTrade::Refunds::Execute.call(refund: r2, raise_on_failure: true) }
      .to raise_error(PallasTrade::Core::GatewayError, /exceeds/)
    expect(r2.reload).to be_failed
    expect(r2.last_error_code).to eq('CAPACITY_EXCEEDED')
    expect(payment.reload.credit_allowed.to_f).to eq(40.0)
  end
end

