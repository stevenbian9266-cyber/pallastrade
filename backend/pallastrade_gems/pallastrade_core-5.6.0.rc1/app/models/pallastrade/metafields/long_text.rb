module PallasTrade
  module Metafields
    class LongText < PallasTrade::Metafield
      normalizes :value, with: ->(value) { value.to_s.strip }
    end
  end
end
