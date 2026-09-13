# frozen_string_literal: true

require 'rails_helper'
require 'stripe'

# PRD-20260913-payments-dsp-p7-9-partial-and-multi-dispute-semantics
# AC-P79-03/09 —— 网关层：BT 明细含 fee；能力矩阵（Stripe 支持 / 基类 UNSUPPORTED）。
RSpec.describe PallasTradeStripe::Gateway, type: :model do
  subject(:gateway) { create(:stripe_gateway) }

  let(:dispute) do
    PallasTrade::Dispute.new(provider: 'stripe', provider_dispute_reference: 'dp_fee_1',
                             state: 'lost', amount: 25, currency: 'usd')
  end

  def stripe_dispute(**overrides)
    Stripe::Dispute.construct_from(
      { id: 'dp_fee_1', status: 'lost', amount: 2500, currency: 'usd', reason: 'fraudulent',
        evidence_details: { due_by: nil, has_evidence: false },
        balance_transactions: [
          { id: 'txn_debit', type: 'adjustment', amount: -2500, fee: 1500, net: -4000, currency: 'usd' },
          { id: 'txn_reinstate', type: 'adjustment', amount: 2500, fee: 0, net: 2500, currency: 'usd' }
        ] }.merge(overrides)
    )
  end

  describe '#fetch_dispute_details（AC-P79-03）' do
    it 'returns balance-transaction details (type/amount/fee/net) and the fee amount' do
      allow(gateway).to receive(:retrieve_dispute).with('dp_fee_1').and_return(stripe_dispute)

      details = gateway.fetch_dispute_details(dispute: dispute)

      expect(details[:balance_transaction_details].size).to eq(2)
      expect(details[:balance_transaction_details].first).to include(
        reference: 'txn_debit', type: 'adjustment', fee: BigDecimal('15'), net: BigDecimal('-40')
      )
      # 手续费 = 扣款那条 BT 的 fee（返还那条为 0）→ 取最大值
      expect(details[:fee_amount]).to eq(BigDecimal('15'))
    end

    it 'does not guess the fee when the provider payload carries no fee field' do
      allow(gateway).to receive(:retrieve_dispute).and_return(
        stripe_dispute(balance_transactions: [{ id: 'txn_debit', type: 'adjustment', amount: -2500 }])
      )

      details = gateway.fetch_dispute_details(dispute: dispute)

      expect(details[:fee_amount]).to be_nil
    end

    it 'returns nil fee when there are no balance transactions at all' do
      allow(gateway).to receive(:retrieve_dispute).and_return(stripe_dispute(balance_transactions: []))

      expect(gateway.fetch_dispute_details(dispute: dispute)[:fee_amount]).to be_nil
    end
  end

  describe '#dispute_capabilities（AC-P79-09）' do
    it 'Stripe 能力矩阵：支持证据提交/接受争议/采费，并给出证据键清单' do
      capabilities = gateway.dispute_capabilities

      expect(capabilities[:supported]).to be(true)
      expect(capabilities[:evidence_submission]).to be(true)
      expect(capabilities[:accept_dispute]).to be(true)
      expect(capabilities[:fee_capture]).to be(true)
      expect(capabilities[:evidence_text_keys]).to include('customer_name')
      expect(capabilities[:evidence_file_keys]).to include('receipt')
    end
  end
end

RSpec.describe PallasTrade::PaymentMethod, type: :model do
  # AC-P79-09（RV-D10）：无契约的 provider 一律 UNSUPPORTED，不得被猜成「支持」。
  it '基类能力矩阵 = UNSUPPORTED 形态（零 I/O、零猜测）' do
    capabilities = PallasTrade::Gateway::Bogus.new.dispute_capabilities

    expect(capabilities[:supported]).to be(false)
    expect(capabilities[:reason]).to eq('unsupported_provider')
    expect(capabilities[:evidence_submission]).to be(false)
    expect(capabilities[:accept_dispute]).to be(false)
    expect(capabilities[:fee_capture]).to be(false)
    expect(capabilities[:evidence_text_keys]).to eq([])
    expect(capabilities[:evidence_file_keys]).to eq([])
  end
end
