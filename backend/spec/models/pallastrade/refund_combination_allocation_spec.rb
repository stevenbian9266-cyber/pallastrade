# frozen_string_literal: true

require 'rails_helper'

# PRD-REV-P6-3 FR-R63-101/102/103 + 源 REV-P6 AC-6008/6010/6011/6012
# —— 组合退款 ownership 冻结：Request 冻结 payment_split/target_order；成功投影只更新冻结
#    split（兄弟 split 不动）；冻结 split 上限 = captured − refunded（创建期拒绝，绝不 enqueue）；
#    多笔 partial 顺序扣减；无冻结走 legacy reimbursement fallback（见
#    original_payment_child_spec，本文件不重复）。
# 注：应用 Sidekiq adapter → 用 ExecuteJob.perform_later mock 断言入队；组合退款资金路径
#    与 original_payment_child_spec 同构（payment.order nil + PaymentSplit 关联 child）。
RSpec.describe PallasTrade::Refund, type: :model do
  let!(:store) { create(:store, code: 'refund_combo_alloc_store') }
  let(:user) { create(:user) }
  let(:payment_method) { create(:bogus_payment_method, name: 'Card', store: store) }

  # child：组合支付成员（无本地 payment），2 个 shipped units；child2 为兄弟成员单
  let(:child) do
    create(:shipped_order, store: store, user: user, line_items_count: 2, line_items_price: 10,
                           shipment_cost: 0, with_payment: false)
  end
  let(:child2) do
    create(:shipped_order, store: store, user: user, line_items_count: 1, line_items_price: 5,
                           shipment_cost: 0, with_payment: false)
  end
  let(:combination) { create(:payment_combination, store: store, customer: user, amount: 15.0) }
  let(:payment) do
    create(:payment, order: nil, payment_combination: combination, payment_method: payment_method,
                     amount: 15, state: 'completed')
  end
  let!(:split) do
    create(:payment_split, payment_combination: combination, order: child, payment: payment,
                           authorized_amount: 10, captured_amount: 10)
  end
  let!(:split2) do
    create(:payment_split, payment_combination: combination, order: child2, payment: payment,
                           authorized_amount: 5, captured_amount: 5)
  end
  let(:reason) { create(:refund_reason) }

  def request_frozen(amount:, target_order: child, payment_split: split, reason: self.reason)
    PallasTrade::Refunds::Request.call(
      payment: payment, amount: amount, reason: reason,
      target_order: target_order, payment_split: payment_split
    )
  end

  it 'AC-6011: 冻结 split 退款上限 = captured − refunded，超限在创建期拒绝且不 enqueue' do
    # 全局 payment capacity = 15（充足），但冻结 split 上限 = 10 → 12 必须被拒
    expect(PallasTrade::Refunds::ExecuteJob).not_to receive(:perform_later)

    result = request_frozen(amount: 12)
    expect(result.success?).to be(false)
    expect(PallasTrade::Refund.count).to eq(0)
    expect(split.reload.refunded_amount.to_f).to eq(0.0)
  end

  it 'AC-6012/AC-6008: 冻结 ownership 持久化，成功后只投影冻结 split（兄弟 split 不动）' do
    expect(PallasTrade::Refunds::ExecuteJob).to receive(:perform_later).with(instance_of(Integer)).once

    result = request_frozen(amount: 8)
    expect(result.success?).to be(true)

    refund = PallasTrade::Refund.last
    expect(refund).to be_requested
    expect(refund.payment_split).to eq(split)
    expect(refund.target_order).to eq(child)

    # 同步执行（观察投影；生产由 ExecuteJob 驱动）
    PallasTrade::Refunds::Execute.call(refund: refund)
    expect(refund.reload).to be_succeeded

    expect(split.reload.refunded_amount).to eq(BigDecimal('8'))
    expect(split2.reload.refunded_amount.to_f).to eq(0.0)
  end

  it 'AC-6012: 多笔 partial 顺序扣减，最后超限的一笔被拒' do
    expect(PallasTrade::Refunds::ExecuteJob).to receive(:perform_later).with(instance_of(Integer)).exactly(2).times

    first = request_frozen(amount: 4)
    second = request_frozen(amount: 4)
    expect(first.success?).to be(true)
    expect(second.success?).to be(true)

    PallasTrade::Refunds::Execute.call(refund: first.value)
    PallasTrade::Refunds::Execute.call(refund: second.value)
    expect(split.reload.refunded_amount).to eq(BigDecimal('8'))

    # 剩余 split 额度 = 10 − 8 = 2 → 4 超限，拒绝
    over = request_frozen(amount: 4)
    expect(over.success?).to be(false)
    expect(split.reload.refunded_amount).to eq(BigDecimal('8'))
  end

  it 'AC-6010/FR-R63-101: 冻结目标可为组合内任意成员单（split2.child2），投影独立' do
    expect(PallasTrade::Refunds::ExecuteJob).to receive(:perform_later).with(instance_of(Integer)).once

    result = request_frozen(amount: 3, target_order: child2, payment_split: split2)
    expect(result.success?).to be(true)
    refund = PallasTrade::Refund.last
    expect(refund.payment_split).to eq(split2)
    expect(refund.target_order).to eq(child2)

    PallasTrade::Refunds::Execute.call(refund: refund)
    expect(refund.reload).to be_succeeded
    expect(split2.reload.refunded_amount).to eq(BigDecimal('3'))
    expect(split.reload.refunded_amount.to_f).to eq(0.0)
  end
end
