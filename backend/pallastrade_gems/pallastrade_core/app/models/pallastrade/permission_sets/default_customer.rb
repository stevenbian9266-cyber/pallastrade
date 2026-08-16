# Permission set for default storefront customers (both authenticated and guests).
#
# This permission set provides the standard permissions needed for browsing
# the store and making purchases.
#
# @example
#   PallasTrade.permissions.assign(:default, PallasTrade::PermissionSets::DefaultCustomer)
#
module PallasTrade
  module PermissionSets
    class DefaultCustomer < Base
      def activate!
        # Read-only access to catalog
        can :read, PallasTrade::Country
        can :read, PallasTrade::OptionType
        can :read, PallasTrade::OptionValue
        can :read, PallasTrade::Product
        can :read, PallasTrade::State
        can :read, PallasTrade::Store
        can :read, PallasTrade::Taxon
        can :read, PallasTrade::Taxonomy
        can :read, PallasTrade::Variant
        can :read, PallasTrade::Zone

        # Content pages
        can :read, PallasTrade::Policy

        # Blog posts (CMS)
        can :read, PallasTrade::Post

        # Order management for the user's own orders
        can :create, PallasTrade::Order
        can :show, PallasTrade::Order do |order, token|
          order.user == user || order.token && token == order.token
        end
        can :update, PallasTrade::Order do |order, token|
          !order.completed? && (order.user == user || order.token && token == order.token)
        end

        # Line item management
        can :create, PallasTrade::LineItem do |line_item, token|
          line_item.order.user == user || line_item.order.token && token == line_item.order.token
        end
        can :update, PallasTrade::LineItem do |line_item, token|
          !line_item.order.completed? && (line_item.order.user == user || line_item.order.token && token == line_item.order.token)
        end
        can :destroy, PallasTrade::LineItem do |line_item, token|
          !line_item.order.completed? && (line_item.order.user == user || line_item.order.token && token == line_item.order.token)
        end

        # User account management - available to all users (including guests for their own record)
        can :create, PallasTrade.user_class
        can [:show, :update, :destroy], PallasTrade.user_class, id: user.id

        # Address management - only for persisted users with matching user_id
        can :manage, PallasTrade::Address, user_id: user.id if user.persisted?

        # Credit card management
        can [:read, :destroy], PallasTrade::CreditCard, user_id: user.id

        # Gift card management - users can view their own gift cards
        can :read, PallasTrade::GiftCard, user_id: user.id

        # Wishlist management
        can :manage, PallasTrade::Wishlist, user_id: user.id
        can :show, PallasTrade::Wishlist do |wishlist|
          wishlist.user == user || wishlist.is_private == false
        end
        can [:create, :update, :destroy], PallasTrade::WishedItem do |wished_item|
          wished_item.wishlist.user == user
        end

        # Invitation acceptance
        can :accept, PallasTrade::Invitation, invitee_id: [user.id, nil], invitee_type: user.class.name, status: 'pending'

        # Digital downloads - token-based access
        can :show, PallasTrade::DigitalLink do |digital_link, token|
          digital_link.token == token
        end
      end
    end
  end
end
