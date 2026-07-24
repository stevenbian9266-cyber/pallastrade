module PallasTrade
  module Api
    module V3
      module Admin
        class CountrySerializer < V3::CountrySerializer
          attributes created_at: :iso8601, updated_at: :iso8601

          many :states,
               resource: proc { PallasTrade.api.admin_state_serializer },
               if: proc { params[:expand]&.include?('states') }
        end
      end
    end
  end
end
