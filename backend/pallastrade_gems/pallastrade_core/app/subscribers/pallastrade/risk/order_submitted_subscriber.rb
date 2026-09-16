# frozen_string_literal: true

# PALLAS-CUSTOM: D15 切片1（PRD-20260916-payments-d15-risk-lists；业务方案 §72.3 / §72.2 接线）——
# `Risk::OrderSubmittedSubscriber` —— 订单提交时跑一次风控评估，命中则**复用既有标记**
# （`Order#considered_risky`）把订单送进既有人工复核闭环（`Orders::Approve`）。
#
# 语义（**只标记，不阻断**）：
#   * 事件源：`Carts::Submit` 发布 `order.submitted`；
#   * 决策非 `allow` → `order.considered_risky!`（已审批订单不重复标记）；
#   * payload 兼容三种形态：`{ 'id' => or_… }` / `{ 'order_id' => or_… }` /
#     `{ 'payload' => { 'order_id' => or_… } }`（既有发布点把 payload 嵌在 `payload` 键下）；
#   * 任何异常 → 日志，**绝不阻断下单**（订阅者默认 async，重试幂等：评估留痕有唯一键）。
module PallasTrade
  module Risk
    class OrderSubmittedSubscriber < PallasTrade::Subscriber
      subscribes_to 'order.submitted'

      def handle(event)
        order = find_order(event.payload)
        return if order.nil?

        result = PallasTrade::Risk::Assess.call(order: order)
        return unless result.success?
        return if result.value[:decision] == 'allow'
        return if order.approved?

        order.considered_risky!
        Rails.logger.info(
          "[Risk::OrderSubmittedSubscriber] order #{order.prefixed_id} flagged (#{result.value[:decision]}, " \
          "#{result.value[:matched].size} match(es))"
        )
      rescue StandardError => e
        Rails.logger.error(
          "[Risk::OrderSubmittedSubscriber] assessment failed: #{e.class} #{e.message}"
        )
      end

      private

      def find_order(payload)
        id = extract_id(payload)
        return if id.blank?

        if id.to_s.start_with?('or_')
          PallasTrade::Order.find_by_param(id)
        else
          PallasTrade::Order.find_by(id: id)
        end
      end

      def extract_id(payload)
        hash = payload.respond_to?(:to_h) ? payload.to_h : {}
        hash['id'] || hash['order_id'] || hash.dig('payload', 'order_id') || hash.dig('payload', 'id')
      rescue StandardError
        nil
      end
    end
  end
end
