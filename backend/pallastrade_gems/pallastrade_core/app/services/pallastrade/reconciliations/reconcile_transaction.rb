# frozen_string_literal: true

# PALLAS-CUSTOM: FIN-P4-7 (PRD-20260906-payments-fin-p4-7)
#
# Reconciliations::ReconcileTransaction —— CommerceTransaction 级财务聚合与核对（P4 §63/§36 第二层/§38）。
#
# 语义：
#   - **local 面权威源 = Immutable Journal**（FIN-P4-2 `FinancialLedgerEntry.active.by_transaction`，
#     按 entry_type 聚合）：不从 Payment 现算 cash（避免与 immutable ledger 分歧）。
#   - **provider 面复用 FIN-P4-6** 逐 payment/refund `ReconcilePayment`/`ReconcileRefund`
#     （只读、幂等；SourceResult 聚合 provider gross/fee/net；P4-6 已捕获 provider 异常）。
#   - 核对矩阵（§38）：
#     1. allocation vs captured（组合场景）→ ALLOCATION_MISMATCH；
#     2. refund vs captured → REFUND_MISMATCH；
#     3. provider gross vs local captured（provider 支持时）→ AMOUNT_MISMATCH；
#     4. commercial vs captured：short-paid（cash < commercial）合法不 alarm（AC-4016）；
#        over-collect（cash > commercial）→ COMMERCIAL_AMOUNT_MISMATCH。
#   - 状态合成（§39）：journal 缺失（有 captured payment 无对应 CASH_CAPTURED entry）
#     → NEEDS_ATTENTION + JOURNAL_POSTING_MISSING（不猜，repair 归 P4-8）；逐源 NEEDS_ATTENTION
#     → NEEDS_ATTENTION；逐源 MISMATCH → MISMATCH；逐源 PENDING（settlement pending §43/AC-4020）
#     → PENDING 不误报；provider 全 UNSUPPORTED → UNSUPPORTED；全 NOT_APPLICABLE（无 PSP）→ provider
#     面 NOT_APPLICABLE；否则 MATCHED。
#   - 只读/幂等（§44/§46/AC-4023/INV-09/11）：零本地写、零 provider mutation、零自动资金动作、
#     绝无自动 charge/refund/倒退 transaction state；纯函数可重跑（AC-4024）。
#   - 输出 transient `TransactionResult` + `TransactionFinancialSummary`，不落表（P4-8 决定持久化）。
module PallasTrade
  module Reconciliations
    class ReconcileTransaction
      prepend PallasTrade::ServiceModule::Base

      ENTRY_BUCKETS = {
        cash: 'CASH_CAPTURED',
        store_credit: 'STORE_CREDIT_APPLIED',
        offline: 'OFFLINE_PAYMENT_RECORDED',
        refund: 'REFUND_SUCCEEDED',
        allocation: 'ORDER_ALLOCATION'
      }.freeze

      # @param transaction [PallasTrade::CommerceTransaction]
      # @return [PallasTrade::ServiceModule::Result] success(TransactionResult) / failure(transaction, message)
      def call(transaction:)
        return failure(nil, 'Transaction not found') if transaction.nil?

        entries = journal_entries(transaction)
        buckets = aggregate(entries)
        payments = source_payments(transaction)
        refunds = source_refunds(payments)
        local_captured_total = local_captured_total(payments)

        source_results = reconcile_sources(payments, refunds)
        reasons = build_reasons(transaction, entries, buckets, payments, refunds, local_captured_total, source_results)

        summary = build_summary(transaction, buckets, source_results)
        status = synthesize_status(buckets, payments, source_results, reasons)
        success(
          PallasTrade::Reconciliations::TransactionResult.new(
            transaction_id: transaction.prefixed_id,
            status: status,
            reasons: reasons,
            summary: summary,
            source_reconciliations: source_results,
            provider_gross_amount: provider_total(source_results, :provider_gross_amount),
            provider_currency: transaction.currency.to_s,
            provider_fee: provider_total(source_results, :provider_fee),
            provider_net: provider_total(source_results, :provider_net),
            observed_at: Time.current
          )
        )
      end

      private

      # ---- journal 聚合（local 金额唯一权威） ------------------------------

      def journal_entries(transaction)
        PallasTrade::FinancialLedgerEntry.active.by_transaction(transaction)
      end

      def aggregate(entries)
        buckets = ENTRY_BUCKETS.transform_values { |_| 0.0 }
        grouped = entries.group_by(&:entry_type)
        ENTRY_BUCKETS.each do |key, entry_type|
          buckets[key] = Array(grouped[entry_type]).sum { |e| e.amount.to_d }
        end
        buckets[:refund] = buckets[:refund].abs
        buckets
      end

      # ---- source 枚举 ------------------------------------------------------

      # txn 可达 payments：sessions→payment（单订单/组合 session 挂 txn）+ 组合 payment
      # （txn.payment_combination.payments）。去重。journal 缺失检测需要此独立枚举（非 journal 反推）。
      def source_payments(transaction)
        payments = transaction.payment_sessions.includes(:payment).filter_map(&:payment)
        combo = transaction.payment_combination
        payments += combo.payments.to_a if combo.present?
        payments.uniq(&:id)
      end

      def source_refunds(payments)
        payments.flat_map { |p| p.refunds.to_a }.uniq(&:id)
      end

      # ---- provider 面（复用 P4-6，逐源只读） -------------------------------

      def reconcile_sources(payments, refunds)
        results = []
        payments.each do |payment|
          result = PallasTrade::Reconciliations::ReconcilePayment.call(payment: payment)
          results << result.value if result.success? && result.value.present?
        end
        refunds.each do |refund|
          result = PallasTrade::Reconciliations::ReconcileRefund.call(refund: refund)
          results << result.value if result.success? && result.value.present?
        end
        results
      end

      def provider_total(source_results, attribute)
        present = source_results.filter_map { |r| r.public_send(attribute) }
        return nil if present.empty?

        present.sum.to_d.round(2)
      end

      # ---- reasons ----------------------------------------------------------

      def build_reasons(transaction, entries, buckets, payments, refunds, local_captured_total, source_results)
        reasons = []

        # 1. Journal 缺失：本地 captured payment 证据存在但 journal 无对应 CASH_CAPTURED entry
        #    （INV-09/12 不猜、不自动 repair——repair 归 P4-8）。仅当有 captured payment 时核对。
        #    FIN-P4 review 批1 (bugfix C3): 判定用全量 entry（含 reversed）——reversed = 有意冲销
        #    （append-only），同 fact 不再重建，避免 sweep→repair 无限空转。
        journal_payment_ids = PallasTrade::FinancialLedgerEntry.by_transaction(transaction)
                                                               .where(entry_type: 'CASH_CAPTURED')
                                                               .pluck(:payment_id).compact
        captured_without_posting = captured_payments(payments).reject { |p| journal_payment_ids.include?(p.id) }

        # REV-P6-7 (G1)：refund 侧 journal 缺失检测——本地 succeeded+transaction_id（provable
        # provider reference，镜像 RepairTransaction#partition_refunds）存在但无 REFUND_SUCCEEDED
        # entry（subscriber 丢失/异常吞掉 W1-W3）→ 并入 JOURNAL_POSTING_MISSING；ReconcileSweeperJob
        # 已按该 reason enqueue RepairTransactionJob（幂等补记）→ 闭环纯 refund posting 缺口。
        journal_refund_ids = PallasTrade::FinancialLedgerEntry.by_transaction(transaction)
                                                              .where(entry_type: 'REFUND_SUCCEEDED')
                                                              .pluck(:refund_id).compact
        provable_refunds = refunds.select { |r| r.succeeded? && r.transaction_id.present? }
        refund_without_posting = provable_refunds.reject { |r| journal_refund_ids.include?(r.id) }

        reasons << 'JOURNAL_POSTING_MISSING' if captured_without_posting.any? || refund_without_posting.any?

        # 2. allocation vs captured（组合场景有 ORDER_ALLOCATION 语义时才核对）
        if entries.where(entry_type: 'ORDER_ALLOCATION').exists? || transaction.payment_combination.present?
          reasons << 'ALLOCATION_MISMATCH' if buckets[:cash].to_d != buckets[:allocation].to_d
        end

        # 3. refund vs captured：退款不得超出本地捕获现金（+store credit 承载）
        reasons << 'REFUND_MISMATCH' if buckets[:refund].to_d > buckets[:cash].to_d + buckets[:store_credit].to_d

        # 4. over-collect（short-paid 合法，AC-4016 不 alarm）
        if buckets[:cash].to_d > transaction.amount.to_d
          reasons << 'COMMERCIAL_AMOUNT_MISMATCH'
        end

        # 5. 源级原因聚合（源级 MISMATCH/NEEDS_ATTENTION/PENDING 明细保留，供 P4-8 展示/升级）
        source_reasons(source_results).each { |r| reasons << r unless reasons.include?(r) }
        reasons
      end

      # 源级非 MATCHED/NOT_APPLICABLE 状态的原因（去重并入交易级 reasons，供 P4-8 展示/升级）。
      def source_reasons(source_results)
        source_results.each_with_object([]) do |r, acc|
          next if r.matched? || r.not_applicable?

          r.reasons.each { |reason| acc << reason }
        end.uniq
      end

      # ---- summary ----------------------------------------------------------

      def build_summary(transaction, buckets, source_results)
        PallasTrade::Reconciliations::TransactionFinancialSummary.new(
          commercial_amount: transaction.amount,
          cash_captured: buckets[:cash],
          store_credit_applied: buckets[:store_credit],
          offline_payment_recorded: buckets[:offline],
          refund_total: buckets[:refund],
          allocation_total: buckets[:allocation],
          currency: transaction.currency.to_s,
          provider_fee: provider_total(source_results, :provider_fee),
          provider_net: provider_total(source_results, :provider_net),
          reconciliation_status: nil # 由 TransactionResult.status 承载，避免双源
        )
      end

      # ---- 状态合成（§39）----------------------------------------------------

      # 优先级：NEEDS_ATTENTION（journal 缺失 / 源级 attention）> MISMATCH（源级 mismatch /
      # 本地核对 reasons）> PENDING（settlement pending，§43/AC-4020 不误报）> UNSUPPORTED
      # （全源无契约，§41 不误报 mismatch）> NOT_APPLICABLE（无 PSP / 无财务活动）> MATCHED。
      def synthesize_status(buckets, payments, source_results, reasons)
        return SourceResult::NEEDS_ATTENTION if reasons.include?('JOURNAL_POSTING_MISSING')
        return SourceResult::NEEDS_ATTENTION if source_results.any?(&:needs_attention?)
        return SourceResult::MISMATCH if source_results.any?(&:mismatch?)
        return SourceResult::PENDING if source_results.any?(&:pending?)

        %w[ALLOCATION_MISMATCH REFUND_MISMATCH COMMERCIAL_AMOUNT_MISMATCH].each do |code|
          return SourceResult::MISMATCH if reasons.include?(code)
        end

        # 无 PSP（StoreCredit/Check-only）或 transaction 无财务活动 → NOT_APPLICABLE
        no_psp = source_results.any? && source_results.all?(&:not_applicable?)
        no_financial_activity = payments.empty? && buckets[:cash].zero? && buckets[:refund].zero? &&
                                buckets[:store_credit].zero? && buckets[:offline].zero?
        return SourceResult::NOT_APPLICABLE if no_psp || no_financial_activity

        # 全源 UNSUPPORTED（Adyen/PayPal legacy 等）→ 不误报 MISMATCH（§41）
        return SourceResult::UNSUPPORTED if source_results.any? && source_results.all?(&:unsupported?)

        SourceResult::MATCHED
      end

      # local captured 总额（CaptureEvidencePolicy 唯一入口，FIN-INV-02；用于 journal 缺失检测）
      def local_captured_total(payments)
        captured_payments(payments).sum do |payment|
          verdict = PallasTrade::FinancialFacts::CaptureEvidencePolicy.call(payment: payment).value
          (verdict[:captured_amount] || payment.amount.to_d).to_d
        end.to_d
      end

      # CaptureEvidencePolicy verdict == :captured 的 payments（本地证据，只读）
      def captured_payments(payments)
        payments.select do |payment|
          verdict = PallasTrade::FinancialFacts::CaptureEvidencePolicy.call(payment: payment).value
          verdict[:verdict] == :captured
        end
      end
    end
  end
end
