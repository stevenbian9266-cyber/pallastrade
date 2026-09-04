# frozen_string_literal: true

# PALLAS-CUSTOM: CHK-P1-3 (PRD-20260903-checkout-chk-p1-1 §12)
module PallasTrade
  module OrderCheckout
    # Server Readiness —— 只读聚合，不复制校验规则。
    #
    # 把「该订单是否可进入支付」判定为对既有 Order/Shipment 谓词与权威列的
    # 只读汇总：email（contact）、requires_ship_address?/ship_address、
    # shipments selected rate（delivery）、amount_due（balance）。
    # digital 订单免 shipping_address；无 shipments 免 delivery_rate。
    # 零副作用：不 save/touch/不跑 updater/不推进状态机。
    class Readiness
      Requirement = Struct.new(:code, :met?, keyword_init: true)

      # @return [Readiness::Result]
      def self.call(order: nil)
        new.call(order: order)
      end

      def call(order: nil)
        return Result.new(ready: false, missing_requirements: []) if order.nil?

        missing = requirements(order).reject(&:met?).map(&:code)
        Result.new(ready: missing.empty?, missing_requirements: missing)
      end

      private

      def requirements(order)
        [
          Requirement.new(code: 'contact', met?: order.email.present?),
          Requirement.new(code: 'shipping_address',
                          met?: !order.requires_ship_address? || order.ship_address.present?),
          Requirement.new(code: 'delivery_rate',
                          met?: order.shipments.empty? || order.shipments.any? { |s| s.selected_shipping_rate.present? }),
          Requirement.new(code: 'balance', met?: order.amount_due.to_d.positive?)
        ]
      end

      # 只读结果 DTO。
      class Result
        attr_reader :ready, :missing_requirements

        def initialize(ready:, missing_requirements:)
          @ready = ready
          @missing_requirements = missing_requirements
        end
      end
    end
  end
end
