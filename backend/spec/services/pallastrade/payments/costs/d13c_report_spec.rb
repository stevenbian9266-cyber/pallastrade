# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13c-fee-cost-report（D13 切片3）
#   AC-6 ← FR-4：报表汇总自洽（totals == Σ detail；入口排名 Σfee == totals.fee）
#   AC-7 ← FR-4：**成本可下钻到入口**（入口排名行下钻，明细条数 == 该入口 payment_count）
#   AC-8 ← FR-4：期间左闭右开 / 跨店隔离 / 未完成支付不入选
#   AC-9 ← FR-4：实际 vs 模型（payout_lines.fee_amount）
#   AC-10 ← FR-8：零资金副作用
#   AC-14 ← NFR-1：查询数不随行数增长
RSpec.describe PallasTrade::Payments::Costs::Report do
  let!(:store) do
    create(:store, code: "d13c_report_#{SecureRandom.hex(4)}", default_currency: 'USD')
  end
  let!(:other_store) { create(:store, code: "d13c_report_other_#{SecureRandom.hex(4)}", default_currency: 'USD') }
  let!(:provider_a) do
    create(:check_payment_method, store: store, active: true, display_on: 'both',
                                  name: "d13c-stripe-#{SecureRandom.hex(3)}",
                                  metadata: { 'optionized' => true,
                                              'options' => [{ 'kind' => 'card', 'active' => true, 'position' => 0,
                                                              'display_name' => 'Card' }] })
  end
  let!(:provider_b) do
    create(:check_payment_method, store: store, active: true, display_on: 'both',
                                  name: "d13c-adyen-#{SecureRandom.hex(3)}")
  end
  # 他店 provider（跨店隔离用例：订单属于 other_store，支付方式也属于 other_store）
  let!(:other_provider) do
    create(:check_payment_method, store: other_store, active: true, display_on: 'both',
                                  name: "d13c-other-#{SecureRandom.hex(3)}")
  end

  let(:from) { Time.zone.parse('2026-09-01 00:00:00') }
  let(:to) { Time.zone.parse('2026-10-01 00:00:00') }

  # 支付金额 = 订单总额口径（`Payment#set_amount` 与 max_amount 校验都以订单总额为准），
  # 因此订单总额必须显式给定且足够大；期间通过 `update_columns` 回写时间戳（不参与任何状态机）。
  # 注意：关键字参数名不能与 `store` let 同名（`store: store` 会被 Ruby 求值为 nil）。
  def build_paid_order(amount:, paid_at:, target_store: store, provider: provider_a, state: 'completed',
                       currency: 'USD')
    order = create(:order_with_line_items, store: target_store, currency: currency, line_items_count: 1,
                                           line_items_price: [amount.to_d, 100.to_d].max * 2, shipment_cost: 0)
    payment = create(:payment, order: order, payment_method: provider, amount: amount, state: state,
                               source: nil, skip_source_requirement: true)
    payment.update_columns(created_at: paid_at, updated_at: paid_at)
    payment
  end

  def call(**overrides)
    described_class.call({ store: store, from: from, to: to }.merge(overrides)).value
  end

  before do
    # 兜底费率：2.9% + 0.30
    create(:payment_fee_policy, store: store, name: 'fallback', scope_type: 'global', percent_fee: 2.9, fixed_fee: 0.3)
    # 入口（method_key）专属费率：provider_a 的 card 入口 1% + 0
    create(:payment_fee_policy, store: store, name: 'entry card', scope_type: 'method', scope_id: 'card',
                                percent_fee: 1, fixed_fee: 0)
  end

  describe 'aggregation' do
    it 'keeps totals consistent with the detail rows' do
      build_paid_order(amount: 100, paid_at: from + 1.day)
      build_paid_order(amount: 250, paid_at: from + 2.days, provider: provider_b)

      result = call

      expect(result[:totals][:payment_count]).to eq(2)
      expect(result[:detail].sum { |row| row[:fee_amount] }).to eq(result[:totals][:fee_amount])
      expect(result[:detail].sum { |row| row[:amount] }).to eq(result[:totals][:gross_amount])
      expect(result[:by_entry].sum { |entry| entry[:fee_amount] }).to eq(result[:totals][:fee_amount])
      expect(result[:by_provider].sum { |entry| entry[:fee_amount] }).to eq(result[:totals][:fee_amount])
      expect(result[:by_currency].sum { |entry| entry[:fee_amount] }).to eq(result[:totals][:fee_amount])
    end

    it 'computes cost per order on distinct orders' do
      order = create(:order_with_line_items, store: store, currency: 'USD', line_items_count: 1,
                                             line_items_price: 5000, shipment_cost: 0)
      create(:payment, order: order, payment_method: provider_a, amount: 100, state: 'completed',
                       source: nil, skip_source_requirement: true)
      create(:payment, order: order, payment_method: provider_a, amount: 50, state: 'completed',
                       source: nil, skip_source_requirement: true)

      result = call

      expect(result[:totals][:order_count]).to eq(1)
      expect(result[:totals][:payment_count]).to eq(2)
      expect(result[:totals][:average_order_cost]).to eq(result[:totals][:fee_amount])
      expect(result[:totals][:average_payment_cost]).to eq((result[:totals][:fee_amount] / 2).round(2))
    end
  end

  describe 'entry ranking and drill-down (AC-7)' do
    it 'groups cost by entry and drills down to the same row set' do
      # provider_a 的 card 入口用 1% 费率；provider_b 无 method 策略 → 落到兜底 2.9% + 0.3
      3.times { |i| build_paid_order(amount: 100, paid_at: from + i.days + 1.hour) }
      2.times { |i| build_paid_order(amount: 200, paid_at: from + i.days + 2.hours, provider: provider_b) }

      result = call

      entry_a = result[:by_entry].find { |entry| entry[:provider_id] == provider_a.id.to_s }
      expect(entry_a[:payment_count]).to eq(3)
      expect(entry_a[:fee_amount]).to eq(3.to_d) # 3 × (100 × 1%)
      expect(entry_a[:average_order_cost]).to eq(1.to_d)

      # 排名按成本降序：provider_b 的 2×6.1=12.2 > 3.0
      expect(result[:by_entry].first[:provider_id]).to eq(provider_b.id.to_s)

      # 下钻：入口过滤后明细条数 == 该入口 payment_count
      drilled = call(method_key: entry_a[:method_key])
      expect(drilled[:detail].size).to eq(entry_a[:payment_count])
      expect(drilled[:detail].all? { |row| row[:provider_key] == provider_a.id.to_s }).to be(true)
    end

    it 'ranks deterministically when costs tie' do
      # 两条入口费率一致 → 成本完全相等，排名靠 key 升序（确定性）
      create(:payment_fee_policy, store: store, name: 'entry check', scope_type: 'method', scope_id: 'check',
                                  percent_fee: 1, fixed_fee: 0)
      build_paid_order(amount: 100, paid_at: from + 1.day, provider: provider_a)
      build_paid_order(amount: 100, paid_at: from + 1.day, provider: provider_b)

      entries = call[:by_entry]

      expect(entries.map { |entry| entry[:fee_amount] }.uniq).to eq([1.to_d])
      expect(entries.map { |entry| entry[:key] }).to eq(entries.map { |entry| entry[:key] }.sort)
    end
  end

  describe 'scope of the fact set (AC-8)' do
    it 'excludes payments outside the period (left-closed, right-open)' do
      inside = build_paid_order(amount: 100, paid_at: from)
      build_paid_order(amount: 100, paid_at: to)
      build_paid_order(amount: 100, paid_at: from - 1.second)

      result = call

      expect(result[:detail].map { |row| row[:payment_id] }).to eq([inside.id])
    end

    it 'excludes payments of another store and non-completed payments' do
      mine = build_paid_order(amount: 100, paid_at: from + 1.day)
      build_paid_order(amount: 100, paid_at: from + 1.day, target_store: other_store, provider: other_provider)
      build_paid_order(amount: 100, paid_at: from + 1.day, state: 'checkout')

      result = call

      expect(result[:detail].map { |row| row[:payment_id] }).to eq([mine.id])
    end

    it 'filters by provider and currency' do
      build_paid_order(amount: 100, paid_at: from + 1.day)
      eur = build_paid_order(amount: 100, paid_at: from + 1.day, provider: provider_b, currency: 'EUR')

      expect(call(payment_method_id: provider_a.id)[:totals][:payment_count]).to eq(1)
      expect(call(currency: 'eur')[:detail].map { |row| row[:payment_id] }).to eq([eur.id])
    end

    it 'clamps an over-wide period to 366 days and flags it' do
      result = described_class.call(store: store, from: 3.years.ago, to: Time.current).value

      expect(result[:period][:clamped]).to be(true)
      expect(result[:period][:days]).to be <= 366
    end
  end

  describe 'actual vs modelled (AC-9)' do
    it 'exposes the provider-reported fee and the variance when a payout line exists' do
      payment = build_paid_order(amount: 100, paid_at: from + 1.day)
      payout = PallasTrade::Payout.create!(store: store, provider: 'stripe', reference: "po_#{SecureRandom.hex(4)}",
                                           currency: 'USD', status: 'settled', settled_at: from + 5.days,
                                           imported_at: Time.current, gross_total: 100, fee_total: 1.5, net_total: 98.5)
      PallasTrade::PayoutLine.create!(payout: payout, payment: payment, kind: 'charge',
                                      provider_reference: "ch_#{SecureRandom.hex(4)}", currency: 'USD',
                                      gross_amount: 100, fee_amount: 1.5, net_amount: 98.5, match_status: 'matched')

      result = call

      row = result[:detail].first
      expect(row[:fee_amount]).to eq(1.to_d) # 模型：100 × 1%（provider_a 的 card 入口）
      expect(row[:actual_fee_amount]).to eq(1.5.to_d)
      expect(row[:variance_amount]).to eq(0.5.to_d)
      expect(result[:totals][:variance_amount]).to eq(0.5.to_d)
      expect(result[:totals][:variance_coverage]).to eq(1)
    end

    it 'leaves actual fee empty when no payout line exists' do
      build_paid_order(amount: 100, paid_at: from + 1.day)

      row = call[:detail].first

      expect(row[:actual_fee_amount]).to be_nil
      expect(row[:variance_amount]).to be_nil
      expect(call[:totals][:variance_coverage]).to eq(0)
    end
  end

  describe 'unpriced (AC-5)' do
    it 'counts unpriced payments and reports why' do
      PallasTrade::PaymentFeePolicy.for_store(store).find_each { |policy| policy.revoke! }
      build_paid_order(amount: 100, paid_at: from + 1.day)

      result = call

      expect(result[:totals][:unpriced_count]).to eq(1)
      expect(result[:totals][:fee_amount]).to eq(0.to_d)
      expect(result[:detail].first[:priced]).to be(false)
      expect(result[:unpriced_reasons]).to include('no_policy' => 1)
    end
  end

  describe 'purity (AC-10)' do
    it 'does not touch money facts' do
      build_paid_order(amount: 100, paid_at: from + 1.day)

      before_snapshot = money_snapshot

      call

      expect(money_snapshot).to eq(before_snapshot)
    end
  end

  describe 'performance (AC-14)' do
    it 'keeps the query count flat as the number of payments grows' do
      2.times { |i| build_paid_order(amount: 100, paid_at: from + i.days + 1.hour) }
      small = count_queries { call }

      8.times { |i| build_paid_order(amount: 100, paid_at: from + i.days + 2.hours) }
      large = count_queries { call }

      expect(large).to be <= small + 1
    end
  end

  def count_queries
    queries = []
    counter = lambda do |_name, _start, _finish, _id, payload|
      queries << payload[:sql] unless payload[:name].to_s == 'SCHEMA' || payload[:cached]
    end

    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { yield }
    queries.size
  end

  def money_snapshot
    {
      payments: PallasTrade::Payment.count,
      payments_sum: PallasTrade::Payment.sum(:amount).to_d,
      refunds: PallasTrade::Refund.count,
      ledger: PallasTrade::FinancialLedgerEntry.count,
      policy_count: PallasTrade::PaymentFeePolicy.count,
      inventory: PallasTrade::StockItem.sum(:count_on_hand).to_i
    }
  end
end
