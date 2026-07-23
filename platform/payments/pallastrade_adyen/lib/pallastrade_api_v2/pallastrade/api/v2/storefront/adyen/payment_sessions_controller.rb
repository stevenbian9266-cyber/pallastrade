module PallasTrade
  module Api
    module V2
      module Storefront
        module Adyen
          class PaymentSessionsController < BaseController
            include PallasTrade::Api::V2::Storefront::OrderConcern
            before_action :ensure_order
            before_action :load_payment_session, only: %i[show complete]

            # POST /api/v2/storefront/adyen/payment_sessions
            def create
              pallastrade_authorize! :update, pallastrade_current_order, order_token

              payment_session_result = PallasTradeAdyen::PaymentSessions::FindOrCreate.new(
                order: pallastrade_current_order,
                amount: permitted_attributes[:amount],
                user: pallastrade_current_user,
                payment_method: adyen_gateway,
                channel: permitted_attributes[:channel],
                return_url: permitted_attributes[:return_url]
              ).call

              if payment_session_result.success?
                render_serialized_payload { serialize_resource(payment_session_result.value) }
              else
                error = payment_session_result.value&.errors || payment_session_result.error.value
                render_error_payload(error)
              end
            end

            # POST /api/v2/storefront/adyen/payment_sessions/:id/complete
            def complete
              pallastrade_authorize! :update, pallastrade_current_order, order_token

              PallasTradeAdyen::PaymentSessions::ProcessWithResult.new(payment_session: @payment_session, session_result: params[:session_result]).call

              if @payment_session.completed?
                render_serialized_payload { serialize_resource(@payment_session) }
              else
                render_error_payload("Can't complete the order for the payment session in the #{@payment_session.status} state")
              end
            rescue PallasTrade::Core::GatewayError => e
              render_error_payload(e.message, :unprocessable_entity)
            end

            # GET /api/v2/storefront/adyen/payment_sessions/:id
            def show
              pallastrade_authorize! :show, pallastrade_current_order, order_token

              render_serialized_payload { serialize_resource(@payment_session) }
            end

            private

            def permitted_attributes
              params.require(:payment_session).permit(:amount, :channel, :return_url)
            end

            def resource_serializer
              PallasTradeAdyen::Api::V2::Storefront::PaymentSessionSerializer
            end

            def load_payment_session
              @payment_session = pallastrade_current_order.adyen_payment_sessions.find(params[:id])
            end
          end
        end
      end
    end
  end
end
