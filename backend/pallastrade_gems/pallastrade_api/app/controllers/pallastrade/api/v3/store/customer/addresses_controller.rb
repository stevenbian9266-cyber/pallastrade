module PallasTrade
  module Api
    module V3
      module Store
        module Customer
          class AddressesController < ResourceController
            prepend_before_action :require_authentication!
            before_action :set_resource, only: [:show, :update, :destroy]

            # POST /api/v3/store/customers/me/addresses
            def create
              result = PallasTrade.address_create_service.call(
                address_params: permitted_params,
                user: current_user
              )

              if result.success?
                render json: serialize_resource(result.value), status: :created
              else
                render_errors(result.value.errors)
              end
            end

            # PATCH /api/v3/store/customers/me/addresses/:id
            def update
              result = PallasTrade.address_update_service.call(
                address: @resource,
                address_params: permitted_params
              )

              if result.success?
                render json: serialize_resource(result.value)
              else
                render_errors(result.value.errors)
              end
            end

            # DELETE /api/v3/store/customers/me/addresses/:id
            # Unlike the generic ResourceController#destroy (which pre-checks
            # can_be_deleted? and 422s when the address is referenced by any
            # shipment — including transient cart/draft orders), we delegate to
            # PallasTrade::Address#destroy, which soft-deletes (sets deleted_at)
            # when the address is referenced by completed orders or shipments,
            # and hard-deletes otherwise. This lets customers remove addresses
            # that were used in abandoned carts / draft orders (the cart row is
            # preserved for checkout history; only the address-book entry goes
            # away). Matches the admin AddressesController#destroy behavior.
            def destroy
              @resource.destroy
              head :no_content
            end

            protected

            def set_parent
              @parent = current_user
            end

            def parent_association
              :addresses
            end

            def model_class
              PallasTrade::Address
            end

            def serializer_class
              PallasTrade.api.address_serializer
            end

            def permitted_params
              params.permit(
                :first_name, :last_name, :address1, :address2, :city,
                :postal_code, :phone, :company, :country_iso, :state_abbr, :state_name,
                :is_default_billing, :is_default_shipping
              )
            end
          end
        end
      end
    end
  end
end
