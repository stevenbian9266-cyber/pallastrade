module PallasTrade
  module Admin
    class ReturnAuthorizationsController < ResourceController
      add_breadcrumb_icon 'receipt-refund'
      add_breadcrumb PallasTrade.t(:returns), :admin_customer_returns_path

      def index; end

      def cancel
        @return_authorization.cancel!
        flash[:success] = PallasTrade.t(:return_authorization_canceled)
        redirect_back fallback_location: PallasTrade.edit_admin_order_path(@return_authorization.order)
      end

      private

      def permitted_resource_params
        params.require(:return_authorization).permit(permitted_return_authorization_attributes)
      end

      def location_after_destroy
        PallasTrade.edit_admin_order_path(@return_authorization.order)
      end
    end
  end
end
