# PALLAS-CUSTOM: 统一拆单引擎 - 策略分组基类（PRD-20260826 P2）
module PallasTrade
  module Orders
    module SplitStrategies
      # 拆单分组策略基类：把订单行项目按某维度分组。
      # 自定义策略继承本类并实现 #groups_for，注册到 PallasTrade.orders_split_strategies。
      class Base
        # @param order [PallasTrade::Order]
        # @return [Hash<Symbol,String => Array<Integer>>] group key → line item ids
        def groups_for(order)
          raise NotImplementedError, "#{self.class} must implement #groups_for"
        end

        protected

        # 按变体的「主供仓库」分组（P2 初版，稳定可测）：
        # 每个行项目归入其变体第一个有货（count_on_hand 最高）且 active 的库存地点。
        # 不依赖 OrderRouting 规则（P5 自动拆单可升级为 Coordinator 精确路由分组）。
        def group_by_inventory_units(order)
          groups = {}
          order.line_items.reload.each do |line_item|
            variant = line_item.variant
            next if variant.nil?

            location_table = PallasTrade::StockLocation.arel_table
            stock_location = variant.stock_items
              .joins(:stock_location)
              .where(location_table[:active].eq(true))
              .order(count_on_hand: :desc, id: :asc)
              .first&.stock_location

            key = "location_#{stock_location&.id || 'none'}"
            groups[key] ||= []
            groups[key] << line_item.id
          end
          groups
        end
      end
    end
  end
end
