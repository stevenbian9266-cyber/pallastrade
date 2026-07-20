module PallasTrade
  module Reports
    class ProductsPerformance < PallasTrade::Report
      def line_items_scope
        line_items_scope = PallasTrade::LineItem.
                           select("
                             #{PallasTrade::LineItem.table_name}.quantity as quantity,
                             #{PallasTrade::LineItem.table_name}.pre_tax_amount as pre_tax_amount,
                             #{PallasTrade::LineItem.table_name}.promo_total as promo_total,
                             #{PallasTrade::LineItem.table_name}.included_tax_total + #{PallasTrade::LineItem.table_name}.additional_tax_total AS tax_total,
                             #{PallasTrade::LineItem.table_name}.pre_tax_amount + #{PallasTrade::LineItem.table_name}.adjustment_total AS total,
                             #{PallasTrade::Variant.table_name}.product_id AS product_id
                           ").
                           joins(:variant, :order).
                           where(
                             PALLASTRADE_line_items: {
                               currency: currency
                             },
                             PALLASTRADE_orders: {
                               completed_at: date_from..date_to
                             }
                           )

        return PallasTrade::Product.none if line_items_scope.empty?

        line_items_sql = line_items_scope.to_sql

        product_scope = store.products
        product_scope = product_scope.where(vendor_id: vendor.id) if defined?(vendor) && vendor.present?

        product_scope.includes(:taxons, :tax_category, variants: :prices, master: :prices).
                              joins("LEFT JOIN (#{line_items_sql}) AS line_items ON #{PallasTrade::Product.table_name}.id = line_items.product_id").
                              select("
                                PALLASTRADE_products.*,
                                COALESCE(SUM(line_items.pre_tax_amount), 0.0) AS pre_tax_amount,
                                COALESCE(SUM(line_items.quantity), 0) AS quantity,
                                COALESCE(SUM(line_items.promo_total), 0.0) AS promo_total,
                                COALESCE(SUM(line_items.tax_total), 0.0) AS tax_total,
                                COALESCE(SUM(line_items.total), 0.0) AS total
                              ").group('pallastrade_products.id')
      end
    end
  end
end
