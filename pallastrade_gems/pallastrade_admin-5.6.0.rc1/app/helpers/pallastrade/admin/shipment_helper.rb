module PallasTrade::Admin
  module ShipmentHelper
    include PallasTrade::ShipmentHelper

    def can_ship?(shipment)
      can?(:update, shipment) && shipment.shippable?
    end

    def stock_locations_for_split(variant)
      available_stock_locations.
        joins(:stock_items).
        where(PALLASTRADE_stock_items: { variant_id: variant.id }).
        group(:id).
        pluck(:name, "sum(PALLASTRADE_stock_items.count_on_hand)", :id).
        map { |name, count, id| [PallasTrade.t('admin.shipments.stock_location_option', name: name, count: count), "stock-location_#{id}"] }
    end

    def shipments_for_transfer(current_shipment)
      current_shipment.
        order.
        shipments.
        ready_or_pending.
        where(stock_location: available_stock_locations).
        where.not(id: current_shipment.id).
        pluck(:number, :id).
        map { |n, i| [n, "shipment_#{i}"] }
    end
  end
end
