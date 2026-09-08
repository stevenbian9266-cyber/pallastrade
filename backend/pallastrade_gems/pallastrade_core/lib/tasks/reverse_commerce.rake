# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-8e (PRD-20260908-payments-rev-p6-8e-reverse-commerce-recover-cross-domain)
#
# ReverseCommerce::Recover ops rake（手动收敛；不做自动调度以免干扰 restock 时序决策）。
# 用法见 docs/operations/reverse-commerce-recover-runbook.md。
#   rake pallastrade:reverse_commerce:recover[order_xxx]        单 order 跨域收敛
#   rake pallastrade:reverse_commerce:list_ambiguous[store_id]  列出 restock AMBIGUOUS return items
namespace :pallastrade do
  namespace :reverse_commerce do
    desc 'Run cross-domain reverse recovery for one order. Usage: rake pallastrade:reverse_commerce:recover[order_xxx]'
    task :recover, [:order_id] => :environment do |_task, args|
      id = args[:order_id].to_s.strip
      abort 'usage: rake pallastrade:reverse_commerce:recover[<order_ prefixed id>]' if id.empty?

      order = PallasTrade::Order.find_by_prefix_id!(id)
      outcome = PallasTrade::ReverseCommerce::Recover.call(order: order)
      abort "recover failed: #{outcome.error.inspect}" if outcome.failure?

      v = outcome.value
      puts "order=#{v[:order_id]}"
      puts "restock\thealed=#{v[:restock][:healed]}\tambiguous=#{v[:restock][:ambiguous]}\t" \
           "restocked=#{v[:restock][:restocked]}\tnot_required=#{v[:restock][:not_required]}\t" \
           "not_restockable=#{v[:restock][:not_restockable]}\tpending=#{v[:restock][:pending]}\t" \
           "errors=#{v[:restock][:errors]}"
      puts "refunds\tattempted=#{v[:refunds][:attempted]}\tok=#{v[:refunds][:ok]}\tnoop=#{v[:refunds][:noop]}\t" \
           "errors=#{v[:refunds][:errors]}"
    end

    desc 'List restock-AMBIGUOUS return items for a store. Usage: rake pallastrade:reverse_commerce:list_ambiguous[store_id]'
    task :list_ambiguous, [:store_id] => :environment do |_task, args|
      store = if args[:store_id].to_s.strip.present?
                PallasTrade::Store.find_by(id: args[:store_id].to_s.strip)
              else
                PallasTrade::Store.default
              end
      abort "Store not found (#{args[:store_id].inspect})" if store.nil?

      resolver = PallasTrade::Returns::RestockFact
      rows = []
      store.orders.find_each do |order|
        order.customer_returns.includes(:return_items).each do |cr|
          cr.return_items.each do |item|
            fact = resolver.resolve(return_item: item)
            rows << [order.number, cr.number, item.prefixed_id, fact] if fact == resolver::AMBIGUOUS
          end
        end
      end
      puts "store=#{store.code} ambiguous=#{rows.size}"
      rows.each { |r| puts r.join("\t") }
    end
  end
end
