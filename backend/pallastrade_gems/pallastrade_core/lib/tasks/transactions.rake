# frozen_string_literal: true

# TXN-P2-7 (PRD-20260905-payments-txn-p2-7): transaction 运维 rake——
# stuck/needs-attention 可见性与 manual recovery tooling。
# 用法见 docs/operations/transaction-recovery-runbook.md。
namespace :pallastrade do
  namespace :transactions do
    desc 'List transactions needing attention (recovery/manual_review or stuck payment_confirmed/finalizing > 1h)'
    task list_needs_attention: :environment do
      rows = PallasTrade::CommerceTransaction.needs_attention.order(:updated_at)
      puts "count=#{rows.count}"
      rows.each do |tx|
        puts [tx.prefixed_id, tx.state, tx.purpose, tx.currency, tx.amount.to_s,
              tx.updated_at.iso8601].join("\t")
      end
    end

    desc 'Manually recover a transaction (manual recovery tooling). Usage: rake pallastrade:transactions:recover[txn_xxx]'
    task :recover, [:id] => :environment do |_task, args|
      id = args[:id].to_s.strip
      abort 'usage: rake pallastrade:transactions:recover[<txn_ prefixed id>]' if id.empty?

      tx = PallasTrade::CommerceTransaction.find_by_prefix_id!(id)
      result = PallasTrade::Transactions::Recover.call(transaction: tx)
      if result.success?
        puts "recovered #{tx.prefixed_id}: action=#{result.value[:action]} state=#{tx.reload.state}"
      else
        error = result.error.respond_to?(:value) ? result.error.value : result.error
        warn "recover failed #{tx.prefixed_id}: #{error.inspect}"
        exit 1
      end
    end
  end
end
