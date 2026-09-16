# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片4（PRD-20260916-payments-d13d-fx-snapshot；业务方案 §70.4）——
# `Currencies::Fx::SyncCases` —— 汇率偏差 → **对账队列**（D13 切片1）的唯一写入口。
#
# 语义（与切片1/2 完全一致）：
#   * `mismatch` 快照 → upsert `ReconciliationCase`（`kind: 'fx'`、`difference_type: fx_rate_mismatch`、
#     `dedupe_key = "fx:<snapshot_id>:<variance_status>"`）；
#   * 快照回到 `matched`（结算修正后复算）→ 对应**开放**案例自动销案（`fixed` + auto）；
#   * 人工判定（explained / fixed by human / dismissed）**永不被覆盖**；
#   * **新开案例**时发布 `fx.settlement.mismatch`（下游告警可订阅；发布失败只记日志）。
#
# 铁律：只写案例表 + 审计 + 事件；零资金副作用。
module PallasTrade
  module Currencies
    module Fx
      class SyncCases
        prepend PallasTrade::ServiceModule::Base

        MISMATCH_DIFFERENCE_TYPE = 'fx_rate_mismatch'
        MISMATCH_REASON_CODE = 'FX_RATE_MISMATCH'
        EVENT_NAME = 'fx.settlement.mismatch'

        # @param store [PallasTrade::Store]
        # @param snapshots [Array<PallasTrade::FxSnapshot>]
        # @param now [Time]
        # @return [PallasTrade::ServiceModule::Result] success({ opened:, touched:, closed: })
        def call(store:, snapshots:, now: Time.current)
          return failure(nil, 'Store is required') if store.nil?

          opened = []
          touched = []
          closed = []
          events = []

          Array(snapshots).each do |snapshot|
            if snapshot.mismatched?
              kase, created = upsert_case(store, snapshot, now)
              created ? opened << kase.id : touched << kase.id
              events << kase if created
            else
              if %w[matched pending undetermined].include?(snapshot.variance_status)
                close_open_cases(store, snapshot, now, closed)
              end
            end
          end

          record_audit(store, opened: opened, touched: touched, closed: closed)
          publish_events(events)

          success({ opened: opened, touched: touched, closed: closed })
        end

        private

        def upsert_case(store, snapshot, now)
          dedupe_key = PallasTrade::ReconciliationCase.key_for(
            prefix: 'fx', subject_id: snapshot.id, signature: snapshot.variance_status
          )
          kase = PallasTrade::ReconciliationCase.find_or_initialize_by(dedupe_key: dedupe_key)
          created = kase.new_record?

          expected = decimal_or_nil(snapshot.metadata['expected_settled_amount'])

          kase.assign_attributes(
            store_id: store.id,
            kind: 'fx',
            difference_type: MISMATCH_DIFFERENCE_TYPE,
            severity: 'attention',
            provider: snapshot.metadata['payout_provider'],
            currency: snapshot.base_currency,
            expected_amount: expected,
            observed_amount: snapshot.settled_gross_amount,
            reason_codes: [MISMATCH_REASON_CODE],
            summary: {
              'order_number' => snapshot.metadata['order_number'],
              'base_currency' => snapshot.base_currency,
              'quote_currency' => snapshot.quote_currency,
              'effective_rate' => snapshot.effective_rate.to_s,
              'settlement_rate' => snapshot.settlement_rate&.to_s,
              'settlement_source' => snapshot.settlement_source,
              'variance_bips' => snapshot.variance_bips
            },
            last_seen_at: now,
            metadata: (kase.metadata || {}).merge(
              'fx_snapshot_id' => snapshot.id,
              'order_id' => snapshot.order_id,
              'payment_id' => snapshot.payment_id
            )
          )

          if created
            kase.detected_at = now
            kase.occurrences = 1
          else
            kase.occurrences = kase.occurrences.to_i + 1
          end
          kase.status = 'open' if kase.status.blank?
          kase.save!

          snapshot.update_columns(reconciliation_case_id: kase.id) if snapshot.reconciliation_case_id != kase.id
          [kase, created]
        end

        # 快照已恢复一致 → 关闭该快照的开放案例（人工判定不动）
        def close_open_cases(store, snapshot, now, closed)
          scope = PallasTrade::ReconciliationCase.where(kind: 'fx', store_id: store.id).open_queue
          scope = scope.where('dedupe_key LIKE ?', "fx:#{snapshot.id}:%")

          scope.find_each do |kase|
            kase.close!(status: 'fixed', source: 'auto', note: 'Settlement rate within tolerance')
            snapshot.update_columns(reconciliation_case_id: nil) if snapshot.reconciliation_case_id == kase.id
            closed << kase.id
            Rails.logger.info(
              message: 'fx.case_auto_closed', case_id: kase.id, dedupe_key: kase.dedupe_key, at: now.iso8601
            )
          end
        end

        def publish_events(cases)
          return if cases.empty?
          return unless PallasTrade::Events.respond_to?(:enabled?) && PallasTrade::Events.enabled?

          cases.each do |kase|
            PallasTrade::Events.publish(EVENT_NAME, {
                                          case_id: kase.id,
                                          dedupe_key: kase.dedupe_key,
                                          store_id: kase.store_id,
                                          currency: kase.currency,
                                          variance_bips: kase.summary&.[]('variance_bips'),
                                          detected_at: kase.detected_at&.iso8601
                                        })
          rescue StandardError => e
            Rails.logger.error("[Fx::SyncCases] event publish failed: #{e.class} #{e.message}")
          end
        end

        def decimal_or_nil(value)
          return nil if value.blank?
          return value.to_d if value.is_a?(Numeric)

          BigDecimal(value.to_s)
        rescue ArgumentError, TypeError
          nil
        end

        def record_audit(store, opened:, touched:, closed:)
          return if opened.empty? && touched.empty? && closed.empty?

          PallasTrade::Audit.record(
            action: 'fx_cases_synced',
            actor: 'system',
            resource: store,
            after: { opened: opened, touched: touched, closed: closed }
          )
        end
      end
    end
  end
end
