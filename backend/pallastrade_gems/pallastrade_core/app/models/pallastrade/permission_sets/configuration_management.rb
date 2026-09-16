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

        # SEO 301 redirects
        can :manage, PallasTrade::Redirect

        # Back-in-stock subscriptions (review + delete)
        can :manage, PallasTrade::BackInStockSubscription

        # Abandoned-cart notifications (P0-3 review + delete + run scan)
        can :manage, PallasTrade::AbandonedCartNotification

        # Product reviews (P0-4 moderate: approve / reject / delete)
        can :manage, PallasTrade::Review

        # Webhooks
        can :manage, PallasTrade::WebhookEndpoint
        can :manage, PallasTrade::WebhookDelivery
        # PALLAS-CUSTOM: D12（PRD-20260915-payments-d12-webhook-governance）——
        # 入站 webhook 事件运营面（事件流 + 重放/隔离/人工标记）。`:manage` 覆盖全部动作。
        can :manage, PallasTrade::PaymentWebhookEvent
        # PALLAS-CUSTOM: D13 切片1（PRD-20260916-payments-d13-reconciliation-cases）——
        # 对账差异队列工作台（指派/备注/关单 + CSV 导出）。`:manage` 覆盖全部案例动作。
        can :manage, PallasTrade::ReconciliationCase
        # PALLAS-CUSTOM: D13 切片2（PRD-20260916-payments-d13b-payout-ledger）——
        # 结算（Payout）台账（导入/匹配/查看）。`:manage` 覆盖全部台账动作。
        can :manage, PallasTrade::Payout

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

        # Blog posts (CMS)
        can :manage, PallasTrade::Post
      end
    end
  end
end
