module PallasTrade
  module Seeds
    class DigitalDelivery
      prepend PallasTrade::ServiceModule::Base

      def call
        digital_shipping_category = PallasTrade::ShippingCategory.find_or_create_by!(name: 'Digital')
        zones = PallasTrade::Zone.all

        digital_shipping_method = PallasTrade::ShippingMethod.find_or_initialize_by(name: PallasTrade.t('digital.digital_delivery'))

        digital_shipping_method.display_on = 'both'
        digital_shipping_method.shipping_categories = [digital_shipping_category]
        digital_shipping_method.calculator ||= PallasTrade::Calculator::Shipping::DigitalDelivery.create!
        digital_shipping_method.zones = zones
        digital_shipping_method.save!
      end
    end
  end
end
