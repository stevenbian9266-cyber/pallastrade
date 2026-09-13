# frozen_string_literal: true

# PRD-20260913-payments (DSP-P7-10 B2) AC-006 / AC-010
# —— 争议运营报表：胜诉率 / 按 reason code / 时限达成 / 处理时长；mixed currency 与无锚点降级；**零写**。
require 'rails_helper'

RSpec.describe PallasTrade::Disputes::OpsReport do
  let!(:store) { create(:store, code: "p710_report_#{SecureRandom.hex(4)}", default: true) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }

  def make_dispute(state: 'needs_response', outcome: nil, reason: nil, network_reason_code: nil,
                   currency: 'usd', amount: 10.0, fee_amount: 15.0,
                   created_at: 10.days.ago, resolved_at: nil,
                   evidence_due_at: nil, evidence_submitted_at: nil)
    order = create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                           item_total: 100, total: 100, payment_state: 'paid',
                           currency: store.default_currency, email: 'p710rep@example.com')
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', response_code: "pi_p710r_#{SecureRandom.hex(4)}",
                               source: nil, skip_source_requirement: true)
    PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: "dp_p710r_#{SecureRandom.hex(4)}",
      state: state, outcome: outcome, reason: reason, network_reason_code: network_reason_code,
      amount: amount, fee_amount: fee_amount, currency: currency,
      store_id: store.id, payment: payment, order: order,
      created_at: created_at, updated_at: created_at,
      resolved_at: resolved_at, evidence_due_at: evidence_due_at, evidence_submitted_at: evidence_submitted_at
    )
  end

  def write_counts
    {
      submissions: PallasTrade::DisputeEvidenceSubmission.count,
      audits: PallasTrade::AuditLog.count,
      payments: PallasTrade::Payment.count,
      refunds: PallasTrade::Refund.count,
      orders: PallasTrade::Order.count,
      ledger_entries: PallasTrade::FinancialLedgerEntry.count,
      inventory_units: PallasTrade::InventoryUnit.count
    }
  end

  describe 'AC-006 指标口径' do
    it 'computes totals, states, outcomes and a nil (not fake) win rate' do
      make_dispute(state: 'won', outcome: 'won', reason: 'fraudulent')
      make_dispute(state: 'lost', outcome: 'lost', reason: 'fraudulent')
      make_dispute(state: 'needs_response', reason: 'product_not_received')
      make_dispute(state: 'closed', outcome: 'closed', reason: 'general')

      report = described_class.call(store: store).value

      expect(report[:totals][:disputes]).to eq(4)
      expect(report[:totals][:active]).to eq(1)
      expect(report[:totals][:terminal]).to eq(3)
      expect(report[:states]['needs_response']).to eq(1)
      expect(report[:outcomes][:won]).to eq(1)
      expect(report[:outcomes][:lost]).to eq(1)
      expect(report[:outcomes][:win_rate]).to eq(0.5)
      expect(report[:degraded]).to be_empty
    end

    it 'groups by reason code with per-reason win rates, falling back to network_reason_code' do
      make_dispute(state: 'won', outcome: 'won', reason: 'fraudulent')
      make_dispute(state: 'lost', outcome: 'lost', reason: 'fraudulent')
      make_dispute(state: 'won', outcome: 'won', reason: nil, network_reason_code: 'product_not_received')
      make_dispute(state: 'needs_response', outcome: nil, reason: nil, network_reason_code: nil)

      by_reason = described_class.call(store: store).value[:by_reason].index_by { |row| row[:reason] }

      expect(by_reason['fraudulent']).to include(total: 2, won: 1, lost: 1, decided: 2, win_rate: 0.5)
      expect(by_reason['product_not_received']).to include(total: 1, won: 1, lost: 0, win_rate: 1.0)
      expect(by_reason['unknown']).to include(total: 1, won: 0, lost: 0, win_rate: nil)
    end

    it 'reports deadline achievement against evidence_due_at' do
      make_dispute(evidence_due_at: 5.days.ago, evidence_submitted_at: 6.days.ago)   # met
      make_dispute(evidence_due_at: 5.days.ago, evidence_submitted_at: 4.days.ago)   # late
      make_dispute(evidence_due_at: 5.days.ago, evidence_submitted_at: nil)          # not submitted
      make_dispute(evidence_due_at: nil)                                             # no deadline

      deadlines = described_class.call(store: store).value[:deadlines]

      expect(deadlines).to include(with_deadline: 3, met: 1, submitted_late: 1, not_submitted: 1,
                                   no_deadline: 1, met_rate: (1.0 / 3).round(4))
    end

    it 'reports handling time (average / median / fastest / slowest) for resolved disputes only' do
      make_dispute(state: 'won', outcome: 'won', created_at: 12.days.ago, resolved_at: 10.days.ago) # 2d
      make_dispute(state: 'lost', outcome: 'lost', created_at: 12.days.ago, resolved_at: 8.days.ago)  # 4d
      make_dispute(state: 'needs_response', created_at: 3.days.ago, resolved_at: nil)                 # 无 resolved_at

      handling = described_class.call(store: store).value[:handling]

      expect(handling[:resolved_count]).to eq(2)
      expect(handling[:average_days]).to eq(3.0)
      expect(handling[:median_days]).to eq(3.0)
      expect(handling[:fastest_days]).to eq(2.0)
      expect(handling[:slowest_days]).to eq(4.0)
    end

    it 'sums amounts only for a single currency' do
      make_dispute(amount: 10.0, fee_amount: 15.0)
      make_dispute(amount: 5.0, fee_amount: 15.0)

      money = described_class.call(store: store).value[:money]

      expect(money).to include(currency: 'usd', mixed_currency: false, disputed_amount: 15.0, fee_amount: 30.0)
    end
  end

  describe 'AC-006 降级（不猜）' do
    it 'degrades amounts (nil) when currencies are mixed instead of summing them' do
      make_dispute(amount: 10.0, currency: 'usd')
      make_dispute(amount: 10.0, currency: 'eur')

      money = described_class.call(store: store).value[:money]

      expect(money[:mixed_currency]).to be(true)
      expect(money[:currency]).to be_nil
      expect(money[:disputed_amount]).to be_nil
      expect(money[:currencies]).to eq(%w[eur usd])
    end

    it 'returns a degraded envelope for a missing store rather than raising' do
      report = described_class.call(store: nil).value

      expect(report[:degraded]).to include('store_missing')
      expect(report[:totals][:disputes]).to eq(0)
    end

    it 'scopes to the store and honours the window' do
      make_dispute(created_at: 5.days.ago)
      make_dispute(created_at: 200.days.ago)
      other_store = create(:store, code: "p710_report_other_#{SecureRandom.hex(4)}")
      PallasTrade::Dispute.create!(
        provider: 'stripe', provider_dispute_reference: "dp_other_#{SecureRandom.hex(4)}",
        state: 'needs_response', amount: 1.0, currency: 'usd', store_id: other_store.id,
        created_at: 1.day.ago, updated_at: 1.day.ago
      )

      this_month = described_class.call(store: store, window_days: 30).value
      all_time = described_class.call(store: store, window_days: :all).value

      expect(this_month[:totals][:disputes]).to eq(1)
      expect(all_time[:totals][:disputes]).to eq(2) # 另一个店铺的争议绝不计入
    end
  end

  describe 'AC-010 铁律：报表零写' do
    it 'never writes receipts, audits, funds, inventory or orders' do
      make_dispute(state: 'won', outcome: 'won', reason: 'fraudulent', created_at: 9.days.ago,
                   resolved_at: 8.days.ago, evidence_due_at: 5.days.ago, evidence_submitted_at: 6.days.ago)
      make_dispute(state: 'lost', outcome: 'lost', reason: 'fraudulent')

      before = write_counts
      expect_any_instance_of(payment_method.class).not_to receive(:submit_dispute_evidence)
      expect_any_instance_of(payment_method.class).not_to receive(:accept_dispute)

      3.times { described_class.call(store: store) }
      described_class.call(store: store, provider: 'stripe', window_days: :all)

      expect(write_counts).to eq(before)
    end
  end
end
