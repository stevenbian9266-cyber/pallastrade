module PallasTrade
  module Api
    module V2
      module Storefront
        module Stripe
          class PaymentIntentsController < BaseController
            include PallasTrade::Api::V2::Storefront::OrderConcern
            before_action :ensure_order, except: [:confirm]

            # POST /api/v2/storefront/stripe/payment_intents
            def create
              PALLASTRADE_authorize! :update, PALLASTRADE_current_order, order_token

              stripe_payment_method_id = permitted_attributes[:stripe_payment_method_id].presence
              stripe_payment_method_id ||= PallasTrade::CreditCard.where(
                id: PALLASTRADE_current_order.payments.from_credit_card.valid.select(:source_id),
                payment_method: stripe_gateway
              ).first&.gateway_payment_profile_id

              @payment_intent = SpreeStripe::CreatePaymentIntent.new.call(
                PALLASTRADE_current_order,
                stripe_gateway,
                stripe_payment_method_id: stripe_payment_method_id,
                off_session: permitted_attributes[:off_session].to_b || false
              )

              render_serialized_payload { serialize_resource(@payment_intent) }
            end

            # GET /api/v2/storefront/stripe/payment_intents
            def show
              PALLASTRADE_authorize! :show, PALLASTRADE_current_order, order_token

              @payment_intent = PALLASTRADE_current_order.payment_intents.find(params[:id])

              render_serialized_payload { serialize_resource(@payment_intent) }
            end

            # PATCH /api/v2/storefront/stripe/payment_intents/:id
            def update
              PALLASTRADE_authorize! :update, PALLASTRADE_current_order, order_token

              @payment_intent = PALLASTRADE_current_order.payment_intents.find(params[:id])
              @payment_intent.attributes = permitted_attributes.except(:off_session)
              @payment_intent.save!

              render_serialized_payload { serialize_resource(@payment_intent) }
            end

            def confirm
              @payment_intent = SpreeStripe::PaymentIntent.find(params[:id])

              stripe_payment_intent = @payment_intent.stripe_payment_intent
              order = @payment_intent.order

              if order.canceled?
                render_error_payload(PallasTrade.t('order_canceled'))
              elsif order.completed?
                render_error_payload(PallasTrade.t('order_already_completed'))
              elsif order != PALLASTRADE_current_order
                raise ActiveRecord::RecordNotFound
              elsif @payment_intent.accepted?
                PALLASTRADE_authorize! :update, PALLASTRADE_current_order, order_token

                SpreeStripe::CompleteOrder.new(payment_intent: @payment_intent).call

                render_serialized_payload { serialize_resource(@payment_intent) }
              else
                render_error_payload(PallasTrade.t("stripe.payment_intent_errors.#{stripe_payment_intent.status}"))
              end
            rescue PallasTrade::Core::GatewayError => e
              render_error_payload(e.message)
            end

            private

            def permitted_attributes
              params.require(:payment_intent).permit(:amount, :stripe_payment_method_id, :off_session)
            end

            def resource_serializer
              PallasTrade::V2::Storefront::PaymentIntentSerializer
            end
          end
        end
      end
    end
  end
end
