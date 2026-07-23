module PallasTrade
  module Api
    module V2
      module Platform
        class PaymentSourceSerializer < BaseSerializer
          belongs_to :payment_method, serializer: PallasTrade.api.platform_payment_method_serializer
          belongs_to :user, serializer: PallasTrade.api.platform_user_serializer
        end
      end
    end
  end
end
