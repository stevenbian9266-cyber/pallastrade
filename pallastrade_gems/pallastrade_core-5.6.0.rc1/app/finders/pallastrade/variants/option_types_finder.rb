module PallasTrade
  module Variants
    class OptionTypesFinder
      COLOR_TYPE = 'color'.freeze

      def initialize(variant_ids:)
        @variant_ids = variant_ids
      end

      def execute
        PallasTrade::OptionType.includes(option_values: :variants).where(PALLASTRADE_variants: { id: variant_ids }).
          reorder('pallastrade_option_types.position ASC, PALLASTRADE_option_values.position ASC').
          partition { |option_type| option_type.name.downcase == COLOR_TYPE }.flatten
      end

      private

      attr_reader :variant_ids
    end
  end
end
