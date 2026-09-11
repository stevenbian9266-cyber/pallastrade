# frozen_string_literal: true

require 'rails_helper'

# PRD-20260911-payments-dsp-p7-2-dispute-fact-resolution AC-002 AC-003 AC-005 AC-006
# `PallasTrade::Disputes::ResolveFact` —— dispute 的只读事实裁决：
#   provider 状态（快照优先，回退本地事件状态）↔ 本地 Dispute → DisputeFact。
# 本 spec 覆盖：8 裁决（aligned/stale_local/stale_provider/conflict/unknown/unsupported/unavailable/
# not_applicable）+ 3 降级（契约缺失/故障/金额不可证）+ VO 常量 + 零副作用。
RSpec.describe PallasTrade::Disputes::ResolveFact do
  let(:store) { @default_store }
  let(:user) { create(:user) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both', auto_capture: true) }

  let(:order) do
    create(:order_with_line_items, store: store, user: user, shipment_cost: 0, line_items_price: 100).tap do |o|
      o.update_columns(state: 'complete', status: 'complete', completed_at: Time.current)
    end
  end

  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: order.total,
                     response_code: 'pi_resolve_anchor')
  end

  # 建 dispute 并把 `#payment` 固定到 let(payment)（便于对 provider 契约打桩）
  def create_dispute(state:, provider_status: nil, payment_record: nil, **attrs)
    record = PallasTrade::Dispute.create!(
      { provider: 'stripe', provider_dispute_reference: "dp_#{SecureRandom.hex(4)}",
        state: state, amount: 12.34, currency: 'usd',
        private_metadata: (provider_status.nil? ? {} : { 'provider_status' => provider_status }) }.merge(attrs)
    )
    record.update!(payment: payment_record || payment)
    allow(record).to receive(:payment).and_return(payment_record || payment)
    record
  end

  def resolve(dispute, fetch: false)
    result = described_class.call(dispute: dispute, fetch: fetch)

    expect(result).to be_success
    result.value
  end

  describe '裁决矩阵（AC-002）' do
    it 'aligned：provider 与本地一致 → CONFIRMED' do
      fact = resolve(create_dispute(state: 'needs_response', provider_status: 'needs_response'))

      expect(fact.resolution).to eq('aligned')
      expect(fact.status).to eq('CONFIRMED')
      expect(fact).to be_confirmed
      expect(fact).not_to be_needs_attention
      expect(fact.provider_status).to eq('needs_response')
      expect(fact.local_state).to eq('needs_response')
      expect(fact.source).to eq('local')
    end

    it 'stale_local：provider 已终态、本地未达 → 需关注' do
      fact = resolve(create_dispute(state: 'under_review', provider_status: 'lost'))

      expect(fact.resolution).to eq('stale_local')
      expect(fact.status).to eq('CONFIRMED')
      expect(fact).to be_needs_attention
    end

    it 'stale_provider：本地终态、provider 未达 → 需关注' do
      fact = resolve(create_dispute(state: 'won', provider_status: 'needs_response'))

      expect(fact.resolution).to eq('stale_provider')
      expect(fact).to be_needs_attention
    end

    it 'conflict：双方终态结论不同 → 需关注' do
      fact = resolve(create_dispute(state: 'won', provider_status: 'lost'))

      expect(fact.resolution).to eq('conflict')
      expect(fact).to be_needs_attention
    end

    it 'conflict：本地 manual_review 一律归冲突' do
      fact = resolve(create_dispute(state: 'manual_review', provider_status: 'lost'))

      expect(fact.resolution).to eq('conflict')
    end

    it 'unknown：无 provider 状态可比 → AMBIGUOUS' do
      fact = resolve(create_dispute(state: 'opened'))

      expect(fact.resolution).to eq('unknown')
      expect(fact.status).to eq('AMBIGUOUS')
      expect(fact).to be_ambiguous
      expect(fact.reason_code).to be_nil
    end

    it 'provider 快照优先于本地历史状态（fetch=true，source=provider_fetch）' do
      dispute = create_dispute(state: 'needs_response')
      allow(payment_method).to receive(:fetch_dispute_details).and_return(
        { status: 'under_review', amount: BigDecimal('12.34'), currency: 'usd',
          evidence_due_at: Time.zone.parse('2026-09-20 12:00:00'), observed_at: Time.current }
      )

      fact = resolve(dispute, fetch: true)

      expect(fact.source).to eq('provider_fetch')
      expect(fact.provider_status).to eq('under_review')
      expect(fact.resolution).to eq('stale_local')
      expect(fact.evidence).to include(:provider_fetch)
      expect(fact.evidence_due_at).to be_within(1.second).of(Time.zone.parse('2026-09-20 12:00:00'))
    end

    it '快照状态与本地一致 → aligned（fetch=true）' do
      dispute = create_dispute(state: 'under_review')
      allow(payment_method).to receive(:fetch_dispute_details).and_return(
        { status: 'under_review', amount: BigDecimal('12.34'), currency: 'usd', observed_at: Time.current }
      )

      expect(resolve(dispute, fetch: true).resolution).to eq('aligned')
    end
  end

  describe '降级纪律（AC-003）' do
    it '契约缺失：bogus 网关未实现 → unsupported / UNSUPPORTED / PROVIDER_CONTRACT_UNSUPPORTED' do
      fact = resolve(create_dispute(state: 'needs_response'), fetch: true)

      expect(fact.resolution).to eq('unsupported')
      expect(fact.status).to eq('UNSUPPORTED')
      expect(fact).to be_unsupported
      expect(fact.reason_code).to eq('PROVIDER_CONTRACT_UNSUPPORTED')
      expect(fact.evidence).to include(:provider_contract_unsupported)
    end

    it 'provider 故障：fetch 抛 GatewayError → unavailable / AMBIGUOUS / PROVIDER_UNAVAILABLE' do
      dispute = create_dispute(state: 'needs_response')
      allow(payment_method).to receive(:fetch_dispute_details).and_raise(PallasTrade::Core::GatewayError, 'boom')

      fact = resolve(dispute, fetch: true)

      expect(fact.resolution).to eq('unavailable')
      expect(fact.status).to eq('AMBIGUOUS')
      expect(fact.reason_code).to eq('PROVIDER_UNAVAILABLE')
    end

    it '金额不可证（0）→ AMBIGUOUS + AMOUNT_UNPROVABLE，且不产生资金事实' do
      fact = resolve(create_dispute(state: 'needs_response', provider_status: 'needs_response', amount: 0))

      expect(fact.status).to eq('AMBIGUOUS')
      expect(fact.reason_code).to eq('AMOUNT_UNPROVABLE')
      expect(fact).not_to be_money_movement
    end

    it '非 PSP 载体（StoreCredit）→ not_applicable / NOT_APPLICABLE' do
      dispute = create_dispute(state: 'needs_response', provider_status: 'needs_response')
      allow(payment).to receive(:payment_method).and_return(PallasTrade::PaymentMethod::StoreCredit.new)

      fact = resolve(dispute)

      expect(fact.resolution).to eq('not_applicable')
      expect(fact.status).to eq('NOT_APPLICABLE')
      expect(fact).to be_not_applicable
    end
  end

  describe 'fact_type 词汇（AC-005）' do
    it '默认 opened；funds 时间戳与终态决定最强事实' do
      expect(resolve(create_dispute(state: 'needs_response')).fact_type).to eq('DISPUTE_OPENED')

      withdrawn = create_dispute(state: 'needs_response', funds_withdrawn_at: Time.current)
      expect(resolve(withdrawn).fact_type).to eq('DISPUTE_FUNDS_WITHDRAWN')

      reinstated = create_dispute(state: 'under_review', funds_withdrawn_at: 2.days.ago,
                                  funds_reinstated_at: Time.current)
      expect(resolve(reinstated).fact_type).to eq('DISPUTE_FUNDS_REINSTATED')

      expect(resolve(create_dispute(state: 'won')).fact_type).to eq('DISPUTE_WON')
      expect(resolve(create_dispute(state: 'lost')).fact_type).to eq('DISPUTE_LOST')
    end

    it 'VO 常量冻结且拒绝未知属性' do
      expect(PallasTrade::Disputes::DisputeFact::FACT_TYPES).to include(
        'DISPUTE_OPENED', 'DISPUTE_FUNDS_WITHDRAWN', 'DISPUTE_FUNDS_REINSTATED', 'DISPUTE_WON', 'DISPUTE_LOST'
      )
      expect(PallasTrade::Disputes::DisputeFact::STATUSES).to eq(%w[CONFIRMED AMBIGUOUS UNSUPPORTED NOT_APPLICABLE])
      expect(PallasTrade::Disputes::DisputeFact::RESOLUTIONS).to include('aligned', 'stale_local', 'conflict')

      expect do
        PallasTrade::Disputes::DisputeFact.new(bogus_attribute: 1)
      end.to raise_error(ArgumentError, /Unknown DisputeFact attributes/)
    end

    it 'money_movement? 只对两类资金事实为真（P7-3 入账输入）' do
      expect(resolve(create_dispute(state: 'needs_response', funds_withdrawn_at: Time.current))).to be_money_movement
      expect(resolve(create_dispute(state: 'won'))).not_to be_money_movement
    end
  end

  describe '零副作用（AC-006）' do
    it '裁决不改 dispute / order / payment / ledger / inventory' do
      dispute = create_dispute(state: 'under_review', provider_status: 'lost')
      before = {
        dispute: dispute.reload.attributes,
        order: order.reload.attributes,
        payment: payment.reload.attributes,
        ledger: PallasTrade::FinancialLedgerEntry.count,
        inventory: PallasTrade::InventoryUnit.count
      }

      resolve(dispute)

      expect(dispute.reload.attributes).to eq(before[:dispute])
      expect(order.reload.attributes).to eq(before[:order])
      expect(payment.reload.attributes).to eq(before[:payment])
      expect(PallasTrade::FinancialLedgerEntry.count).to eq(before[:ledger])
      expect(PallasTrade::InventoryUnit.count).to eq(before[:inventory])
    end

    it 'provider 快照路径同样零本地写（fetch=true）' do
      dispute = create_dispute(state: 'needs_response')
      allow(payment_method).to receive(:fetch_dispute_details).and_return(
        { status: 'lost', amount: BigDecimal('12.34'), currency: 'usd', observed_at: Time.current }
      )
      before = dispute.reload.attributes

      resolve(dispute, fetch: true)

      expect(dispute.reload.attributes).to eq(before)
    end

    it '无 payment 锚点且请求 fetch → AMBIGUOUS + UNLINKED_PAYMENT' do
      dispute = create_dispute(state: 'needs_response')
      allow(dispute).to receive(:payment).and_return(nil)

      fact = resolve(dispute, fetch: true)

      expect(fact.status).to eq('AMBIGUOUS')
      expect(fact.reason_code).to eq('UNLINKED_PAYMENT')
    end
  end
end
