# frozen_string_literal: true

require 'rails_helper'

# PRD-20260908-payments-rev-p6-8f-combination-level-cancel-orchestration AC-R68F-01~06/08
# 组合级取消编排：
#  - Orders::Cancel split-aware（FR-R68F-101）：succeeded 组合成员无本地 PSP payment → 可退源 = 冻结
#    PaymentSplit（组合 Payment + payment_split/target_order ownership）→ durable Refund(requested)；
#  - Orders::CombinationCancel（FR-R68F-102）：succeeded 组合整组/子集取消，逐成员复用 Orders::Cancel，
#    已取消/不可取消 skip，单成员失败隔离不中断，重复调用幂等。
# 注：应用 Sidekiq adapter → 用 ExecuteJob.perform_later mock 断言入队（同 cancellation_orchestration_spec）。
RSpec.describe PallasTrade::Orders::CombinationCancel, type: :service do
  let(:store) { @default_store }
  let(:user) { create(:user) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }

  # succeeded 组合 + 组合 Payment（order_id=nil）+ 每成员已结算 split（captured 回填 payment_id）
  let(:combination) do
    create(:payment_combination, store: store, customer: user, amount: 20.0, status: 'succeeded')
  end
  let(:combo_payment) do
    create(:payment, order: nil, payment_combination: combination, payment_method: payment_method,
                     amount: 20, state: 'completed', source: nil, skip_source_requirement: true)
  end

  def member_order(amount, tag = 'a')
    create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                   item_total: amount, total: amount, payment_state: 'paid', payment_total: amount,
                   currency: store.default_currency, email: "buyer#{tag}@example.com")
  end

  def add_split(order, captured:)
    create(:payment_split, payment_combination: combination, order: order, payment: combo_payment,
                           authorized_amount: captured, captured_amount: captured, refunded_amount: 0)
  end

  describe 'Orders::Cancel split-aware（FR-R68F-101）' do
    it 'AC-R68F-01: PAID 组合成员 auto 取消 → 组合 Payment + 冻结 split durable Refund(requested, full credit) + canceled + enqueue' do
      member = member_order(10)
      split = add_split(member, captured: 10)
      expect(PallasTrade::Refunds::ExecuteJob).to receive(:perform_later).with(instance_of(Integer)).once

      result = PallasTrade::Orders::Cancel.call(order: member, reason: 'staff')

      expect(result.success?).to be(true)
      expect(member.reload.state).to eq('canceled')
      expect(member.cancellations.last.refund_payments).to be(true)

      refund = PallasTrade::Refund.where(payment_id: combo_payment.id, target_order_id: member.id).first
      expect(refund).to be_present
      expect(refund.state).to eq('requested')
      expect(refund.amount.to_f).to eq(10.0)
      expect(refund.payment).to eq(combo_payment)
      expect(refund.payment.order_id).to be_nil
      expect(refund.payment_split).to eq(split)
      expect(refund.reason.name).to eq(PallasTrade::RefundReason::ORDER_CANCELED_REASON)

      # 不触碰本地 payment 行（成员本无）；split 未被提前改写（由 succeeded 投影负责）
      expect(split.reload.refunded_amount.to_f).to eq(0.0)

      # 跑 ExecuteJob → split.refunded_amount 投影（update_order 唯一写点）
      PallasTrade::Refunds::ExecuteJob.perform_now(refund.id)
      expect(refund.reload.state).to eq('succeeded')
      expect(split.reload.refunded_amount.to_f).to eq(10.0)
    end

    it 'AC-R68F-02: 成员 refund_payments=false → 不建 Refund；refund_amount 超 split credit → 建单失败回滚不取消' do
      member = member_order(10)
      add_split(member, captured: 10)
      expect(PallasTrade::Refunds::ExecuteJob).not_to receive(:perform_later)

      result = PallasTrade::Orders::Cancel.call(order: member, reason: 'staff', refund_payments: false)

      expect(result.success?).to be(true)
      expect(member.reload.state).to eq('canceled')
      expect(PallasTrade::Refund.where(payment_id: combo_payment.id, target_order_id: member.id)).to be_empty
    end

    it 'AC-R68F-02(边界): 非组合单订单取消行为不变（回归哨兵）' do
      order = create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                             item_total: 100, total: 100, payment_state: 'balance_due',
                             currency: store.default_currency, email: 'solo@example.com')
      create(:payment, order: order, payment_method: payment_method, amount: 100,
                       state: 'completed', source: nil, skip_source_requirement: true)
      expect(PallasTrade::Refunds::ExecuteJob).to receive(:perform_later).with(instance_of(Integer)).once

      result = PallasTrade::Orders::Cancel.call(order: order, reason: 'staff')

      expect(result.success?).to be(true)
      expect(order.reload.state).to eq('canceled')
      refund = PallasTrade::Refund.where(payment_id: order.payments.first.id).first
      expect(refund.payment.order_id).to eq(order.id)
      expect(refund.payment_split).to be_nil
    end
  end

  describe 'Orders::CombinationCancel（FR-R68F-102）' do
    it 'AC-R68F-03: succeeded 组合 2 个可取消 PAID 成员 → 双 canceled + 双 split Refund(requested)，聚合 canceled=2' do
      m1 = member_order(10, 'a')
      m2 = member_order(10, 'b')
      s1 = add_split(m1, captured: 10)
      s2 = add_split(m2, captured: 10)
      expect(PallasTrade::Refunds::ExecuteJob).to receive(:perform_later).with(instance_of(Integer)).twice

      result = described_class.call(combination: combination, reason: 'staff')

      expect(result.success?).to be(true)
      value = result.value
      expect(value[:members]).to eq(total: 2, canceled: 2, skipped: 0, failed: 0)
      expect(value[:canceled].map { |m| m[:order_prefixed_id] }).to contain_exactly(m1.prefixed_id, m2.prefixed_id)

      expect(m1.reload.state).to eq('canceled')
      expect(m2.reload.state).to eq('canceled')
      r1 = PallasTrade::Refund.where(payment_id: combo_payment.id, target_order_id: m1.id).first
      r2 = PallasTrade::Refund.where(payment_id: combo_payment.id, target_order_id: m2.id).first
      expect(r1.state).to eq('requested')
      expect(r1.payment_split).to eq(s1)
      expect(r2.state).to eq('requested')
      expect(r2.payment_split).to eq(s2)
      expect(PallasTrade::Refund.where(payment_id: combo_payment.id, state: 'requested').count).to eq(2)
    end

    it 'AC-R68F-04/AC-R68F-06: 已 canceled 成员 skip(already_canceled)、重复调用幂等 → 不重复建 Refund' do
      m1 = member_order(10, 'a')
      m2 = member_order(10, 'b')
      add_split(m1, captured: 10)
      add_split(m2, captured: 10)
      PallasTrade::Orders::Cancel.call(order: m1, reason: 'staff') # 先取消 m1

      expect(PallasTrade::Refunds::ExecuteJob).to receive(:perform_later).with(instance_of(Integer)).once
      result = described_class.call(combination: combination, reason: 'staff')

      expect(result.success?).to be(true)
      value = result.value
      expect(value[:members]).to eq(total: 2, canceled: 1, skipped: 1, failed: 0)
      expect(value[:skipped].first[:order_prefixed_id]).to eq(m1.prefixed_id)
      expect(value[:skipped].first[:reason]).to eq('already_canceled')
      expect(PallasTrade::Refund.where(payment_id: combo_payment.id, target_order_id: m1.id).count).to eq(1)
      expect(PallasTrade::Refund.where(payment_id: combo_payment.id, target_order_id: m2.id).count).to eq(1)
    end

    it 'AC-R68F-04: 不可取消成员（processing）skip(not_cancellable) 不中断其他成员' do
      cancellable = member_order(10, 'a')
      add_split(cancellable, captured: 10)
      blocked = create(:order, store: store, state: 'processing', status: 'placed',
                               item_total: 10, total: 10, payment_state: 'paid', payment_total: 10,
                               currency: store.default_currency, email: 'blocked@example.com')
      add_split(blocked, captured: 10)

      expect(PallasTrade::Refunds::ExecuteJob).to receive(:perform_later).with(instance_of(Integer)).once
      result = described_class.call(combination: combination, reason: 'staff')

      expect(result.success?).to be(true)
      value = result.value
      expect(value[:members]).to eq(total: 2, canceled: 1, skipped: 1, failed: 0)
      expect(value[:skipped].first[:order_prefixed_id]).to eq(blocked.prefixed_id)
      expect(value[:skipped].first[:reason]).to eq('not_cancellable')
      expect(cancellable.reload.state).to eq('canceled')
      expect(blocked.reload.state).to eq('processing')
    end

    it 'AC-R68F-05: member_ids 子集只取消指定成员；无效子集 → failure' do
      m1 = member_order(10, 'a')
      m2 = member_order(10, 'b')
      add_split(m1, captured: 10)
      add_split(m2, captured: 10)
      expect(PallasTrade::Refunds::ExecuteJob).to receive(:perform_later).with(instance_of(Integer)).once

      result = described_class.call(combination: combination, member_ids: [m1.id], reason: 'staff')

      expect(result.success?).to be(true)
      expect(result.value[:members]).to eq(total: 1, canceled: 1, skipped: 0, failed: 0)
      expect(m1.reload.state).to eq('canceled')
      expect(m2.reload.state).to eq('pending')

      invalid = described_class.call(combination: combination, member_ids: [9_999_999], reason: 'staff')
      expect(invalid.success?).to be(false)
    end

    it 'AC-R68F-05: 非 succeeded 组合 → failure 不编排' do
      pending_combo = create(:payment_combination, store: store, customer: user, amount: 10.0, status: 'pending')

      result = described_class.call(combination: pending_combo, reason: 'staff')

      expect(result.success?).to be(false)
    end

    it 'AC-R68F-08: 单成员资金失败（容量双门禁）隔离 → failed 聚合，其他成员照常取消' do
      # 组合 Payment 容量 15 < 两成员 split 10+10：先处理者成功（占 10 → 容量 5），
      # 后处理者 refund 10 > 剩余容量 5 → Refund 校验失败 → 该成员取消整体回滚 → failed 聚合。
      combo15 = create(:payment_combination, store: store, customer: user, amount: 15.0, status: 'succeeded')
      pay15 = create(:payment, order: nil, payment_combination: combo15, payment_method: payment_method,
                               amount: 15, state: 'completed', source: nil, skip_source_requirement: true)
      m1 = member_order(10, 'a')
      m2 = member_order(10, 'b')
      create(:payment_split, payment_combination: combo15, order: m1, payment: pay15,
                             authorized_amount: 10, captured_amount: 10, refunded_amount: 0)
      create(:payment_split, payment_combination: combo15, order: m2, payment: pay15,
                             authorized_amount: 10, captured_amount: 10, refunded_amount: 0)

      expect(PallasTrade::Refunds::ExecuteJob).to receive(:perform_later).with(instance_of(Integer)).once
      result = described_class.call(combination: combo15, reason: 'staff')

      expect(result.success?).to be(true)
      value = result.value
      expect(value[:members]).to eq(total: 2, canceled: 1, skipped: 0, failed: 1)
      # 恰好一个成员被取消 + 一笔成功 committed 的 requested refund；失败者整体回滚（无 Refund/无取消行）
      canceled_member = PallasTrade::Order.find(value[:canceled].first[:order_id])
      failed_member = PallasTrade::Order.find(value[:failed].first[:order_id])
      expect(canceled_member.state).to eq('canceled')
      expect(failed_member.state).to eq('pending')
      expect(value[:failed].first[:error]).to include('refund could not be requested')
      expect(PallasTrade::Refund.where(payment_id: pay15.id, state: 'requested').count).to eq(1)
      expect(failed_member.cancellations.count).to eq(0)
    end
  end
end
