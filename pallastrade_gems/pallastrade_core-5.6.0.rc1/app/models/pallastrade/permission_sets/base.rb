# Base class for all permission sets.
#
# Permission sets are reusable groups of permissions that can be assigned to roles.
# They provide a clean abstraction over CanCanCan abilities, making it easier to
# manage permissions in a modular way.
#
# @example Creating a custom permission set
#   class PallasTrade::PermissionSets::InventoryManagement < PallasTrade::PermissionSets::Base
#     def activate!
#       can :manage, PallasTrade::StockItem
#       can :manage, PallasTrade::StockLocation
#       can :manage, PallasTrade::StockMovement
#     end
#   end
#
# @example Assigning the permission set to a role
#   PallasTrade.permissions.assign(:warehouse_manager, PallasTrade::PermissionSets::InventoryManagement)
#
module PallasTrade
  module PermissionSets
    class Base
      # @return [CanCan::Ability] the ability instance to add permissions to
      attr_reader :ability

      # @param ability [CanCan::Ability] the ability instance to add permissions to
      def initialize(ability)
        @ability = ability
      end

      # Activates this permission set by adding its permissions to the ability.
      # Override this method in subclasses to define the permissions.
      #
      # @abstract
      # @return [void]
      def activate!
        raise NotImplementedError, "#{self.class} must implement #activate!"
      end

      protected

      # Delegates the `can` method to the ability instance.
      #
      # @param args [Array] arguments to pass to CanCan::Ability#can
      # @param block [Proc] optional block for conditional permissions
      def can(*args, &block)
        ability.can(*args, &block)
      end

      # Delegates the `cannot` method to the ability instance.
      #
      # @param args [Array] arguments to pass to CanCan::Ability#cannot
      # @param block [Proc] optional block for conditional permissions
      def cannot(*args, &block)
        ability.cannot(*args, &block)
      end

      # Delegates the `can?` method to the ability instance.
      #
      # @param args [Array] arguments to pass to CanCan::Ability#can?
      # @return [Boolean]
      def can?(*args)
        ability.can?(*args)
      end

      # Returns the user from the ability instance.
      # This method assumes the ability has a user accessor.
      #
      # @return [Object] the current user
      def user
        ability.user
      end

      # Returns the store from the ability instance options.
      #
      # @return [PallasTrade::Store, nil] the current store
      def store
        ability.store
      end
    end
  end
end
