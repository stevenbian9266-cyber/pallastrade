# frozen_string_literal: true

require 'rails_helper'

# PRD-20260828-checkout-p7 AC-001/002/003 + REV-P6-8c async 语义（PRD-20260908-payments-rev-p6-8c）
# 拆单/组合支付子订单售后退款：子订单无本地 payment → 退款挂组合 payment + split.refunded_amount。
# REV-P6-8c：退款 = durable(requested) → enqueue ExecuteJob（不同步 Execute）；split 投影在 job 跑完后更新；
# perform 判定 = initiated（covering）。
RSpec.describe PallasTrade::ReimbursementType::OriginalPayment, type: :model do
  ActiveJob::Base.queue_adapter = :test

  let!(:store) { create(:store, code: 'orig_payment_child_store') }
  let(:user) { create(:user) }
  let(:payment_method) { create(:bogus_payment_method, name: 'Card', store: store) }

  let(:child) do
    create(:shipped_order, store: store, user: user, line_items_count: 2, line_items_price: 10, shipment_cost: 0, with_payment: false)
  end
  let(:combination) { create(:payment_combination, store: store, customer: user, amount: 10.0) }
  let(:payment) do
    create(:payment, order: nil, payment_combination: combination, payment_method: payment_method,
                     amount: 10, state: 'completed')
  end
  let!(:split) do
    create(:payment_split, payment_combination: combination, order: child, payment: payment,
                           authorized_amount: 10, captured_amount: 10)
  end

  let(:ra) { create(:return_authorization, order: child) }
  let(:cr) do
    customer_return = build(:customer_return_without_return_items, store: store, stock_location: ra.stock_location)
    customer_return.return_items << create(:return_item, inventory_unit: child.inventory_units.shipped.first, return_authorization: ra)
    customer_return.save!
    customer_return
  end
  let(:reimbursement) do
    PallasTrade::Reimbursement.new(order: child, customer_return: cr, return_items: cr.return_items)
  end

  describe 'AC-001 child order refund via combined payment (async)' do
    it 'creates a durable requested refund + enqueues ExecuteJob; split projected after job runs' do
      reimbursement.save!

      expect do
        reimbursement.perform!
      end.to change { enqueued_jobs.count { |j| j[:job] == PallasTrade::Refunds::ExecuteJob } }.by(1)
      expect(reimbursement.reload).to be_reimbursed

      refund = reimbursement.refunds.first
      expect(refund).to be_present
      expect(refund.payment).to eq(payment)
      expect(refund.payment.order_id).to be_nil
      # async 语义：perform 结束仍是 requested（无同步 Execute）
      expect(refund.state).to eq('requested')

      # 跑 ExecuteJob → ApplySuccess → split.refunded_amount / child.payment_total 更新
      PallasTrade::Refunds::ExecuteJob.perform_now(refund.id)
      expect(refund.reload.state).to eq('succeeded')
      expect(split.reload.refunded_amount).to eq(BigDecimal('10'))
      expect(child.reload.payment_total.to_f).to eq(0.0)
    end

    it 'does not create duplicate refunds on repeat perform while job in flight' do
      reimbursement.save!
      reimbursement.perform!

      first_count = reimbursement.reload.refunds.count
      expect(first_count).to eq(1)
      # ExecuteJob 未跑完（refund 仍 requested）时重复 perform → covering 扣除 → 不重复建单
      reimbursement.reload
      PallasTrade::ReimbursementPerformer.perform(reimbursement)
      expect(reimbursement.reload.refunds.count).to eq(first_count)
      expect(reimbursement.reload).to be_reimbursed
    end
  end

  describe 'AC-002 Refund#order resolves from the reimbursement chain' do
    it 'returns the child order when payment.order is nil' do
      reimbursement.save!
      reimbursement.perform!

      refund = reimbursement.refunds.first
      expect(refund.order).to eq(child)
      expect(refund.editable?).to be true
      expect(refund.currency).to eq('USD')
    end
  end

  describe 'AC-003 refund is capped by the split credit' do
    it 'caps the refund at split.captured - refunded - covering and errors on uncovered remainder' do
      second_unit = child.inventory_units.shipped.second
      second_item = create(:return_item, inventory_unit: second_unit, return_authorization: ra)
      second_item.accept!
      cr.return_items << second_item

      reimbursement.save!
      # 两个 shipped units（20），但 split 只捕获 10 → durable requested 只建 10，剩余 10 无法覆盖 → errored+raise
      expect { reimbursement.perform! }.to raise_error(PallasTrade::Reimbursement::IncompleteReimbursementError)

      refund = reimbursement.reload.refunds.first
      expect(refund.amount.to_f).to eq(10.0)
      expect(refund.state).to eq('requested')
      expect(reimbursement.reload).to be_errored

      # 跑 ExecuteJob 后 split.refunded_amount 投影到已退 10（succeeded 口径）
      PallasTrade::Refunds::ExecuteJob.perform_now(refund.id)
      expect(refund.reload.state).to eq('succeeded')
      expect(split.reload.refunded_amount).to eq(BigDecimal('10'))
      expect(reimbursement.reload.paid_amount.to_f).to eq(10.0)
      expect(reimbursement.reload).to be_errored
    end
  end
end
