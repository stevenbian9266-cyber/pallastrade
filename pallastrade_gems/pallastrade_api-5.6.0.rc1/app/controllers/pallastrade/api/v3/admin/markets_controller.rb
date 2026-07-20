module PallasTrade
  module Api
    module V3
      module Admin
        # Admin Markets surface. Markets are store-scoped (`store_id` column +
        # `acts_as_list scope: :store_id`), so the base ResourceController's
        # `scope` chain narrows appropriately when we restrict to
        # `current_store.markets`.
        #
        # `country_isos` and `supported_locales` are accepted as arrays on the
        # wire and translated by model setters (`PallasTrade::Market#country_isos=`,
        # `#supported_locales=`).
        class MarketsController < ResourceController
          scoped_resource :settings

          protected

          def model_class
            PallasTrade::Market
          end

          def serializer_class
            PallasTrade.api.admin_market_serializer
          end

          def collection_includes
            [:countries]
          end

          def permitted_params
            normalize_params(
              params.permit(
                :name, :currency, :default_locale, :tax_inclusive,
                :default, :position, supported_locales: [], country_isos: []
              )
            )
          end
        end
      end
    end
  end
end
