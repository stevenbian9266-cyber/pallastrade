# frozen_string_literal: true

require 'rails_helper'

# PRD-20260912-payments-dsp-p7-3-dispute-posting-and-reconcile AC-P73-04 AC-P73-05 AC-P73-06
# `PallasTrade::FinancialFacts::ResolveDispute` —— Dispute → FinancialFact（P4 §16 契约）：
#   现金事实（withdrawn/reinstated）带方向符号；非现金事实（opened/won/lost）不入账；
#   终态优先的 P7-2 事实不吞掉后续 funds 资金事件（fact_type 提示）。
RSpec.describe PallasTrade::FinancialFacts::ResolveDispute, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }
  let(:order) { create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100) }
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: 100,
                     state: 'completed', source: nil, skip_source_requirement: true)
  end
  let(:txn) { PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: 100) }

  def make_dispute(**attrs)
    defaults = { state: 'needs_response', provider_status: 'needs_response', funds_withdrawn_at: nil,
                 funds_reinstated_at: nil, amount: 12.34, currency: 'usd' }
    values = defaults.merge(attrs)

    PallasTrade::Dispute.create!(
      provider: 'stripe',
      provider_dispute_reference: "dp_#{SecureRandom.hex(4)}",
      state: values[:state],
      amount: values[:amount],
      currency: values[:currency],
      private_metadata: { 'provider_status' => values[:provider_status] },
      funds_withdrawn_at: values[:funds_withdrawn_at],
      funds_reinstated_at: values[:funds_reinstated_at],
      commerce_transaction: txn,
      payment: payment
    )
  end

  def resolve(dispute, fact_type: nil)
    result = described_class.call(dispute: dispute, fact_type: fact_type)

    expect(result).to be_success
    result.value
  end

  it 'AC-P73-04 funds withdrawn → 现金事实，金额取负（资金流出）' do
    dispute = make_dispute(funds_withdrawn_at: Time.current)
    fact = resolve(dispute)

    expect(fact.fact_type).to eq('DISPUTE_FUNDS_WITHDRAWN')
    expect(fact.status).to eq('CONFIRMED')
    expect(fact.amount.to_d).to eq(-12.34.to_d)
    expect(fact.instrument_class).to eq('PSP_CASH')
    expect(fact.dispute_id).to eq(dispute.prefixed_id)
    expect(fact.commerce_transaction_id).to eq(txn.prefixed_id)
    expect(fact.effective_at).to eq(dispute.funds_withdrawn_at)
    expect(fact.provider_dispute_reference).to eq(dispute.provider_dispute_reference)
  end

  it 'AC-P73-04 funds reinstated → 现金事实，金额取正（资金流入）' do
    dispute = make_dispute(funds_withdrawn_at: 2.days.ago, funds_reinstated_at: Time.current)
    fact = resolve(dispute)

    expect(fact.fact_type).to eq('DISPUTE_FUNDS_REINSTATED')
    expect(fact.amount.to_d).to eq(12.34.to_d)
    expect(fact.effective_at).to eq(dispute.funds_reinstated_at)
  end

  it 'AC-P73-05 非现金事实（opened）→ UNKNOWN 工具类，保留原值且无资金时间戳' do
    fact = resolve(make_dispute)

    expect(fact.fact_type).to eq('DISPUTE_OPENED')
    expect(fact.instrument_class).to eq('UNKNOWN')
    expect(fact.amount.to_d).to eq(12.34.to_d)
    expect(PallasTrade::FinancialLedgerEntry::ENTRY_TYPES).not_to include('DISPUTE_OPENED')
  end

  it 'AC-P73-04 终态 won 不吞掉资金事件：hint 覆盖「当前最强事实」' do
    dispute = make_dispute(state: 'won', provider_status: 'won',
                           funds_withdrawn_at: 3.days.ago, funds_reinstated_at: 1.day.ago)

    # 无 hint → P7-2 语义（终态优先）→ 非现金事实，永不入账
    expect(resolve(dispute).fact_type).to eq('DISPUTE_WON')

    # 事件作用域 hint → 现金事实，资金返还仍可入账（否则出现资金缺口）
    reinstated = resolve(dispute, fact_type: 'DISPUTE_FUNDS_REINSTATED')
    expect(reinstated.fact_type).to eq('DISPUTE_FUNDS_REINSTATED')
    expect(reinstated.amount.to_d).to eq(12.34.to_d)
    expect(reinstated.effective_at).to eq(dispute.funds_reinstated_at)
  end

  it 'AC-P73-06 金额不可证（0）→ AMBIGUOUS（不猜）' do
    fact = resolve(make_dispute(funds_withdrawn_at: Time.current, amount: 0))

    expect(fact.status).to eq('AMBIGUOUS')
    expect(fact).not_to be_confirmed
  end

  it 'AC-P73-08 只读：解析前后 dispute 属性不变' do
    dispute = make_dispute(funds_withdrawn_at: Time.current)
    before = dispute.reload.attributes

    resolve(dispute)

    expect(dispute.reload.attributes).to eq(before)
  end
end
