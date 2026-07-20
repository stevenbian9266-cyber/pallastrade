module PallasTrade
  module Metafields
    class Boolean < PallasTrade::Metafield
      normalizes :value, with: ->(value) { value.to_b.to_s }

      def csv_value
        value.to_b ? PallasTrade.t(:say_yes) : PallasTrade.t(:say_no)
      end

      def serialize_value
        value.to_b
      end
    end
  end
end
