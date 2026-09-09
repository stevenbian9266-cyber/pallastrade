# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-8m (PRD-20260909-payments-孤儿退款补记-backfill-refunds-backfillproviderrefund-rake-dry-run-)
#
# 孤儿退款补记 rake —— 人工门（默认 dry-run 只读；APPLY=1 才写）。
# 用法：
#   rake pallastrade:refunds:backfill_orphans[store_id]     # dry-run：TSV 计划 + summary
#   APPLY=1 rake pallastrade:refunds:backfill_orphans[store_id]
#
# 语义：扫单店 completed PSP 支付 → OrphanPairing 孤儿（provider-only）→ 每条调
# Refunds::BackfillProviderRefund（幂等 noop / 金额不可证明 skip）。**绝不调 PSP**（补记=记录已发生资金）。
# 单条异常隔离不中断；Audit.record 由服务完成。
namespace :pallastrade do
  namespace :refunds do
    desc 'Backfill provider orphan refunds as local durable records (dry-run default; APPLY=1 to write)'
    task :backfill_orphans, [:store_id] => :environment do |_task, args|
      store = if args[:store_id].to_s.strip.present?
                PallasTrade::Store.find_by(id: args[:store_id].to_s.strip)
              else
                PallasTrade::Store.default
              end
      abort "Store not found (#{args[:store_id].inspect})" if store.nil?

      apply = ENV['APPLY'] == '1'
      via_order = PallasTrade::Payment.completed
                     .joins(:order)
                     .where(pallastrade_orders: { store_id: store.id })
      via_combination = PallasTrade::Payment.completed
                          .joins(:payment_combination)
                          .where(pallastrade_payment_combinations: { store_id: store.id })
      # or 需结构兼容 → id 子查询（镜像 Refund#for_store 模式，规避 joins 不兼容）
      payments = PallasTrade::Payment
                 .where(id: via_order)
                 .or(PallasTrade::Payment.where(id: via_combination))
                 .distinct.order(:id)
      puts "store=#{store.code} mode=#{apply ? 'APPLY' : 'DRY-RUN'} payments=#{payments.count}"

      counts = Hash.new(0)
      payments.each do |payment|
        begin
          outcome = PallasTrade::Refunds::OrphanPairing.call(payment: payment)
          value = outcome.success? ? outcome.value : nil
          next if outcome.failure? || value.nil?
          next unless value.status == 'needs_attention'
          next if value.orphans.empty?

          value.orphans.each do |orphan|
            provider_id = orphan[:provider_id].to_s
            next if provider_id.blank?

            if apply
              result = PallasTrade::Refunds::BackfillProviderRefund.call(
                payment: payment,
                provider_id: provider_id,
                amount: orphan[:amount],
                currency: orphan[:currency],
                actor: 'rake'
              )
              if result.success?
                v = result.value
                counts[v[:status]] += 1
                puts [payment.prefixed_id, payment.currency, provider_id, orphan[:amount], v[:status],
                      v[:reason], v[:refund_id]].join("\t")
              else
                counts['error'] += 1
                puts [payment.prefixed_id, payment.currency, provider_id, orphan[:amount], 'error',
                      result.error].join("\t")
              end
            else
              counts['planned'] += 1
              puts [payment.prefixed_id, payment.currency, provider_id, orphan[:amount], 'planned',
                    orphan[:amount].nil? ? 'orphan_amount_unavailable' : ''].join("\t")
            end
          end
        rescue StandardError => e
          counts['error'] += 1
          puts [payment&.prefixed_id, 'error', "#{e.class}: #{e.message}"].join("\t")
        end
      end

      puts "summary\t#{counts.map { |k, v| "#{k}=#{v}" }.join(' ')}"
      puts 'DRY-RUN only — set APPLY=1 to write' unless apply
    end
  end
end
