module PallasTrade
  module Admin
    module PaymentsHelper
      def payment_method_name(payment)
        return unless payment.payment_method.present?

        payment_method = payment.payment_method

        if can?(:update, payment_method)
          link_to payment_method.name, PallasTrade.edit_admin_payment_method_path(payment_method)
        else
          payment_method.name
        end
      end

      def available_payment_methods
        @available_payment_methods ||= PallasTrade::PaymentMethod.providers.map { |provider| provider.name.constantize.new }.delete_if { |payment_method| !payment_method.show_in_admin? || current_store.payment_methods.pluck(:type).include?(payment_method.type) }.sort_by(&:name)
      end
    end
  end
end
