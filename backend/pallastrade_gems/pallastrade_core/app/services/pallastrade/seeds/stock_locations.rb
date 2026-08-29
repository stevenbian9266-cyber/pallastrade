module PallasTrade
  module Seeds
    class StockLocations
      prepend PallasTrade::ServiceModule::Base

      def call
        country = PallasTrade::Store.default.default_country
        PallasTrade::StockLocation.find_or_create_by!(
          name: PallasTrade.t(:default_stock_location_name),
          propagate_all_variants: false,
          country: country,
          active: true,
          default: true,
          # 默认仓库允许超卖（backorder），与测试工厂默认一致（backorderable_default: true）。
          # 若不显式设置，DB 默认 false 会使 seed 后新建的 variant 全部不可超卖，
          # 导致 CI（db:prepare 自动 seed）下创建 line_item 报 "Quantity selected ... not available"。
          backorderable_default: true
        )
      end
    end
  end
end
