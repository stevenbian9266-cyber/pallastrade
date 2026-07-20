module PallasTrade
  module Variants
    class TouchJob < PallasTrade::BaseJob
      def perform(variant_ids)
        PallasTrade::Variant.where(id: variant_ids).find_each(&:touch)
      end
    end
  end
end
