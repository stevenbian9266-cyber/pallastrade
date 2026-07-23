module PallasTrade
  module Api
    module V2
      module Platform
        class OptionTypeSerializer < BaseSerializer
          include ResourceSerializerConcern

          has_many :option_values, serializer: PallasTrade.api.platform_option_value_serializer
        end
      end
    end
  end
end
