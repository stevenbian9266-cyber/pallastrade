# frozen_string_literal: true

# PRD-20260905-payments-fin-p4-1 AC-4P1-22
require 'rails_helper'

RSpec.describe PallasTrade::FinancialFacts::RetryPaymentSafetyPolicy, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end

  it 'AC-4P1-22 policy is named and documented' do
    expect(described_class::POLICY_NAME).to eq('RETRY_PAYMENT_FINANCIAL_SAFETY_POLICY')
  end

  it 'AC-4P1-22 existing provider space (session external_id) → must verify before new charge' do
    session = create(:bogus_payment_session, order: order, payment_method: payment_method, status: 'pending',
                                             amount: 100, currency: 'USD')
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'pending', payment_session: session)

    expect(described_class.requires_provider_verification_before_retry?(payment)).to be(true)
  end

  it 'AC-4P1-22 existing provider reference (response_code) → must verify before new charge' do
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'processing', response_code: 'pi_existing')

    expect(described_class.requires_provider_verification_before_retry?(payment)).to be(true)
  end

  it 'AC-4P1-22 completed payment → no retry scenario (false)' do
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100, state: 'completed')
    expect(described_class.requires_provider_verification_before_retry?(payment)).to be(false)
  end

  it 'AC-4P1-22 store credit payment → no PSP provider space (false)' do
    user = create(:user)
    create(:store_credit, store: store, user: user, amount: 200.0, currency: 'USD')
    order_sc = create(:order, store: store, user: user, state: 'pending', status: 'placed',
                              item_total: 100, total: 100, payment_state: 'balance_due')
    sc_pm = create(:store_credit_payment_method, store: store, active: true)
    sc_credit = user.store_credits.for_store(store).available.first
    sc_payment = create(:payment, order: order_sc, payment_method: sc_pm, amount: 100, state: 'pending',
                                  source: sc_credit)
    expect(described_class.requires_provider_verification_before_retry?(sc_payment)).to be(false)
  end

  it 'AC-4P1-22 offline check payment → no PSP provider space (false)' do
    check_pm = create(:check_payment_method, store: store)
    check_payment = create(:payment, order: order, payment_method: check_pm, amount: 100, state: 'pending',
                                     source: nil, skip_source_requirement: true)
    expect(described_class.requires_provider_verification_before_retry?(check_payment)).to be(false)
  end

  it 'AC-4P1-22 local-only pending payment without provider space → false' do
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'pending', response_code: nil)
    expect(described_class.requires_provider_verification_before_retry?(payment)).to be(false)
  end
end
