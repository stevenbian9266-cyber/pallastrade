# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-8h (PRD-20260908-payments-rev-p6-8h-orphan-amounts-payment-ops)
#
# Admin Payments Ops —— Payment 只读检视（Orders → Payments；含组合 payment order_id=nil）。
# index：store 作用域 completed PSP payments（经 order 或 combination 归属）；show：逐 payment 在线执行
# Refunds::OrphanPairing（只读配对，含孤儿金额 REV-P6-8h），异常降级 nil 不 500（8a ReconcileRefund 模式）。
# 不变式：零资金副作用、零 provider mutation、不自动退款（同 8d/Reconcile 只读哲学）。
module PallasTrade
  module Admin
    class PaymentsOpsController < ResourceController
      include PallasTrade::Admin::TableConcern

      # GET /admin/payments
      def index
        super
      end

      # GET /admin/payments/:id —— 隐式渲染（@payment）；show 在线跑一次 OrphanPairing
      def show
        @pairing = begin
          outcome = PallasTrade::Refunds::OrphanPairing.call(payment: @payment || @object)
          outcome.success? ? outcome.value : nil
        rescue StandardError
          nil
        end
      end

      private

      def model_class
        PallasTrade::Payment
      end

      def object_name
        'payment'
      end

      def scope
        base = PallasTrade::Payment.completed
                        .joins('LEFT JOIN pallastrade_orders o ON o.id = pallastrade_payments.order_id ' \
                               'LEFT JOIN pallastrade_payment_combinations pc ON pc.id = pallastrade_payments.payment_combination_id')
                        .where('o.store_id = :sid OR pc.store_id = :sid', sid: current_store.id)
                        .distinct
        base.order(id: :desc)
      end

      def collection_default_sort
        'id desc'
      end
    end
  end
end
