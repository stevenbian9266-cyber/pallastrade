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

      # PALLAS-CUSTOM (2026-09-11, PRD-20260911-promotions-promo-batch5b):
      # 从 PermissionRegistry 派生授权，避免权限集与注册表各写一份资源清单。
      #
      # @param resources [Array<Symbol>] 注册表资源名
      # @param actions [Array<Symbol>, Symbol] 授予的动作（默认 :manage）
      # @return [void]
      def self.grants_registry_resource(*resources, actions: :manage)
        registry_grants << [resources.flatten, Array(actions)]
      end

      # @return [Array<Array>] `[[resources, actions], ...]`
      def self.registry_grants
        @registry_grants ||= []
      end

      # Activates this permission set by adding its permissions to the ability.
      #
      # 默认实现将 `grants_registry_resource` 声明的资源展开为 can 语句；
      # 子类可覆写并 `super` 以追加特殊行（如无后台 UI 的模型）。
      #
      # @return [void]
      def activate!
        raise NotImplementedError, "#{self.class} must implement #activate!" if self.class.registry_grants.empty?

        apply_registry_grants
      end

      protected

      # 把注册表声明的资源展开为 `can action, model`（模型取自注册表覆盖集合）。
      def apply_registry_grants
        self.class.registry_grants.each do |resources, actions|
          resources.each do |resource|
            models = Array(PallasTrade::PermissionRegistry[resource]&.models)
            next if models.empty?

            actions.each { |action| models.each { |model| can action, model } }
          end
        end
      end

      # Delegates the `can` method to the ability instance.
      #
      # @param args [Array] arguments to pass to CanCan::Ability#can
      # @param block [Proc] optional block for conditional permissions
      def can(*, &)
        ability.can(*, &)
      end

      # Delegates the `cannot` method to the ability instance.
      #
      # @param args [Array] arguments to pass to CanCan::Ability#cannot
      # @param block [Proc] optional block for conditional permissions
      def cannot(*, &)
        ability.cannot(*, &)
      end

      # Delegates the `can?` method to the ability instance.
      #
      # @param args [Array] arguments to pass to CanCan::Ability#can?
      # @return [Boolean]
      def can?(*)
        ability.can?(*)
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
