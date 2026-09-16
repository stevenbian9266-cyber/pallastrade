# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d14c-dispute-rate-board AC-009（巡检：多店遍历 + 失败隔离 + 指标日志 + 零资金副作用）
RSpec.describe PallasTrade::Disputes::RateAlertSweeperJob, type: :job do
  let(:suffix) { SecureRandom.hex(4) }
  let(:us) do
    PallasTrade::Country.find_by(iso: 'US') ||
      create(:country, iso: 'US', name: 'United States', iso_name: 'UNITED STATES', iso3: 'USA', numcode: 840)
  end

  def build_store(prefix)
    create(:store, code: "d14c_sweep_#{prefix}_#{suffix}", default_currency: 'USD', supported_currencies: 'USD')
  end

  def configure_thresholds(store, policy)
    store.update_columns(private_metadata: (store.private_metadata || {}).merge(
      PallasTrade::Disputes::RatePolicy::KEY => policy
    ))
    store.reload
  end

  def seed_breaching(store, email:)
    order = create(:order_with_line_items, store: store, currency: 'USD', email: "#{email}@example.com",
                                           line_items_count: 1, line_items_price: 100, shipment_cost: 0)
    address = create(:address, country: us)
    order.update_columns(bill_address_id: address.id, email: "#{email}@example.com", total: 100,
                         item_total: 100, payment_total: 0)
    method = create(:credit_card_payment_method, stores: [store])
    card = create(:credit_card, cc_type: 'visa', payment_method: method,
                                fingerprint: "fp_#{SecureRandom.hex(3)}")
    payment = create(:payment, order: order, payment_method: method, source: card,
                               amount: 100, state: 'completed')
    PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: "dp_#{SecureRandom.hex(6)}",
      state: 'needs_response', kind: 'chargeback', amount: 100, currency: 'USD',
      payment: payment, order: order, store: store
    )
  end

  # AC-009
  it 'sweeps every store, isolates failures and logs structured metrics' do
    breaching = build_store('breach')
    failing = build_store('fail')
    quiet = build_store('quiet')
    configure_thresholds(breaching, 'networks' => { 'visa' => { 'count_bps' => 1_000 } })
    configure_thresholds(quiet, 'networks' => { 'visa' => { 'count_bps' => 1_000 } })
    seed_breaching(breaching, email: 'sweep-breach')

    stores = [breaching, failing, quiet]
    allow(PallasTrade::Store).to receive(:find_each) { |&block| stores.each(&block) }
    allow(PallasTrade::Disputes::RatePolicy).to receive(:for).and_wrap_original do |original, store|
      raise 'boom' if store.id == failing.id

      original.call(store)
    end
    allow(Rails.logger).to receive(:info).and_call_original
    allow(Rails.logger).to receive(:error).and_call_original

    before = { payments: PallasTrade::Payment.count, ledger: PallasTrade::FinancialLedgerEntry.count,
               inventory: PallasTrade::StockItem.sum(:count_on_hand).to_i }

    metrics = described_class.new.perform

    expect(metrics[:stores]).to eq(3)
    expect(metrics[:evaluated]).to eq(2)
    expect(metrics[:failed]).to eq(1)
    expect(metrics[:recorded]).to eq(1)
    expect(metrics[:escalated]).to eq(1)

    alert = PallasTrade::DisputeRateAlert.last
    expect(alert.store_id).to eq(breaching.id)
    expect(alert.tier).to eq(PallasTrade::DisputeRateAlert::BREACHED)
    expect(PallasTrade::DisputeRateAlert.count).to eq(1)

    expect(Rails.logger).to have_received(:info).with(a_string_including('dispute.rate_alert_sweeper'))
    expect(Rails.logger).to have_received(:error).with(a_string_including("store #{failing.id} raised"))

    expect(PallasTrade::Payment.count).to eq(before[:payments])
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(before[:ledger])
    expect(PallasTrade::StockItem.sum(:count_on_hand).to_i).to eq(before[:inventory])
  end

  # AC-009（窗口参数可覆盖店铺策略：20 天前的数据在 7 天策略下不算，在 30 天覆盖下算）
  it 'honors a window override and leaves unconfigured stores untouched' do
    store = build_store('window')
    configure_thresholds(store, 'window_days' => 7, 'networks' => { 'visa' => { 'count_bps' => 1_000 } })
    seed_breaching(store, email: 'sweep-window')
    PallasTrade::Payment.update_all(created_at: 20.days.ago, updated_at: 20.days.ago)
    PallasTrade::Dispute.update_all(created_at: 20.days.ago, updated_at: 20.days.ago)

    allow(PallasTrade::Store).to receive(:find_each) { |&block| [store].each(&block) }
    allow(Rails.logger).to receive(:info).and_call_original

    policy_window = described_class.new.perform
    expect(policy_window[:recorded]).to eq(0)
    expect(PallasTrade::DisputeRateAlert.count).to eq(0)

    override_window = described_class.new.perform(window_days: 30)
    expect(override_window[:recorded]).to eq(1)
    expect(PallasTrade::DisputeRateAlert.last.window_days).to eq(30)
  end

  # AC-009（纯本地统计：全程不接触任何 provider 实例）
  it 'never talks to a payment provider' do
    store = build_store('providers')
    configure_thresholds(store, 'networks' => { 'visa' => { 'count_bps' => 1_000 } })
    seed_breaching(store, email: 'sweep-provider')

    allow(PallasTrade::Store).to receive(:find_each) { |&block| [store].each(&block) }
    allow(Rails.logger).to receive(:info).and_call_original
    allow_any_instance_of(PallasTrade::Gateway).to receive(:provider).and_raise('provider must not be called')

    expect { described_class.new.perform }.not_to raise_error
    expect(PallasTrade::DisputeRateAlert.count).to eq(1)
  end
end
