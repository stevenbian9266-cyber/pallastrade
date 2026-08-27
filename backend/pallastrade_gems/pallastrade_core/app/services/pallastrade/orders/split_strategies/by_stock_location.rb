# PALLAS-CUSTOM: 统一拆单引擎 - 按商品仓库地址分组（PRD-20260826 P2）
module PallasTrade
  module Orders
    module SplitStrategies
      # 按履约仓库（StockLocation）分组：复用订单路由（Stock::Coordinator）把行项目
      # 分配到各仓库的 package，同一行项目只归入首个分配的仓库。
      class ByStockLocation < Base
        def groups_for(order)
          group_by_inventory_units(order)
        end
      end
    end
  end
end
