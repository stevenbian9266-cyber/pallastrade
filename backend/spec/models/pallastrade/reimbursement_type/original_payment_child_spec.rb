# frozen_string_literal: true

require 'rails_helper'

# PRD-20260828-checkout-p7 AC-001/002/003：拆单/组合支付子订单售后退款
# 子订单无本地 payment（资金在组合 payment，经 PaymentSplit 关联）→ 退款挂组合 payment + 更新 split.refunded_amount。
RSpec.describe PallasTrade::ReimbursementType::OriginalPayment, type: :model do
  let!(:store) { create(:store, code: 'orig_payment_child_store') }
  let(:user) { create(:user) }
  let(:payment_method) { create(:bogus_payment_method, name: 'Card', store: store) }

  # 子订单：completed + 2 个 shipped inventory_units（各 10），无本地 payment（组合支付成员）
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

  describe 'AC-001 child order refund via combined payment' do
    it 'creates a refund on the combined payment and updates split.refunded_amount' do
      reimbursement.save!
      expect { reimbursement.perform! }.not_to raise_error

      expect(reimbursement.reload).to be_reimbursed
      refund = reimbursement.refunds.first
      expect(refund).to be_present
      expect(refund.payment).to eq(payment)
      expect(refund.payment.order_id).to be_nil

      expect(split.reload.refunded_amount).to eq(BigDecimal('10'))
      expect(child.reload.payment_total.to_f).to eq(0.0)
    end

    it 'does not create duplicate refunds on repeat reimbursement' do
      reimbursement.save!
      reimbursement.perform!

      first_count = reimbursement.reload.refunds.count
      # 再次执行 ReimbursementPerformer（unpaid 已为 0）不会创建新 refund
      PallasTrade::ReimbursementPerformer.perform(reimbursement.reload)
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
    it 'caps the refund at split.captured - refunded and leaves unpaid remainder' do
      # 两个 shipped units（20），但 split 只捕获 10 → 退款被截断到 10，剩余 10 无法退款
      second_unit = child.inventory_units.shipped.second
      second_item = create(:return_item, inventory_unit: second_unit, return_authorization: ra)
      second_item.accept!
      cr.return_items << second_item

      reimbursement.save!
      expect { reimbursement.perform! }.to raise_error(PallasTrade::Reimbursement::IncompleteReimbursementError)

      refund = reimbursement.reload.refunds.first
      expect(refund.amount.to_f).to eq(10.0)
      expect(split.reload.refunded_amount).to eq(BigDecimal('10'))
      # 剩余 10 无法从 split 退 → 保持未退
      expect(reimbursement.reload.paid_amount.to_f).to eq(10.0)
      expect(reimbursement.reload).to be_errored
    end
  end
end
