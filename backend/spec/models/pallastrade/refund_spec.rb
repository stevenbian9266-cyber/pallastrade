# frozen_string_literal: true

# review 批2 (bugfix A6, 2026-09-06): Refund perform! 对 payment 行加锁 + 锁内重校验已退额度。
# 两条并发 Refund 都会在 create validation（amount <= credit_allowed，非原子）通过；
# 真实网关调用前以 payment 行锁串行化，后到者看到并发方已占额度 → raise → 该 Refund 创建
# 回滚 → 防双退。回归：锁内校验拒绝超额；正常退款不受影响。
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

  it 'bugfix A6: perform! re-validates credit allowed under the payment lock (blocks double refund)' do
    payment = captured_payment(amount: 100)
    r1 = create(:refund, payment: payment, amount: 60, transaction_id: nil) # 真实 bogus credit
    expect(r1.transaction_id).to be_present
    expect(payment.reload.credit_allowed.to_f).to eq(40.0)

    # 模拟并发窗口：第二条 refund 的 create validation 通过（旧额度视图），真实网关调用前
    # perform! 在 payment 锁内重校验发现额度已被 r1 占用 → raise → 创建回滚（不落库）。
    r2 = build(:refund, payment: payment, amount: 60, transaction_id: nil)
    expect { r2.save(validate: false) }.to raise_error(PallasTrade::Core::GatewayError, /exceeds/)
    expect(r2).not_to be_persisted
    expect(PallasTrade::Refund.count).to eq(1)
    expect(payment.reload.credit_allowed.to_f).to eq(40.0)
  end
end
