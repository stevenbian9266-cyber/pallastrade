# @deprecated This module is now a no-op. All logic has been moved to PallasTrade::Asset.
# Will be removed in PallasTrade 6.0.
module PallasTrade
  class Image < Asset
    module Configuration
      module ActiveStorage
        extend ActiveSupport::Concern
      end
    end
  end
end
