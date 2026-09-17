# frozen_string_literal: true

# PRD-20260917-payments-d3-risk-dashboard-threshold-alerts AC-004 / AC-005 / AC-006 / AC-007
# 5 指标口径（可复算）+ 不可判定不猜 + 跨店隔离 + 查询数不随行数增长
require 'rails_helper'

RSpec.describe PallasTrade::Risk::DashboardReport, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, stores: [store], active: true) }

  def submitted_order(target_store: store, submitted_at: Time.current, price: 200)
    order = create(:order_with_line_items, store: target_store, shipment_cost: 0,
                                          line_items_count: 1, line_items_price: price)
    order.update_columns(state: 'pending', status: 'placed', submitted_at: submitted_at, completed_at: nil)
    order.reload
  end

  def flagged_assessment(order, target_store: store, decision: 'review', evaluated_at: Time.current)
    PallasTrade::PaymentRiskAssessment.create!(order: order, store: target_store, decision: decision,
                                               evaluated_at: evaluated_at)
  end

  def payment_session(order, hint: nil, created_at: Time.current)
    session = create(:bogus_payment_session, order: order, payment_method: payment_method, status: 'pending',
                                            amount: order.total, currency: order.currency.to_s)
    data = { 'idempotency_key' => "k-#{SecureRandom.hex(4)}" }
    data['three_d_secure_hint'] = hint if hint
    session.update_columns(external_data: data, created_at: created_at, updated_at: created_at)
    session.reload
  end

  def manual_review_transaction(target_store: store, currency: 'USD', amount: 10, reviewed_at: nil)
    tx = PallasTrade::CommerceTransaction.create!(store: target_store, purpose: 'purchase',
                                                  currency: currency, amount: amount)
    tx.start_payment!
    tx.confirm_payment!
    tx.mark_recovery_required!
    tx.manual_review!
    tx.update_columns(manual_review_at: reviewed_at) if reviewed_at.present?
    tx.reload
  end

  def metric(report, key)
    report.value[:metrics].detect { |row| row[:key] == key.to_s }
  end

  def count_queries
    count = 0
    callback = ->(*) { count += 1 }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { yield }
    count
  end

  describe 'AC-004 5 指标口径可复算' do
    it 'computes risky_orders as flagged order ratio in bps' do
      orders = Array.new(4) { submitted_order }
      flagged_assessment(orders[0])
      flagged_assessment(orders[1])

      row = metric(described_class.call(store: store), :risky_orders)

      expect(row[:available]).to be(true)
      expect(row[:value]).to eq(5_000)
      expect(row[:unit]).to eq('bps')
      expect(row[:detail]).to eq(flagged_orders: 2, submitted_orders: 4)
    end

    it 'excludes allow-only assessments from the numerator' do
      order = submitted_order
      flagged_assessment(order, decision: 'allow')

      row = metric(described_class.call(store: store), :risky_orders)

      expect(row[:value]).to eq(0)
      expect(row[:detail][:flagged_orders]).to eq(0)
    end

    it 'computes three_ds_challenge_rate from the session hint trail' do
      order = submitted_order
      payment_session(order, hint: 'three_d_secure')
      payment_session(order, hint: 'none')
      payment_session(order)
      payment_session(order)

      row = metric(described_class.call(store: store), :three_ds_challenge_rate)

      expect(row[:value]).to eq(2_500)
      expect(row[:detail]).to eq(applied_count: 1, required_count: 2, total_sessions: 4)
    end

    it 'computes refund_rate as refunded amount over captured amount' do
      order = submitted_order
      payment = create(:payment, order: order, payment_method: payment_method, amount: 200, state: 'completed')
      create(:refund, payment: payment, amount: 50)

      row = metric(described_class.call(store: store), :refund_rate)

      expect(row[:value]).to eq(2_500)
      expect(row[:detail][:refund_amount]).to eq('50.0')
      expect(row[:detail][:captured_amount]).to eq('200.0')
    end

    it 'computes review_queue_duration (oldest pending + handled p90) from D2 trail' do
      pending = manual_review_transaction(reviewed_at: 90.minutes.ago)
      handled = manual_review_transaction(reviewed_at: 30.minutes.ago)
      PallasTrade::Audit.record(action: 'transaction_review_captured', actor: 'system', resource: handled)

      row = metric(described_class.call(store: store), :review_queue_duration)

      expect(row[:available]).to be(true)
      expect(row[:value]).to eq(90)
      # 两单都仍在 manual_review（未真正裁决）→ 待办计数 2；仅其中一单有裁决审计 → 已处理样本 1
      expect(row[:detail][:pending_count]).to eq(2)
      expect(row[:detail][:handled_samples]).to eq(1)
      expect(row[:detail][:p90_handled_minutes]).to be_between(28, 32)
      expect(pending.reload.state).to eq('manual_review')
    end

    it 'delegates dispute_rate to the D14c authority instead of recomputing' do
      ratio = 0.0123
      allow_any_instance_of(described_class).to receive(:rate_report).and_return(
        double(success?: true, value: { totals: { count_ratio: ratio, disputes_count: 3, transactions_count: 500 },
                                        degraded: [] })
      )

      report = described_class.call(store: store)
      row = metric(report, :dispute_rate)

      expect(row[:value]).to eq(123)
      expect(row[:detail][:source]).to eq('Disputes::RateReport')
      expect(row[:detail][:disputes_count]).to eq(3)
      expect(row[:sources]).to eq(%w[disputes payments])
    end
  end

  describe 'AC-005 不可判定不猜（返回 nil + 结构化 reason）' do
    it 'marks ratios without a denominator as unavailable' do
      report = described_class.call(store: store)

      %i[risky_orders three_ds_challenge_rate refund_rate].each do |key|
        row = metric(report, key)
        expect(row[:value]).to be_nil
        expect(row[:available]).to be(false)
        expect(row[:reason]).to eq('no_denominator')
      end
    end

    it 'marks a degraded dispute report as unavailable with the reason passed through' do
      allow_any_instance_of(described_class).to receive(:rate_report).and_return(
        double(success?: true, value: { degraded: ['report_unavailable:PG::Error'] })
      )

      row = metric(described_class.call(store: store), :dispute_rate)

      expect(row[:available]).to be(false)
      expect(row[:reason]).to include('report_unavailable')
    end

    it 'marks a failed dispute report as unavailable without raising' do
      allow_any_instance_of(described_class).to receive(:rate_report).and_return(
        double(success?: false, value: nil, error: 'boom')
      )

      report = described_class.call(store: store)
      row = metric(report, :dispute_rate)

      expect(report).to be_success
      expect(row[:reason]).to eq('report_unavailable')
    end

    it 'degrades the whole envelope for a nil store' do
      report = described_class.call(store: nil)

      expect(report.value[:degraded]).to eq(['store_missing'])
      expect(report.value[:metrics].size).to eq(5)
    end
  end

  describe 'AC-006 跨店隔离' do
    it 'does not count another store rows' do
      other_store = create(:store, code: "d3_other_#{SecureRandom.hex(4)}", default: false)
      other_order = submitted_order(target_store: other_store)
      flagged_assessment(other_order, target_store: other_store, decision: 'block')
      other_tx = manual_review_transaction(target_store: other_store, currency: other_store.default_currency.to_s)
      other_tx.update_columns(manual_review_at: 10.hours.ago)

      report = described_class.call(store: store)

      expect(metric(report, :risky_orders)[:value]).to be_nil
      expect(metric(report, :review_queue_duration)[:value]).to eq(0)
      expect(metric(report, :review_queue_duration)[:detail][:pending_count]).to eq(0)
    end

    it 'keeps another store handled audits out of this store handled samples' do
      # 审计表无 store_id：别店的 `transaction_review_*` 不得进入本店 P90（否则数据越多越歪）
      other_store = create(:store, code: "d3_other_audit_#{SecureRandom.hex(4)}", default: false)
      other_tx = manual_review_transaction(target_store: other_store,
                                           currency: other_store.default_currency.to_s)
      other_tx.update_columns(manual_review_at: 9.hours.ago)
      PallasTrade::Audit.record(action: 'transaction_review_captured', actor: 'system', resource: other_tx)

      row = metric(described_class.call(store: store), :review_queue_duration)

      expect(row[:detail][:handled_samples]).to eq(0)
      expect(row[:detail][:p90_handled_minutes]).to be_nil
      expect(row[:detail][:pending_count]).to eq(0)
    end

    it 'keeps the subject store isolated when both stores have data' do
      mine = submitted_order
      flagged_assessment(mine)
      other_store = create(:store, code: "d3_other_#{SecureRandom.hex(4)}", default: false)
      3.times do
        other = submitted_order(target_store: other_store)
        flagged_assessment(other, target_store: other_store)
      end

      row = metric(described_class.call(store: store), :risky_orders)

      expect(row[:detail]).to eq(flagged_orders: 1, submitted_orders: 1)
      expect(row[:value]).to eq(10_000)
    end
  end

  describe 'AC-007 查询数不随行数增长' do
    it 'keeps the query count flat when the row count grows 12x' do
      # 两份数据集必须**走到同一组代码分支**（含「已处理」样本）——否则比较的是两种查询形状，
      # 本地空库绿、CI 有种子数据红（2026-09-17 CI 实测：12 vs 13）。
      order = submitted_order
      payment_session(order, hint: 'three_d_secure')
      flagged_assessment(order)
      reviewed = manual_review_transaction(reviewed_at: 10.minutes.ago)
      PallasTrade::Audit.record(action: 'transaction_review_captured', actor: 'system', resource: reviewed)

      small = count_queries { described_class.call(store: store) }

      12.times do
        extra = submitted_order
        payment_session(extra)
        flagged_assessment(extra, decision: 'allow')
        handled = manual_review_transaction(reviewed_at: 5.minutes.ago)
        PallasTrade::Audit.record(action: 'transaction_review_released', actor: 'system', resource: handled)
      end

      large = count_queries { described_class.call(store: store) }

      expect(large).to eq(small)
    end

    it 'keeps the query count flat when the store has no rows at all' do
      # 空库 vs 有数据 —— 正是本地绿 / CI 红的差异场景（查询形状不得依赖数据是否存在）
      empty_store = create(:store, code: "d3_empty_#{SecureRandom.hex(4)}", default: false)
      order = submitted_order
      payment_session(order, hint: 'three_d_secure')
      flagged_assessment(order)
      reviewed = manual_review_transaction(reviewed_at: 10.minutes.ago)
      PallasTrade::Audit.record(action: 'transaction_review_captured', actor: 'system', resource: reviewed)

      empty_count = count_queries { described_class.call(store: empty_store) }
      populated = count_queries { described_class.call(store: store) }

      expect(empty_count).to eq(populated)
    end
  end
end
