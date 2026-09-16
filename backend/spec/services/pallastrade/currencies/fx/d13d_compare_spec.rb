# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13d-fx-snapshot（D13 切片4）
#   AC-7 ← FR-4：结算汇率对比（报文显式优先 / 推导 / 不可判定）+ bips 与容差判定
#   AC-8 ← FR-5：差异入队（kind=fx）+ 恢复一致自动销案 + 人工判定不被覆盖 + 事件
#   AC-9 ← FR-4：跨店隔离 + 期间口径
#   AC-10 ← FR-11：零资金副作用 + 查询数不随行数增长
RSpec.describe PallasTrade::Currencies::Fx::Compare do
  let!(:store) do
    create(:store, code: "d13d_cmp_#{SecureRandom.hex(4)}", default_currency: 'USD',
                   supported_currencies: 'USD,CNY,EUR')
  end
  let!(:other_store) do
    create(:store, code: "d13d_cmp_other_#{SecureRandom.hex(4)}", default_currency: 'USD',
                   supported_currencies: 'USD,CNY')
  end
  let!(:provider) do
    create(:check_payment_method, store: store, active: true, display_on: 'both',
                                  name: "d13d-cmp-pm-#{SecureRandom.hex(3)}")
  end
  let!(:other_provider) do
    create(:check_payment_method, store: other_store, active: true, display_on: 'both',
                                  name: "d13d-cmp-other-pm-#{SecureRandom.hex(3)}")
  end

  before do
    create(:currency_rate, store: store, base_currency: 'USD', quote_currency: 'CNY', rate: BigDecimal('7.1'),
                           source: 'manual')
    create(:currency_rate, store: other_store, base_currency: 'USD', quote_currency: 'CNY',
                           rate: BigDecimal('6.0'), source: 'manual')
    allow(PallasTrade::Events).to receive(:enabled?).and_return(true)
    allow(PallasTrade::Events).to receive(:publish)
  end

  def paid_order(amount, target_store: store, payment_provider: provider, paid_at: Time.current)
    order = create(:order_with_line_items, store: target_store, currency: 'CNY', line_items_count: 1,
                                           line_items_price: amount, shipment_cost: 0)
    payment = create(:payment, order: order, payment_method: payment_provider, amount: amount, state: 'completed',
                               source: nil, skip_source_requirement: true)
    payment.update_columns(created_at: paid_at, updated_at: paid_at)
    [order, payment.reload]
  end

  def lock_snapshot(order, at: Time.current)
    PallasTrade::Currencies::Fx::Lock.call(order: order, at: at).value[:snapshot]
  end

  def settle(payment, gross:, currency: 'USD', fx_rate: nil)
    payout = PallasTrade::Payout.create!(store: payment.order.store, provider: 'stripe',
                                         reference: "po_d13d_#{SecureRandom.hex(4)}", currency: currency,
                                         status: 'settled', settled_at: Time.current, imported_at: Time.current,
                                         gross_total: gross, fee_total: 0, net_total: gross)
    PallasTrade::PayoutLine.create!(
      payout: payout, payment: payment, kind: 'charge', provider_reference: "ch_#{SecureRandom.hex(4)}",
      currency: currency, gross_amount: gross, fee_amount: 0, net_amount: gross, match_status: 'matched',
      raw: fx_rate ? { 'fx_rate' => fx_rate.to_s } : {}
    )
  end

  def compare(**opts)
    described_class.call(**{ store: store }.merge(opts)).value
  end

  describe 'settlement rate sources' do
    it 'prefers the provider-reported rate from the settlement line' do
      order, payment = paid_order(1000)
      snapshot = lock_snapshot(order)
      settle(payment, gross: 7400, fx_rate: '7.42')

      result = compare

      row = snapshot.reload
      expect(row.variance_status).to eq('mismatch')
      expect(row.settlement_source).to eq('provider_reported')
      expect(row.settlement_rate.to_d).to eq(BigDecimal('7.42'))
      expect(row.variance_bips).to eq(451) # (7.42-7.1)/7.1*10000 ≈ 450.7
      expect(result[:mismatched]).to eq(1)
      expect(result[:cases][:opened].size).to eq(1)
    end

    it 'derives the rate from the settled amount when the report has no rate' do
      order, payment = paid_order(1000)
      snapshot = lock_snapshot(order)
      settle(payment, gross: 7100)

      result = compare

      row = snapshot.reload
      expect(row.settlement_source).to eq('implied')
      expect(row.settlement_rate.to_d).to eq(BigDecimal('7.1'))
      expect(row.variance_bips).to eq(0)
      expect(row.variance_status).to eq('matched')
      expect(result[:matched]).to eq(1)
      expect(result[:cases][:opened]).to be_empty
    end

    it 'flags a mismatch beyond tolerance and queues exactly one fx case' do
      order, payment = paid_order(1000)
      snapshot = lock_snapshot(order)
      settle(payment, gross: 7500)

      expect { compare }.to change { PallasTrade::ReconciliationCase.where(kind: 'fx').count }.by(1)

      kase = PallasTrade::ReconciliationCase.where(kind: 'fx').last
      expect(kase.difference_type).to eq('fx_rate_mismatch')
      expect(kase.store_id).to eq(store.id)
      expect(kase.currency).to eq('USD')
      expect(kase.summary['variance_bips']).to eq(563)
      expect(snapshot.reload.reconciliation_case_id).to eq(kase.id)
      expect(PallasTrade::Events).to have_received(:publish).with('fx.settlement.mismatch', hash_including(:case_id))
    end

    it 'stays pending (no case) when nothing has settled yet' do
      order, = paid_order(1000)
      snapshot = lock_snapshot(order)

      result = compare

      row = snapshot.reload
      expect(row.variance_status).to eq('pending')
      expect(row.signal_list).to include('settlement_pending')
      expect(result[:pending]).to eq(1)
      expect(PallasTrade::ReconciliationCase.where(kind: 'fx').count).to eq(0)
    end

    it 'is undetermined when the settled currency is not the snapshot base currency' do
      order, payment = paid_order(1000)
      snapshot = lock_snapshot(order)
      settle(payment, gross: 900, currency: 'EUR')

      result = compare

      row = snapshot.reload
      expect(row.variance_status).to eq('undetermined')
      expect(row.signal_list).to include('currency_pair_mismatch')
      expect(result[:undetermined]).to eq(1)
      expect(row.settlement_rate).to be_nil
    end
  end

  describe 'tolerance and auto-close' do
    it 'honours a store tolerance override and a per-call override' do
      store.update!(private_metadata: { 'fx_policy' => { 'variance_tolerance_bips' => 1000 } })
      order, payment = paid_order(1000)
      snapshot = lock_snapshot(order)
      settle(payment, gross: 7500)

      expect(compare[:matched]).to eq(1)

      strict = compare(snapshots: [snapshot.reload], tolerance_bips: 10)
      expect(strict[:mismatched]).to eq(1)
    end

    it 'closes the open case automatically once the settlement is corrected' do
      order, payment = paid_order(1000)
      snapshot = lock_snapshot(order)
      line = settle(payment, gross: 7500)

      compare
      kase = PallasTrade::ReconciliationCase.where(kind: 'fx').last
      expect(kase.status).to eq('open')

      # 结算单修正（重新导入）→ 结算行金额回到一致；再比对应翻回 matched 并自动销案
      line.update_columns(gross_amount: 7100, updated_at: 1.minute.from_now)

      result = compare

      expect(snapshot.reload.variance_status).to eq('matched')
      expect(kase.reload.status).to eq('fixed')
      expect(kase.resolution_source).to eq('auto')
      expect(result[:cases][:closed]).to include(kase.id)
    end

    it 'never overrides a human decision' do
      order, payment = paid_order(1000)
      lock_snapshot(order)
      line = settle(payment, gross: 7500)
      compare
      kase = PallasTrade::ReconciliationCase.where(kind: 'fx').last
      kase.close!(status: 'dismissed', source: 'human', note: 'provider 已确认')

      line.update_columns(gross_amount: 7100, updated_at: 1.minute.from_now)
      compare

      expect(kase.reload.status).to eq('dismissed')
      expect(kase.resolution_source).to eq('human')
    end

    it 'does not queue a second case for the same snapshot' do
      order, payment = paid_order(1000)
      snapshot = lock_snapshot(order)
      settle(payment, gross: 7500)

      expect { compare }.to change { PallasTrade::ReconciliationCase.where(kind: 'fx').count }.by(1)
      expect { compare(snapshots: [snapshot.reload]) }
        .not_to change { PallasTrade::ReconciliationCase.where(kind: 'fx').count }
      expect(PallasTrade::ReconciliationCase.where(kind: 'fx').last.occurrences).to eq(2)
    end
  end

  describe 'scope of the fact set (AC-9)' do
    it 'ignores other stores' do
      foreign_order, foreign_payment = paid_order(1000, target_store: other_store,
                                                       payment_provider: other_provider)
      foreign_snapshot = lock_snapshot(foreign_order)
      settle(foreign_payment, gross: 6000)

      result = compare

      expect(result[:scanned]).to eq(0)
      expect(foreign_snapshot.reload.variance_status).to eq('pending')
    end

    it 'limits the scan to the given lock period (left-closed, right-open)' do
      in_period, payment = paid_order(1000)
      in_snapshot = lock_snapshot(in_period, at: Time.zone.parse('2026-09-10 10:00:00'))
      settle(payment, gross: 7100)
      out_of_period, = paid_order(1000)
      out_snapshot = lock_snapshot(out_of_period, at: Time.zone.parse('2026-08-01 10:00:00'))

      result = compare(from: Time.zone.parse('2026-09-01'), to: Time.zone.parse('2026-10-01'))

      expect(result[:scanned]).to eq(1)
      expect(in_snapshot.reload.variance_status).to eq('matched')
      expect(out_snapshot.reload.variance_status).to eq('pending')
    end
  end

  describe 'purity and performance (AC-10)' do
    it 'does not touch money facts' do
      order, payment = paid_order(1000)
      lock_snapshot(order)
      settle(payment, gross: 7500)
      before = money_snapshot

      compare

      expect(money_snapshot).to eq(before)
    end

    # 只断言**读路径**不随行数增长：对比结果的持久化（每行 1 次 UPDATE）与案例 upsert
    # （每行 1 次 SELECT，与 `Payouts::SyncCases` 同范式）是**按行**设计，不计入该断言。
    it 'keeps the read query count flat as snapshots grow' do
      order, payment = paid_order(1000)
      lock_snapshot(order)
      settle(payment, gross: 7100)
      small = count_select_queries { compare(sync_cases: false) }

      5.times do
        o, p = paid_order(1500)
        lock_snapshot(o)
        settle(p, gross: 10_650)
      end
      large = count_select_queries { compare(from: 1.day.ago, to: Time.current, sync_cases: false) }

      expect(large).to be <= small + 2
    end
  end

  def count_select_queries
    queries = []
    counter = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      queries << sql if sql.start_with?('SELECT') && payload[:name].to_s != 'SCHEMA' && !payload[:cached]
    end

    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { yield }
    queries.size
  end

  def money_snapshot
    {
      payments: PallasTrade::Payment.count,
      payments_sum: PallasTrade::Payment.sum(:amount).to_d.to_s,
      refunds: PallasTrade::Refund.count,
      ledger: PallasTrade::FinancialLedgerEntry.count,
      inventory: PallasTrade::StockItem.sum(:count_on_hand).to_i,
      snapshots: PallasTrade::FxSnapshot.count
    }
  end
end
