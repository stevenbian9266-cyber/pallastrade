module PallasTrade
  module NumberAsParam
    extend ActiveSupport::Concern

    included do
      PallasTrade::Deprecation.warn(
        'PallasTrade::NumberAsParam is deprecated and will be removed in Spree 6.0. ' \
        'Models now use PallasTrade::PrefixedId with Sqids-based prefixed_id method instead. ' \
        'This concern no longer provides any functionality and can be safely removed.'
      )
    end
  end
end
