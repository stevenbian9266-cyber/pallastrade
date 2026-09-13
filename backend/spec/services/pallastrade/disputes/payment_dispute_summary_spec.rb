# frozen_string_literal: true

require 'rails_helper'

# PRD-20260913-payments-dsp-p7-9-partial-and-multi-dispute-semantics
# AC-P79-08 —— 支付级多争议只读聚合：1:N 争议、剩余额度、超限提示、**零写**。
RSpec.describe PallasTrade::Disputes::PaymentDisputeSummary, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }
  let(:order) { create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100) }
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: 100,
                     state: 'completed', source: nil, skip_source_requirement: true)
  end

  def make_dispute(amount:, state: 'needs_response', currency: 'usd', link_payment: true)
    PallasTrade::Dispute.create!(
      provider: 'stripe',
      provider_dispute_reference: "dp_p79s_#{SecureRandom.hex(4)}",
      state: state,
      amount: amount,
      currency: currency,
      payment: link_payment ? payment : nil
    )
  end

  def summary
    result = described_class.call(payment: payment)
    expect(result).to be_success
    result.value
  end

  it 'AC-P79-08 同一支付两笔争议：笔数/合计/剩余额度/超限标记正确' do
    make_dispute(amount: 30)
    make_dispute(amount: 20, state: 'lost')

    value = summary

    expect(value[:dispute_count]).to eq(2)
    expect(value[:active_count]).to eq(1)
    expect(value[:disputed_total].to_d).to eq(50.to_d)
    expect(value[:remaining_amount].to_d).to eq(50.to_d)
    expect(value[:exceeds_payment]).to be(false)
    expect(value[:currency].to_s.downcase).to eq('usd')
  end

  it 'AC-P79-08 合计超过支付额 → exceeds_payment（仅提示，不做任何动作）' do
    make_dispute(amount: 70)
    make_dispute(amount: 40)

    expect(summary[:exceeds_payment]).to be(true)
  end

  it 'AC-P79-08 币种不一致 → 不给合计（mixed_currency，不猜）' do
    make_dispute(amount: 30)
    make_dispute(amount: 30, currency: 'eur')

    value = summary

    expect(value[:mixed_currency]).to be(true)
    expect(value[:disputed_total]).to be_nil
    expect(value[:remaining_amount]).to be_nil
    expect(value[:exceeds_payment]).to be(false)
  end

  it 'AC-P79-08 无争议 → 计数 0、合计 0、剩余 = 支付额' do
    value = summary

    expect(value[:dispute_count]).to eq(0)
    expect(value[:disputed_total].to_d).to eq(0.to_d)
    expect(value[:remaining_amount].to_d).to eq(100.to_d)
  end

  it 'AC-P79-08 铁律：聚合零写（账本/事实不变，支付/订单关键列不变）' do
    make_dispute(amount: 30)
    counts = {
      ledger: PallasTrade::FinancialLedgerEntry.count,
      payments: PallasTrade::Payment.count
    }
    payment_snapshot = payment.reload.slice('id', 'state', 'amount', 'currency', 'updated_at')
    order_snapshot = order.reload.slice('id', 'state', 'status', 'total', 'updated_at')

    summary

    expect(PallasTrade::FinancialLedgerEntry.count).to eq(counts[:ledger])
    expect(PallasTrade::Payment.count).to eq(counts[:payments])
    expect(payment.reload.slice('id', 'state', 'amount', 'currency', 'updated_at')).to eq(payment_snapshot)
    expect(order.reload.slice('id', 'state', 'status', 'total', 'updated_at')).to eq(order_snapshot)
  end
end
