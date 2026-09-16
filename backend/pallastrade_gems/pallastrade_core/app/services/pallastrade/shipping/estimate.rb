# frozen_string_literal: true

module PallasTrade
  module Shipping
    # Catalog F-2 (PRD-20260916-catalog-batch-f2-stock-shipping): the read model
    # behind the PDP "shipping" block — transit window, an estimated price, and
    # the free-shipping hint. Answers for a product/variant and an optional
    # visitor country.
    #
    # Deliberately read-only and side-effect free: nothing here touches rates,
    # shipments or the checkout's own delivery selection (the authoritative
    # price is still computed at submit time by `Carts::Submit`).
    class Estimate
      # Business days assumption: Monday–Friday, no holiday calendar. Rendered
      # verbatim in the API docs so the storefront never promises more.
      BUSINESS_DAY_SOURCE = 'weekdays'

      Result = Struct.new(
        :available, :digital, :min_days, :max_days,
        :free_shipping, :free_shipping_threshold, :methods,
        keyword_init: true
      ) do
        def to_h
          {
            available: available,
            digital: digital,
            min_days: min_days,
            max_days: max_days,
            free_shipping: free_shipping,
            free_shipping_threshold: free_shipping_threshold,
            business_day_source: BUSINESS_DAY_SOURCE,
            methods: methods.map do |method|
              {
                id: method.id,
                name: method.name,
                estimated_transit_business_days_min: method.estimated_transit_business_days_min,
                estimated_transit_business_days_max: method.estimated_transit_business_days_max,
                estimated_price: method.display_estimated_price
              }
            end
          }
        end
      end

      class << self
        # @param store [PallasTrade::Store]
        # @param country [String, nil] ISO country code of the visitor
        # @param product [PallasTrade::Product, nil]
        # @param variant [PallasTrade::Variant, nil]
        # @return [Result]
        def call(store:, country: nil, product: nil, variant: nil)
          target = variant || product&.default_variant

          if target&.digital?
            return Result.new(
              available: false, digital: true, min_days: nil, max_days: nil,
              free_shipping: false,
              free_shipping_threshold: nil, methods: []
            )
          end

          methods = scoped_methods(store, country)
          mins = methods.filter_map(&:estimated_transit_business_days_min)
          maxes = methods.filter_map(&:estimated_transit_business_days_max)

          Result.new(
            available: methods.any?,
            digital: false,
            min_days: mins.min,
            # A method with only a minimum still gives an honest upper bound.
            max_days: maxes.max || mins.min,
            free_shipping: free_shipping_promotion?(store) || zero_price_method?(methods),
            free_shipping_threshold: free_shipping_threshold(store),
            methods: methods
          )
        end

        # Front-end delivery methods, narrowed to the visitor's country when a
        # zone matches. When nothing matches we fall back to the full set rather
        # than claim "no delivery" for a country the zones simply don't model.
        def scoped_methods(store, country)
          scope = PallasTrade::ShippingMethod.where(display_on: %w[both front_end]).order(:name)
          return scope if country.blank?

          filtered = scope.joins(zones: :countries).
                     where(pallastrade_countries: { iso: country.to_s.upcase }).distinct
          filtered.exists? ? filtered : scope
        end

        # A front-end method already priced at zero (plain flat rate 0) means
        # "free shipping" without any promotion involved.
        def zero_price_method?(methods)
          methods.any? do |method|
            calculator = method.calculator
            calculator.respond_to?(:preferred_amount) && calculator.preferred_amount.to_d.zero?
          end
        rescue StandardError
          false
        end

        # True when the store has a running free-shipping promotion — mirrors
        # `Promotion#active?` (started, not yet expired) for automatic promos.
        def free_shipping_promotion?(store)
          return false if store.nil?

          running = store.promotions.
                    where('starts_at <= ?', Time.current).
                    where('expires_at IS NULL OR expires_at > ?', Time.current)

          PallasTrade::PromotionAction.
            where(type: 'PallasTrade::Promotion::Actions::FreeShipping').
            where(promotion_id: running.select(:id)).
            exists?
        end

        # Store preference; an active free-shipping promotion wins over it.
        def free_shipping_threshold(store)
          threshold = store&.preferred_free_shipping_threshold
          return nil if threshold.blank? || threshold.to_d <= 0

          threshold
        end
      end
    end
  end
end
