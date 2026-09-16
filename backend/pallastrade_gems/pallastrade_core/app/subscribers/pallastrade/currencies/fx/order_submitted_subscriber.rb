# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片4（PRD-20260916-payments-d13d-fx-snapshot；业务方案 §70.4）——
# `Currencies::Fx::OrderSubmittedSubscriber` —— **下单时锁定展示汇率**（一次），形成逐单汇率凭证。
#
# 语义（只记录，不阻断）：
#   * 事件源：`Carts::Submit` 发布 `order.submitted`；
#   * payload 兼容三种形态：`{ 'id' => or_… }` / `{ 'order_id' => or_… }` / `{ 'payload' => { 'order_id' => … } }`；
#   * 走 `Fx::Lock`（幂等：一单一种币对只锁一次）；
#   * 任何异常 → 只记日志，**绝不阻断下单**。
module PallasTrade
  module Currencies
    module Fx
      class OrderSubmittedSubscriber < PallasTrade::Subscriber
        subscribes_to 'order.submitted'

        def handle(event)
          order = find_order(event.payload)
          return if order.nil?

          result = PallasTrade::Currencies::Fx::Lock.call(order: order)
          return unless result.success?

          signals = result.value[:signals]
          if result.value[:snapshot].present?
            Rails.logger.info(
              "[Currencies::Fx::OrderSubmittedSubscriber] locked #{order.prefixed_id} " \
              "#{result.value[:snapshot].base_currency}/#{result.value[:snapshot].quote_currency} " \
              "effective=#{result.value[:snapshot].effective_rate}"
            )
          elsif signals.any?
            Rails.logger.info(
              "[Currencies::Fx::OrderSubmittedSubscriber] no snapshot for #{order.prefixed_id} (#{signals.join(',')})"
            )
          end
        rescue StandardError => e
          Rails.logger.error(
            "[Currencies::Fx::OrderSubmittedSubscriber] lock failed: #{e.class} #{e.message}"
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
end
