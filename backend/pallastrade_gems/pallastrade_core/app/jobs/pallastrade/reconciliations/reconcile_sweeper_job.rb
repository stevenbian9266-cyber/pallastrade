# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-8 (PRD-20260906-payments-fin-p4-8)
#
# Reconciliations::ReconcileSweeperJob —— 保守的 reconciliation sweeper（sidekiq-cron 周期调度）。
#
# 设计决策（保守自动，参考 Transactions::RecoverSweeperJob）：
#   - 扫描有 reconciliation 价值（completed / payment_confirmed / finalizing）的 transaction：
#     逐个 `ReconcileTransaction`（只读、幂等）→ 统计 status 分布（metrics 日志）。
#   - **自动修复（安全子集）**：journal-missing（JOURNAL_POSTING_MISSING）→ enqueue
#     `FinancialLedger::RepairTransactionJob`（幂等补记——§44「repair missing Journal projection」允许；
#     不触碰 Payment/Refund/资金）。
#   - **绝不自动**（§44/§46）：mismatch / needs_attention / provider 冲突 → 仅计数 + warn 日志，
#     人工/runbook 介入；不自动 charge/refund/倒退 transaction state。
#   - 幂等：ReconcileTransaction 纯函数 + RepairTransactionJob 幂等；重复调度安全。
#   - metrics 输出结构化 JSON（event/store_id/status 分布/repair 计数），供告警与 runbook。
module PallasTrade
  module Reconciliations
    class ReconcileSweeperJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.default

      # @param store_id [Integer, nil] 限定单店（默认全店扫描）
      # @param states [Array<String>, nil] 覆盖默认扫描状态（测试注入；默认 completed/
      #   payment_confirmed/finalizing）
      def perform(store_id: nil, states: nil)
        stores = PallasTrade::Store.all
        stores = stores.where(id: store_id) if store_id
        stores.find_each { |store| sweep_store(store, Array(states)) }
      end

      private

      SCOPE_STATES = %w[completed payment_confirmed finalizing].freeze

      def sweep_store(store, states)
        scope_states = states.presence || SCOPE_STATES
        base = store.commerce_transactions.where(state: scope_states).reorder(:id)

        counts = Hash.new(0)
        repair_enqueued = 0
        needs_human = []
        cases_opened = 0
        cases_auto_closed = 0

        base.find_each do |tx|
          result = PallasTrade::Reconciliations::ReconcileTransaction.call(transaction: tx)
          next unless result.success?

          value = result.value
          counts[value.status.to_s] += 1
          if value.reasons.include?('JOURNAL_POSTING_MISSING')
            PallasTrade::FinancialLedger::RepairTransactionJob.perform_later(tx.prefixed_id)
            repair_enqueued += 1
          end
          needs_human << tx.prefixed_id if value.needs_attention? || value.mismatch? || value.pending?

          # D13 切片1（PRD-20260916-payments-d13）：把只读结论落成**差异案例队列**（唯一写入口）。
          # 仅写案例表 + 审计；失败（含异常）不阻断巡检（下一轮重试）。
          cases_opened, cases_auto_closed = sync_cases(tx, cases_opened, cases_auto_closed)
        end

        log_payload = {
          event: 'reconciliations.sweeper',
          store_id: store.id,
          status_counts: counts,
          repair_enqueued: repair_enqueued,
          cases_opened: cases_opened,
          cases_auto_closed: cases_auto_closed,
          needs_human: needs_human
        }
        Rails.logger.info(log_payload.to_json)

        if needs_human.any?
          Rails.logger.warn(
            "[FIN-P4-8] transactions need financial review (store #{store.id}): " \
            "#{needs_human.inspect} — use rake pallastrade:reconciliations:{reconcile,repair}[txn] " \
            'or docs/operations/financial-reconciliation-runbook.md'
          )
        end
      end

      # D13：案例同步（失败降级为 warn，不中断巡检）。
      # @return [Array(Integer, Integer)] [opened_count, auto_closed_count]
      def sync_cases(tx, opened_count, closed_count)
        cases = PallasTrade::Reconciliations::SyncCases.call(transaction: tx)
        return [opened_count, closed_count] unless cases.success?

        [opened_count + cases.value[:opened].size, closed_count + cases.value[:closed].size]
      rescue StandardError => e
        Rails.logger.warn(
          message: 'reconciliations.sweeper_case_sync_failed',
          transaction: tx.prefixed_id,
          error: e.class.name,
          detail: e.message.to_s.truncate(200)
        )
        [opened_count, closed_count]
      end
    end
  end
end
