module PallasTrade
  module Admin
    module Orders
      class PaymentLinksController < PallasTrade::Admin::BaseController
        include PallasTrade::Admin::OrderConcern

        before_action :load_order
        before_action :ensure_frontend_available

        def create
          recipient_email = @order.user&.email || @order.email

          if recipient_email.present?
            PallasTrade::OrderMailer.payment_link_email(@order.id).deliver_later
            flash[:success] = PallasTrade.t('admin.orders.payment_link_sent')
          else
            flash[:error] = PallasTrade.t('admin.orders.no_email_present')
          end

          redirect_back fallback_location: PallasTrade.edit_admin_order_url(@order)
        end

        private

        def ensure_frontend_available
          unless PallasTrade::Core::Engine.frontend_available? && PallasTrade.respond_to?(:checkout_state_url)
            redirect_to PallasTrade.edit_admin_order_url(@order)
          end
        end
      end
    end
  end
end
