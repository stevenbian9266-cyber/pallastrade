# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片1（PRD-20260916-payments-d13-reconciliation-cases；业务方案 §70.1）——
# `Reconciliations::SyncCases` —— 对账结论 → 差异案例队列的**唯一写入口**。
#
# 语义（自动 vs 人工边界）：
#   * 数据源 = 既有只读 `ReconcileTransaction`（P4-7）；本服务**不重算**对账、不调 provider 写。
#   * MATCHED / NOT_APPLICABLE → 该交易下仍开放的案例**自动销案**（`fixed` + `resolution_source: auto`）。
#   * 差异态（MISMATCH / NEEDS_ATTENTION / PENDING / UNSUPPORTED）→ 按
#     `dedupe_key = txn:<id>:<signature>` upsert：新建（open）或触碰（`last_seen_at` / `occurrences`）。
#   * 同一交易出现**新签名** → 旧签名案例自动销案（finding superseded），队列不堆积陈旧项。
#   * **人工判定（explained / dismissed / fixed-by-human）永不被覆盖** —— 自动逻辑只处理开放态。
#
# 铁律：**零资金副作用** —— 只写 `pallastrade_reconciliation_cases` + `AuditLog`；
# 绝不修改 Payment/Refund/Transaction/Journal/订单/库存，绝不触发 provider 调用。
module PallasTrade
  module Reconciliations
    class SyncCases
      prepend PallasTrade::ServiceModule::Base

      # @param transaction [PallasTrade::CommerceTransaction]
      # @param now [Time]
      # @return [PallasTrade::ServiceModule::Result] success({ opened:, touched:, closed:, status:, signature: })
      def call(transaction:, now: Time.current)
        return failure(nil, 'Transaction not found') if transaction.nil?

        outcome = PallasTrade::Reconciliations::ReconcileTransaction.call(transaction: transaction)
        return failure(transaction, outcome.error&.to_s.presence || 'Reconciliation failed') unless outcome.success?

        value = outcome.value
        signature = PallasTrade::ReconciliationCase.signature_for(status: value.status, reasons: value.reasons)
        open_cases = PallasTrade::ReconciliationCase.where(transaction_id: transaction.id, kind: 'transaction').open_queue

        opened = []
        touched = []
        closed = []

        if value.matched? || value.not_applicable?
          open_cases.find_each do |kase|
            close_case(kase, 'Reconciliation reports no open difference', now)
            closed << kase.id
          end
        else
          kase = upsert_case(transaction, value, signature, now)
          is_new = kase.new_record?
          persisted = save_case(kase)
          is_new ? opened << persisted.id : touched << persisted.id

          # 旧签名被取代：仅关闭「除当前案例外」的开放案例（人工判定不动）
          open_cases.where.not(id: persisted.id).find_each do |stale|
            close_case(stale, 'Superseded by a newer reconciliation finding', now)
            closed << stale.id
          end
        end

        record_audit(transaction, value, opened: opened, touched: touched, closed: closed)
        success({ opened: opened, touched: touched, closed: closed, status: value.status, signature: signature })
      end

      private

      def upsert_case(transaction, value, signature, now)
        dedupe_key = PallasTrade::ReconciliationCase.dedupe_key_for(
          transaction_id: transaction.id, signature: signature
        )
        kase = PallasTrade::ReconciliationCase.find_or_initialize_by(dedupe_key: dedupe_key)
        summary = value.summary

        kase.assign_attributes(
          store_id: transaction.store_id,
          kind: 'transaction',
          commerce_transaction: transaction,
          difference_type: PallasTrade::ReconciliationCase.difference_type_for(
            status: value.status, reasons: value.reasons
          ),
          severity: PallasTrade::ReconciliationCase.severity_for(status: value.status),
          provider: providers_for(transaction).first,
          currency: summary&.currency.presence || value.provider_currency,
          expected_amount: summary&.cash_captured,
          observed_amount: value.provider_gross_amount,
          reason_codes: value.reasons,
          summary: summary.present? ? summary.to_h.stringify_keys : {},
          last_seen_at: now,
          metadata: (kase.metadata || {}).merge(
            'providers' => providers_for(transaction),
            'source_statuses' => source_statuses(value)
          )
        )

        if kase.new_record?
          kase.detected_at = now
          kase.occurrences = 1
        else
          kase.occurrences = kase.occurrences.to_i + 1
        end

        kase.status = 'open' if kase.status.blank?
        kase
      end

      def close_case(kase, reason, now)
        kase.close!(status: 'fixed', source: 'auto', note: reason)
        Rails.logger.info(
          message: 'reconciliations.case_auto_closed',
          case_id: kase.id,
          dedupe_key: kase.dedupe_key,
          reason: reason,
          at: now.iso8601
        )
      end

      # 并发安全：唯一键冲突（两处 sweeper 同时同步）→ 退回既有行并只做触碰。
      # @return [PallasTrade::ReconciliationCase] 持久化后的记录
      def save_case(kase)
        kase.save!
        kase
      rescue ActiveRecord::RecordNotUnique
        existing = PallasTrade::ReconciliationCase.find_by!(dedupe_key: kase.dedupe_key)
        existing.update!(
          last_seen_at: kase.last_seen_at,
          occurrences: existing.occurrences.to_i + 1,
          reason_codes: kase.reason_codes,
          severity: kase.severity,
          difference_type: kase.difference_type
        )
        existing
      end

      # provider 标识：统一走 `PaymentMethod#default_option_kind`（已内置 api_type → 类名回退，
      # 不假设每个网关都实现 `api_type`）。
      def providers_for(transaction)
        transaction.payment_sessions.filter_map do |session|
          method = session.payment_method
          next if method.blank?

          method.default_option_kind.to_s.presence
        rescue StandardError
          nil
        end.uniq
      end

      def source_statuses(value)
        Array(value.source_reconciliations).map { |source| source.status.to_s }.tally
      end

      def record_audit(transaction, value, opened:, touched:, closed:)
        return if opened.empty? && closed.empty?

        PallasTrade::Audit.record(
          actor: 'system',
          action: 'reconciliation_cases_synced',
          resource: transaction,
          metadata: {
            status: value.status.to_s,
            reasons: value.reasons,
            opened: opened,
            touched: touched,
            closed: closed
          }
        )
      end
    end
  end
end
