# frozen_string_literal: true

# PRD-20260906-payments-fin-p4-5 AC-4P5-06
require 'rails_helper'

RSpec.describe PallasTrade::Gateway::Bogus, type: :model do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end

  def session_with(status:, payment: nil)
    create(:bogus_payment_session, order: order, payment_method: payment_method, status: status,
                                   amount: 100, currency: 'USD', payment: payment)
  end

  it 'AC-4P5-06 completed → deterministic settled snapshot (gross + fee 0 + net)' do
    session = session_with(status: 'completed')
    details = payment_method.fetch_financial_details(payment_session: session)

    expect(details[:settlement_status]).to eq('settled')
    expect(details[:gross_amount]).to eq(100.0)
    expect(details[:gross_currency]).to eq('USD')
    expect(details[:fee_amount]).to eq(0.0)
    expect(details[:net_amount]).to eq(100.0)
    expect(details[:provider_payment_reference]).to eq(session.external_id)
    expect(details[:provider_charge_reference]).to eq("ch_bogus_#{session.external_id}")
    expect(details[:provider_balance_transaction_reference]).to eq("txn_bogus_#{session.external_id}")
  end

  it 'AC-4P5-06 pending/processing → settlement pending, fee/net nil (no guess)' do
    session = session_with(status: 'pending')
    details = payment_method.fetch_financial_details(payment_session: session)
    expect(details[:settlement_status]).to eq('processing')
    expect(details[:gross_amount]).to eq(100.0)
    expect(details[:fee_amount]).to be_nil
    expect(details[:net_amount]).to be_nil
    expect(details[:provider_balance_transaction_reference]).to be_nil
  end

  it 'AC-4P5-06 derives refund_total from local refunds when present' do
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', source: nil, skip_source_requirement: true)
    create(:refund, payment: payment, amount: 20, transaction_id: 're_bogus_1')
    session = session_with(status: 'completed', payment: payment)

    details = payment_method.fetch_financial_details(payment_session: session)
    expect(details[:refund_total]).to eq(20.0)
    expect(details[:provider_refund_references]).to eq(["re_bogus_#{payment.refunds.first.id}"])
  end

  it 'normalized output is consumable by ProviderFinancialDetails.from_hash' do
    session = session_with(status: 'completed')
    vo = PallasTrade::FinancialFacts::ProviderFinancialDetails.from_hash(
      payment_method.fetch_financial_details(payment_session: session)
    )
    expect(vo).to be_settled
    expect(vo.gross_amount).to eq(100.0)
  end
end
