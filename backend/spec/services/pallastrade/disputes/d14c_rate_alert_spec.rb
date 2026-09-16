# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d14c-dispute-rate-board
#   AC-006 台账幂等（同店/组织/评估日唯一，重复评估不新增行）
#   AC-007 档位升级（approaching → breached 更新同一行 + escalated_at；未升级不发事件）
#   AC-008 事件仅在档位变化时发布；事件系统未启用/发布失败不影响台账
#   AC-014 只读 + 零资金副作用
RSpec.describe PallasTrade::Disputes::RateAlert, type: :service do
  let(:suffix) { SecureRandom.hex(4) }
  let(:store) do
    create(:store, code: "d14c_alert_#{suffix}", default_currency: 'USD', supported_currencies: 'USD,EUR')
  end
  let(:us) do
    PallasTrade::Country.find_by(iso: 'US') ||
      create(:country, iso: 'US', name: 'United States', iso_name: 'UNITED STATES', iso3: 'USA', numcode: 840)
  end

  def build_order(email:, at: 5.days.ago, amount: 100, currency: 'USD')
    order = create(:order_with_line_items, store: store, currency: currency, email: email,
                                           line_items_count: 1, line_items_price: amount, shipment_cost: 0)
    address = create(:address, country: us)
    order.update_columns(bill_address_id: address.id, email: email, total: amount, item_total: amount,
                         payment_total: 0, created_at: at, updated_at: at)
    order.reload
  end

  def build_card_payment(order:, brand: 'visa', amount: 100, at: 5.days.ago)
    method = create(:credit_card_payment_method, stores: [store])
    card = create(:credit_card, cc_type: brand, payment_method: method,
                                fingerprint: "fp_#{brand}_#{SecureRandom.hex(3)}")
    payment = create(:payment, order: order, payment_method: method, source: card,
                               amount: amount, state: 'completed')
    payment.update_columns(created_at: at, updated_at: at)
    payment.reload
  end

  def build_dispute(payment:, amount:, at: 4.days.ago)
    dispute = PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: "dp_#{SecureRandom.hex(6)}",
      state: 'needs_response', kind: 'chargeback', amount: amount,
      currency: payment.order.currency, payment: payment, order: payment.order, store: store
    )
    dispute.update_columns(created_at: at, updated_at: at)
    dispute
  end

  # 事件收集（只统计本服务的事件名：争议创建本身也会发布资金事件）
  def capture_rate_events
    published = []
    allow(PallasTrade::Events).to receive(:enabled?).and_return(true)
    allow(PallasTrade::Events).to receive(:publish) { |name, payload| published << [name, payload] }
    published
  end

  # 只保留本服务的事件名（建单/建支付会发布其它事件，不能整体计数）
  def rate_events(published)
    published.select { |name, _payload| name == described_class::EVENT_NAME }
  end

  def configure_thresholds(policy)
    store.update_columns(private_metadata: (store.private_metadata || {}).merge(
      PallasTrade::Disputes::RatePolicy::KEY => policy
    ))
    store.reload
  end

  # 造「阈值已配置 + 有数据」的场景：支付与争议都显式控制笔数
  def seed_transaction(email:, at: 5.days.ago, brand: 'visa', amount: 100, index: nil)
    suffix_email = index ? "#{email}-#{index}@example.com" : "#{email}@example.com"
    build_card_payment(order: build_order(email: suffix_email, at: at), brand: brand, amount: amount, at: at)
  end

  def seed_disputes(payment:, count:, at: 4.days.ago)
    count.times { build_dispute(payment: payment, amount: payment.amount.to_d, at: at) }
    payment
  end

  describe 'tier recording' do
    # AC-006（ok / unconfigured 不落行，避免噪声）
    it 'records nothing when the network is ok or unconfigured' do
      configure_thresholds('networks' => { 'visa' => { 'count_bps' => 9_000 } })
      10.times { |i| seed_transaction(email: 'ok', index: i, at: (i + 1).days.ago) }
      seed_disputes(payment: seed_transaction(email: 'ok-extra'), count: 1)

      outcome = described_class.call(store: store, evaluated_on: Date.current)

      expect(outcome).to be_success
      expect(outcome.value[:recorded]).to eq([])
      expect(outcome.value[:skipped]).to include('ok')
      expect(PallasTrade::DisputeRateAlert.count).to eq(0)
    end

    # AC-006 / AC-007（首次即 breached → 落行 + 事件 + escalated_at）
    it 'records a breached row and publishes one event on first detection' do
      configure_thresholds('networks' => { 'visa' => { 'count_bps' => 1_000 } })
      payment = seed_transaction(email: 'breach')
      seed_disputes(payment: payment, count: 1)

      events = []
      allow(PallasTrade::Events).to receive(:enabled?).and_return(true)
      allow(PallasTrade::Events).to receive(:publish) { |name, payload| events << [name, payload] }

      outcome = described_class.call(store: store, evaluated_on: Date.current)
      alert = PallasTrade::DisputeRateAlert.last

      expect(outcome.value[:recorded].size).to eq(1)
      expect(outcome.value[:escalated].size).to eq(1)
      expect(alert.tier).to eq(PallasTrade::DisputeRateAlert::BREACHED)
      expect(alert.escalated_at).to be_present
      expect(alert.triggered).to include('count')
      expect(alert.count_ratio_bps).to eq(10_000)
      expect(alert.transactions_count).to eq(1)
      expect(alert.disputes_count).to eq(1)
      expect(alert.dedupe_key).to eq("rate:#{store.id}:visa:#{Date.current.iso8601}")

      expect(events.size).to eq(1)
      expect(events.first.first).to eq(described_class::EVENT_NAME)
      expect(events.first.last).to include(
        store_id: store.id, network: 'visa', tier: 'breached',
        count_ratio_bps: 10_000, count_threshold_bps: 1_000, triggered_metrics: ['count']
      )
    end

    # AC-006（同日重复评估：同一行，不新增、不发事件）
    it 'reuses the same row on a repeated evaluation of the same day' do
      configure_thresholds('networks' => { 'visa' => { 'count_bps' => 1_000 } })
      payment = seed_transaction(email: 'repeat')
      seed_disputes(payment: payment, count: 1)

      published = capture_rate_events

      first = described_class.call(store: store, evaluated_on: Date.current)
      second = described_class.call(store: store, evaluated_on: Date.current)

      expect(PallasTrade::DisputeRateAlert.count).to eq(1)
      expect(first.value[:escalated]).to eq([PallasTrade::DisputeRateAlert.last.id])
      expect(second.value[:escalated]).to eq([])
      expect(rate_events(published).size).to eq(1)
    end

    # AC-007（升级：同一天 approaching → breached → 同一行升级 + escalated_at + 第二条事件）
    it 'escalates the same row when the ratio crosses the threshold later the same day' do
      # 3 笔交易；2 笔争议 → 6667 bps（阈值 8000 的 80% = 6400）→ approaching
      configure_thresholds('warning_ratio' => 0.8, 'networks' => { 'visa' => { 'count_bps' => 8_000 } })
      payment_a = seed_transaction(email: 'escalate')
      seed_transaction(email: 'escalate-b')
      seed_transaction(email: 'escalate-c')
      seed_disputes(payment: payment_a, count: 2)

      published = capture_rate_events

      first = described_class.call(store: store, evaluated_on: Date.current)
      alert = PallasTrade::DisputeRateAlert.last
      expect(first.value[:recorded].size).to eq(1)
      expect(alert.tier).to eq(PallasTrade::DisputeRateAlert::APPROACHING)
      expect(alert.count_ratio_bps).to eq(6_667)
      expect(rate_events(published).size).to eq(1)

      # 再加 1 笔争议（分母不变）→ 3/3 = 100% ≥ 80% → 升级 breached
      seed_disputes(payment: payment_a, count: 1)
      second = described_class.call(store: store, evaluated_on: Date.current)
      alert.reload

      expect(second.value[:recorded].size).to eq(1)
      expect(second.value[:escalated]).to eq([alert.id])
      expect(PallasTrade::DisputeRateAlert.count).to eq(1)
      expect(alert.tier).to eq(PallasTrade::DisputeRateAlert::BREACHED)
      expect(alert.escalated_at).to be_present
      expect(rate_events(published).size).to eq(2)
    end

    # AC-007（同日不降档：比率回落只刷新观测值并记 relaxed_at）
    it 'never downgrades the tier recorded for the same day' do
      configure_thresholds('warning_ratio' => 0.8, 'networks' => { 'visa' => { 'count_bps' => 8_000 } })
      payment = seed_transaction(email: 'relax')
      seed_transaction(email: 'relax-b')
      seed_transaction(email: 'relax-c')
      seed_disputes(payment: payment, count: 2)

      published = capture_rate_events

      described_class.call(store: store, evaluated_on: Date.current)
      alert = PallasTrade::DisputeRateAlert.last
      expect(alert.tier).to eq(PallasTrade::DisputeRateAlert::APPROACHING)

      20.times { |i| seed_transaction(email: 'relax-extra', index: i, at: (i + 1).days.ago) }
      second = described_class.call(store: store, evaluated_on: Date.current)
      alert.reload

      expect(second.value[:escalated]).to eq([])
      expect(alert.tier).to eq(PallasTrade::DisputeRateAlert::APPROACHING)
      expect(alert.transactions_count).to eq(23)
      expect(alert.metadata['observed_tier']).to eq('ok')
      expect(alert.metadata['relaxed_at']).to be_present
      expect(rate_events(published).size).to eq(1)
    end

    # AC-006（unknown 组织不落行）
    it 'skips the unknown network bucket' do
      configure_thresholds('networks' => { 'visa' => { 'count_bps' => 1_000 } })
      method = create(:check_payment_method, stores: [store])
      order = build_order(email: "unknown-#{suffix}@example.com")
      payment = create(:payment, order: order, payment_method: method, source: nil,
                                 skip_source_requirement: true, amount: 100, state: 'completed')
      build_dispute(payment: payment, amount: 100)

      outcome = described_class.call(store: store, evaluated_on: Date.current)

      expect(outcome.value[:skipped]).to include('unknown_network')
      expect(PallasTrade::DisputeRateAlert.count).to eq(0)
    end

    # AC-006（策略关闭 → 不评估、不落行）
    it 'does nothing when alerting is disabled in the policy' do
      configure_thresholds('enabled' => false, 'networks' => { 'visa' => { 'count_bps' => 100 } })
      payment = seed_transaction(email: 'disabled')
      seed_disputes(payment: payment, count: 1)

      outcome = described_class.call(store: store, evaluated_on: Date.current)

      expect(outcome.value[:recorded]).to eq([])
      expect(outcome.value[:skipped]).to eq(['disabled'])
      expect(PallasTrade::DisputeRateAlert.count).to eq(0)
    end

    # AC-008（事件系统未启用 → 台账照写、不报错）
    it 'writes the ledger even when the event system is disabled' do
      configure_thresholds('networks' => { 'visa' => { 'count_bps' => 1_000 } })
      payment = seed_transaction(email: 'no-events')
      seed_disputes(payment: payment, count: 1)

      allow(PallasTrade::Events).to receive(:enabled?).and_return(false)
      outcome = described_class.call(store: store, evaluated_on: Date.current)

      expect(outcome.value[:recorded].size).to eq(1)
      expect(PallasTrade::DisputeRateAlert.count).to eq(1)
    end

    # AC-014（只读：不改支付/订单/争议金额与状态；写审计）
    it 'never touches money or dispute state and records an audit' do
      configure_thresholds('networks' => { 'visa' => { 'count_bps' => 1_000 } })
      payment = seed_transaction(email: 'audit')
      seed_disputes(payment: payment, count: 1)

      before = {
        payments_sum: PallasTrade::Payment.sum(:amount).to_d.to_s,
        orders_total: PallasTrade::Order.sum(:total).to_d.to_s,
        dispute_states: PallasTrade::Dispute.group(:state).count,
        ledger: PallasTrade::FinancialLedgerEntry.count,
        inventory: PallasTrade::StockItem.sum(:count_on_hand).to_i
      }

      described_class.call(store: store, evaluated_on: Date.current)

      after = {
        payments_sum: PallasTrade::Payment.sum(:amount).to_d.to_s,
        orders_total: PallasTrade::Order.sum(:total).to_d.to_s,
        dispute_states: PallasTrade::Dispute.group(:state).count,
        ledger: PallasTrade::FinancialLedgerEntry.count,
        inventory: PallasTrade::StockItem.sum(:count_on_hand).to_i
      }

      expect(after).to eq(before)
      expect(
        PallasTrade::AuditLog.where(action: described_class::AUDIT_ACTION).where(resource_id: store.id).count
      ).to eq(1)
    end

    # AC-009（store 缺失 → 失败结果，不写库）
    it 'fails without writing when the store is missing' do
      outcome = described_class.call(store: nil)

      expect(outcome).not_to be_success
      expect(PallasTrade::DisputeRateAlert.count).to eq(0)
    end
  end
end
