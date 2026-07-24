module PallasTrade
  module Cart
    class EstimateShippingRates
      prepend PallasTrade::ServiceModule::Base

      def call(order:, country_iso: nil)
        country_id = country_id(order.store, country_iso)
        dummy_order = generate_dummy_order(order, country_id)

        packages = ::PallasTrade::Stock::Coordinator.new(dummy_order).packages
        estimator = ::PallasTrade::Stock::Estimator.new(dummy_order)
        shipping_rates = if order.line_items.any? && packages.any?
                           estimator.shipping_rates(packages.first)
                         else
                           []
                         end

        success(shipping_rates)
      end

      private

      def country_id(store, country_iso)
        if country_iso.present?
          ::PallasTrade::Country.by_iso(country_iso)&.id
        else
          store.default_country_id
        end
      end

      def generate_dummy_order(order, country_id)
        dummy_order = order.dup
        dummy_order.line_items = order.line_items
        dummy_order.ship_address = ::PallasTrade::Address.new(country_id: country_id)
        dummy_order
      end
    end
  end
end
