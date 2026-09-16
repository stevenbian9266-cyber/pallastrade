# frozen_string_literal: true

# PALLAS-CUSTOM: D14 切片3（PRD-20260916-payments-d14c-dispute-rate-board；业务方案 §71.3 + §72.5）——
# `Disputes::RateAlert` —— 把「拒付率逼近/超过阈值」**落成台账**并按需发布事件。
#
# 职责边界：
#   * 只写 `pallastrade_dispute_rate_alerts`（唯一键幂等）+ 审计；**不**改支付/订单/争议状态，零资金副作用；
#   * 只对**已配置阈值**的组织落行（`ok` / `unconfigured` 不落行，避免噪声）；
#   * 同一「店铺 × 组织 × 评估日」重复评估**只更新同一行**；档位**升级**（approaching → breached）
#     记 `escalated_at` 并发布事件；同日回落只刷新观测值并记 `metadata['relaxed_at']`（不降档、不发事件）。
#
# 事件：`dispute.rate_threshold`（仅在**新档位 / 档位升级**时发布；事件系统未启用或发布失败只记日志）。
module PallasTrade
  module Disputes
    class RateAlert
      prepend PallasTrade::ServiceModule::Base

      EVENT_NAME = 'dispute.rate_threshold'
      AUDIT_ACTION = 'dispute_rate_alert_recorded'

      # @param store [PallasTrade::Store]
      # @param evaluated_on [Date, Time] 评估日（台账幂等键的一部分）
      # @param window_days [Integer, nil] 覆盖策略窗口
      # @param now [Time]
      # @param report [Hash, nil] 复用已算好的 `RateReport` 结果（避免重复计算）
      # @return [PallasTrade::ServiceModule::Result] success({ evaluated_on:, recorded:, escalated:, events:, skipped: })
      def call(store:, evaluated_on: Date.current, window_days: nil, now: Time.current, report: nil)
        return failure(nil, 'Store is required') if store.nil?

        @now = now
        @evaluated_on = evaluated_on.respond_to?(:to_date) ? evaluated_on.to_date : evaluated_on
        policy = PallasTrade::Disputes::RatePolicy.for(store)

        unless policy.enabled?
          return success({ store_id: store.id, evaluated_on: @evaluated_on, recorded: [], escalated: [],
                           events: [], skipped: ['disabled'] })
        end

        report ||= PallasTrade::Disputes::RateReport.call(
          store: store, window_days: window_days, to: now
        ).value

        if report[:degraded].present?
          return success({ store_id: store.id, evaluated_on: @evaluated_on, recorded: [], escalated: [],
                           events: [], skipped: report[:degraded].map { |reason| "report_degraded:#{reason}" } })
        end

        recorded = []
        escalated = []
        skipped = []
        events = []

        report[:networks].each do |row|
          network = row[:network].to_s
          tier = row[:status].to_s

          if network == PallasTrade::DisputeRateAlert::UNKNOWN_NETWORK
            skipped << 'unknown_network'
            next
          end

          # `ok` / `unconfigured` **不新建行**（避免噪声），但若当日已有行则**刷新观测值**
          # （台账语义 =「当日曾经达到过的最高档位 + 最新观测值」；回落只记 `relaxed_at`，不降档）。
          alert, escalated_now = upsert_alert(
            store: store, row: row, window_days: report[:scope][:window_days],
            allow_create: PallasTrade::DisputeRateAlert::TIERS.include?(tier)
          )
          if alert.nil?
            skipped << tier
            next
          end

          recorded << alert.id
          next unless escalated_now

          escalated << alert.id
          events << event_payload(alert)
        end

        record_audit(store, recorded: recorded, escalated: escalated, skipped: skipped)
        publish_events(events)

        success({ store_id: store.id, evaluated_on: @evaluated_on, recorded: recorded,
                  escalated: escalated, events: events, skipped: skipped.uniq })
      end

      private

      # @param allow_create [Boolean] 是否允许新建台账行（`ok` / `unconfigured` 只刷新已有行）
      # @return [Array(DisputeRateAlert, Boolean)] 台账行 + 本次是否**升级**
      def upsert_alert(store:, row:, window_days:, allow_create: true)
        network = row[:network].to_s
        tier = row[:status].to_s
        dedupe_key = PallasTrade::DisputeRateAlert.key_for(
          store_id: store.id, network: network, evaluated_on: @evaluated_on
        )

        alert = PallasTrade::DisputeRateAlert.find_or_initialize_by(dedupe_key: dedupe_key)
        created = alert.new_record?
        return [nil, false] if created && !allow_create

        previous_tier = alert.tier
        escalated = created || severity(tier) > severity(previous_tier)

        if created
          alert.assign_attributes(store_id: store.id, network: network, detected_at: @now)
        elsif tier != previous_tier
          # 同日不降档：保留更高档位（台账语义 = 当日曾经达到过的最严重档位）
          alert.metadata = (alert.metadata || {}).merge('relaxed_at' => @now.iso8601)
        end

        alert.assign_attributes(
          tier: escalated ? tier : alert.tier,
          window_days: window_days.to_i.positive? ? window_days.to_i : alert.window_days,
          evaluated_on: @evaluated_on,
          count_ratio_bps: row[:count_ratio_bps],
          amount_ratio_bps: row[:amount_ratio_bps],
          count_threshold_bps: row[:count_threshold_bps],
          amount_threshold_bps: row[:amount_threshold_bps],
          transactions_count: row[:transactions_count].to_i,
          disputes_count: row[:disputes_count].to_i,
          transactions_amount: row[:transactions_amount],
          disputes_amount: row[:disputes_amount],
          currency: row[:currency].presence || default_currency(store),
          triggered_metrics: escalated ? Array(row[:triggered_metrics]).map(&:to_s) : alert.triggered,
          metadata: (alert.metadata || {}).merge(
            'observed_tier' => tier,
            'warning_ratio' => row[:warning_ratio]
          )
        )
        alert.detected_at = @now if alert.detected_at.blank?
        alert.escalated_at = @now if escalated && alert.escalated_at.blank?
        alert.save!

        [alert, escalated]
      end

      def severity(tier)
        PallasTrade::DisputeRateAlert::TIER_SEVERITY[tier.to_s].to_i
      end

      def event_payload(alert)
        {
          store_id: alert.store_id,
          network: alert.network,
          tier: alert.tier,
          count_ratio_bps: alert.count_ratio_bps,
          amount_ratio_bps: alert.amount_ratio_bps,
          count_threshold_bps: alert.count_threshold_bps,
          amount_threshold_bps: alert.amount_threshold_bps,
          triggered_metrics: alert.triggered,
          evaluated_on: alert.evaluated_on.iso8601,
          detected_at: alert.detected_at&.iso8601
        }
      end

      def publish_events(events)
        return if events.empty?
        return unless PallasTrade::Events.respond_to?(:enabled?) && PallasTrade::Events.enabled?

        events.each do |payload|
          PallasTrade::Events.publish(EVENT_NAME, payload)
        rescue StandardError => e
          Rails.logger.error("[Disputes::RateAlert] event publish failed: #{e.class} #{e.message}")
        end
      end

      def record_audit(store, recorded:, escalated:, skipped:)
        return if recorded.empty?

        PallasTrade::Audit.record(
          action: AUDIT_ACTION,
          actor: 'system',
          resource: store,
          after: { evaluated_on: @evaluated_on.iso8601, recorded: recorded.size,
                   escalated: escalated.size, skipped: skipped.uniq }
        )
      rescue StandardError => e
        Rails.logger.error("[Disputes::RateAlert] audit failed: #{e.class} #{e.message}")
      end

      def default_currency(store)
        (store.default_currency.presence || store.currency.presence).to_s.upcase
      end
    end
  end
end
