# frozen_string_literal: true

# PALLAS-CUSTOM: CHK-P1-1A (PRD-20260903-checkout-chk-p1-1a-read-only-checkoutview)
# Order-centric Checkout — 只读投影入口。
#
# 职责：
#   * 按 order 显式预加载 Checkout 所需关联，避免序列化 N+1；
#   * 返回 CheckoutView DTO —— 当前 Order Checkout 商业事实的服务端投影；
#   * 零副作用、确定性：不 save/touch、不跑 OrderUpdater、不 requote/retax/repricing、
#     不推进状态机、不创建 PaymentSession。
#
# 禁止：在 View 内重算金额/税/运费；新增 CheckoutSession / 数据镜像表 / Pricing Engine。
module PallasTrade
  module OrderCheckout
    class View
      # 服务惯例：支持类级调用 View.call(order:)。
      def self.call(order: nil)
        new.call(order: order)
      end

      # 与 CheckoutSerializer 消费一致的预加载集（防 N+1）。
      # 注：Shipment#shipping_method 是方法（非 AR 关联），不可 includes —— 由
      # FulfillmentSerializer 按需读取（每 shipment 至多 1 次查询）。
      INCLUDES = [
        { line_items: [:variant] },
        { shipments: [:stock_location, :shipping_rates, { inventory_units: %i[line_item variant] }] },
        :adjustments,
        :bill_address,
        :ship_address
      ].freeze

      # @param order [PallasTrade::Order, nil]
      # @return [PallasTrade::OrderCheckout::CheckoutView, nil]
      def call(order: nil)
        return nil if order.nil?

        loaded = PallasTrade::Order.includes(INCLUDES).find(order.id)
        CheckoutView.new(order: loaded)
      end
    end

    # CheckoutView DTO（只读投影值对象；非 AR Model、非新数据源、不拥有业务数据）。
    class CheckoutView
      # 权威标量：状态/联系/金额 —— 全部委托 Order 现有列与只读方法，零计算。
      DELEGATED = %i[
        number state status payment_state shipment_state email currency
        item_total display_item_total
        delivery_total display_delivery_total
        adjustment_total display_adjustment_total
        discount_total display_discount_total
        tax_total display_tax_total
        included_tax_total display_included_tax_total
        additional_tax_total display_additional_tax_total
        total display_total amount_due display_amount_due
        submitted_at completed_at
        # CHK-P1-2：版本/过期正式列（checkout_version 内容版本；price_version 金额指纹；checkout_expires_at 报价过期）
        checkout_version price_version checkout_expires_at
      ].freeze

      attr_reader :order

      def initialize(order:)
        @order = order
      end

      DELEGATED.each do |name|
        define_method(name) { order.public_send(name) }
      end

      def id
        order.prefixed_id
      end

      def items
        order.line_items
      end

      def shipping_address
        order.ship_address
      end

      def billing_address
        order.bill_address
      end

      def fulfillments
        order.shipments
      end

      # 解释性折扣明细（只读权威列；合计权威 = discount_total）。
      def discounts
        order.adjustments.select { |a| a.eligible? && a.promotion? }.map { |adj| Line.new(adj) }
      end

      # 解释性税明细（只读权威列；合计权威 = tax_total）。
      def taxes
        order.adjustments.select { |a| a.eligible? && a.tax? }.map { |adj| Line.new(adj) }
      end

      # CHK-P1-3：Server Readiness（只读聚合；委托 OrderCheckout::Readiness，零副作用）。
      def ready
        readiness.ready
      end

      def missing_requirements
        readiness.missing_requirements
      end

      # 明细行（非 API 资源，仅供展示解释；不重新求和）。
      class Line
        attr_reader :id, :amount, :currency

        def initialize(adjustment)
          @id = adjustment.prefixed_id
          @amount = adjustment.amount&.to_s
          @currency = adjustment.currency
        end
      end

      private

      def readiness
        @readiness ||= PallasTrade::OrderCheckout::Readiness.call(order: order)
      end
    end
  end
end
