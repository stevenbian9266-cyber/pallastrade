module PallasTrade
  module Api
    module V2
      module Platform
        class CustomerReturnSerializer < BaseSerializer
          include ResourceSerializerConcern

          belongs_to :stock_location, serializer: PallasTrade.api.platform_stock_location_serializer

          has_many :reimbursements, serializer: PallasTrade.api.platform_reimbursement_serializer
          has_many :return_items, serializer: PallasTrade.api.platform_return_item_serializer
          has_many :return_authorizations, serializer: PallasTrade.api.platform_return_authorization_serializer
        end
      end
    end
  end
end
