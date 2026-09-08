# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-8d (PRD-20260908-payments-rev-p6-8d-provider-orphan-refund-pairing)
#
# Refund ops rake —— provider 孤儿退款配对（只读）。用法见
# docs/operations/refund-orphan-pairing-runbook.md。
#   rake pallastrade:refunds:orphans[store_id]  扫单店 completed PSP 支付 → TSV + 汇总
namespace :pallastrade do
  namespace :refunds do
    desc 'List provider orphan refunds (read-only pairing). Usage: rake pallastrade:refunds:orphans[store_id]'
    task :orphans, [:store_id] => :environment do |_task, args|
      store = if args[:store_id].to_s.strip.present?
                PallasTrade::Store.find_by(id: args[:store_id].to_s.strip)
              else
                PallasTrade::Store.default
              end
      abort "Store not found (#{args[:store_id].inspect})" if store.nil?

      via_order = PallasTrade::Payment.completed
                     .joins(:order)
                     .where(pallastrade_orders: { store_id: store.id })
      via_combination = PallasTrade::Payment.completed
                          .joins(:payment_combination)
                          .where(pallastrade_payment_combinations: { store_id: store.id })
      payments = via_order.or(via_combination).distinct.order(:id)
      puts "store=#{store.code} payments=#{payments.count}"

      counts = Hash.new(0)
      payments.each do |payment|
        outcome = PallasTrade::Refunds::OrphanPairing.call(payment: payment)
        value = outcome.success? ? outcome.value : nil
        status = outcome.success? ? value.status : "error:#{outcome.error.inspect}"
        counts[status] += 1

        next if outcome.failure?
        next if value.status.in?(%w[not_applicable unsupported matched])

        reasons = value.reasons.join(',')
        orphans = value.orphans.map { |o| o[:provider_id] }.join('|')
        # REV-P6-8h：孤儿金额/币种（只读；能力缺失或异常为空白）
        orphan_amounts = value.orphans.map { |o| o[:amount] }.join('|')
        orphan_currencies = value.orphans.map { |o| o[:currency] }.join('|')
        local_missing = value.local_unmatched.map { |u| u[:transaction_id] }.join('|')
        puts [payment.prefixed_id, payment.currency, status, reasons, orphans, orphan_amounts,
              orphan_currencies, local_missing, payment.updated_at.iso8601].join("\t")
      end

      puts "summary\t#{counts.map { |k, v| "#{k}=#{v}" }.join(' ')}"
    end
  end
end
