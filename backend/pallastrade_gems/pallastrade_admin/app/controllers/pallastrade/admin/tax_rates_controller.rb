module PallasTrade
  module Admin
    class TaxRatesController < ResourceController
      include PallasTrade::Admin::SettingsConcern
      add_breadcrumb PallasTrade.t(:tax_rates), :admin_tax_rates_path

      before_action :load_data
      before_action :set_defaults, only: :new

      private

      def set_defaults
        @object.calculator_type = 'PallasTrade::Calculator::DefaultTax'
      end

      def load_data
        @available_zones = PallasTrade::Zone.order(:name)
        @available_categories = PallasTrade::TaxCategory.order(:name)
        @calculators = PallasTrade::TaxRate.calculators.sort_by(&:name)
      end

      def permitted_resource_params
        params.require(:tax_rate).permit(permitted_tax_rate_attributes)
      end
    end
  end
end
