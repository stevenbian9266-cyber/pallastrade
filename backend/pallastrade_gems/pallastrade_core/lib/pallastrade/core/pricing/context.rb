module PallasTrade
  module Pricing
    class Context
      attr_reader :variant, :currency, :store, :zone, :market, :channel, :user, :quantity, :date, :order

      # Initializes the context
      # @param variant [PallasTrade::Variant]
      # @param currency [String]
      # @param store [PallasTrade::Store]
      # @param zone [PallasTrade::Zone]
      # @param market [PallasTrade::Market]
      # @param channel [PallasTrade::Channel]
      # @param user [PallasTrade::User]
      # @param quantity [Integer]
      # @param date [Time]
      # @param order [PallasTrade::Order]
      def initialize(variant: nil, currency:, store: nil, zone: nil, market: nil, channel: nil, user: nil, quantity: nil, date: nil, order: nil)
        @variant = variant
        @currency = currency
        @store = store || PallasTrade::Current.store
        @zone = zone || PallasTrade::Current.zone
        @market = market || PallasTrade::Current.market
        @channel = channel || PallasTrade::Current.channel
        @user = user
        @quantity = quantity
        @date = date || Time.current
        @order = order
      end

      # Returns a new context from a variant and currency
      # @param variant [PallasTrade::Variant]
      # @param currency [String]
      # @return [PallasTrade::Pricing::Context]
      def self.from_currency(variant, currency)
        new(variant: variant, currency: currency)
      end

      def self.from_order(variant, order, quantity: nil)
        new(
          variant: variant,
          currency: order.currency,
          store: order.store,
          zone: order.tax_zone || PallasTrade::Zone.default_tax,
          channel: order.channel,
          user: order.user,
          quantity: quantity || order.line_items.find_by(variant: variant)&.quantity,
          order: order
        )
      end

      # Returns the cache key for the context
      # @return [String]
      def cache_key
        [
          'pallastrade',
          'pricing',
          variant.id,
          currency,
          store&.id,
          zone&.id,
          market&.id,
          channel&.id,
          user&.id,
          quantity,
          date&.to_i
        ].compact.join('/')
      end
    end
  end
end
