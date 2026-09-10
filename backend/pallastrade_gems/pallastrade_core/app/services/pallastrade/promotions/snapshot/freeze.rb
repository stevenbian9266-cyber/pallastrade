# frozen_string_literal: true

# PRD-20260910-promotions-promo-batch4a-orderpromotion-snapshot (FR-003, D2/D3/D6/D7)
#
# 成交快照冻结：把「订单成交（资金确认）时的促销展示事实」写入
# `pallastrade_order_promotions` 快照列，此后促销改名 / 改 kind / 停用或改码 /
# 删除动作都不会再影响历史订单展示（架构 §35 Promotion Snapshot、§134）。
#
# 设计要点：
#   * 金额直接复用 batch2 统一投影 `DiscountProjection`（唯一口径，不重算引擎）；
#   * 仅对**已成交**订单生效（`completed?` 或标准流程 `paid+`），购物车/未支付订单不写；
#   * 幂等：已冻结行（`frozen?`）原样跳过，绝不覆盖历史值；
#   * 容错：整体 rescue + 日志，**不打断** `complete/pay` 事务与支付确认链路。
module PallasTrade
  module Promotions
    module Snapshot
      class Freeze
        # 标准流程（Carts::Submit 创建）中代表"资金已确认"的状态。
        MONEY_CONFIRMED_STATES = %w[paid processing shipped completed].freeze

        def self.call(order, force: false)
          new(order, force: force).call
        end

        def initialize(order, force: false)
          @order = order
          @force = force
        end

        # @return [Array<PallasTrade::OrderPromotion>] 本次实际冻结的行（幂等跳过的不计）
        def call
          return [] if order.nil?
          return [] unless force || freezeable?

          lines = PallasTrade::Promotions::Projection::DiscountProjection.for(order: order)
          return [] if lines.empty?

          lines.filter_map { |line| freeze_line(line) }
        rescue StandardError => e
          Rails.logger.error(
            "[Promotions::Snapshot::Freeze] order=#{order&.id} freeze failed: #{e.class} #{e.message}"
          )
          []
        end

        private

        attr_reader :order, :force

        # R1：只有"资金已确认"的订单才冻结（购物车 / 未支付订单保持实时）。
        # `force: true` 仅供 `commerce_transaction.payment_confirmed` 这一资金确认事件
        # 使用——事件本身就是资金信号，订单状态机可能尚未推进（D2）。
        def freezeable?
          return true if order.completed_at.present?

          MONEY_CONFIRMED_STATES.include?(order.state.to_s)
        end

        # R2/R9：同一 (order, promotion) 一行；已冻结跳过；唯一索引兜底并发。
        def freeze_line(line)
          promotion = line.promotion
          return nil if promotion.nil?

          row = PallasTrade::OrderPromotion.find_or_initialize_by(
            order_id: order.id,
            promotion_id: promotion.id
          )
          return nil if row.frozen?

          row.assign_attributes(
            name: line.name,
            kind: promotion.kind,
            code: line.code,
            description: line.description,
            definition_digest: promotion.definition_digest,
            item_amount: line.item_amount,
            order_amount: line.order_amount,
            shipping_amount: line.shipping_amount,
            total_amount: line.amount,
            currency: order.currency,
            frozen_at: Time.current
          )
          row.save!
          row
        rescue ActiveRecord::RecordNotUnique
          # 并发下另一个执行路径刚插入同一行：重取并返回（不覆盖，保持幂等语义）。
          PallasTrade::OrderPromotion.find_by(order_id: order.id, promotion_id: promotion.id)
        end
      end
    end
  end
end
