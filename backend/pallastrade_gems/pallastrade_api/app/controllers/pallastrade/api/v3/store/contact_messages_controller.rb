module PallasTrade
  module Api
    module V3
      module Store
        # POST /api/v3/store/contact_messages — submit a complaint, feedback or
        # inquiry from the storefront. Guest-accessible; classified by kind and
        # surfaced in the admin Email → Inbox & Feedback page.
        class ContactMessagesController < Store::BaseController
          allow_guest_storefront_access!

          # POST /api/v3/store/contact_messages
          def create
            message = current_store.contact_messages.new(contact_message_params)

            if message.save
              render json: serialize_resource(message), status: :created
            else
              render_errors(message.errors)
            end
          end

          protected

          def serializer_class
            PallasTrade::Api::V3::ContactMessageSerializer
          end

          private

          def contact_message_params
            params.require(:contact_message).permit(
              :kind, :name, :email, :subject, :body
            )
          end
        end
      end
    end
  end
end
