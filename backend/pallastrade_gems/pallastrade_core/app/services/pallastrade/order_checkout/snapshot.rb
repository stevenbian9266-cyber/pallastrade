# frozen_string_literal: true

require 'digest'

# PALLAS-CUSTOM: CHK-P1-3 (PRD-20260903-checkout-chk-p1-1 §12)
module PallasTrade
  module OrderCheckout
    # CheckoutSnapshot —— Order + Checkout Version + Price Version 的确定性
    # transaction projection（只读值对象，不落库；PRD 禁 CheckoutSession/新表）。
    #
    # 用途：支付启动/后续 409 冲突比对时的「客户端所见报价」冻结事实。
    # 零副作用：不 save/touch/不跑 updater/不推进状态机。
    class Snapshot
      # @return [PallasTrade::OrderCheckout::CheckoutSnapshot, nil]
      def self.call(order: nil)
        new.call(order: order)
      end

      def call(order: nil)
        return nil if order.nil?

        fields = {
          order_id: order.prefixed_id,
          number: order.number,
          state: order.state,
          currency: order.currency,
          checkout_version: order.checkout_version,
          price_version: order.price_version,
          checkout_expires_at: order.checkout_expires_at&.iso8601,
          item_total: order.item_total.to_s,
          shipment_total: order.shipment_total.to_s,
          adjustment_total: order.adjustment_total.to_s,
          discount_total: order.discount_total.to_s,
          tax_total: order.tax_total.to_s,
          total: order.total.to_s,
          amount_due: order.amount_due.to_s
        }
        CheckoutSnapshot.new(**fields, fingerprint: fingerprint(fields))
      end

      private

      # 与 Recalculate 金额指纹同源精神：含 quote 身份 + 版本 + 权威金额，
      # 任一变化 → fingerprint 变化（供后续 409/客户端比对）。
      def fingerprint(fields)
        parts = [
          fields[:order_id], fields[:checkout_version], fields[:price_version],
          fields[:currency], fields[:amount_due]
        ].join('|')
        Digest::SHA256.hexdigest(parts)[0, 16]
      end
    end

    # 冻结的只读投影值对象。
    class CheckoutSnapshot
      FIELDS = %i[
        order_id number state currency checkout_version price_version checkout_expires_at
        item_total shipment_total adjustment_total discount_total tax_total total amount_due
        fingerprint
      ].freeze

      attr_reader(*FIELDS)

      def initialize(**fields)
        FIELDS.each { |name| instance_variable_set("@#{name}", fields.fetch(name)) }
        freeze
      end

      def to_h
        FIELDS.index_with { |name| public_send(name) }
      end

      def ==(other)
        other.is_a?(CheckoutSnapshot) && to_h == other.to_h
      end
    end
  end
end
