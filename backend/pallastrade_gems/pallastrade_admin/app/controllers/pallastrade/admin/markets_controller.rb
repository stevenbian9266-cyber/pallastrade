module PallasTrade
  module Admin
    class MarketsController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      add_breadcrumb PallasTrade.t(:markets), :admin_markets_path

      before_action :load_data, except: :index
      before_action :normalize_supported_locales, only: [:create, :update]

      protected

      def load_data
        @countries = current_store.countries_with_shipping_coverage

        # Exclude countries already assigned to other markets in the store
        if @object&.persisted?
          taken_country_ids = PallasTrade::MarketCountry.joins(:market)
                                .where(pallastrade_markets: { store_id: current_store.id, deleted_at: nil })
                                .where.not(market_id: @object.id)
                                .pluck(:country_id)
        else
          taken_country_ids = PallasTrade::MarketCountry.joins(:market)
                                .where(pallastrade_markets: { store_id: current_store.id, deleted_at: nil })
                                .pluck(:country_id)
        end

        @countries = @countries.where.not(id: taken_country_ids) if taken_country_ids.any?
      end

      def permitted_resource_params
        params.require(:market).permit(permitted_market_attributes)
      end

      private

      def normalize_supported_locales
        if params.dig(:market, :supported_locales)&.is_a?(Array)
          params[:market][:supported_locales] = params[:market][:supported_locales].compact.uniq.reject(&:blank?).join(',')
        end
      end
    end
  end
end
