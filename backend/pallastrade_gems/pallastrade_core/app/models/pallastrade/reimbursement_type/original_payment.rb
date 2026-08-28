class PallasTrade::ReimbursementType::OriginalPayment < PallasTrade::ReimbursementType
  extend PallasTrade::ReimbursementType::ReimbursementHelpers

  class << self
    def reimburse(reimbursement, return_items, simulate)
      unpaid_amount = return_items.map { |ri| ri.total.to_d.round(2) }.sum
      order = reimbursement.order
      payments = order.payments.completed

      # P7 (2026-08-28)：拆单/组合支付子订单无本地 payment（资金在组合/共享 payment，经 PaymentSplit 关联）
      # → 从 payment_splits 定位关联 payment 退款，且退款上限按 split 未退部分（captured - refunded）。
      credit_limits = {}
      if payments.empty?
        splits = order.payment_splits.includes(:payment).order(:id)
        payments = splits.filter_map(&:payment).uniq
        splits.each { |split| credit_limits[split.payment_id] = (split.captured_amount.to_f - split.refunded_amount.to_f) }
      end

      reimbursement_list, unpaid_amount = create_refunds(reimbursement, payments, unpaid_amount, simulate, [], credit_limits)
      reimbursement_list
    end
  end
end
