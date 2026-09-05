# frozen_string_literal: true

# PALLAS-CUSTOM: TXN-P2-7 slice2 (PRD-20260905-payments-txn-p2-7, REQ-20260905-txn-p2-7-admin-sweeper)
#
# Transactions::RecoverSweeperJob —— 保守的自动 stuck sweeper（sidekiq-cron 周期调度）。
#
# 设计决策（用户确认「保守」）：只自动处理明确可安全恢复的 `recovery_required`
# 交易（enqueue Transactions::RecoverJob——先 PaymentFactResolver 权威判定再分支，
# 幂等：with_lock + 状态守卫 + attempts 计数）。以下状态一律**不自动处理**，仅计数
# 并输出结构化日志（metrics）供人工/告警：
#   - manual_review：AC-2014 状态无法确定必须人工，不猜测
#   - stuck payment_confirmed / finalizing（超阈值未进展）：可能正在 finalize 或
#     provider I/O 中，自动重跑有重复副作用风险；列示 + 日志（stuck visibility），
#     Admin/rake 人工介入（INV-04 不默认新建动作；INV-08 由人工时机决定）
#
# 幂等性：enqueue RecoverJob 本身无副作用（Recover 幂等）；重复调度安全。
module PallasTrade
  module Transactions
    class RecoverSweeperJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.default

      # @param threshold_hours [Integer] stuck（payment_confirmed/finalizing）判定阈值
      # @param store_id [Integer, nil] 限定单店（默认全店扫描）
      def perform(threshold_hours: 1, store_id: nil)
        stores = PallasTrade::Store.all
        stores = stores.where(id: store_id) if store_id
        stores.find_each { |store| sweep_store(store, threshold_hours.to_i.hours) }
      end

      private

      def sweep_store(store, threshold)
        stuck_before = Time.current - threshold
        base = store.commerce_transactions

        # prefixed_id 是 has_prefix_id 计算值（非物理列），须经 find_each 取对象。
        # reorder(:id)：find_each 需要 PK 稳定序，避免默认序触发的 Rails 告警。
        recovery = base.where(state: 'recovery_required').reorder(:id)
        recovery_count = recovery.count
        recovery.find_each do |tx|
          PallasTrade::Transactions::RecoverJob.perform_later(tx.prefixed_id)
        end

        manual_review_count = base.where(state: 'manual_review').count
        stuck_counts = PallasTrade::CommerceTransaction::STUCK_STATES.to_h do |state|
          [state, base.where(state: state).where(updated_at_lt(stuck_before)).count]
        end

        log_payload = {
          event: 'transactions.recover_sweeper',
          store_id: store.id,
          recovery_required_enqueued: recovery_count,
          manual_review: manual_review_count,
          stuck_payment_confirmed: stuck_counts['payment_confirmed'] || 0,
          stuck_finalizing: stuck_counts['finalizing'] || 0,
          threshold_hours: threshold / 3600
        }
        Rails.logger.info(log_payload.to_json)

        # alerts（最小集）：不新建通知通道，存在需人工项时提升为 warn 日志
        if manual_review_count.positive? || stuck_counts.values.any? { |v| v.to_i.positive? }
          Rails.logger.warn(
            "[TXN-P2-7] transactions need human attention (store #{store.id}): " \
            "manual_review=#{manual_review_count} stuck=#{stuck_counts.inspect} " \
            '— use Admin Transactions or rake pallastrade:transactions:recover[id]'
          )
        end
      end

      def updated_at_lt(before)
        PallasTrade::CommerceTransaction.arel_table[:updated_at].lt(before)
      end
    end
  end
end
