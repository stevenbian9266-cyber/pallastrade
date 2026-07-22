module PallasTrade
  module Api
    module V2
      module Platform
        class DataFeedsController < ResourceController
          private

          def model_class
            PallasTrade::DataFeed
          end

          def resource_serializer
            PallasTrade.api.platform_data_feed_serializer
          end
        end
      end
    end
  end
end
