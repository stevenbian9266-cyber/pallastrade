# Permission set for managing store configuration and settings.
#
# This permission set provides access to manage store settings,
# payment methods, shipping methods, and other configuration.
#
# @example
#   PallasTrade.permissions.assign(:store_admin, PallasTrade::PermissionSets::ConfigurationManagement)
#
module PallasTrade
  module PermissionSets
    class ConfigurationManagement < Base
      def activate!
        # Store settings
        can :manage, PallasTrade::Store

        # Payment configuration
        can :manage, PallasTrade::PaymentMethod
        can :manage, PallasTrade::Gateway

        # Shipping configuration
        can :manage, PallasTrade::ShippingMethod
        can :manage, PallasTrade::ShippingCategory
        can :manage, PallasTrade::Zone
        can :manage, PallasTrade::ZoneMember

        # Markets — Channel / Market is the long-term replacement for
        # Zone (see docs/plans/6.0-tax-provider.md), but both coexist
        # during the migration and need admin read/write either way.
        can :manage, PallasTrade::Market

        # Tax configuration
        can :manage, PallasTrade::TaxCategory
        can :manage, PallasTrade::TaxRate

        # CORS allowlist used by Rack::Cors + admin cookie auth (see
        # docs/plans/5.5-admin-auth-cookie-refresh.md).
        can :manage, PallasTrade::AllowedOrigin

        # Webhooks
        can :manage, PallasTrade::WebhookEndpoint
        can :manage, PallasTrade::WebhookDelivery

        # General configuration
        can :manage, PallasTrade::RefundReason
        can :manage, PallasTrade::ReimbursementType
        can :manage, PallasTrade::ReturnReason

        # Channels
        can :manage, PallasTrade::Channel

        # Restrictions on immutable types
        cannot [:edit, :update], PallasTrade::RefundReason, mutable: false
        cannot [:edit, :update], PallasTrade::ReimbursementType, mutable: false

        # Metafield configuration
        can :manage, PallasTrade::MetafieldDefinition

        # Policies
        can :manage, PallasTrade::Policy
      end
    end
  end
end
