# frozen_string_literal: true

# PALLAS-CUSTOM: D3（PRD-20260917-payments-d3-risk-dashboard-threshold-alerts；业务方案 §78-D3 / §60.2-P3）
#
# Risk::DashboardReport —— 支付风控看板的**只读读模型**：把 5 个水位的**原始事实**拉成一页。
#
# 铁律：
#   * **零写库、零 provider I/O、零资金副作用**（只 count/sum/pluck）；
#   * **不可判定不猜**：分母为 0 / 无样本 → `value: nil` + `available: false` + 结构化 `reason`，
#     绝不回落成 0（0 是"健康"的语义，不能用来表达"不知道"）；
#   * **不重算拒付率**：直接调用 `Disputes::RateReport`（D14c 的唯一权威口径）；
#   * **跨店隔离**：所有查询以 `store` 收窄；
#   * 查询数固定（≤ 12），不随订单量增长。
module PallasTrade
  module Risk
    class DashboardReport
      prepend PallasTrade::ServiceModule::Base

      # D2 人工裁决的审计动作 = 「已处理」样本（`transaction_review_*`）
      HANDLED_ACTIONS = %w[transaction_review_captured transaction_review_released].freeze
      SAMPLES_LIMIT = 2_000

      THREE_DS_APPLIED = 'three_d_secure'
      THREE_DS_KEY = 'three_d_secure_hint'
      # JSONB 取值谓词：`->>` 右侧**必须是字面量**（绑定参数会触发 PreparedStatementInvalid），
      # 故此处用常量拼进字面片段（`THREE_DS_KEY` 是代码常量，无注入面）。
      THREE_DS_VALUE_SQL = "pallastrade_payment_sessions.external_data ->> 'three_d_secure_hint'"
      THREE_DS_PRESENT_SQL = "pallastrade_payment_sessions.external_data ? 'three_d_secure_hint'"

      # @param store [PallasTrade::Store]
      # @param window_days [Integer, nil] 覆盖店铺策略窗口
      # @param now [Time]
      # @return [PallasTrade::ServiceModule::Result] success(Hash)（含 metrics 五元组）
      def call(store:, window_days: nil, now: Time.current)
        return success(degraded_envelope('store_missing')) if store.nil?

        @store = store
        @now = now
        @policy = PallasTrade::Risk::DashboardPolicy.for(store)
        @window_days = window_days.present? ? normalize_window(window_days) : @policy.window_days
        @from = @now - @window_days.days

        metrics = PallasTrade::Risk::DashboardPolicy.metric_keys.map { |key| send("metric_#{key}") }

        success(scope: { store_id: store.id, window_days: @window_days, from: @from, to: @now },
                policy: @policy.to_h,
                metrics: metrics,
                evaluated_at: @now,
                degraded: [])
      rescue StandardError => e
        success(degraded_envelope("report_unavailable:#{e.class}"))
      end

      private

      # ---- 指标 1：risky 单占比（风险评估留痕 → 去重订单 / 下单数）----
      def metric_risky_orders
        flagged = PallasTrade::PaymentRiskAssessment
                  .where(store_id: @store.id)
                  .flagged
                  .where(evaluated_at: @from..@now)
        numerator = flagged.distinct.count(:order_id)
        denominator = @store.orders.where(submitted_at: @from..@now).count

        if denominator.zero?
          return unavailable('risky_orders', 'count', 'no_denominator',
                             detail: { flagged_orders: numerator, submitted_orders: 0 })
        end

        metric('risky_orders', ratio_bps(numerator, denominator), 'bps',
               detail: { flagged_orders: numerator, submitted_orders: denominator },
               sources: %w[payment_risk_assessments orders])
      end

      # ---- 指标 2：3DS 挑战率（会话 external_data 的 three_d_secure_hint 留痕）----
      def metric_three_ds_challenge_rate
        sessions = store_sessions
        total = sessions.count
        applied = sessions.where("#{THREE_DS_VALUE_SQL} = ?", THREE_DS_APPLIED).count
        required = sessions.where(THREE_DS_PRESENT_SQL).count

        if total.zero?
          return unavailable('three_ds_challenge_rate', 'bps', 'no_denominator',
                             detail: { applied_count: 0, required_count: 0, total_sessions: 0 })
        end

        metric('three_ds_challenge_rate', ratio_bps(applied, total), 'bps',
               detail: { applied_count: applied, required_count: required, total_sessions: total },
               sources: %w[payment_sessions])
      end

      # ---- 指标 3：拒付率（**复用** D14c 的唯一权威口径，不重算）----
      def metric_dispute_rate
        outcome = rate_report(store: @store, window_days: @window_days, to: @now)
        unless outcome.success?
          return unavailable('dispute_rate', 'bps', 'report_unavailable',
                             detail: { source: 'Disputes::RateReport' })
        end

        value = outcome.value || {}
        if value[:degraded].present?
          return unavailable('dispute_rate', 'bps', "report_degraded:#{Array(value[:degraded]).first}",
                             detail: { source: 'Disputes::RateReport' })
        end

        totals = value[:totals] || {}
        ratio = totals[:count_ratio]
        detail = { disputes_count: totals[:disputes_count], transactions_count: totals[:transactions_count],
                   source: 'Disputes::RateReport' }

        return unavailable('dispute_rate', 'bps', 'no_denominator', detail: detail) if ratio.nil?

        metric('dispute_rate', (ratio.to_f * 10_000).round, 'bps', detail: detail,
               sources: %w[disputes payments])
      end

      # ---- 指标 4：退款率（退款单金额 / 已完成支付金额，同窗口）----
      def metric_refund_rate
        order_ids = @store.orders.select(:id)
        payment_ids = PallasTrade::Payment.where(order_id: order_ids).select(:id)

        denominator = PallasTrade::Payment
                      .where(order_id: order_ids, state: 'completed')
                      .where(created_at: @from..@now).sum(:amount).to_d
        numerator = PallasTrade::Refund
                    .where(created_at: @from..@now)
                    .where('payment_id IN (?) OR target_order_id IN (?)', payment_ids, order_ids)
                    .sum(:amount).to_d

        detail = { refund_amount: numerator.to_s('F'), captured_amount: denominator.to_s('F') }
        return unavailable('refund_rate', 'bps', 'no_denominator', detail: detail) if denominator.zero?

        metric('refund_rate', (numerator / denominator * 10_000).round, 'bps', detail: detail,
               sources: %w[refunds payments])
      end

      # ---- 指标 5：审核队列时长（当前排队最久 + 窗口内已处理 P90）----
      def metric_review_queue_duration
        pending = PallasTrade::CommerceTransaction.where(store_id: @store.id, state: 'manual_review')
        pending_count = pending.count
        oldest = pending.minimum(:manual_review_at)
        oldest_minutes = oldest ? ((@now - oldest) / 60.0).round : 0
        durations = handled_durations

        metric('review_queue_duration', oldest_minutes, 'minutes',
               detail: { pending_count: pending_count,
                         pending_since: oldest&.iso8601,
                         p90_handled_minutes: percentile(durations, 90),
                         handled_samples: durations.size },
               sources: %w[commerce_transactions audit_logs])
      end

      # ---- 辅助 ----

      # 委派 D14c 唯一权威口径（不重算）。抽出为接缝：便于规格注入失败/降级结果，
      # 不影响生产调用路径。
      def rate_report(**kwargs)
        PallasTrade::Disputes::RateReport.call(**kwargs)
      end

      def store_sessions
        PallasTrade::PaymentSession
          .joins(:order)
          .where(pallastrade_orders: { store_id: @store.id })
          .where(created_at: @from..@now)
      end

      # 窗口内「已处理」时长（分钟）= 裁决审计时间 − manual_review_at（来源 D2 审计，即留痕）
      def handled_durations
        audits = PallasTrade::AuditLog
                 .where(action: HANDLED_ACTIONS, resource_type: 'PallasTrade::CommerceTransaction')
                 .where(created_at: @from..@now)
                 .order(:created_at)
                 .limit(SAMPLES_LIMIT)
        return [] if audits.empty?

        starts = PallasTrade::CommerceTransaction
                 .where(id: audits.map(&:resource_id).uniq, store_id: @store.id)
                 .pluck(:id, :manual_review_at).to_h

        audits.filter_map do |audit|
          started_at = starts[audit.resource_id]
          next if started_at.nil?

          ((audit.created_at - started_at) / 60.0).round
        end
      end

      def percentile(values, rank)
        return nil if values.empty?

        sorted = values.sort
        index = ((rank / 100.0) * sorted.size).ceil - 1
        sorted[index.clamp(0, sorted.size - 1)]
      end

      def ratio_bps(numerator, denominator)
        return nil if denominator.zero?

        (numerator.to_d / denominator.to_d * 10_000).round
      end

      def metric(key, value, unit, detail:, sources:)
        { key: key, value: value, unit: unit, available: true, reason: nil,
          window: window_scope, detail: detail, sources: sources }
      end

      def unavailable(key, unit, reason, detail: {})
        { key: key, value: nil, unit: unit, available: false, reason: reason,
          window: window_scope, detail: detail, sources: [] }
      end

      def window_scope
        { days: @window_days, from: @from, to: @now }
      end

      def normalize_window(value)
        parsed = value.to_i
        return 30 if parsed < PallasTrade::Risk::DashboardPolicy::MIN_WINDOW_DAYS ||
                     parsed > PallasTrade::Risk::DashboardPolicy::MAX_WINDOW_DAYS

        parsed
      end

      # 降级信封：字段齐全但数值不可用，并说明原因 —— 不猜、不 500
      def degraded_envelope(reason)
        { scope: { store_id: nil, window_days: nil, from: nil, to: nil },
          policy: PallasTrade::Risk::DashboardPolicy.new.to_h,
          metrics: PallasTrade::Risk::DashboardPolicy.metric_keys.map do |key|
            { key: key, value: nil, unit: key == 'review_queue_duration' ? 'minutes' : 'bps',
              available: false, reason: reason, window: {}, detail: {}, sources: [] }
          end,
          evaluated_at: nil,
          degraded: [reason] }
      end
    end
  end
end
