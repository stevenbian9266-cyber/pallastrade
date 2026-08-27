# PALLAS-CUSTOM: 统一拆单引擎 - 按店铺分组（PRD-20260826 P2）
module PallasTrade
  module Orders
    module SplitStrategies
      # 按行项目所属店铺（商品归属 store）分组。
      # 当前单 store 商品体系下基本只有一组；该策略为跨店铺拆单（P6 手动跨店）预留
      # 分组接口，多 store 商品落地后可自动按店铺拆分。
      class ByStore < Base
        def groups_for(order)
          groups = {}
          # reload：调用方可能持有缓存为空的 line_items 关联
          order.line_items.reload.each do |line_item|
            store_id = line_item.product&.store_id
            key = "store_#{store_id || 'nil'}"
            groups[key] ||= []
            groups[key] << line_item.id
          end
          groups
        end
      end
    end
  end
end
