module PallasTrade
  module Admin
    module ChannelsHelper
      # Registered +PallasTrade::OrderRouting::Strategy::Base+ subclasses presented in
      # the channel edit form, sourced from +PallasTrade.order_routing.strategies+ so the
      # picker can never drift from what the model accepts. A blank value clears the
      # channel-level override and falls back to
      # +Store#preferred_order_routing_strategy+.
      def channel_order_routing_strategy_options
        PallasTrade.order_routing.strategies.map { |strategy| [strategy.display_name, strategy.to_s] }
      end

      # Storefront access levels for the channel edit form. A blank selection
      # clears the channel override and falls back to +Store#preferred_storefront_access+.
      def channel_storefront_access_options
        PallasTrade::Channel::Gating::STOREFRONT_ACCESS.map do |value|
          [PallasTrade.t("admin.channels.storefront_access_options.#{value}"), value]
        end
      end

      # Tri-state guest-checkout override for the channel edit form. A blank
      # selection clears the override and falls back to +Store#preferred_guest_checkout+.
      def channel_guest_checkout_options
        [
          [PallasTrade.t('admin.channels.guest_checkout_allowed'), 'true'],
          [PallasTrade.t('admin.channels.guest_checkout_blocked'), 'false']
        ]
      end
    end
  end
end
