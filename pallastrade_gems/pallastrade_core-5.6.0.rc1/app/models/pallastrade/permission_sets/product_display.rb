# Permission set for viewing products and catalog information.
#
# This permission set provides read-only access to products, variants,
# and related catalog models.
#
# @example
#   PallasTrade.permissions.assign(:content_editor, PallasTrade::PermissionSets::ProductDisplay)
#
module PallasTrade
  module PermissionSets
    class ProductDisplay < Base
      def activate!
        can [:read, :admin, :index], PallasTrade::Product
        can [:read, :admin], PallasTrade::Variant
        can [:read, :admin], PallasTrade::OptionType
        can [:read, :admin], PallasTrade::OptionValue
        can [:read, :admin], PallasTrade::Metafield
        can [:read, :admin], PallasTrade::Taxon
        can [:read, :admin], PallasTrade::Taxonomy
        can [:read, :admin], PallasTrade::Classification
        can [:read, :admin], PallasTrade::Price
        can [:read, :admin], PallasTrade::PriceList
        can [:read, :admin], PallasTrade::PriceRule
      end
    end
  end
end
