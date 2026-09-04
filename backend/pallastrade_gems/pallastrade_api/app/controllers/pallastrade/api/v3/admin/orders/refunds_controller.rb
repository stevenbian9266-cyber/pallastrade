module PallasTrade
  module Api
    module V3
      module Admin
        module Orders
          class RefundsController < BaseController
            scoped_resource :refunds

            # POST /api/v3/admin/orders/:order_id/refunds
            def create
              with_order_lock do
                payment = @parent.payments.accessible_by(current_ability, :update).find_by_prefix_id!(params[:payment_id])
                reason = PallasTrade::RefundReason.accessible_by(current_ability, :show).find_by_prefix_id!(params[:refund_reason_id]) if params[:refund_reason_id].present?
                reason ||= PallasTrade::RefundReason.accessible_by(current_ability, :show).first

                @resource = payment.refunds.build(
                  amount: params[:amount],
                  reason: reason,
                  transaction_id: nil
                )
                authorize_resource!(@resource, :create)

                if @resource.save
                  # P0-6 (PRD FR-064): Refund 敏感操作审计。
                  PallasTrade::Audit.record(
                    actor: (respond_to?(:current_admin_user) ? current_admin_user : 'admin'),
                    action: 'refund',
                    resource: @resource,
                    after: {
                      payment_id: payment.prefixed_id,
                      amount: @resource.amount.to_s,
                      reason_id: reason&.prefixed_id,
                      currency: @resource.currency
                    }
                  )
                  render json: serialize_resource(@resource), status: :created
                else
                  render_validation_error(@resource.errors)
                end
              end
            end

            protected

            def model_class
              PallasTrade::Refund
            end

            def serializer_class
              PallasTrade.api.admin_refund_serializer
            end

            def scope
              PallasTrade::Refund.where(payment_id: @parent.payment_ids)
            end

            def collection_includes
              [:payment, :reason]
            end
          end
        end
      end
    end
  end
end
