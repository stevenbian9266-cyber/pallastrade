# frozen_string_literal: true

require 'rails_helper'

# P0-6 (PRD FR-062): Canonical Failure Mapping —— 只映射，不外泄 provider 细节。
RSpec.describe PallasTrade::Payments::ErrorCodes, type: :service do
  it 'maps Stripe decline codes to canonical semantics' do
    expect(described_class.map(provider_code: 'card_declined')).to eq(:declined)
    expect(described_class.map(provider_code: 'insufficient_funds')).to eq(:insufficient_funds)
    expect(described_class.map(provider_code: 'expired_card')).to eq(:expired_card)
    expect(described_class.map(provider_code: 'invalid_card')).to eq(:invalid_card)
    expect(described_class.map(provider_code: 'authentication_required')).to eq(:authentication_failed)
    expect(described_class.map(provider_code: 'processing_error')).to eq(:processing_error)
  end

  it 'falls back to provider_error for unknown codes' do
    expect(described_class.map(provider_code: 'some_unknown_xyz')).to eq(:provider_error)
  end

  it 'never leaks provider detail through safe messages' do
    expect(described_class.safe_message(:declined)).to include('declined')
    expect(described_class.safe_message(:provider_error)).to eq('Payment provider error.')
    expect(described_class.safe_message(:unknown)).to eq(described_class.safe_message(:provider_error))
  end
end
