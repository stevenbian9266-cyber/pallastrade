# frozen_string_literal: true

# Order lifecycle P4 (2026-08-27): combined-payment carrier services.
# A PaymentCombinations::Create 在支付发生前为每个成员订单创建 PaymentSplit
# （此时尚未产生 Payment 记录），payment_id 需要在组合支付完成后才回填，
# 因此将 payment_id 改为可空。单订单 / P2 拆单分摊场景不受影响（payment 始终存在）。
class ChangePaymentNullableOnPallasTradePaymentSplits < ActiveRecord::Migration[8.1]
  def change
    change_column_null :pallastrade_payment_splits, :payment_id, true
  end
end
