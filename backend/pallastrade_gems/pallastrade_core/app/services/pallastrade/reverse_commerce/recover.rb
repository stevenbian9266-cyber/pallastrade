# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-8e (PRD-20260908-payments-rev-p6-8e-reverse-commerce-recover-cross-domain)
#
# ReverseCommerce::Recover —— Order 锚点的跨域收敛（源 REV-P6 §45：统一 application layer，消费事实、不猜）。
#
# 本包收敛面：
#   - Restock 域（新能力）：order 可达 return_items 逐条 `Returns::RestockFact.resolve`；
#     AMBIGUOUS（accepted+eligible 但 StockMovement 缺失 —— REV-P6-5 后唯一无人收敛的缺口）→
#     `return_item.restock_if_ambiguous!` 幂等自愈（exactly-once，partial unique 兜底）；
#     RESTOCKED/NOT_REQUIRED/NOT_RESTOCKABLE/PENDING 只计数不动作（PENDING 由上游验收裁决）。
#   - Refund 域（复用）：order.payments 可达 refunds 逐条 `Refunds::Recover.call(refund:)`
#     （幂等；fresh/terminal 为 no-op 不产生副作用）。组合/无 order 退款由全局
#     Refunds::RecoverSweeperJob 覆盖，本服务不重复扫描。
#
# 边界（记录不实施）：Journal/Reconcile 修复派发归 P4 ReconcileSweeper；取消意图恢复/组合级编排；自动调度。
# 零新增资金副作用：restock 自愈只建正向 StockMovement（已决策的 exactly-once 事实），退款只走既有 Recover。
module PallasTrade
  module ReverseCommerce
    class Recover
      prepend PallasTrade::ServiceModule::Base

      # @param order [PallasTrade::Order]
      # @return [PallasTrade::ServiceModule::Result] success({order_id:, restock:{}, refunds:{}, errors:})
      def call(order:)
        return failure(nil, 'Order not found') if order.nil?

        order = PallasTrade::Order.find_by(id: order.id)
        return failure(nil, 'Order not found') if order.nil?

        restock = recover_restock(order)
        refunds = recover_refunds(order)

        success(order_id: order.prefixed_id, restock: restock, refunds: refunds,
                errors: restock[:errors] + refunds[:errors])
      end

      private

      def recover_restock(order)
        counts = { healed: 0, ambiguous: 0, restocked: 0, not_required: 0, not_restockable: 0,
                   pending: 0, errors: 0 }
        fact_klass = PallasTrade::Returns::RestockFact

        order.customer_returns.includes(:return_items).each do |customer_return|
          customer_return.return_items.each do |item|
            fact = begin
              fact_klass.resolve(return_item: item)
            rescue StandardError => e
              counts[:errors] += 1
              Rails.logger.warn("[ReverseCommerce::Recover] restock resolve error order=#{order.number} " \
                                "return_item=#{item.id}: #{e.class} #{e.message}")
              next
            end

            case fact
            when fact_klass::AMBIGUOUS
              counts[:ambiguous] += 1
              begin
                counts[:healed] += 1 if item.restock_if_ambiguous!
              rescue StandardError => e
                counts[:errors] += 1
                Rails.logger.warn("[ReverseCommerce::Recover] restock heal error order=#{order.number} " \
                                  "return_item=#{item.id}: #{e.class} #{e.message}")
              end
            when fact_klass::RESTOCKED then counts[:restocked] += 1
            when fact_klass::NOT_REQUIRED then counts[:not_required] += 1
            when fact_klass::NOT_RESTOCKABLE then counts[:not_restockable] += 1
            when fact_klass::PENDING then counts[:pending] += 1
            else counts[:errors] += 1 # 未知 fact（不应发生）
            end
          end
        end
        counts
      end

      def recover_refunds(order)
        stats = { attempted: 0, ok: 0, noop: 0, errors: 0 }
        order.payments.includes(:refunds).each do |payment|
          payment.refunds.each do |refund|
            stats[:attempted] += 1
            begin
              outcome = PallasTrade::Refunds::Recover.call(refund: refund)
              outcome.success? ? stats[:ok] += 1 : stats[:noop] += 1
            rescue StandardError => e
              stats[:errors] += 1
              Rails.logger.warn("[ReverseCommerce::Recover] refund recover error order=#{order.number} " \
                                "refund=#{refund.id}: #{e.class} #{e.message}")
            end
          end
        end
        stats
      end
    end
  end
end
