# PALLAS-CUSTOM: 支付后系统自动拆单（PRD-20260824-checkout-正向订单-逆向订单链路重构或优化）
#
# FR-023：单笔订单支付成功 或 合并支付成功 → 按配置策略评估是否拆单，需拆则拆分。
# 拆分条件（FR-022）：auto_split_orders = 'warehouse'（仓库地址）| 'store'（店铺）| 自定义扩展
# 子订单归入原父订单（parent_id），已付金额按行项目分摊（继承已付状态，不重复支付）。
module PallasTrade
  module Orders
    module Splitting
      class AfterPayment
        prepend PallasTrade::ServiceModule::Base

        # @param order [PallasTrade::Order] 已支付订单
        # @return [ServiceResult<PallasTrade::Order | Array<PallasTrade::Order>>]
        def call(order:)
          return success(order) unless enabled?

          strategy = strategy_for(order)
          return success(order) if strategy.blank?

          result = PallasTrade::Orders::Splitter.call(order: order, by: strategy, allow_paid: true)
          return success(order) if result.success?

          # 不需要拆（单组/无分组）属于正常情况，不算失败
          code = result.error&.value
          code = code[:code] if code.is_a?(Hash)
          return success(order) if %i[no_split_groups no_split_line_items order_not_splittable].include?(code)

          failure(order, result.error.value)
        end

        private

        def enabled?
          PallasTrade::Config[:auto_split_orders].to_s.presence.present?
        end

        # 店铺级覆盖 > 全局配置
        def strategy_for(order)
          store_strategy = order.store&.respond_to?(:preferred_auto_split_orders) ?
                           order.store.preferred_auto_split_orders : nil
          store_strategy.presence || PallasTrade::Config[:auto_split_orders].to_s.presence
        end
      end
    end
  end
end
