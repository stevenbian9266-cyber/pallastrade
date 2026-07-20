# Backward compatibility — all logic now lives in PallasTrade::Asset.
# This class will be removed in Spree 6.0.
module PallasTrade
  class Image < Asset
  end
end
