module PallasTrade
  module Metafields
    class ShortText < PallasTrade::Metafield
      normalizes :value, with: ->(value) { value.to_s.strip }
    end
  end
end
