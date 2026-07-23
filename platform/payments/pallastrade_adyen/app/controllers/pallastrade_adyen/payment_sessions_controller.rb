# this is the endpoint that Adyen JS SDK will redirect customer to after payment
# it will handle the payment session status and process the payment

module PallasTradeAdyen
  class PaymentSessionsController < defined?(PallasTrade::StoreController) ? PallasTrade::StoreController : PallasTrade::BaseController
    include PallasTrade::CheckoutAnalyticsHelper if defined?(PallasTrade::CheckoutAnalyticsHelper)

    # GET /adyen/payment_sessions/redirect
    def redirect
      @payment_session = PallasTradeAdyen::PaymentSession.find_by(adyen_id: params[:sessionId])
      render layout: 'pallastrade_adyen/default'
    end

    # GET /adyen/payment_sessions
    def show
      @payment_session = PallasTradeAdyen::PaymentSession.find_by!(adyen_id: params[:sessionId])
      @order = @payment_session.order
      # handle duplicated requests or already processed through webhook
      if @payment_session.canceled? || @order.canceled?
        redirect_to pallastrade.cart_path, status: :see_other
        return
      elsif @order.completed?
        redirect_to pallastrade.checkout_complete_path(@order.token), status: :see_other
        return
      end

      PallasTradeAdyen::PaymentSessions::ProcessWithResult.new(payment_session: @payment_session, session_result: params[:sessionResult]).call

      if @payment_session.completed?
        handle_success
      elsif @payment_session.pending?
        handle_pending_payment
      elsif @payment_session.canceled?
        redirect_to pallastrade.checkout_path(@order.token), status: :see_other
      elsif @payment_session.refused?
        handle_failure
      end
    rescue PallasTrade::Core::GatewayError => e
      handle_failure(e.message)
    end

    private

    # TODO: handle pending payment
    def handle_pending_payment; end

    def handle_success
      # update the payment session status

      # set the session flag to indicate that the order was placed now
      track_checkout_completed if @order.completed? && defined?(track_checkout_completed)

      redirect_to pallastrade.checkout_complete_path(@order.token), status: :see_other
    end

    def handle_failure(message = nil)
      flash[:error] = message || PallasTrade.t("adyen.payment_session_errors.#{@payment_session.status}")

      Rails.logger.error("Payment failed for order #{@order.id}: #{@payment_session.status}")

      # this should be a rare race condition, but we need to handle it
      @order.payments.valid.find_by(response_code: @payment_session.id)&.void!

      redirect_to pallastrade.checkout_path(@order.token), status: :see_other
    end
  end
end
