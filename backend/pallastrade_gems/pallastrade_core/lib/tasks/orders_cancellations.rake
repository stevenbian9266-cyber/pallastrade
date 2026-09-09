# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-8j (PRD-20260909-payments-rev-p6-8j-ordercancellation-state-machine)
#
# OrderCancellation 取消意图审计 rake —— 只读。§34 durable intent + §35 恢复收尾。
#   rake pallastrade:orders:cancellations:list_attention[store_id]
# 覆盖两类 attention：
#   - state ∈ recovery_required/manual_review（Ops 标记需关注）
#   - applied 且 refund_payments=true（意图已决定退款）但订单无可退源 durable Refund 行
#     → ATTENTION_NO_DURABLE_REFUND（资金意图未落地：8f 前 legacy/异常；修复后重跑 Orders::Cancel 幂等收敛）
namespace :pallastrade do
  namespace :orders do
    namespace :cancellations do
      desc 'List cancellation intents needing attention. Usage: rake pallastrade:orders:cancellations:list_attention[store_id]'
      task :list_attention, [:store_id] => :environment do |_task, args|
        store = if args[:store_id].to_s.strip.present?
                  PallasTrade::Store.find_by(id: args[:store_id].to_s.strip)
                else
                  PallasTrade::Store.default
                end
        abort "Store not found (#{args[:store_id].inspect})" if store.nil?

        durable_refund_count = lambda do |order|
          payment_ids = PallasTrade::Payment.where(order_id: order.id).pluck(:id)
          split_ids = order.payment_splits.pluck(:id)
          scope = PallasTrade::Refund.none
          scope = scope.or(PallasTrade::Refund.where(payment_id: payment_ids)) if payment_ids.any?
          scope = scope.or(PallasTrade::Refund.where(payment_split_id: split_ids)) if split_ids.any?
          scope.count
        end

        scope = PallasTrade::OrderCancellation.joins(:order)
                                               .where(pallastrade_orders: { store_id: store.id })
        rows = []
        counts = Hash.new(0)
        scope.find_each do |oc|
          order = oc.order
          if oc.state.in?(%w[recovery_required manual_review])
            rows << [order.number, oc.prefixed_id, oc.state, '', oc.updated_at.iso8601]
            counts[oc.state] += 1
          elsif oc.state == 'applied' && oc.refund_payments && order.canceled? && durable_refund_count.call(order).zero?
            rows << [order.number, oc.prefixed_id, 'applied', 'ATTENTION_NO_DURABLE_REFUND', oc.updated_at.iso8601]
            counts['ATTENTION_NO_DURABLE_REFUND'] += 1
          end
        end

        puts "store=#{store.code} cancellations=#{scope.count} attention=#{rows.size}"
        rows.each { |r| puts r.join("\t") }
        puts "summary\t#{counts.map { |k, v| "#{k}=#{v}" }.join(' ')}"
      end
    end
  end
end
