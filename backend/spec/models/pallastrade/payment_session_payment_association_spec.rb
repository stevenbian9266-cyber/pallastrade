# frozen_string_literal: true

require 'spec_helper'

# P0-1 (2026-09-02)：PaymentSession ↔ Payment 正式关联（payment_session_id）。
#
# 语义（P0-1 起）：
#   - 内部关联唯一来源 = payments.payment_session_id（正式 FK）
#   - response_code 仅作 PSP reference，不再承担内部关联
#   - 通过 session.find_or_create_payment! 创建的 Payment 必须带 payment_session_id
#   - 非 PaymentSession 来源的 Payment（如 factory/手工/legacy 未回填）保持 NULL
#   - 一个 PaymentSession 最多产生一个 Payment（FR-015）
RSpec.describe 'PaymentSession ↔ Payment association', type: :model do
  let(:store) { @default_store }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                   item_total: 10, total: 10, payment_state: 'balance_due')
  end
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }

  it 'find_or_create_payment! links the Payment to the originating session via payment_session_id' do
    session = create(:bogus_payment_session, order: order, payment_method: payment_method,
                                             amount: order.total, external_id: 'pi_test_abc')

    payment = session.find_or_create_payment!

    expect(payment.payment_session_id).to eq(session.id)
    expect(session.reload.payment).to eq(payment)
    expect(payment.reload.payment_session).to eq(session)
    # response_code 仍是 PSP reference（pi_ 模式 == external_id），但不承担关联
    expect(payment.response_code).to eq('pi_test_abc')
  end

  it 'does not rely on response_code == external_id for the association (cs_-style id mismatch still links)' do
    # cs_ 模式真实形态：session.external_id=cs_xxx，Payment.response_code=pi_xxx。
    # 因 P0-1 走 payment_session_id，二者不同也能正确关联。
    session = create(:bogus_payment_session, order: order, payment_method: payment_method,
                                             amount: order.total, external_id: 'cs_test_xyz')

    payment = order.payments.create!(
      payment_method: payment_method,
      amount: order.total,
      response_code: 'pi_test_xyz',
      payment_session: session,
      skip_source_requirement: true
    )

    expect(payment.response_code).not_to eq(session.external_id)
    expect(session.reload.payment).to eq(payment)
    expect(payment.reload.payment_session).to eq(session)
  end

  it 'one session does not produce two payments through find_or_create_payment!' do
    session = create(:bogus_payment_session, order: order, payment_method: payment_method,
                                             amount: order.total, external_id: 'pi_test_one')

    p1 = session.find_or_create_payment!
    p2 = session.find_or_create_payment!

    expect(p1).to eq(p2)
    expect(order.payments.count).to eq(1)
    expect(order.payments.where(payment_session_id: session.id).count).to eq(1)
  end

  it 'non-session payments (manual/legacy) keep payment_session_id NULL and stay compatible' do
    payment = create(:payment, order: order, payment_method: payment_method,
                               amount: order.total, state: 'completed', response_code: 'manual_ref_1')

    expect(payment.payment_session_id).to be_nil
    expect(payment.payment_session).to be_nil
    expect(order.payments.find_by(response_code: 'manual_ref_1')).to eq(payment)
  end
end
