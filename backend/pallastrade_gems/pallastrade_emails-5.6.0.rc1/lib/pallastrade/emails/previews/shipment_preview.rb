require 'pallastrade/core/previews/preview_data'

# Preview PallasTrade shipment emails at /rails/mailers/pallastrade/shipment
class PallasTrade::ShipmentPreview < ActionMailer::Preview
  include PallasTrade::PreviewData::LocaleParam

  def shipped_email
    shipment = PallasTrade::Shipment.shipped.last
    shipment.order.locale = locale if shipment && locale.present?
    PallasTrade::ShipmentMailer.shipped_email(shipment)
  end
end
