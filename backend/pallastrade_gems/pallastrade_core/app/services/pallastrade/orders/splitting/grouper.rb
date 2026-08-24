# PALLAS-CUSTOM: 系统拆单-分组策略（PRD-20260824-checkout-正向订单-逆向订单链路重构或优化）
#
# 按可配置策略把订单的行项目分组成多组（每组 → 一个子订单）：
#   :warehouse — 按商品仓库地址（复用 Stock::Coordinator 的选仓结果）
#   :store      — 按店铺（行项目归属店铺）
#   custom      — 扩展点：PallasTrade::Config[:auto_split_orders_custom] = ->(order) { { key => [line_item_ids] } }
module PallasTrade
  module Orders
    module Splitting
      class Grouper
        prepend PallasTrade::ServiceModule::Base

        # @param order [PallasTrade::Order]
        # @param by [Symbol, String] :warehouse | :store | :custom
        # @return [ServiceResult<Hash<String, Array<Integer>>>] group key → line item ids
        def call(order:, by:)
          strategy = by.to_sym
          groups = case strategy
                   when :warehouse then by_warehouse(order)
                   when :store then by_store(order)
                   when :custom then custom(order)
                   else
                     return failure(order, { code: :unknown_split_strategy, message: "unknown strategy #{by}" })
                   end

          return failure(order, { code: :no_split_groups, message: PallasTrade.t(:no_split_groups) }) if groups.blank?
          return failure(order, { code: :no_split_groups, message: PallasTrade.t(:no_split_groups) }) if groups.size <= 1

          success(groups)
        end

        private

        # 按商品仓库地址分组（沿用 Checkout::SplitOrders 的选仓逻辑）
        def by_warehouse(order)
          packages = PallasTrade::Stock::Coordinator.new(order).packages
          groups = Hash.new { |h, k| h[k] = [] }
          packages.each do |package|
            package.contents.each do |inventory_unit|
              next unless inventory_unit.respond_to?(:line_item_id) && inventory_unit.line_item_id.present?

              groups["location_#{package.stock_location.id}"] << inventory_unit.line_item_id
            end
          end
          groups
        end

        # 按店铺分组（行项目归属商品店铺；单店时不会产生多组）
        def by_store(order)
          groups = Hash.new { |h, k| h[k] = [] }
          order.line_items.each do |li|
            store_id = li.variant&.product&.store_id || order.store_id
            groups["store_#{store_id}"] << li.id
          end
          groups
        end

        # 自定义策略扩展点
        def custom(order)
          hook = PallasTrade::Config[:auto_split_orders_custom]
          return {} unless hook.respond_to?(:call)

          hook.call(order).to_h
        end
      end
    end
  end
end
