module PallasTrade
  module HasImageAltText
    extend ActiveSupport::Concern

    # @return [String] Alt text resolved from preference, asset filename, or i18n fallback.
    def image_alt
      return preferred_image_alt if respond_to?(:preferred_image_alt) && preferred_image_alt.present?

      if respond_to?(:asset) && asset&.filename.present?
        filename = asset.filename.to_s
        base = File.basename(filename, File.extname(filename))
        return base.tr('-_.', ' ').squeeze(' ').strip
      end

      PallasTrade.t(:image, default: 'Image')
    end
  end
end