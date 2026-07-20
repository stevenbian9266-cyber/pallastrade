module PallasTrade
  module Admin
    module Orders
      class ContactInformationController < PallasTrade::Admin::BaseController
        include PallasTrade::Admin::OrderConcern

        before_action :load_order

        def edit; end

        def update
          if PallasTrade::Orders::UpdateContactInformation.call(order: @order, order_params: order_params).success?
            unless @order.completed?
              max_state = if @order.ship_address.present?
                            @order.ensure_updated_shipments
                            'payment'
                          else
                            'address'
                          end

              result = PallasTrade.checkout_advance_service.call(order: @order, state: max_state)

              unless result.success?
                flash[:error] = result.error.value.full_messages.to_sentence
                @order.ensure_updated_shipments
                return redirect_to PallasTrade.edit_admin_order_path(@order)
              end
            end

            flash[:success] = PallasTrade.t(:successfully_updated, resource: PallasTrade.t(:contact_information))
            redirect_to PallasTrade.edit_admin_order_path(@order)
          else
            render :edit
          end
        end

        private

        def order_params
          params.require(:order).permit(:email)
        end
      end
    end
  end
end
