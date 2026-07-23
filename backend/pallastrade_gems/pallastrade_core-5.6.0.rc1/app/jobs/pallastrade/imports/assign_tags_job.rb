module PallasTrade
  module Imports
    class AssignTagsJob < PallasTrade::Imports::BaseJob
      def perform(product_id, tags)
        product = PallasTrade::Product.find(product_id)
        product.tag_list = tags
        product.save!
      end
    end
  end
end
