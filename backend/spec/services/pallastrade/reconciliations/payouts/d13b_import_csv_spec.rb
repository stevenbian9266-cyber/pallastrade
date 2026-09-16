# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13b-payout-ledger（切片2，core 服务）
#   AC-002 ← FR-002：结算报表导入是台账**唯一写入口** —— 分组建批次 + 行幂等（重复导入只跳行）
#            + 汇总/状态随之合成
#   AC-003 ← FR-003：缺列 / 空文件 / 坏行 → 拒绝或收集（行级错误不中断整批）
#   AC-009 ← FR-007：零资金副作用（支付/退款/订单/账本不变）
RSpec.describe PallasTrade::Reconciliations::Payouts::ImportCSV, type: :service do
  let(:store) { @default_store }

  def csv(*rows)
    <<~CSV
      payout_reference,kind,provider_reference,gross,fee,net,currency,arrived_on
      #{rows.join("\n")}
    CSV
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-002
  it 'imports a settlement report grouped by payout reference and sums its lines' do    result = described_class.call(
      store: store, provider: 'stripe', source: 'stripe_2026_09.csv',
      csv: csv(
        'po_100,charge,ch_1,100.00,3.20,96.80,USD,2026-09-10',
        'po_100,fee,ch_1,3.20,0,3.20,USD,2026-09-10',
        'po_100,refund,re_1,25.00,0,-25.00,USD,2026-09-10',
        'po_101,charge,ch_2,50.00,1.75,48.25,USD,'
      )
    )

    expect(result.success?).to be(true)
    expect(result.value[:lines_created]).to eq(4)
    expect(result.value[:lines_skipped]).to eq(0)
    expect(result.value[:errors]).to be_empty
    expect(result.value[:payouts].size).to eq(2)

    payout = PallasTrade::Payout.find_by(store_id: store.id, provider: 'stripe', reference: 'po_100')
    expect(payout.gross_total.to_d).to eq(128.20.to_d)
    expect(payout.fee_total.to_d).to eq(3.20.to_d)
    expect(payout.net_total.to_d).to eq(75.to_d)
    expect(payout.currency).to eq('USD')
    expect(payout.settled_at).to eq(Time.zone.parse('2026-09-10').beginning_of_day)
    expect(payout.status).to eq('settled')
    expect(payout.import_source).to eq('stripe_2026_09.csv')
    expect(payout.imported_at).to be_present
    expect(payout.lines.pluck(:match_status).uniq).to eq(['pending'])
    # net 缺省 = gross - fee
    pending_payout = PallasTrade::Payout.find_by(reference: 'po_101')
    expect(pending_payout.net_total.to_d).to eq(48.25.to_d)
    expect(pending_payout.status).to eq('in_transit')
  end

  # PRD-20260916-payments-d13d-fx-snapshot AC-13（D13 切片4）：
  # 结算报文可携带**结算汇率**（可选列 `fx_rate`）→ 写入 `line.raw['fx_rate']`（十进制字符串）；
  # 非法值 → 行级错误但**不阻断**导入；缺列行为与既有导入完全一致。
  it 'keeps an optional settlement fx_rate in the raw snapshot without breaking the import' do
    with_rate = <<~CSV
      payout_reference,kind,provider_reference,gross,fee,net,currency,arrived_on,fx_rate
      po_210,charge,ch_19,7100.00,0,7100.00,USD,2026-09-10,7.42
      po_210,charge,ch_20,100.00,0,100.00,USD,2026-09-10,not-a-number
    CSV

    result = described_class.call(store: store, provider: 'stripe', csv: with_rate)

    expect(result.success?).to be(true)
    expect(result.value[:lines_created]).to eq(2)
    expect(result.value[:errors].map { |error| error[:message] }).to include(
      a_string_matching(/fx_rate must be a number/)
    )

    payout = PallasTrade::Payout.find_by(reference: 'po_210')
    expect(payout.lines.find_by(provider_reference: 'ch_19').raw['fx_rate']).to eq('7.42')
    expect(payout.lines.find_by(provider_reference: 'ch_20').raw['fx_rate']).to eq('not-a-number')

    without_rate = described_class.call(
      store: store, provider: 'stripe', csv: csv('po_211,charge,ch_21,10.00,0,10.00,USD,2026-09-10')
    )

    expect(without_rate.success?).to be(true)
    expect(PallasTrade::Payout.find_by(reference: 'po_211').lines.first.raw.key?('fx_rate')).to be(false)
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-002
  it 'is idempotent: re-importing the same report only skips existing lines' do
    payload = csv('po_200,charge,ch_9,80.00,2.00,78.00,USD,2026-09-11')
    described_class.call(store: store, provider: 'stripe', csv: payload)

    second = described_class.call(store: store, provider: 'stripe', csv: payload)

    expect(second.success?).to be(true)
    expect(second.value[:lines_created]).to eq(0)
    expect(second.value[:lines_skipped]).to eq(1)
    expect(PallasTrade::Payout.where(reference: 'po_200').count).to eq(1)
    expect(PallasTrade::PayoutLine.count).to eq(1)
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-003
  it 'collects row level errors without aborting the import' do
    result = described_class.call(
      store: store, provider: 'stripe',
      csv: csv(
        'po_300,charge,ch_ok,10.00,0,10.00,USD,',
        'po_300,teleport,ch_bad,10.00,0,10.00,USD,',
        'po_300,charge,,10.00,0,10.00,USD,',
        'po_300,charge,ch_bad_amount,abc,0,,USD,'
      )
    )

    expect(result.success?).to be(true)
    expect(result.value[:lines_created]).to eq(1)
    expect(result.value[:errors].pluck(:row)).to eq([3, 4, 5])
    expect(result.value[:errors].pluck(:message).join(' ')).to include('unsupported kind: teleport')
    expect(result.value[:errors].pluck(:message).join(' ')).to include('provider_reference is required')
    expect(result.value[:errors].pluck(:message).join(' ')).to include('gross must be a number')
    expect(PallasTrade::Payout.where(reference: 'po_300').sole.lines.count).to eq(1)
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-003
  it 'rejects blank input, missing columns and malformed CSV without writing anything' do
    expect(PallasTrade::Payout.count).to eq(0)

    expect(described_class.call(store: store, provider: 'stripe', csv: '  ').error.to_s).to eq('CSV is empty')
    expect(described_class.call(store: nil, provider: 'stripe', csv: csv('a,b,c,d')).error.to_s).to eq('Store not found')
    expect(described_class.call(store: store, provider: '', csv: csv('a,b,c,d')).error.to_s).to eq('Provider is required')
    expect(described_class.call(store: store, provider: 'stripe', csv: "payout_reference,kind\npo,charge\n").error.to_s)
      .to eq('Missing columns: provider_reference, gross')
    expect(described_class.call(store: store, provider: 'stripe',
                                csv: "payout_reference,kind,provider_reference,gross\n").error.to_s)
      .to eq('CSV has no data rows')
    expect(described_class.call(store: store, provider: 'stripe', csv: 'x' * (6 * 1024 * 1024)).error.to_s).to eq('CSV is too large')

    allow(CSV).to receive(:parse).and_raise(CSV::MalformedCSVError.new('unclosed quoted field', 1))
    expect(described_class.call(store: store, provider: 'stripe', csv: csv('po_1,charge,ch_1,1,0,1,USD,')).error.to_s)
      .to start_with('Malformed CSV')

    expect(PallasTrade::Payout.count).to eq(0)
    expect(PallasTrade::PayoutLine.count).to eq(0)
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-009（零资金副作用）
  it 'never touches payments, refunds, orders or the financial ledger' do
    order = create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                           payment_state: 'balance_due')
    payment = create(:payment, order: order, amount: 100, state: 'completed', response_code: 'ch_import')
    refund = create(:refund, payment: payment, amount: 25, transaction_id: 're_import')

    before = [PallasTrade::Payment.count, PallasTrade::Refund.count, PallasTrade::Order.count,
              PallasTrade::FinancialLedgerEntry.count]
    before_amounts = [payment.reload.amount.to_d, refund.reload.amount.to_d, order.reload.total.to_d]

    described_class.call(
      store: store, provider: 'stripe',
      csv: csv('po_400,charge,ch_import,100.00,0,100.00,USD,2026-09-12', 'po_400,refund,re_import,25.00,0,-25.00,USD,')
    )

    after = [PallasTrade::Payment.count, PallasTrade::Refund.count, PallasTrade::Order.count,
             PallasTrade::FinancialLedgerEntry.count]
    expect(after).to eq(before)
    expect([payment.reload.amount.to_d, refund.reload.amount.to_d, order.reload.total.to_d]).to eq(before_amounts)
    expect(payment.reload.state).to eq('completed')
    expect(refund.reload.state).to eq('succeeded')
    expect(PallasTrade::Payout.where(reference: 'po_400').sole.lines.count).to eq(2)
    expect(PallasTrade::AuditLog.where(action: 'payouts_imported').count).to be >= 1
  end
end
