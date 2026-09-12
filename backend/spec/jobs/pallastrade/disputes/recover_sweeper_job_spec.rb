# frozen_string_literal: true

require 'rails_helper'
# 调度常量定义在 config/sidekiq_schedule.rb（仅 Sidekiq server 进程 require）→ 用例显式加载
require Rails.root.join('config/sidekiq_schedule')

ActiveJob::Base.queue_adapter = :test

# PRD-20260912-payments-dsp-p7-6-dispute-recovery
# AC-P76-17/18 —— sweeper job：摘要计数 / 事件 / 结构化日志 / 单条隔离 / 调度登记。
RSpec.describe PallasTrade::Disputes::RecoverSweeperJob, type: :job do
  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }
  let(:order) do
    create(:order_with_line_items, store: store, line_items_price: 50, shipment_cost: 0).tap do |o|
      o.update_columns(state: 'complete', status: 'complete', completed_at: Time.current)
    end
  end
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: order.total, state: 'completed',
                     response_code: 'pi_p76_sweep', source: nil, skip_source_requirement: true)
  end
  let(:txn) do
    PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: order.total)
  end

  let(:logged) { [] }
  let(:logger) do
    instance_double(Logger).tap do |double|
      allow(double).to receive(:info) { |message| logged << message }
      allow(double).to receive(:error) { |message| logged << message }
    end
  end

  def make_dispute(**overrides)
    options = { state: 'opened', funds_withdrawn_at: nil, attention_reason: nil, link_payment: true,
                provider_status: nil, reference: nil }.merge(overrides)
    PallasTrade::Dispute.create!(
      provider: 'stripe',
      provider_dispute_reference: options[:reference] || "dp_p76j_#{SecureRandom.hex(4)}",
      state: options[:state], amount: 12.34, currency: 'usd',
      private_metadata: options[:provider_status] ? { 'provider_status' => options[:provider_status] } : {},
      funds_withdrawn_at: options[:funds_withdrawn_at],
      attention_reason: options[:attention_reason],
      commerce_transaction: txn,
      payment: options[:link_payment] ? payment : nil,
      order: options[:link_payment] ? order : nil
    )
  end

  before do
    allow(Rails).to receive(:logger).and_return(logger)
    allow(PallasTrade::Events).to receive(:enabled?).and_return(true)
  end

  it 'AC-P76-17 三类候选一次扫过：补账 / 人工 / 降级各自归类并计数' do
    manual = make_dispute(state: 'opened', attention_reason: 'unlinked_payment', link_payment: false,
                          reference: 'dp_p76j_manual')
    gap = make_dispute(state: 'lost', funds_withdrawn_at: Time.current - 2.hours, provider_status: 'lost',
                       reference: 'dp_p76j_gap')
    degraded = make_dispute(state: 'opened', reference: 'dp_p76j_degraded')
    degraded.update_columns(updated_at: Time.current - 48.hours)

    expect(PallasTrade::Events).to receive(:publish).with(
      'dispute.recovery_repaired', hash_including('id' => gap.prefixed_id)
    ).and_call_original
    expect(PallasTrade::Events).to receive(:publish).with(
      'dispute.recovery_manual_review', hash_including('id' => manual.prefixed_id)
    ).and_call_original

    summary = described_class.perform_now

    expect(summary[:scanned]).to eq(3)
    expect(summary[:recovered]).to eq(1)
    expect(summary[:manual_review]).to eq(1)
    expect(summary[:unavailable]).to eq(1) # bogus 网关无只读契约 → unsupported（零写）
    expect(summary[:noop]).to eq(0)
    expect(summary[:failed]).to eq(0)
    expect(summary[:journal_entries_posted]).to eq(1)
    expect(manual.reload.state).to eq('manual_review')
    expect(gap.reload.state).to eq('lost')
    expect(degraded.reload.state).to eq('opened')
    expect(logged.join).to include('disputes.recover_sweeper')
    expect(logged.join).to include(gap.prefixed_id)
  end

  it 'AC-P76-17 幂等：连续两次运行 → 第二次无新账行，人工待办转入 noop' do
    gap = make_dispute(state: 'lost', funds_withdrawn_at: Time.current - 2.hours, provider_status: 'lost',
                       reference: 'dp_p76j_idem_gap')
    manual = make_dispute(state: 'opened', attention_reason: 'unlinked_payment', link_payment: false,
                          reference: 'dp_p76j_idem_manual')

    described_class.perform_now
    entries_after_first = PallasTrade::FinancialLedgerEntry.count

    second = described_class.perform_now

    expect(PallasTrade::FinancialLedgerEntry.count).to eq(entries_after_first)
    expect(second[:recovered]).to eq(0)
    expect(second[:journal_entries_posted]).to eq(0)
    # 已对齐且账行齐备的争议不再是候选（不在三类 selection 内）；已标人工的行转入待办
    expect(second[:scanned]).to eq(1)
    expect(second[:noop]).to eq(1)
    expect(gap.reload.state).to eq('lost')
    expect(manual.reload.state).to eq('manual_review')
  end

  it 'AC-P76-17 单条异常隔离：一条事件发布失败不影响其余，job 不 raise' do
    bad = make_dispute(state: 'lost', funds_withdrawn_at: Time.current - 2.hours, provider_status: 'lost',
                       reference: 'dp_p76j_bad')
    good = make_dispute(state: 'lost', funds_withdrawn_at: Time.current - 3.hours, provider_status: 'lost',
                        reference: 'dp_p76j_good')
    allow(PallasTrade::Events).to receive(:publish) do |_name, payload|
      raise StandardError, 'event bus down' if payload['id'] == bad.prefixed_id
    end

    summary = nil
    expect { summary = described_class.perform_now }.not_to raise_error

    expect(summary[:failed]).to eq(1)
    # 两条账行都已补出（事实已修）；失败的那条仅通知失败 → recovered 仍计 2（见 job 计数口径）
    expect(summary[:recovered]).to eq(2)
    expect(summary[:journal_entries_posted]).to eq(2)
    expect(logged.join).to include('recovery failed')
    expect(good.reload.state).to eq('lost')
  end

  it 'AC-P76-18 调度登记存在（PALLAS_CART_SCHEDULE：每日 01:30，limit 50）' do
    entry = PALLAS_CART_SCHEDULE.find { |item| item[:name] == 'dispute_recovery_sweep' }

    expect(entry).to be_present
    expect(entry[:class]).to eq('PallasTrade::Disputes::RecoverSweeperJob')
    expect(entry[:cron]).to eq('30 1 * * *')
    expect(entry[:queue]).to eq('default')
    expect(entry[:args]).to eq([{ 'limit' => 50, 'verify_after_hours' => 24 }])
  end
end
