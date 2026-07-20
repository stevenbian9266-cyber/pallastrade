module PallasTrade
  module DefaultPrice
    extend ActiveSupport::Concern

    DEPRECATION_MSG = 'PallasTrade::DefaultPrice is deprecated and will be removed in Spree 6.0. ' \
      'Use variant.set_price(currency, amount) and variant.price_in(currency) instead.'

    included do
      has_one :default_price,
              -> { with_deleted.where(currency: PallasTrade::Store.default.default_currency) },
              class_name: 'PallasTrade::Price',
              dependent: :destroy

      after_save :save_default_price, if: -> { PallasTrade::Config.enable_legacy_default_price }

      def price
        PallasTrade::Deprecation.warn(PallasTrade::DefaultPrice::DEPRECATION_MSG)
        if PallasTrade::Config.enable_legacy_default_price
          find_or_build_default_price.price
        else
          price_in(PallasTrade::Store.default.default_currency).amount
        end
      end

      def price=(value)
        PallasTrade::Deprecation.warn(PallasTrade::DefaultPrice::DEPRECATION_MSG)
        if PallasTrade::Config.enable_legacy_default_price
          find_or_build_default_price.price = value
        else
          set_price(PallasTrade::Store.default.default_currency, value)
        end
      end

      def currency
        PallasTrade::Deprecation.warn(PallasTrade::DefaultPrice::DEPRECATION_MSG)
        if PallasTrade::Config.enable_legacy_default_price
          find_or_build_default_price.currency
        else
          PallasTrade::Store.default.default_currency
        end
      end

      def currency=(value)
        PallasTrade::Deprecation.warn(PallasTrade::DefaultPrice::DEPRECATION_MSG)
        if PallasTrade::Config.enable_legacy_default_price
          find_or_build_default_price.currency = value
        end
        # no-op when legacy is disabled — currency is determined by the store
      end

      def display_price
        PallasTrade::Deprecation.warn(PallasTrade::DefaultPrice::DEPRECATION_MSG)
        if PallasTrade::Config.enable_legacy_default_price
          find_or_build_default_price.display_price
        else
          price_in(PallasTrade::Store.default.default_currency).display_amount
        end
      end

      def display_amount
        PallasTrade::Deprecation.warn(PallasTrade::DefaultPrice::DEPRECATION_MSG)
        if PallasTrade::Config.enable_legacy_default_price
          find_or_build_default_price.display_amount
        else
          price_in(PallasTrade::Store.default.default_currency).display_amount
        end
      end

      def compare_at_price
        PallasTrade::Deprecation.warn(PallasTrade::DefaultPrice::DEPRECATION_MSG)
        if PallasTrade::Config.enable_legacy_default_price
          find_or_build_default_price.compare_at_price
        else
          price_in(PallasTrade::Store.default.default_currency).compare_at_amount
        end
      end

      def compare_at_price=(value)
        PallasTrade::Deprecation.warn(PallasTrade::DefaultPrice::DEPRECATION_MSG)
        if PallasTrade::Config.enable_legacy_default_price
          find_or_build_default_price.compare_at_price = value
        else
          default_currency = PallasTrade::Store.default.default_currency
          price_record = price_in(default_currency)
          price_record.compare_at_amount = value
          price_record.save! if price_record.persisted?
        end
      end

      def display_compare_at_price
        PallasTrade::Deprecation.warn(PallasTrade::DefaultPrice::DEPRECATION_MSG)
        if PallasTrade::Config.enable_legacy_default_price
          find_or_build_default_price.display_compare_at_price
        else
          price_in(PallasTrade::Store.default.default_currency).display_compare_at_amount
        end
      end

      def price_including_vat_for(price_options)
        PallasTrade::Deprecation.warn(PallasTrade::DefaultPrice::DEPRECATION_MSG)
        if PallasTrade::Config.enable_legacy_default_price
          find_or_build_default_price.price_including_vat_for(price_options)
        else
          price_in(PallasTrade::Store.default.default_currency).price_including_vat_for(price_options)
        end
      end

      def has_default_price?
        PallasTrade::Deprecation.warn(PallasTrade::DefaultPrice::DEPRECATION_MSG)
        if PallasTrade::Config.enable_legacy_default_price
          !default_price.nil?
        else
          prices.base_prices.any? { |p| p.currency == PallasTrade::Store.default.default_currency }
        end
      end

      def find_or_build_default_price
        PallasTrade::Deprecation.warn(PallasTrade::DefaultPrice::DEPRECATION_MSG)
        if PallasTrade::Config.enable_legacy_default_price
          default_price || build_default_price
        else
          prices.base_prices.find { |p| p.currency == PallasTrade::Store.default.default_currency } ||
            prices.build(currency: PallasTrade::Store.default.default_currency)
        end
      end

      private

      def default_price_changed?
        default_price && (default_price.changed? || default_price.new_record?)
      end

      def save_default_price
        default_price.save if default_price_changed?
      end
    end
  end
end
