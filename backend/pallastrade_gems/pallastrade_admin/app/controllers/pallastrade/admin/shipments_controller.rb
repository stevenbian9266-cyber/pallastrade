module PallasTrade
  module Admin
    class ShipmentsController < PallasTrade::Admin::ResourceController
      include PallasTrade::Admin::StockLocationsHelper

      layout 'turbo_rails/frame'

      belongs_to 'pallastrade/order', find_by: :prefix_id

      before_action :load_variant, only: [:split, :transfer]
      before_action :refresh_shipping_rates, only: :edit

      def update
        @result = PallasTrade.shipment_update_service.call(shipment: @shipment, shipment_attributes: permitted_resource_params)
        flash[:success] = PallasTrade.t(:successfully_updated, resource: PallasTrade.t(:shipment)) if @result.success?

        redirect_back fallback_location: PallasTrade.edit_admin_order_path(@order)
      end

      def ship
        if @shipment.shippable? && @shipment.ship
          flash[:success] = PallasTrade.t(:shipment_successfully_shipped)
        else
          flash[:error] = PallasTrade.t(:cannot_ship)
        end

        redirect_back fallback_location: PallasTrade.edit_admin_order_path(@order)
      end

      def split
        @max_quantity = @shipment.inventory_units.where(variant_id: @variant.id).sum(:quantity)
      end

      def transfer
        destination_name, destination_id = params[:destination].split('_')
        quantity = params[:quantity]&.to_i || 1

        errors = []
        errors << "#{PallasTrade.t(:quantity)} #{PallasTrade.t('validation.is_too_large')}" if quantity <= 0

        transfer = nil

        case destination_name
        when 'stock-location'
          destination = available_stock_locations.find(destination_id)
          transfer = @shipment.transfer_to_location(@variant, quantity, destination)
        when 'shipment'
          destination = parent.shipments.
                        where(stock_location: available_stock_locations).
                        find(destination_id)
          transfer = @shipment.transfer_to_shipment(@variant, quantity, destination)
        end

        errors << PallasTrade.t('admin.shipment_transfer.wrong_destination') if transfer.nil?

        if errors.any?
          flash[:error] = errors.to_sentence
          return redirect_back(fallback_location: PallasTrade.edit_admin_order_path(@order))
        end

        if transfer.valid? && transfer.run!
          flash[:success] = PallasTrade.t(:shipment_transfer_success)
        else
          flash[:error] = transfer.errors.full_messages.to_sentence
        end

        redirect_back(fallback_location: PallasTrade.edit_admin_order_path(@order))
      end

      private

      def refresh_shipping_rates
        unless @order.completed?
          ActiveRecord::Base.connected_to(role: :writing) do
            @order.refresh_shipment_rates(ShippingMethod::DISPLAY_ON_BACK_END)
          end
        end
      end

      def model_class
        PallasTrade::Shipment
      end

      def find_resource
        record = parent.shipments.find_by_prefix_id!(params[:id])
        authorize! action, record
      end

      def collection_url
        PallasTrade.edit_admin_order_path(@order)
      end

      def load_variant
        @variant = current_store.variants.accessible_by(current_ability, :manage).find_by_prefix_id!(params[:variant_id])
      end

      def permitted_resource_params
        params.require(:shipment).permit(permitted_shipment_attributes)
      end
    end
  end
end
