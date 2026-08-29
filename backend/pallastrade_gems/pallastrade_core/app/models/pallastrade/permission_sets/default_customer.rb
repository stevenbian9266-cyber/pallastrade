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

        # 订单流程标准电商改造 P1（2026-08-30）：新购物车（pallastrade_carts）授权。
        # 游客/登录用户可创建并管理自己的购物车（owner 或 token 匹配）；converted/abandoned 不可改。
        can :create, PallasTrade::Cart
        can :show, PallasTrade::Cart do |cart, token|
          cart.user == user || cart.token && token == cart.token
        end
        can :update, PallasTrade::Cart do |cart, token|
          cart.active? && (cart.user == user || cart.token && token == cart.token)
        end
        can :destroy, PallasTrade::Cart do |cart, token|
          cart.active? && (cart.user == user || cart.token && token == cart.token)
        end

        # CartItem 权限透传所属购物车权限（token 由 CartResolvable 透传）
        can :create, PallasTrade::CartItem do |item, token|
          item.cart.active? && (item.cart.user == user || item.cart.token && token == item.cart.token)
        end
        can :update, PallasTrade::CartItem do |item, token|
          item.cart.active? && (item.cart.user == user || item.cart.token && token == item.cart.token)
        end
        can :destroy, PallasTrade::CartItem do |item, token|
          item.cart.active? && (item.cart.user == user || item.cart.token && token == item.cart.token)
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
