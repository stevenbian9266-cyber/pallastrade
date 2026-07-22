module PallasTrade
  module Api
    module V2
      module Platform
        class PaymentCaptureEventSerializer < BaseSerializer
          include ResourceSerializerConcern

          belongs_to :payment, serializer: PallasTrade.api.platform_payment_serializer
        end
      end
    end
  end
end
