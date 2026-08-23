# PALLAS-CUSTOM: 多订单合并支付（PRD-20260823-checkout-多订单拆分与合并支付）
#
# Completes every unpaid member order of a payment group after a successful
# payment. Idempotent: already-paid/completed orders are skipped, and the
# group/session transitions only fire when possible — safe for duplicate
# webhooks and job retries.
module PallasTrade
  module PaymentGroups
    class Complete
      prepend PallasTrade::ServiceModule::Base

      # @param payment_group [PallasTrade::PaymentGroup]
      # @param payment_session [PallasTrade::PaymentSession] the successfully
      #   paid session that covers the group
      # @return [ServiceResult<PallasTrade::PaymentGroup>]
      def call(payment_group:, payment_session:)
        ApplicationRecord.transaction do
          payment_group.orders.each do |order|
            next if (order.completed? && order.paid?) || order.canceled?

            order.with_lock do
              next if (order.reload.completed? && order.paid?) || order.canceled?

              payment = payment_session.find_or_create_payment_for_order!(order)
              payment.confirm! if payment.present? && !payment.completed?

              unless order.reload.completed?
                PallasTrade::Dependencies.carts_complete_service.constantize.call(cart: order)
              end
            end
          end

          payment_session.complete if payment_session.can_complete?

          payment_group.reload
          payment_group.completed_at ||= Time.current
          payment_group.complete if payment_group.can_complete?

          success(payment_group)
        end
      rescue StandardError => e
        Rails.error.report(e, context: { payment_group_id: payment_group.id }, source: 'PallasTrade.payment_group.complete')
        failure(payment_group, e.message)
      end
    end
  end
end
