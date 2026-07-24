# Permission set for full product and catalog management.
#
# This permission set provides complete access to manage products, variants,
# and related catalog models like taxonomies and properties.
#
# @example
#   PallasTrade.permissions.assign(:merchandiser, PallasTrade::PermissionSets::ProductManagement)
#
module PallasTrade
  module PermissionSets
    class ProductManagement < Base
      def activate!
        can :manage, PallasTrade::Product
        can :manage, PallasTrade::Variant
        can :manage, PallasTrade::OptionType
        can :manage, PallasTrade::OptionValue
        can :manage, PallasTrade::Taxon
        can :manage, PallasTrade::Taxonomy
        can :manage, PallasTrade::Classification
        can :manage, PallasTrade::Price
        can :manage, PallasTrade::PriceList
        can :manage, PallasTrade::PriceRule
        can :manage, PallasTrade::Asset
        can :manage, PallasTrade::ProductPublication
      end
    end
  end
end
