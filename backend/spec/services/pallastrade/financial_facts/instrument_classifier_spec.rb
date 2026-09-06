# frozen_string_literal: true

# PRD-20260905-payments-fin-p4-1 AC-4P1-02
require 'rails_helper'

RSpec.describe PallasTrade::FinancialFacts::InstrumentClassifier, type: :service do
  let(:store) { @default_store }

  def classify!(payment_method)
    described_class.call(payment_method: payment_method)
  end

  it 'AC-4P1-02 bogus/PSP gateway → PSP_CASH' do
    pm = create(:bogus_payment_method, store: store, active: true)
    result = classify!(pm)
    expect(result).to be_success
    expect(result.value[:instrument_class]).to eq(PallasTrade::FinancialFact::PSP_CASH)
    expect(result.value[:provider]).to eq('PallasTrade::Gateway::Bogus')
  end

  it 'AC-4P1-02 StoreCredit → STORE_CREDIT' do
    pm = create(:store_credit_payment_method, store: store, active: true)
    result = classify!(pm)
    expect(result.value[:instrument_class]).to eq(PallasTrade::FinancialFact::STORE_CREDIT)
  end

  it 'AC-4P1-02 Check → OFFLINE' do
    pm = create(:check_payment_method, store: store)
    result = classify!(pm)
    expect(result.value[:instrument_class]).to eq(PallasTrade::FinancialFact::OFFLINE)
  end

  it 'AC-4P1-02 base PaymentMethod (no gateway) → UNKNOWN, never PSP_CASH' do
    pm = create(:payment_method, store: store)
    result = classify!(pm)
    expect(result).to be_success
    expect(result.value[:instrument_class]).to eq(PallasTrade::FinancialFact::UNKNOWN)
  end

  it 'AC-4P1-02 nil payment method → failure' do
    result = classify!(nil)
    expect(result).to be_failure
  end
end
