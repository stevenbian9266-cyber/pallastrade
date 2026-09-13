# frozen_string_literal: true

# PRD-20260913-payments-dsp-p7-8-dispute-dangerous-actions-and-evidence-submission
# AC-P78-01/02 —— provider 证据目录与写契约能力探测（零 I/O）。
require 'rails_helper'

RSpec.describe PallasTrade::Disputes::EvidenceCatalog do
  let!(:store) { create(:store, code: "p78_catalog_#{SecureRandom.hex(4)}", default: true) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }

  subject(:catalog) { described_class.new(payment_method: payment_method) }

  describe 'AC-P78-01 能力探测' do
    it 'is unsupported for gateways without a catalog' do
      expect(catalog.supported?).to be(false)
      expect(catalog.entries).to be_empty
    end

    it 'is supported when the gateway declares a catalog' do
      allow_any_instance_of(payment_method.class).to receive(:dispute_evidence_catalog).and_return(
        [{ key: 'customer_name', type: 'text' }, { key: 'receipt', type: 'file' }]
      )

      expect(catalog.supported?).to be(true)
      expect(catalog.text_entries.map(&:key)).to eq(['customer_name'])
      expect(catalog.file_entries.map(&:key)).to eq(['receipt'])
    end
  end

  describe 'AC-P78-02 校验' do
    before do
      allow_any_instance_of(payment_method.class).to receive(:dispute_evidence_catalog).and_return(
        [{ key: 'customer_name', type: 'text', max_length: 10 }, { key: 'receipt', type: 'file' }]
      )
    end

    it 'accepts valid text and rejects unknown keys / oversized values' do
      ok = catalog.validate('customer_name' => 'Jane')
      expect(ok[:ok]).to be(true)
      expect(ok[:text]).to eq('customer_name' => 'Jane')

      too_long = catalog.validate('customer_name' => 'x' * 11)
      expect(too_long[:ok]).to be(false)
      expect(too_long[:errors]).to include('evidence_too_long:customer_name')

      unknown = catalog.validate('what' => 'x')
      expect(unknown[:ok]).to be(false)
      expect(unknown[:errors]).to include('unknown_evidence_key:what')
    end

    it 'treats a text key given a file as a type error' do
      file = Tempfile.new(['x', '.png'])
      file.write('x')
      file.rewind

      outcome = catalog.validate('customer_name' => file)
      expect(outcome[:ok]).to be(false)
      expect(outcome[:errors]).to include('evidence_not_text:customer_name')
    end

    it 'rejects an empty payload' do
      outcome = catalog.validate({})
      expect(outcome[:ok]).to be(false)
      expect(outcome[:errors]).to include('evidence_empty')
    end
  end
end
