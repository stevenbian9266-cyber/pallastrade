# frozen_string_literal: true

require 'rails_helper'

# PRD-20260913-payments-dsp-p7-9-partial-and-multi-dispute-semantics
# AC-P79-01/02 —— partial 语义三态 + 金额来源唯一性（铁律：禁止用 payment.amount 推导争议金额）。
RSpec.describe PallasTrade::Dispute, type: :model do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }
  let(:order) { create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100) }
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: 100,
                     state: 'completed', source: nil, skip_source_requirement: true)
  end

  def make_dispute(amount:, payment: self.payment)
    PallasTrade::Dispute.create!(
      provider: 'stripe',
      provider_dispute_reference: "dp_p79_#{SecureRandom.hex(4)}",
      state: 'needs_response',
      amount: amount,
      currency: 'usd',
      payment: payment
    )
  end

  describe '#partial?' do
    it 'AC-P79-01 全额争议 → false' do
      expect(make_dispute(amount: 100).partial?).to be(false)
    end

    it 'AC-P79-01 部分争议（amount < payment.amount）→ true' do
      expect(make_dispute(amount: 12.34).partial?).to be(true)
    end

    it 'AC-P79-01 无 payment 锚点 → false（未知 ≠ 部分争议，不猜）' do
      expect(make_dispute(amount: 12.34, payment: nil).partial?).to be(false)
    end

    it 'AC-P79-01 支付金额为 0（结构异常）→ false（不判定部分）' do
      payment.update_columns(amount: 0)
      expect(make_dispute(amount: 12.34).partial?).to be(false)
    end
  end

  describe 'AC-P79-02 金额来源唯一性' do
    it '裁决/入账路径不得使用 payment.amount 推导争议金额' do
      paths = %w[
        pallastrade_gems/pallastrade_core/app/services/pallastrade/disputes/resolve_fact.rb
        pallastrade_gems/pallastrade_core/app/services/pallastrade/financial_facts/resolve_dispute.rb
        pallastrade_gems/pallastrade_core/app/services/pallastrade/financial_ledger/post_dispute.rb
      ].map { |relative| Rails.root.join(relative) }

      offenders = paths.select do |path|
        source = File.read(path)
        source.match?(/(?:dispute|dispute_fact)\.payment&?\.amount/) ||
          source.match?(/payment\.amount.*(?:fact|amount_for|abs)/)
      end

      expect(offenders).to be_empty
    end

    it '争议金额逐字节等于 dispute 快照（provider 无法构造 partial → fixture 钉死）' do
      dispute = make_dispute(amount: 12.34)
      fact = PallasTrade::Disputes::ResolveFact.call(dispute: dispute).value

      expect(fact.amount.to_d).to eq(12.34.to_d)
      expect(dispute.reload.amount.to_d).to eq(12.34.to_d)
    end
  end
end
