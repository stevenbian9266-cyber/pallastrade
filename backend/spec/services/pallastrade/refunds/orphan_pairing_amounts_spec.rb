# frozen_string_literal: true

# PRD-REV-P6-8h AC-R68H-01~03/06 —— OrphanPairing 孤儿金额扩展（只读）
require 'rails_helper'

# 金额能力用 factory bogus + 单例方法覆写 provider_refund_amount 模拟（owner=singleton ≠ PaymentMethod）；
# 未覆写的 Bogus（owner==PaymentMethod 继承 base）→ 能力缺失 → amount nil + ORPHAN_AMOUNT_UNAVAILABLE。
RSpec.describe PallasTrade::Refunds::OrphanPairing, type: :service do
  let(:store) { @default_store }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                   item_total: 100, total: 100, payment_state: 'paid',
                   currency: store.default_currency, email: 'orphan@example.com')
  end

  def capable_pm
    pm = create(:bogus_payment_method, store: store, active: true)
    allow(pm).to receive(:fetch_financial_details).and_return(provider_refund_references: ['re_orphan_1'])
    def pm.provider_refund_amount(reference)
      { amount: 12.5, currency: 'usd' }
    end
    pm
  end

  def plain_pm
    pm = create(:bogus_payment_method, store: store, active: true)
    allow(pm).to receive(:fetch_financial_details).and_return(provider_refund_references: ['re_orphan_1'])
    pm
  end

  def completed_payment(pm:)
    create(:payment, order: order, payment_method: pm, amount: 100,
                     state: 'completed', source: nil, skip_source_requirement: true)
  end

  def attach_session(payment, pm)
    session = create(:bogus_payment_session, order: order, payment_method: pm,
                                             status: 'completed', amount: 100, currency: 'USD')
    payment.update_columns(payment_session_id: session.id)
    session
  end

  it 'AC-R68H-01: 具备金额能力时孤儿条目含 amount/currency（只读），reason 仅 ORPHAN_REFUND' do
    pm = capable_pm
    payment = completed_payment(pm: pm)
    attach_session(payment, pm)

    result = described_class.call(payment: payment)

    expect(result.success?).to be(true)
    value = result.value
    expect(value.status).to eq('needs_attention')
    expect(value.reasons).to contain_exactly('ORPHAN_REFUND')
    orphan = value.orphans.first
    expect(orphan[:provider_id]).to eq('re_orphan_1')
    expect(orphan[:amount]).to eq(12.5)
    expect(orphan[:currency]).to eq('usd')
  end

  it 'AC-R68H-02: 无金额能力（owner=base，如 Bogus）→ amount nil + ORPHAN_AMOUNT_UNAVAILABLE，整体仍 needs_attention' do
    pm = plain_pm
    payment = completed_payment(pm: pm)
    attach_session(payment, pm)

    result = described_class.call(payment: payment)

    expect(result.success?).to be(true)
    value = result.value
    expect(value.status).to eq('needs_attention')
    expect(value.reasons).to include('ORPHAN_REFUND', 'ORPHAN_AMOUNT_UNAVAILABLE')
    orphan = value.orphans.first
    expect(orphan[:amount]).to be_nil
    expect(orphan[:currency]).to be_nil
  end

  it 'AC-R68H-03: 单条孤儿金额 provider 异常降级为 nil，不影响其他孤儿与整体结果' do
    pm = create(:bogus_payment_method, store: store, active: true)
    allow(pm).to receive(:fetch_financial_details).and_return(provider_refund_references: %w[re_bad re_good])
    calls = []
    def pm.provider_refund_amount(reference)
      raise 'boom' if reference == 're_bad'

      { amount: 7.0, currency: 'eur' }
    end
    allow(pm).to receive(:provider_refund_amount).and_wrap_original { |m, ref| calls << ref; m.call(ref) }

    payment = completed_payment(pm: pm)
    attach_session(payment, pm)

    result = described_class.call(payment: payment)

    expect(result.success?).to be(true)
    value = result.value
    expect(value.status).to eq('needs_attention')
    bad = value.orphans.find { |o| o[:provider_id] == 're_bad' }
    good = value.orphans.find { |o| o[:provider_id] == 're_good' }
    expect(bad[:amount]).to be_nil
    expect(good[:amount]).to eq(7.0)
    expect(good[:currency]).to eq('eur')
    expect(value.reasons).to include('ORPHAN_AMOUNT_UNAVAILABLE')
    expect(calls).to contain_exactly('re_bad', 're_good')
  end

  it 'AC-R68H-06: matched / local_unmatched 结构向后兼容（8d 语义不变）' do
    pm = capable_pm
    payment = completed_payment(pm: pm)
    attach_session(payment, pm)
    # 本地 refund 引用 = provider 're_orphan_1'（matched 路径）
    create(:refund, payment: payment, amount: 10, state: 'succeeded',
                    transaction_id: 're_orphan_1', succeeded_at: Time.current)

    result = described_class.call(payment: payment)

    expect(result.success?).to be(true)
    value = result.value
    expect(value.status).to eq('matched')
    expect(value.matched).to eq([{ provider_id: 're_orphan_1', refund_id: payment.refunds.first.prefixed_id }])
    expect(value.orphans).to be_empty
    expect(value.local_unmatched).to be_empty
  end
end

