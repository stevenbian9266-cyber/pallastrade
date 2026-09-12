# frozen_string_literal: true

require 'rails_helper'

# PRD-20260912-payments-dsp-p7-6-dispute-recovery
# AC-P76-01..14 —— 收敛动作：单调收敛 / 幂等补记 / 人工通道 / 降级零写 / dry-run / 审计 / 铁律负向断言。
RSpec.describe PallasTrade::Disputes::Recover, type: :service do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }
  let(:order) do
    create(:order_with_line_items, store: store, line_items_price: 50, shipment_cost: 0).tap do |o|
      o.update_columns(state: 'complete', status: 'complete', completed_at: Time.current)
    end
  end
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: order.total, state: 'completed',
                     response_code: 'pi_p76_anchor', source: nil, skip_source_requirement: true)
  end
  let(:txn) do
    PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: order.total)
  end
  let(:withdrawn_at) { Time.current.change(usec: 0) - 3.hours }

  def make_dispute(**overrides)
    options = { state: 'opened', amount: 12.34, funds_withdrawn_at: nil, funds_reinstated_at: nil,
                attention_reason: nil, provider_status: nil, link_payment: true, link_transaction: true,
                reference: nil }.merge(overrides)
    PallasTrade::Dispute.create!(
      provider: 'stripe',
      provider_dispute_reference: options[:reference] || "dp_p76_#{SecureRandom.hex(4)}",
      state: options[:state],
      amount: options[:amount],
      currency: 'usd',
      private_metadata: options[:provider_status] ? { 'provider_status' => options[:provider_status] } : {},
      funds_withdrawn_at: options[:funds_withdrawn_at],
      funds_reinstated_at: options[:funds_reinstated_at],
      attention_reason: options[:attention_reason],
      commerce_transaction: options[:link_transaction] ? txn : nil,
      payment: options[:link_payment] ? payment : nil,
      order: options[:link_payment] ? order : nil
    )
  end

  # 类级打桩：服务内部可能 `reload`（清空关联缓存）导致实例级 stub 失效 → 必须按类打
  # （能力判定为 `method(:fetch_dispute_details).owner != PaymentMethod`，类级 stub 会装到 singleton 上）
  def stub_provider(status:, amount: BigDecimal('12.34'), currency: 'usd')
    allow_any_instance_of(payment_method.class).to receive(:fetch_dispute_details).and_return(
      { status: status, amount: amount, currency: currency, observed_at: Time.current }
    )
  end

  def recover(dispute, fetch: true, apply: true)
    result = described_class.call(dispute: dispute, fetch: fetch, apply: apply)

    expect(result).to be_success
    result.value
  end

  # 铁律观测面：不属于争议域的表在收敛前后必须逐字节不变
  def money_counts
    {
      payments: PallasTrade::Payment.count,
      refunds: PallasTrade::Refund.count,
      orders: PallasTrade::Order.count,
      transactions: PallasTrade::CommerceTransaction.count,
      shipments: PallasTrade::Shipment.count,
      inventory_units: PallasTrade::InventoryUnit.count,
      stock_reservations: PallasTrade::StockReservation.count,
      disputes: PallasTrade::Dispute.count,
      ledger_entries: PallasTrade::FinancialLedgerEntry.count
    }
  end

  describe '生命周期收敛（FR-P76-03）' do
    it 'AC-P76-01 漏终态事件：provider lost / 本地 opened → 单调收敛并写 resolved_at' do
      dispute = make_dispute(state: 'opened')
      stub_provider(status: 'lost')

      value = recover(dispute)

      expect(value[:decision]).to eq('lifecycle_repaired')
      expect(value[:state_before]).to eq('opened')
      expect(value[:state_after]).to eq('lost')
      expect(value[:fact][:resolution]).to eq('stale_local')
      expect(value[:actions]).to include(
        a_hash_including('type' => 'lifecycle_repair', 'from' => 'opened', 'to' => 'lost', 'status' => 'applied')
      )
      expect(dispute.reload.state).to eq('lost')
      expect(dispute.resolved_at).to be_present
    end

    it 'AC-P76-02 幂等：收敛后重复执行 → noop（零写 / 零新账行 / 审计不刷新）' do
      dispute = make_dispute(state: 'opened', funds_withdrawn_at: withdrawn_at)
      stub_provider(status: 'lost')

      first = recover(dispute)
      expect(first[:decision]).to eq('lifecycle_and_journal_repaired')

      entries_after_first = PallasTrade::FinancialLedgerEntry.count
      metadata_after_first = dispute.reload.private_metadata

      second = recover(dispute.reload)

      expect(second[:decision]).to eq('noop')
      expect(second[:actions]).to eq([])
      expect(dispute.reload.state).to eq('lost')
      expect(PallasTrade::FinancialLedgerEntry.count).to eq(entries_after_first)
      expect(dispute.private_metadata).to eq(metadata_after_first)
    end

    it 'AC-P76-03 乱序事件：本地已 lost / provider 仍 needs_response → 零写（绝不倒退）' do
      dispute = make_dispute(state: 'lost')
      stub_provider(status: 'needs_response')
      attributes_before = dispute.reload.attributes

      value = recover(dispute)

      expect(value[:fact][:resolution]).to eq('stale_provider')
      expect(value[:decision]).to eq('noop')
      expect(value[:actions]).to eq([])
      expect(dispute.reload.attributes).to eq(attributes_before)
    end

    it 'AC-P76-13 人工态：provider 已到终态 → 收敛；provider 未到终态 → 零写' do
      terminal = make_dispute(state: 'manual_review', reference: 'dp_p76_mr_terminal')
      stub_provider(status: 'lost')

      converged = recover(terminal)

      expect(converged[:decision]).to eq('lifecycle_repaired')
      expect(terminal.reload.state).to eq('lost')

      pending = make_dispute(state: 'manual_review', reference: 'dp_p76_mr_pending')
      allow(payment_method).to receive(:fetch_dispute_details).and_return(
        { status: 'needs_response', amount: BigDecimal('12.34'), currency: 'usd' }
      )

      idle = recover(pending)

      expect(idle[:decision]).to eq('noop')
      expect(idle[:actions]).to eq([])
      expect(pending.reload.state).to eq('manual_review')
      expect(pending.attention_reason).to be_nil
    end
  end

  describe '账行补记（FR-P76-04）' do
    it 'AC-P76-05 缺账补记：funds_withdrawn_at 有值无账行 → 补记负数（恰好一次）' do
      dispute = make_dispute(state: 'lost', funds_withdrawn_at: withdrawn_at)
      stub_provider(status: 'lost')

      value = recover(dispute)
      entry = PallasTrade::FinancialLedgerEntry.find_by(entry_type: 'DISPUTE_FUNDS_WITHDRAWN')

      expect(value[:decision]).to eq('journal_repaired')
      expect(entry).to be_present
      expect(entry.amount.to_d).to eq(BigDecimal('-12.34'))
      expect(entry.currency).to eq('usd')
      expect(entry.effective_at).to be_within(1.second).of(withdrawn_at)
      expect(entry.dispute_id).to eq(dispute.id)
      expect(value[:actions]).to include(
        a_hash_including('type' => 'journal_repair', 'entry_type' => 'DISPUTE_FUNDS_WITHDRAWN', 'status' => 'applied')
      )

      expect { recover(dispute.reload) }.not_to change(PallasTrade::FinancialLedgerEntry, :count)
    end

    it 'AC-P76-06 终态不吞资金事件：won + funds_reinstated_at 无账行 → 补记正数返还' do
      reinstated_at = Time.current.change(usec: 0) - 1.hour
      dispute = make_dispute(state: 'won', funds_reinstated_at: reinstated_at)
      stub_provider(status: 'won')

      value = recover(dispute)
      entry = PallasTrade::FinancialLedgerEntry.find_by(entry_type: 'DISPUTE_FUNDS_REINSTATED')

      expect(value[:decision]).to eq('journal_repaired')
      expect(entry).to be_present
      expect(entry.amount.to_d).to eq(BigDecimal('12.34'))
      expect(entry.effective_at).to be_within(1.second).of(reinstated_at)
    end

    it 'AC-P76-08 补记被幂等原语拒绝（无 txn）→ 零账行 + skip_reason + journal_gap 人工' do
      dispute = make_dispute(state: 'lost', funds_withdrawn_at: withdrawn_at, link_transaction: false)
      stub_provider(status: 'lost')

      value = recover(dispute)

      expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
      expect(value[:actions]).to include(
        a_hash_including('type' => 'journal_repair', 'status' => 'skipped', 'reason' => 'commerce_transaction_missing')
      )
      expect(value[:attention_reason]).to eq('journal_gap')
      expect(value[:decision]).to eq('manual_review_flagged')
      expect(dispute.reload.state).to eq('manual_review')
    end
  end

  describe '人工复核通道（FR-P76-05）' do
    it 'AC-P76-04 终局冲突：本地 won / provider lost → 零覆盖 + provider_conflict' do
      dispute = make_dispute(state: 'won')
      stub_provider(status: 'lost')

      value = recover(dispute)

      expect(value[:decision]).to eq('manual_review_flagged')
      expect(value[:attention_reason]).to eq('provider_conflict')
      expect(value[:actions]).to include(a_hash_including('type' => 'manual_review', 'status' => 'applied'))
      expect(dispute.reload.state).to eq('manual_review')
      expect(dispute.attention_reason).to eq('provider_conflict')
    end

    it 'AC-P76-07 孤儿账行：事实不可证而账行存在 → 零账本写 + journal_gap' do
      dispute = make_dispute(state: 'lost', funds_withdrawn_at: withdrawn_at)
      stub_provider(status: 'lost')
      recover(dispute)
      dispute.update_columns(amount: 0) # 金额不可证 → 事实 AMBIGUOUS（既有账行成孤儿）
      count_before = PallasTrade::FinancialLedgerEntry.count

      value = recover(dispute.reload, fetch: false)

      expect(value[:reconciliation][:classification]).to eq('orphan_entry')
      expect(value[:attention_reason]).to eq('journal_gap')
      expect(PallasTrade::FinancialLedgerEntry.count).to eq(count_before)
      expect(PallasTrade::FinancialLedgerEntry.where(entry_type: 'DISPUTE_FUNDS_WITHDRAWN').first.amount.to_d).
        to eq(BigDecimal('-12.34'))
    end

    it 'AC-P76-07 金额不符：既有账行不可改写 → 零账本写 + journal_gap' do
      dispute = make_dispute(state: 'lost', funds_withdrawn_at: withdrawn_at)
      stub_provider(status: 'lost')
      # 账行 append-only（模型层禁止 update_columns）→ 直接造一条金额不符的行模拟历史异常
      PallasTrade::FinancialLedgerEntry.create!(
        commerce_transaction: txn, dispute: dispute, payment: payment, order: order,
        entry_type: 'DISPUTE_FUNDS_WITHDRAWN', amount: BigDecimal('-99.99'), currency: 'usd',
        idempotency_key: 'fact:tmp:p76:mismatch', effective_at: withdrawn_at, provider: 'stripe', state: 'posted'
      )
      count_before = PallasTrade::FinancialLedgerEntry.count

      value = recover(dispute)

      expect(value[:reconciliation][:classification]).to eq('amount_mismatch')
      expect(value[:attention_reason]).to eq('journal_gap')
      expect(PallasTrade::FinancialLedgerEntry.count).to eq(count_before)
      expect(PallasTrade::FinancialLedgerEntry.find_by(idempotency_key: 'fact:tmp:p76:mismatch').amount.to_d).
        to eq(BigDecimal('-99.99'))
    end

    it 'AC-P76-09 资金时间戳缺失：provider 终局已示资金移动而本地无时间戳 → 不猜、交人工' do
      dispute = make_dispute(state: 'lost')
      stub_provider(status: 'lost')

      value = recover(dispute)

      expect(value[:decision]).to eq('manual_review_flagged')
      expect(value[:attention_reason]).to eq('funds_evidence_missing')
      expect(dispute.reload.funds_withdrawn_at).to be_nil
      expect(dispute.state).to eq('manual_review')
      expect(PallasTrade::FinancialLedgerEntry.count).to eq(0)
    end

    it 'AC-P76-05 既有 attention 不被覆盖（只补不覆盖），仅打开人工态' do
      dispute = make_dispute(state: 'opened', attention_reason: 'unlinked_payment', link_payment: false)

      value = recover(dispute)

      expect(value[:decision]).to eq('manual_review_flagged')
      expect(value[:attention_reason]).to eq('unlinked_payment')
      expect(dispute.reload.attention_reason).to eq('unlinked_payment')
      expect(dispute.state).to eq('manual_review')
    end
  end

  describe '降级纪律（FR-P76-03 / NFR 零猜测）' do
    it 'AC-P76-10 无只读契约 → unsupported 且零写（不落 attention）' do
      dispute = make_dispute(state: 'opened')
      attributes_before = dispute.reload.attributes

      value = recover(dispute)

      expect(value[:decision]).to eq('unsupported')
      expect(value[:actions]).to eq([])
      expect(dispute.reload.attributes).to eq(attributes_before)
    end

    it 'AC-P76-10 provider 报错 → unavailable 且零写' do
      dispute = make_dispute(state: 'opened')
      allow(payment_method).to receive(:fetch_dispute_details).and_raise(PallasTrade::Core::GatewayError, 'boom')

      value = recover(dispute)

      expect(value[:decision]).to eq('unavailable')
      expect(value[:actions]).to eq([])
      expect(dispute.reload.attention_reason).to be_nil
    end
  end

  describe 'dry-run 与审计（FR-P76-07/09）' do
    it 'AC-P76-12 dry-run：返回计划且数据库零变化' do
      dispute = make_dispute(state: 'opened', funds_withdrawn_at: withdrawn_at)
      stub_provider(status: 'lost')
      attributes_before = dispute.reload.attributes
      counts_before = money_counts

      value = recover(dispute, apply: false)

      expect(value[:dry_run]).to be(true)
      expect(value[:decision]).to eq('lifecycle_and_journal_repaired')
      expect(value[:actions].map { |a| a['status'] }).to all(eq('planned'))
      expect(dispute.reload.attributes).to eq(attributes_before)
      expect(money_counts).to eq(counts_before)
    end

    it 'AC-P76-14 审计痕迹：有动作记录最近一次 recovery（at/decision/from/to/actions）' do
      dispute = make_dispute(state: 'opened')
      stub_provider(status: 'lost')

      recover(dispute)
      recovery = dispute.reload.private_metadata['recovery']

      expect(recovery).to include('decision' => 'lifecycle_repaired', 'from' => 'opened', 'to' => 'lost')
      expect(recovery['at']).to be_present
      expect(recovery['actions']).to include(a_hash_including('type' => 'lifecycle_repair'))
    end
  end

  describe '铁律负向断言（FR-P76-06）' do
    it 'AC-P76-11 只补账行：不碰 payment/refund/order/txn/inventory，不调 provider 写方法' do
      dispute = make_dispute(state: 'lost', funds_withdrawn_at: withdrawn_at)
      stub_provider(status: 'lost')
      %i[authorize purchase capture void credit cancel].select { |m| payment_method.respond_to?(m) }.each do |method_name|
        allow_any_instance_of(payment_method.class).to receive(method_name).
          and_raise("provider write attempted: #{method_name}")
      end
      counts_before = money_counts
      order_attributes = order.reload.attributes
      transaction_attributes = txn.reload.attributes
      payment_attributes = payment.reload.attributes

      recover(dispute)

      counts_after = money_counts
      expect(counts_after.except(:ledger_entries)).to eq(counts_before.except(:ledger_entries))
      expect(counts_after[:ledger_entries]).to eq(counts_before[:ledger_entries] + 1) # 唯一允许的写
      expect(order.reload.attributes).to eq(order_attributes)
      expect(txn.reload.attributes).to eq(transaction_attributes)
      expect(payment.reload.attributes).to eq(payment_attributes)
    end
  end
end
