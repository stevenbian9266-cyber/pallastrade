module PallasTrade
  module Api
    module V3
      module Admin
        class StockReservationsController < ResourceController
          scoped_resource :stock

          protected

          def model_class
            PallasTrade::StockReservation
          end

          def serializer_class
            PallasTrade.api.admin_stock_reservation_serializer
          end

          def scope
            PallasTrade::StockReservation.for_store(current_store).accessible_by(current_ability, ability_action_for_request)
          end

          def collection_includes
            [{ stock_item: [:variant, :stock_location], line_item: [], order: [] }]
          end
        end
      end
    end
  end
end
