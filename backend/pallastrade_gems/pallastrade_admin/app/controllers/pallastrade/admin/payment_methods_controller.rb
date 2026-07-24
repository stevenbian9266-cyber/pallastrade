module PallasTrade
  module Admin
    class PaymentMethodsController < ResourceController
      include PallasTrade::Admin::PreferencesConcern
      include PallasTrade::Admin::SettingsConcern

      prepend_before_action :require_payment_type, only: [:new, :create]
      before_action -> { clear_empty_password_preferences(:payment_method) }, only: :update
      before_action :set_breadcrumb, only: :edit

      private

      def build_resource
        if params[:payment_method].present?
          payment_type = params[:payment_method].delete(:type)
          # Find the actual class from our allowed types rather than using constantize
          payment_class = allowed_payment_types.find { |type| type == payment_type }

          if payment_class.present?
            @object = payment_class.constantize.new
          end
        end
      end

      def require_payment_type
        redirect_to PallasTrade.admin_payment_methods_path unless params.dig(:payment_method, :type).present?
      end

      def set_breadcrumb
        add_breadcrumb @payment_method.name, PallasTrade.edit_admin_payment_method_path(@payment_method)
      end

      def allowed_payment_types
        # We need to map to strings, otherwise some weird things happen with STI
        # where Rails can't find the ancestor class when we try to save the payment method.
        PallasTrade.payment_methods.map(&:to_s)
      end

      def permitted_resource_params
        params.require(:payment_method).permit(permitted_payment_method_attributes + @object.preferences.keys.map { |key| "preferred_#{key}" })
      end
    end
  end
end
