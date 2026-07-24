module PallasTrade
  module Admin
    class RefundsController < ResourceController
      include PallasTrade::Admin::OrderBreadcrumbConcern

      belongs_to 'pallastrade/payment', find_by: :prefix_id

      before_action :load_order
      before_action :assign_refunder, only: :create

      helper_method :refund_reasons

      rescue_from PallasTrade::Core::GatewayError, with: :pallastrade_core_gateway_error

      private

      def location_after_save
        PallasTrade.edit_admin_order_path(@payment.order)
      end

      def load_order
        @order = @payment.order if @payment

        add_breadcrumb @order.number, PallasTrade.edit_admin_order_path(@order)
      end

      def refund_reasons
        @refund_reasons ||= RefundReason.active.all
      end

      def build_resource
        super.tap do |refund|
          refund.amount = refund.payment.credit_allowed
        end
      end

      def pallastrade_core_gateway_error(error)
        flash[:error] = error.message
        render :new
      end

      def assign_refunder
        @refund.refunder = try_pallastrade_current_user
      end

      def permitted_resource_params
        params.require(:refund).permit(permitted_refund_attributes)
      end
    end
  end
end
