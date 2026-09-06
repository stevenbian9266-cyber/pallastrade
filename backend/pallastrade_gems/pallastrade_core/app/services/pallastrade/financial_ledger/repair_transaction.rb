# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-8 (PRD-20260906-payments-fin-p4-8)
#
# FinancialLedger::RepairTransaction —— Journal 幂等补记原语（P4 §49 Journal Posting Recovery）。
#
# 语义：
#   - **目标**：missing Journal + source financial fact 仍存在 → idempotent repost（§49）。
#   - **绝不**（§44/§49/INV-08/09/12）：重新 Payment、重新 Refund、修改任何 state machine、
#     自动 charge/refund/倒退 transaction state。唯一写 = FinancialLedgerEntry（经既有幂等
#     PostPayment/PostRefund/PostAllocation 编排——内部 Resolve → 门禁 postable? → Post 幂等 key）。
#   - **修复范围**（复用 FIN-P4-7 的 journal-missing 检测语义）：
#     1. captured payments（CaptureEvidencePolicy verdict=captured）缺 CASH_CAPTURED active entry → PostPayment；
#     2. succeeded refunds（transaction_id present）缺 REFUND_SUCCEEDED active entry → PostRefund；
#     3. settled combination splits（combination.succeeded 且 split.captured>0）缺 ORDER_ALLOCATION
#        active entry → PostAllocation（组合 txn 路径）。
#   - 不可证明/缺证据源 → skipped（不猜，UNPROVABLE 语义 §50/AC-4025 由 backfill rake 分类处理）。
#   - 幂等：全编排幂等（Post idempotency key）+ already_present 检测不重复调用；纯函数可重跑。
#   - 供 `reconciliations.rake:repair[txn]` / `ReconcileSweeperJob`（journal-missing 自动）消费。
module PallasTrade
  module FinancialLedger
    class RepairTransaction
      prepend PallasTrade::ServiceModule::Base

      # @param transaction [PallasTrade::CommerceTransaction]
      # @return [PallasTrade::ServiceModule::Result]
      #   success({ repaired: [FinancialLedgerEntry], already_present: [Hash], skipped: [Hash] })
      #   / failure(transaction, message)
      def call(transaction:)
        return failure(nil, 'Transaction not found') if transaction.nil?

        payments = source_payments(transaction)
        refunds = source_refunds(payments)
        splits = source_splits(transaction)

        repaired = []
        already_present = []
        skipped = []

        capture_missing, capture_present = partition_captures(payments, transaction)
        capture_present.each { |p| already_present << { source_type: :payment, source_id: p.prefixed_id } }
        capture_missing.each do |payment|
          outcome = post_payment(payment)
          record(outcome, repaired, already_present, skipped, :payment, payment)
        end

        refund_missing, refund_present = partition_refunds(refunds, transaction)
        refund_present.each { |r| already_present << { source_type: :refund, source_id: r.prefixed_id } }
        refund_missing.each do |refund|
          outcome = post_refund(refund)
          record(outcome, repaired, already_present, skipped, :refund, refund)
        end

        allocation_missing, allocation_present = partition_allocations(splits, transaction)
        allocation_present.each { |s| already_present << { source_type: :split, source_id: s.prefixed_id } }
        allocation_missing.each do |split|
          outcome = post_allocation(split)
          record(outcome, repaired, already_present, skipped, :split, split)
        end

        success(repaired: repaired, already_present: already_present, skipped: skipped)
      end

      private

      # ---- source 枚举（复用 P4-7 语义）-------------------------------------

      def source_payments(transaction)
        payments = transaction.payment_sessions.includes(:payment).filter_map(&:payment)
        combo = transaction.payment_combination
        payments += combo.payments.to_a if combo.present?
        payments.uniq(&:id)
      end

      def source_refunds(payments)
        payments.flat_map { |p| p.refunds.to_a }.uniq(&:id)
      end

      # 组合 split（allocation source of truth）——txn 挂组合时枚举其 splits
      def source_splits(transaction)
        combo = transaction.payment_combination
        return [] if combo.nil?

        combo.payment_splits.to_a
      end

      # ---- journal-missing 检测（复用 P4-7 语义；返回 [缺失集, 已存在集]）-----

      # FIN-P4 review 批1 (bugfix C3): missing 判定不再限定 state='posted' —— journal 有**任何**
      # entry（含 reversed）即视为已处理，避免「Reverse 冲销后 repair 无限空转」：
      # Reverse 保留原 idempotency_key，若仍按 active 判定缺失，Repair 会反复对同一被冲销的
      # fact 补记（Post 幂等命中 reversed 原条目）→ 每轮 sweep 都 JOURNAL_POSTING_MISSING。
      # reversed 条目 = 有意冲销（append-only 语义），同 fact 不再重建；与 partition_allocations
      # （本就全量判定）一致。
      def partition_captures(payments, transaction)
        entry_payment_ids = PallasTrade::FinancialLedgerEntry.by_transaction(transaction)
                                                             .where(entry_type: 'CASH_CAPTURED')
                                                             .pluck(:payment_id).compact
        captured = captured_payments(payments)
        [captured.reject { |p| entry_payment_ids.include?(p.id) },
         captured.select { |p| entry_payment_ids.include?(p.id) }]
      end

      def partition_refunds(refunds, transaction)
        entry_refund_ids = PallasTrade::FinancialLedgerEntry.by_transaction(transaction)
                                                            .where(entry_type: 'REFUND_SUCCEEDED')
                                                            .pluck(:refund_id).compact
        provable = refunds.select { |r| r.transaction_id.present? }
        [provable.reject { |r| entry_refund_ids.include?(r.id) },
         provable.select { |r| entry_refund_ids.include?(r.id) }]
      end

      def partition_allocations(splits, transaction)
        combo = transaction.payment_combination
        return [[], []] if combo.nil? || !combo.succeeded?

        split_ids = splits.select { |s| s.captured_amount.to_d.positive? }.map(&:id)
        return [[], []] if split_ids.empty?

        posted_split_ids = PallasTrade::FinancialLedgerEntry.active
                                                            .where(entry_type: 'ORDER_ALLOCATION')
                                                            .where(payment_split_id: split_ids)
                                                            .pluck(:payment_split_id).compact
        provable = splits.select { |s| split_ids.include?(s.id) }
        [provable.reject { |s| posted_split_ids.include?(s.id) },
         provable.select { |s| posted_split_ids.include?(s.id) }]
      end

      def captured_payments(payments)
        payments.select do |payment|
          verdict = PallasTrade::FinancialFacts::CaptureEvidencePolicy.call(payment: payment).value
          verdict[:verdict] == :captured
        end
      end

      # ---- posting 编排（复用既有幂等原语）------------------------------------

      def post_payment(payment)
        PallasTrade::FinancialLedger::PostPayment.call(payment: payment)
      end

      def post_refund(refund)
        PallasTrade::FinancialLedger::PostRefund.call(refund: refund)
      end

      def post_allocation(split)
        PallasTrade::FinancialLedger::PostAllocation.call(split: split)
      end

      def record(result, repaired, already_present, skipped, source_type, source)
        unless result.success?
          skipped << { source_type: source_type, source_id: source.prefixed_id,
                       reason: result.error.inspect }
          return
        end

        value = result.value
        if value[:entry].present?
          repaired << value[:entry]
        elsif value[:skipped]
          skipped << { source_type: source_type, source_id: source.prefixed_id,
                       reason: value[:reason].presence || 'skipped' }
        else
          already_present << { source_type: source_type, source_id: source.prefixed_id }
        end
      end
    end
  end
end
