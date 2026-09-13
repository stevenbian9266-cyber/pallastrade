# frozen_string_literal: true

# PRD-20260913-payments (DSP-P7-10 B1) AC-001 / AC-002 / AC-010
# —— 证据素材库：入库 / 停用 / 引用（纯值，不提交）；无契约 provider 不编造建议；零资金副作用。
require 'rails_helper'

RSpec.describe PallasTrade::Disputes::EvidenceAssets do
  let!(:store) { create(:store, code: "p710_assets_#{SecureRandom.hex(4)}", default: true) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:assets) { described_class.new(store: store) }

  def make_dispute
    order = create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                           item_total: 100, total: 100, payment_state: 'paid',
                           currency: store.default_currency, email: 'p710@example.com')
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', response_code: "pi_p710_#{SecureRandom.hex(4)}",
                               source: nil, skip_source_requirement: true)
    PallasTrade::Dispute.create!(
      provider: 'stripe',
      provider_dispute_reference: "dp_p710_#{SecureRandom.hex(4)}",
      state: 'needs_response', amount: 12.34, currency: 'usd',
      store_id: store.id, payment: payment, order: order
    )
  end

  def money_counts
    {
      payments: PallasTrade::Payment.count,
      refunds: PallasTrade::Refund.count,
      orders: PallasTrade::Order.count,
      ledger_entries: PallasTrade::FinancialLedgerEntry.count,
      inventory_units: PallasTrade::InventoryUnit.count,
      stock_reservations: PallasTrade::StockReservation.count,
      submissions: PallasTrade::DisputeEvidenceSubmission.count
    }
  end

  def stub_catalog
    allow_any_instance_of(payment_method.class).to receive(:dispute_evidence_catalog).and_return(
      [{ key: 'customer_name', type: 'text', required: true }, { key: 'receipt', type: 'file' }]
    )
  end

  describe 'AC-001 素材入库 / 停用 / 引用（只读引用）' do
    it 'creates a text asset, audits it, and lists it for the store' do
      outcome = assets.create(name: 'Delivery proof wording', kind: 'text',
                              body: 'Delivered on 2026-09-01, signed by J. Doe.',
                              evidence_key: 'customer_name', reason_code: 'product_not_received',
                              actor: 'ops@example.com')

      expect(outcome[:ok]).to be(true)
      asset = outcome[:asset]
      expect(asset).to be_persisted
      expect(asset.prefixed_id).to start_with('dea_')
      expect(asset.active).to be(true)
      expect(asset.created_by).to eq('ops@example.com')
      expect(PallasTrade::AuditLog.where(action: 'dispute_evidence_asset_created').count).to eq(1)

      expect(assets.list.map(&:prefixed_id)).to eq([asset.prefixed_id])
      expect(assets.list(reason_code: 'product_not_received').count).to eq(1)
      expect(assets.list(reason_code: 'fraudulent')).to be_empty
    end

    it 'rejects text assets without a body and duplicate names within the same store' do
      expect(assets.create(name: 'No body', kind: 'text')[:ok]).to be(false)

      expect(assets.create(name: 'Receipt wording', kind: 'text', body: 'A')[:ok]).to be(true)
      duplicate = assets.create(name: 'Receipt wording', kind: 'text', body: 'B')
      expect(duplicate[:ok]).to be(false)
      expect(duplicate[:errors].join).to include('asset_invalid')
      expect(PallasTrade::DisputeEvidenceAsset.count).to eq(1)
    end

    it 'retires an asset without deleting it' do
      asset = assets.create(name: 'Old template', kind: 'text', body: 'x')[:asset]

      expect(assets.retire(asset: asset, actor: 'ops@example.com')[:ok]).to be(true)
      expect(asset.reload.active).to be(false)
      expect(assets.list).to be_empty
      expect(assets.list(include_inactive: true).map(&:id)).to eq([asset.id])
      expect(PallasTrade::AuditLog.where(action: 'dispute_evidence_asset_retired').count).to eq(1)
    end

    it 'inserts an asset as a plain value and never creates a submission' do
      asset = assets.create(name: 'Tracking text', kind: 'text', body: 'Tracking: 1Z999',
                            evidence_key: 'customer_name')[:asset]
      before = money_counts

      inserted = assets.insert(asset: asset)

      expect(inserted[:ok]).to be(true)
      expect(inserted[:key]).to eq('customer_name')
      expect(inserted[:value]).to eq('Tracking: 1Z999')
      expect(inserted[:asset_id]).to eq(asset.prefixed_id)
      expect(money_counts).to eq(before) # AC-010：引用不产生任何回执/资金写
    end

    it 'refuses to insert a retired asset or a file asset without an attachment' do
      retired = assets.create(name: 'Retired', kind: 'text', body: 'x')[:asset]
      assets.retire(asset: retired)
      expect(assets.insert(asset: retired)[:errors]).to include('asset_inactive')

      stub_catalog
      file_asset = assets.create(name: 'Blank file', kind: 'file', evidence_key: 'receipt')[:asset]
      expect(assets.insert(asset: file_asset)[:errors]).to include('asset_value_missing')
    end
  end

  describe 'AC-002 建议只来自 provider 契约（无契约不编造）' do
    it 'returns an unsupported envelope when the provider declares no catalog' do
      result = assets.suggest(dispute: make_dispute)

      expect(result[:supported]).to be(false)
      expect(result[:suggestions]).to be_empty
    end

    it 'maps library assets onto catalog entries without generating content' do
      stub_catalog
      assets.create(name: 'Name letter', kind: 'text', body: 'Jane Doe', evidence_key: 'customer_name')

      result = assets.suggest(dispute: make_dispute)

      expect(result[:supported]).to be(true)
      keys = result[:suggestions].map { |s| s[:key] }
      expect(keys).to include('customer_name')
      suggestion = result[:suggestions].find { |s| s[:key] == 'customer_name' }
      expect(suggestion[:required]).to be(true)
      expect(suggestion[:assets].first[:name]).to eq('Name letter')
      # 建议仅是元数据：不产生素材/回执/资金写
      expect(PallasTrade::DisputeEvidenceSubmission.count).to eq(0)
    end
  end

  describe 'AC-010 铁律：素材库零资金副作用' do
    it 'keeps funds / inventory / order counts unchanged across create + retire + insert' do
      before = money_counts
      asset = assets.create(name: 'Ledger neutral', kind: 'text', body: 'text')[:asset]
      assets.insert(asset: asset)
      assets.retire(asset: asset)

      expect(money_counts).to eq(before)
      expect(PallasTrade::DisputeEvidenceAsset.count).to eq(1)
    end
  end
end
