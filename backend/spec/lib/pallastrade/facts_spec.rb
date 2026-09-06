# frozen_string_literal: true

require 'rails_helper'

# CORE-P5-3 FR：Facts 统一 Result contract（P5 §12-13）——确定性词汇 + 映射 + 构造器
RSpec.describe PallasTrade::Facts, type: :service do
  describe '.certainty_for' do
    it 'maps payment verdicts' do
      expect(described_class.certainty_for(:payment, :paid)).to eq(:confirmed)
      expect(described_class.certainty_for(:payment, :unpaid)).to eq(:unconfirmed)
      expect(described_class.certainty_for(:payment, :ambiguous)).to eq(:ambiguous)
    end

    it 'maps inventory verdicts' do
      %i[committed reserved released expired].each do |v|
        expect(described_class.certainty_for(:inventory, v)).to eq(:confirmed)
      end
      expect(described_class.certainty_for(:inventory, :unreserved)).to eq(:not_applicable)
      expect(described_class.certainty_for(:inventory, :not_required)).to eq(:not_applicable)
      expect(described_class.certainty_for(:inventory, :ambiguous)).to eq(:ambiguous)
    end

    it 'falls back to unconfirmed for unknown verdicts (no guessing)' do
      expect(described_class.certainty_for(:payment, :mystery)).to eq(:unconfirmed)
      expect(described_class.certainty_for(:unknown_domain, :paid)).to eq(:unconfirmed)
    end
  end

  describe '.contract_fields' do
    it 'builds canonical fields from status and reason codes' do
      fields = described_class.contract_fields(
        status: :ambiguous,
        reason_codes: %i[short_payment provider_unavailable],
        source: 'payment_fact_resolver'
      )

      expect(fields[:status]).to eq(:ambiguous)
      expect(fields[:reason_code]).to eq('short_payment,provider_unavailable')
      expect(fields[:evidence]).to eq(%w[short_payment provider_unavailable])
      expect(fields[:source]).to eq('payment_fact_resolver')
      expect(fields[:observed_at]).to be_present
    end

    it 'defaults observed_at to now ISO8601 when omitted' do
      fields = described_class.contract_fields(status: :confirmed, source: 'x')
      expect { Time.iso8601(fields[:observed_at]) }.not_to raise_error
    end
  end
end
