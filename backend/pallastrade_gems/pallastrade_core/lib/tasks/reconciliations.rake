# frozen_string_literal: true

# FIN-P4-8 (PRD-20260906-payments-fin-p4-8): reconciliation ops rake——
# manual repair / reconcile / backfill（三类语义 §50）tooling。
# 用法见 docs/operations/financial-reconciliation-runbook.md。
namespace :pallastrade do
  namespace :reconciliations do
    desc 'List transactions needing financial attention (completed/payment_confirmed/finalizing)'
    task list_needs_attention: :environment do
      states = %w[completed payment_confirmed finalizing]
      rows = PallasTrade::CommerceTransaction.where(state: states).order(:updated_at)
      puts "count=#{rows.count}"
      rows.each do |tx|
        result = PallasTrade::Reconciliations::ReconcileTransaction.call(transaction: tx)
        status = result.success? ? result.value.status : "error:#{result.error.inspect}"
        reasons = result.success? ? result.value.reasons.join(',') : ''
        puts [tx.prefixed_id, tx.state, status, reasons, tx.currency, tx.amount.to_s,
              tx.updated_at.iso8601].join("\t")
      end
    end

    desc 'Manually re-run transaction reconciliation (read-only). Usage: rake pallastrade:reconciliations:reconcile[txn_xxx]'
    task :reconcile, [:id] => :environment do |_task, args|
      id = args[:id].to_s.strip
      abort 'usage: rake pallastrade:reconciliations:reconcile[<txn_ prefixed id>]' if id.empty?

      tx = PallasTrade::CommerceTransaction.find_by_prefix_id!(id)
      result = PallasTrade::Reconciliations::ReconcileTransaction.call(transaction: tx)
      if result.success?
        value = result.value
        puts "reconcile #{tx.prefixed_id}: status=#{value.status} reasons=#{value.reasons.join(',')}"
        puts "  summary=#{value.summary.to_h}"
      else
        warn "reconcile failed #{tx.prefixed_id}: #{result.error.inspect}"
        exit 1
      end
    end

    desc 'Idempotently repair missing journal entries for a transaction. Usage: rake pallastrade:reconciliations:repair[txn_xxx]'
    task :repair, [:id] => :environment do |_task, args|
      id = args[:id].to_s.strip
      abort 'usage: rake pallastrade:reconciliations:repair[<txn_ prefixed id>]' if id.empty?

      tx = PallasTrade::CommerceTransaction.find_by_prefix_id!(id)
      result = PallasTrade::FinancialLedger::RepairTransaction.call(transaction: tx)
      if result.success?
        value = result.value
        puts "repair #{tx.prefixed_id}: repaired=#{value[:repaired].size} " \
             "already_present=#{value[:already_present].size} skipped=#{value[:skipped].inspect}"
      else
        warn "repair failed #{tx.prefixed_id}: #{result.error.inspect}"
        exit 1
      end
    end

    desc 'Controlled journal backfill (three-way, §50). Usage: rake pallastrade:reconciliations:backfill[store_id?]'
    task :backfill, [:store_id] => :environment do |_task, args|
      stores = PallasTrade::Store.all
      stores = stores.where(id: args[:store_id].to_i) if args[:store_id].to_s.present?
      txn_provable = 0
      txn_partially = 0
      txn_unprovable = 0
      repaired = 0

      stores.find_each do |store|
        txns = store.commerce_transactions.where(state: 'completed').reorder(:id)
        txns.find_each do |tx|
          result = PallasTrade::FinancialLedger::RepairTransaction.call(transaction: tx)
          next unless result.success?

          value = result.value
          # PROVABLE：至少补记一条 entry（captured/refund/allocation 证据可证明）。
          # PARTIALLY_PROVABLE：journal 已完整（无缺失）或全部 skipped 但 source 存在——
          #   reconcile 状态如实 PENDING/UNSUPPORTED（缺 provider settlement 信息）。
          # UNPROVABLE：无可修复 source（无 captured payment / 无 succeeded refund /
          #   无 settled combination），证据无法证明 → 不写不猜（AC-4025/§50）。
          if value[:repaired].any?
            txn_provable += 1
            repaired += value[:repaired].size
          elsif value[:already_present].any? || value[:skipped].any?
            txn_partially += 1
          else
            txn_unprovable += 1
          end
        end
      end

      puts "backfill done: journal_entries_repaired=#{repaired} txn_provable=#{txn_provable} " \
           "txn_partially_provable=#{txn_partially} txn_unprovable=#{txn_unprovable}"
    end
  end
end
