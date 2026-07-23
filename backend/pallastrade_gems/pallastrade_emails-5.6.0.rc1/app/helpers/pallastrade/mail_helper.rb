module PallasTrade
  module MailHelper
    include PallasTrade::BaseHelper
    include PallasTrade::ImagesHelper

    def variant_image_url(variant)
      PallasTrade::Deprecation.warn(
        'PallasTrade::MailHelper#variant_image_url is deprecated. Use pallastrade_image_url instead. Will be removed in PallasTrade 6.0.'
      )

      image = variant.primary_media
      image.present? && image.attached? ? pallastrade_image_url(image, variant: :mini) : image_url('noimage/small.png')
    end

    def name_for(order)
      order.name || PallasTrade.t('customer')
    end

    def store_logo
      @store_logo ||= current_store&.mailer_logo || current_store&.logo
    end
  end
end
