# frozen_string_literal: true

# PALLAS-CUSTOM: 自动拆单（PRD-20260827 P5a）——订单完成（支付确认后）按配置策略拆分。
# flag 灰度：策略列表来自 store.preferred_auto_split_orders（preference，JSON 数组字符串），
# 回退 PallasTrade::Config[:auto_split_orders]，默认 []（关闭）。
# 语义：不在 cart 状态中途拆；拆单失败不影响订单完成（Rails.error.report + 返回 success）。
module PallasTrade
  module Carts
    class AutoSplit
      prepend PallasTrade::ServiceModule::Base

      # @param order [PallasTrade::Order] 已完成的订单
      # @return [PallasTrade::ServiceModule::Result] success(order)（含未拆/拆单失败场景）
      def call(order:)
        return success(order) if order.canceled?

        strategies = auto_split_strategies(order.store)
        return success(order) if strategies.empty?

        strategies.each do |strategy_class|
          groups = strategy_class.new.groups_for(order)
          next if groups.blank?

          # 尽力而为：调用拆单但忽略其业务结果（成功/失败都不影响订单完成），
          # 拆分后源订单成为父容器，行项目已迁移，不再尝试后续策略。
          PallasTrade::Orders::Splitter.call(order: order, groups: groups)
          return success(order)
        end

        success(order)
      rescue StandardError => e
        # 拆单异常不影响订单完成：记录并保持完成态
        Rails.error.report(e, context: { order_id: order.id }, source: 'PallasTrade.carts.auto_split')
        success(order)
      end

      private

      # 策略列表解析：store preference（JSON 数组）→ Config 回退 → 默认 []
      def auto_split_strategies(store)
        raw = store.preferred_auto_split_orders.presence || PallasTrade::Config[:auto_split_orders]
        parsed = raw.is_a?(String) ? (JSON.parse(raw) rescue []) : Array(raw)
        parsed.map { |name| name.to_s.constantize }
      rescue NameError
        []
      end
    end
  end
end
