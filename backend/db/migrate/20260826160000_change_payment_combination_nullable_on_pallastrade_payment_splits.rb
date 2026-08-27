# frozen_string_literal: true

# PALLAS-CUSTOM: P2 统一拆单引擎（PRD-20260826）
# PaymentSplit 允许「尚未归入组合」的记账分摊（拆单时先记账，P4 合并支付再归入组合）。
class ChangePaymentCombinationNullableOnPallasTradePaymentSplits < ActiveRecord::Migration[8.1]
  def change
    change_column_null :pallastrade_payment_splits, :payment_combination_id, true
  end
end
