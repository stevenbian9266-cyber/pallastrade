# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d14c-dispute-rate-board
#   AC-002 比率口径（分子=窗口内争议；分母=窗口内该组织已完成卡支付；分母 0 → nil）
#   AC-003 卡组织归因（mastercard/maestro → master、amex → american_express；不可判定 → unknown 且不判定）
#   AC-004 跨币种不混算（其他币种计入 excluded_* 计数并明示）
#   AC-005 状态判定（ok / approaching ≥80% / breached ≥100% / unconfigured）
#   AC-010 下钻四维度（桶合计 == 汇总；unknown 桶保留）
#   AC-014 只读 + 查询数不随行数增长
RSpec.describe PallasTrade::Disputes::RateReport, type: :service do
  let(:suffix) { SecureRandom.hex(4) }
  let(:store) do
    create(:store, code: "d14c_report_#{suffix}", default_currency: 'USD', supported_currencies: 'USD,EUR')
  end
  let(:us) do
    PallasTrade::Country.find_by(iso: 'US') ||
      create(:country, iso: 'US', name: 'United States', iso_name: 'UNITED STATES', iso3: 'USA', numcode: 840)
  end
  let(:de) do
    PallasTrade::Country.find_by(iso: 'DE') ||
      create(:country, iso: 'DE', name: 'Germany', iso_name: 'GERMANY', iso3: 'DEU', numcode: 276)
  end

  # 一个订单承载一笔支付（`Payment` 金额受订单可用额度约束 —— 用真实行项目价格建单最稳）
  # ⚠️ 订单工厂会用自己的序列邮箱，必须显式回写 `email`（客群维度依赖它）
  def build_order(email:, country:, currency: 'USD', at: 5.days.ago, amount: 100)
    order = create(:order_with_line_items, store: store, currency: currency, email: email,
                                           line_items_count: 1, line_items_price: amount, shipment_cost: 0)
    address = create(:address, country: country)
    order.update_columns(bill_address_id: address.id, email: email, total: amount, item_total: amount,
                         payment_total: 0, created_at: at, updated_at: at)
    order.reload
  end

  def build_card_payment(order:, brand:, amount:, at: 5.days.ago, fingerprint: nil, legacy_brand: nil)
    method = create(:credit_card_payment_method, stores: [store])
    card = create(:credit_card, cc_type: brand, payment_method: method,
                                fingerprint: fingerprint || "fp_#{brand}_#{SecureRandom.hex(3)}")
    # 模拟历史行：绕过写入期归一（`cc_type=` 会把 mastercard/amex 归一），验证读取期别名处理
    card.update_columns(cc_type: legacy_brand) if legacy_brand.present?
    payment = create(:payment, order: order, payment_method: method, source: card,
                               amount: amount, state: 'completed')
    payment.update_columns(created_at: at, updated_at: at)
    payment.reload
  end

  def build_check_payment(order:, amount: 40, at: 5.days.ago)
    payment = create(:payment, order: order, payment_method: create(:check_payment_method, stores: [store]),
                               source: nil, skip_source_requirement: true, amount: amount, state: 'completed')
    payment.update_columns(created_at: at, updated_at: at)
    payment.reload
  end

  def build_dispute(payment:, amount:, at: 4.days.ago, currency: nil)
    dispute = PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: "dp_#{SecureRandom.hex(6)}",
      state: 'needs_response', kind: 'chargeback', amount: amount,
      currency: currency || payment.order.currency, payment: payment, order: payment.order, store: store
    )
    dispute.update_columns(created_at: at, updated_at: at)
    dispute
  end

  def configure_thresholds(policy)
    store.update_columns(private_metadata: (store.private_metadata || {}).merge(
      PallasTrade::Disputes::RatePolicy::KEY => policy
    ))
    store.reload
  end

  def count_sql_queries
    count = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name].to_s == 'SCHEMA'
      next if payload[:cached]

      count += 1
    end
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { yield }
    count
  end

  # === 汇总口径 ===

  # AC-002 / AC-003 / AC-004 / AC-005
  it 'computes per-network ratios with unknown and cross-currency handled explicitly' do
    configure_thresholds(
      'warning_ratio' => 0.8,
      'networks' => { 'visa' => { 'count_bps' => 6_000, 'amount_bps' => 5_000 },
                      'master' => { 'count_bps' => 2_000, 'amount_bps' => 2_000 } }
    )

    visa_a = build_card_payment(order: build_order(email: "a-#{suffix}@example.com", country: us),
                                brand: 'visa', amount: 100)
    build_card_payment(order: build_order(email: "b-#{suffix}@example.com", country: us),
                       brand: 'visa', amount: 100)
    build_card_payment(order: build_order(email: "c-#{suffix}@example.com", country: de),
                       brand: 'visa', amount: 100)
    # 历史行别名：mastercard → master
    master_payment = build_card_payment(order: build_order(email: "d-#{suffix}@example.com", country: us),
                                        brand: 'master', amount: 50, legacy_brand: 'mastercard')
    # 历史行别名：amex → american_express
    build_card_payment(order: build_order(email: "e-#{suffix}@example.com", country: us),
                       brand: 'american_express', amount: 20, legacy_brand: 'amex')
    check_payment = build_check_payment(order: build_order(email: "f-#{suffix}@example.com", country: us),
                                        amount: 40)
    eur_order = build_order(email: "g-#{suffix}@example.com", country: us, currency: 'EUR', at: 6.days.ago)
    eur_payment = build_card_payment(order: eur_order, brand: 'visa', amount: 100, at: 6.days.ago)

    # 窗口外：不计入任何比率
    old_payment = build_card_payment(order: build_order(email: "h-#{suffix}@example.com", country: us,
                                                        at: 90.days.ago),
                                     brand: 'visa', amount: 100, at: 90.days.ago)

    build_dispute(payment: visa_a, amount: 100)
    build_dispute(payment: master_payment, amount: 50)
    build_dispute(payment: check_payment, amount: 40)
    build_dispute(payment: eur_payment, amount: 100, currency: 'EUR')
    build_dispute(payment: old_payment, amount: 100, at: 80.days.ago)

    report = described_class.call(store: store, window_days: 30).value

    expect(report[:degraded]).to eq([])
    expect(report[:scope][:currency]).to eq('USD')

    # 汇总：7 笔窗口内支付（含 1 笔 EUR、1 笔非卡）；4 笔窗口内争议（含 1 笔 EUR 争议）
    expect(report[:totals][:transactions_count]).to eq(7)
    expect(report[:totals][:disputes_count]).to eq(4)
    expect(report[:totals][:transactions_amount].to_s).to eq('410.0')
    expect(report[:totals][:disputes_amount].to_s).to eq('190.0')
    expect(report[:totals][:excluded_other_currency_payments]).to eq(1)
    expect(report[:totals][:excluded_other_currency_disputes]).to eq(1)
    expect(report[:totals][:unknown_network_disputes]).to eq(1)
    expect(report[:totals][:count_ratio]).to eq(BigDecimal('0.571429'))

    by_network = report[:networks].index_by { |row| row[:network] }
    expect(by_network.keys).to contain_exactly('visa', 'master', 'american_express', 'unknown')

    # visa 4/2（EUR 争议同样归因 visa，只是不进金额比）→ 50% ≥ 80%×60% → approaching（只触发笔数）
    visa = by_network['visa']
    expect(visa[:transactions_count]).to eq(4)
    expect(visa[:disputes_count]).to eq(2)
    expect(visa[:count_ratio]).to eq(BigDecimal('0.5'))
    expect(visa[:count_ratio_bps]).to eq(5_000)
    expect(visa[:status]).to eq('approaching')
    expect(visa[:triggered_metrics]).to eq(['count'])
    expect(visa[:count_usage_percent]).to eq(83.3)
    # 金额比只算默认币种：3 笔 USD 交易 300 / 1 笔 USD 争议 100 → 33.3% < 80%×50% → 仅笔数触发
    expect(visa[:transactions_amount].to_s).to eq('300.0')
    expect(visa[:amount_ratio_bps]).to eq(3_333)
    expect(visa[:amount_usage_percent]).to eq(66.7)

    # 别名归一后的 master：1/1 → breached（笔数 + 金额双触发）
    master = by_network['master']
    expect(master[:status]).to eq('breached')
    expect(master[:triggered_metrics]).to contain_exactly('count', 'amount')

    # american_express（历史 amex 别名归一）：有交易但无阈值 → unconfigured
    expect(by_network['american_express'][:transactions_count]).to eq(1)
    expect(by_network['american_express'][:status]).to eq('unconfigured')
    expect(by_network['american_express'][:count_threshold_bps]).to be_nil

    # 非卡支付 → unknown；不可判定 → 不参与任何组织的阈值判定
    expect(by_network['unknown'][:disputes_count]).to eq(1)
    expect(by_network['unknown'][:status]).to eq('unconfigured')

    expect(report[:notes]).to include('bin_unavailable', 'other_currency_excluded')
  end

  # AC-002（分母为 0 → 比率为 nil，不用 0 伪装）
  it 'returns nil ratios when the window has no denominator' do
    configure_thresholds('networks' => { 'visa' => { 'count_bps' => 100 } })
    payment = build_card_payment(order: build_order(email: "nod-#{suffix}@example.com", country: us,
                                                    at: 90.days.ago),
                                 brand: 'visa', amount: 100, at: 90.days.ago)
    build_dispute(payment: payment, amount: 100, at: 90.days.ago)

    report = described_class.call(store: store, window_days: 30).value

    expect(report[:totals][:transactions_count]).to eq(0)
    expect(report[:totals][:count_ratio]).to be_nil
    expect(report[:totals][:amount_ratio]).to be_nil
    expect(report[:networks]).to eq([])
    expect(report[:notes]).to include('unconfigured_networks').or be_present
  end

  # AC-003（争议引用的支付在窗口外时仍按该支付的卡组织归因，但不进入交易分母）
  it 'attributes a dispute to the network of an out-of-window payment without counting it as a transaction' do
    configure_thresholds('networks' => { 'visa' => { 'count_bps' => 100 } })
    old_payment = build_card_payment(order: build_order(email: "attrib-#{suffix}@example.com", country: us,
                                                        at: 90.days.ago),
                                     brand: 'visa', amount: 100, at: 90.days.ago)
    build_dispute(payment: old_payment, amount: 100)

    report = described_class.call(store: store, window_days: 30).value
    visa = report[:networks].find { |row| row[:network] == 'visa' }

    expect(visa[:disputes_count]).to eq(1)
    expect(visa[:transactions_count]).to eq(0)
    expect(visa[:count_ratio]).to be_nil
    expect(visa[:status]).to eq('ok')
  end

  # AC-010（维度可选 + 未知桶保留 + 桶合计 == 汇总）
  it 'drills down by the requested dimension with bucket sums equal to the totals' do
    configure_thresholds('networks' => { 'visa' => { 'count_bps' => 4_000 } })
    visa_payment = build_card_payment(order: build_order(email: "bd-us-#{suffix}@example.com", country: us),
                                      brand: 'visa', amount: 100)
    build_card_payment(order: build_order(email: "bd-de-#{suffix}@example.com", country: de),
                       brand: 'visa', amount: 100)
    check_payment = build_check_payment(order: build_order(email: "bd-check-#{suffix}@example.com", country: us),
                                        amount: 40)
    build_dispute(payment: visa_payment, amount: 100)
    build_dispute(payment: check_payment, amount: 40)

    described_class::DIMENSIONS.each do |dimension|
      report = described_class.call(store: store, window_days: 30, dimension: dimension).value
      rows = report[:breakdown][:rows]

      expect(report[:breakdown][:dimension]).to eq(dimension)
      expect(rows.sum { |row| row[:transactions_count] }).to eq(report[:totals][:transactions_count])
      expect(rows.sum { |row| row[:disputes_count] }).to eq(report[:totals][:disputes_count])
      expect(rows.sum { |row| row[:dispute_share].to_d }).to be_within(0.0001).of(1)
    end

    country = described_class.call(store: store, window_days: 30, dimension: 'country').value[:breakdown][:rows]
    expect(country.map { |row| row[:key] }).to contain_exactly('US', 'DE')
    expect(country.find { |row| row[:key] == 'DE' }[:disputes_count]).to eq(0)

    entry = described_class.call(store: store, window_days: 30, dimension: 'entry').value[:breakdown][:rows]
    # 入口口径来自 `PaymentMethod#effective_payment_option`（未选项化 → 隐式默认入口 kind）
    expect(entry.map { |row| row[:key] }).to contain_exactly('bogus', 'check')

    fingerprint = described_class.call(store: store, window_days: 30,
                                       dimension: 'card_fingerprint').value[:breakdown][:rows]
    expect(fingerprint.map { |row| row[:key] }).to include('unknown')

    segment = described_class.call(store: store, window_days: 30, dimension: 'segment').value[:breakdown][:rows]
    expect(segment.map { |row| row[:key] }).to contain_exactly('new')
  end

  # AC-010（客群维度：窗口前已下单的邮箱 = 回头客）
  it 'separates returning customers in the segment dimension' do
    build_card_payment(order: build_order(email: "returning-#{suffix}@example.com", country: us,
                                          at: 40.days.ago),
                       brand: 'visa', amount: 50, at: 40.days.ago)
    build_card_payment(order: build_order(email: "returning-#{suffix}@example.com", country: us, amount: 80),
                       brand: 'visa', amount: 80)

    rows = described_class.call(store: store, window_days: 30, dimension: 'segment').value[:breakdown][:rows]

    expect(rows.map { |row| row[:key] }).to contain_exactly('returning')
    expect(rows.first[:transactions_count]).to eq(1)
  end

  # AC-012（network 过滤只影响汇总卡片，不影响下钻口径）
  it 'filters the network cards without changing the breakdown caliber' do
    configure_thresholds('networks' => { 'visa' => { 'count_bps' => 4_000 } })
    visa = build_card_payment(order: build_order(email: "filter-a-#{suffix}@example.com", country: us),
                              brand: 'visa', amount: 100)
    master = build_card_payment(order: build_order(email: "filter-b-#{suffix}@example.com", country: us),
                                brand: 'master', amount: 100)
    build_dispute(payment: visa, amount: 100)
    build_dispute(payment: master, amount: 100)

    all_networks = described_class.call(store: store, window_days: 30).value[:networks].map { |row| row[:network] }
    filtered = described_class.call(store: store, window_days: 30, network: 'visa').value

    expect(all_networks).to contain_exactly('visa', 'master')
    expect(filtered[:networks].map { |row| row[:network] }).to eq(['visa'])
    expect(filtered[:totals][:transactions_count]).to eq(2)
    expect(filtered[:breakdown][:rows].size).to eq(2)
  end

  # AC-014（只读：报表前后不改动任何金额/状态；查询数恒定）
  it 'is read-only and keeps the query count flat as rows grow' do
    configure_thresholds('networks' => { 'visa' => { 'count_bps' => 4_000 } })
    first_payment = build_card_payment(order: build_order(email: "flat-#{suffix}@example.com", country: us),
                                       brand: 'visa', amount: 10)
    build_dispute(payment: first_payment, amount: 10)

    small_queries = count_sql_queries { described_class.call(store: store, window_days: 30) }

    12.times do |index|
      payment = build_card_payment(
        order: build_order(email: "flat-#{suffix}@example.com", country: us),
        brand: 'visa', amount: 10, at: index.days.ago
      )
      build_dispute(payment: payment, amount: 10, at: index.days.ago)
    end

    # 夹具建完后再取快照：报表本身不得变动任何金额/状态
    before = money_snapshot
    large_queries = count_sql_queries { described_class.call(store: store, window_days: 30) }
    report = described_class.call(store: store, window_days: 30).value
    after = money_snapshot

    expect(report[:totals][:transactions_count]).to eq(13)
    expect(report[:totals][:disputes_count]).to eq(13)
    expect(large_queries).to be <= small_queries + 3
    expect(after).to eq(before)
  end

  # AC-009（降级：store 缺失 → 字段齐全的降级信封，绝不 500）
  it 'returns a degraded envelope for a missing store' do
    report = described_class.call(store: nil).value

    expect(report[:degraded]).to eq(['store_missing'])
    expect(report[:totals][:transactions_count]).to eq(0)
    expect(report[:totals][:count_ratio]).to be_nil
    expect(report[:networks]).to eq([])
    expect(report[:policy][:window_days]).to be_nil
  end

  # AC-005（窗口参数覆盖店铺策略）
  it 'honors an explicit window_days override instead of the store policy' do
    configure_thresholds('window_days' => 7, 'networks' => { 'visa' => { 'count_bps' => 100 } })
    payment = build_card_payment(order: build_order(email: "win-#{suffix}@example.com", country: us,
                                                    at: 20.days.ago),
                                 brand: 'visa', amount: 100, at: 20.days.ago)
    build_dispute(payment: payment, amount: 100, at: 20.days.ago)

    expect(described_class.call(store: store).value[:scope][:window_days]).to eq(7)
    expect(described_class.call(store: store).value[:totals][:disputes_count]).to eq(0)
    expect(described_class.call(store: store, window_days: 30).value[:totals][:disputes_count]).to eq(1)
  end

  def money_snapshot
    {
      payments: PallasTrade::Payment.count,
      payment_sum: PallasTrade::Payment.sum(:amount).to_d.to_s,
      disputes: PallasTrade::Dispute.count,
      dispute_state_counts: PallasTrade::Dispute.group(:state).count,
      ledger: PallasTrade::FinancialLedgerEntry.count,
      inventory: PallasTrade::StockItem.sum(:count_on_hand).to_i,
      orders_total: PallasTrade::Order.sum(:total).to_d.to_s
    }
  end
end
