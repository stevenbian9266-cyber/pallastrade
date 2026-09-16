# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('config/sidekiq_schedule')

ActiveJob::Base.queue_adapter = :test

# PRD-20260916-payments-d13d-fx-snapshot（D13 切片4，巡检作业）
#   FR-9：CompareSweeperJob 汇总指标（scanned/compared/matched/mismatched/pending/undetermined/cases）+ 失败隔离
RSpec.describe PallasTrade::Currencies::Fx::CompareSweeperJob, type: :job do
  let!(:store) do
    create(:store, code: "d13d_job_#{SecureRandom.hex(4)}", default_currency: 'USD',
                   supported_currencies: 'USD,CNY')
  end
  let!(:provider) do
    create(:check_payment_method, store: store, active: true, display_on: 'both',
                                  name: "d13d-job-pm-#{SecureRandom.hex(3)}")
  end

  before do
    create(:currency_rate, store: store, base_currency: 'USD', quote_currency: 'CNY', rate: BigDecimal('7.1'))
    allow(PallasTrade::Events).to receive(:enabled?).and_return(true)
    allow(PallasTrade::Events).to receive(:publish)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  def lock_and_settle(amount:, gross:)
    order = create(:order_with_line_items, store: store, currency: 'CNY', line_items_count: 1,
                                           line_items_price: amount, shipment_cost: 0)
    snapshot = PallasTrade::Currencies::Fx::Lock.call(order: order).value[:snapshot]
    payment = create(:payment, order: order, payment_method: provider, amount: amount, state: 'completed',
                               source: nil, skip_source_requirement: true)
    payout = PallasTrade::Payout.create!(store: store, provider: 'stripe',
                                         reference: "po_d13d_job_#{SecureRandom.hex(4)}", currency: 'USD',
                                         status: 'settled', settled_at: Time.current, imported_at: Time.current,
                                         gross_total: gross, fee_total: 0, net_total: gross)
    PallasTrade::PayoutLine.create!(payout: payout, payment: payment, kind: 'charge',
                                    provider_reference: "ch_#{SecureRandom.hex(4)}", currency: 'USD',
                                    gross_amount: gross, fee_amount: 0, net_amount: gross,
                                    match_status: 'matched', raw: {})
    snapshot
  end

  it 'compares each store and returns aggregated metrics' do
    matched = lock_and_settle(amount: 1000, gross: 7100)
    mismatched = lock_and_settle(amount: 2000, gross: 15_000)
    pending_order = create(:order_with_line_items, store: store, currency: 'CNY', line_items_count: 1,
                                                   line_items_price: 500, shipment_cost: 0)
    pending = PallasTrade::Currencies::Fx::Lock.call(order: pending_order).value[:snapshot]

    summary = described_class.new.perform

    expect(summary[:stores]).to be >= 1
    expect(summary[:scanned]).to be >= 3
    expect(summary[:matched]).to be >= 1
    expect(summary[:mismatched]).to be >= 1
    expect(summary[:pending]).to be >= 1
    expect(summary[:opened]).to be >= 1
    expect(matched.reload.variance_status).to eq('matched')
    expect(mismatched.reload.variance_status).to eq('mismatch')
    expect(pending.reload.variance_status).to eq('pending')
  end

  it 'limits the run to a single store when asked' do
    lock_and_settle(amount: 1000, gross: 7100)

    summary = described_class.new.perform(store_code: store.code)

    expect(summary[:stores]).to eq(1)
    expect(summary[:failed]).to eq(0)
  end

  it 'isolates a store that raises and keeps going' do
    # `ServiceModule::Base` 的类级/实例级 `call` 由 prepend 提供（RSpec 不支持 any_instance 覆盖）→
    # 改为让对比内部的读取路径抛出，同样走作业的失败隔离分支
    allow(PallasTrade::FxSnapshot).to receive(:for_store).and_raise(StandardError, 'boom')

    summary = described_class.new.perform

    expect(summary[:failed]).to be >= 1
    expect(Rails.logger).to have_received(:error).with(/failed:/).at_least(:once)
  end

  it 'is registered in the sidekiq schedule' do
    source = File.read(Rails.root.join('config/sidekiq_schedule.rb'))

    expect(source).to include("name: 'fx_rate_compare_sweep'")
    expect(source).to include("class: 'PallasTrade::Currencies::Fx::CompareSweeperJob'")
    expect(source).to include("cron: '*/30 * * * *'")
  end
end
