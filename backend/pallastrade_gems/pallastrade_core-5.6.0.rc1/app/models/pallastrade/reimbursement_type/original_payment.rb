class PallasTrade::ReimbursementType::OriginalPayment < PallasTrade::ReimbursementType
  extend PallasTrade::ReimbursementType::ReimbursementHelpers

  class << self
    def reimburse(reimbursement, return_items, simulate)
      unpaid_amount = return_items.map { |ri| ri.total.to_d.round(2) }.sum
      payments = reimbursement.order.payments.completed

      reimbursement_list, unpaid_amount = create_refunds(reimbursement, payments, unpaid_amount, simulate)
      reimbursement_list
    end
  end
end
