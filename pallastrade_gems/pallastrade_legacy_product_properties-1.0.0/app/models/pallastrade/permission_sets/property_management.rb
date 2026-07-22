module PallasTrade
  module PermissionSets
    class PropertyManagement < PermissionSets::Base
      def activate!
        can :manage, PallasTrade::Property
        can :manage, PallasTrade::ProductProperty
      end
    end
  end
end
