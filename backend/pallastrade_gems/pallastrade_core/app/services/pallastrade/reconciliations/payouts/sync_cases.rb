# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片2（PRD-20260916-payments-d13b-payout-ledger；业务方案 §70.2）——
# `Reconciliations::Payouts::SyncCases` —— 结算台账差异行 → **对账队列**（D13 切片1）的唯一写入口。
#
# 语义（与切片1 一致）：
#   * `unmatched` / `amount_mismatch` 行 → upsert `ReconciliationCase`
#     （`kind: 'payout'`、`dedupe_key = "payout:<payout_id>:<provider_reference>:<signature>"`）；
#   * 行已恢复 `matched` → 对应**开放**案例自动销案（`fixed` + auto）；
#   * 人工判定（explained / dismissed）**永不被覆盖**。
#
# 铁律：只写案例表 + 审计；零资金副作用。
module PallasTrade
  module Reconciliations
    module Payouts
      class SyncCases
        prepend PallasTrade::ServiceModule::Base

        # 匹配状态 → 差异类型 / 原因码（唯一映射）
        DIFFERENCE_TYPES = {
          'unmatched' => 'payout_unmatched',
          'amount_mismatch' => 'payout_amount_mismatch'
        }.freeze
        REASON_CODES = {
          'unmatched' => 'PAYOUT_LINE_UNMATCHED',
          'amount_mismatch' => 'PAYOUT_AMOUNT_MISMATCH'
        }.freeze

        # @param payout [PallasTrade::Payout]
        # @param now [Time]
        # @return [PallasTrade::ServiceModule::Result] success({ opened:, touched:, closed: })
        def call(payout:, now: Time.current)
          return failure(nil, 'Payout not found') if payout.nil?

          opened = []
          touched = []
          closed = []

          payout.lines.find_each do |line|
            signature = "#{line.match_status}:#{line.kind}"
            dedupe_key = PallasTrade::ReconciliationCase.key_for(
              prefix: 'payout', subject_id: payout.id, signature: "#{line.provider_reference}:#{signature}"
            )

            if line.difference?
              kase = upsert_case(payout, line, dedupe_key, now)
              created = kase.new_record?
              kase.save!
              created ? opened << kase.id : touched << kase.id

              # 同一行的旧签名（如 unmatched → amount_mismatch）自动销案，队列不残留陈旧项
              close_stale_cases(payout, line, dedupe_key, now, closed, 'Superseded by a newer payout finding')
            else
              close_stale_cases(payout, line, dedupe_key, now, closed, 'Payout line matched')
            end
          end

          record_audit(payout, opened: opened, touched: touched, closed: closed)
          success({ opened: opened, touched: touched, closed: closed })
        end

        private

        def upsert_case(payout, line, dedupe_key, now)
          kase = PallasTrade::ReconciliationCase.find_or_initialize_by(dedupe_key: dedupe_key)

          kase.assign_attributes(
            store_id: payout.store_id,
            kind: 'payout',
            difference_type: DIFFERENCE_TYPES.fetch(line.match_status, 'needs_attention'),
            severity: 'attention',
            provider: payout.provider,
            currency: line.currency.presence || payout.currency,
            expected_amount: line.local_amount,
            observed_amount: line.gross_amount,
            reason_codes: [REASON_CODES.fetch(line.match_status, 'PAYOUT_LINE_UNMATCHED')],
            summary: {
              'payout_reference' => payout.reference,
              'line_kind' => line.kind,
              'provider_reference' => line.provider_reference,
              'difference' => line.difference_amount,
              'match_details' => line.match_details
            },
            last_seen_at: now,
            metadata: (kase.metadata || {}).merge('payout_id' => payout.id, 'payout_line_id' => line.id)
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

        # 关闭该行对应的**其他开放**案例（人工判定不动）。
        def close_stale_cases(payout, line, current_key, now, closed, note)
          scope = PallasTrade::ReconciliationCase.where(kind: 'payout', store_id: payout.store_id).open_queue
          scope = scope.where('dedupe_key LIKE ?', "payout:#{payout.id}:#{line.provider_reference}:%")
          scope = scope.where.not(dedupe_key: current_key)

          scope.find_each do |kase|
            kase.close!(status: 'fixed', source: 'auto', note: note)
            closed << kase.id
            Rails.logger.info(
              message: 'payouts.case_auto_closed',
              case_id: kase.id,
              dedupe_key: kase.dedupe_key,
              at: now.iso8601
            )
          end
        end

        def record_audit(payout, opened:, touched:, closed:)
          return if opened.empty? && closed.empty? && touched.empty?

          PallasTrade::Audit.record(
            actor: 'system',
            action: 'payout_cases_synced',
            resource: payout,
            metadata: { opened: opened, touched: touched, closed: closed }
          )
        end
      end
    end
  end
end
