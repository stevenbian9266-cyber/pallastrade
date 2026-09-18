# frozen_string_literal: true

# PALLAS-CUSTOM: D3（PRD-20260917-payments-d3-risk-dashboard-threshold-alerts；业务方案 §78-D3 / §60.2-P3）——
# Admin 支付风控看板（Orders → 支付风控）：
#   * index          ：5 指标卡（值 / 档位 / 阈值 / 窗口 / 下钻）+ 阈值策略区块 + 最近告警留痕；
#   * update_policy  ：保存阈值策略（`Store#private_metadata['payment_risk_dashboard_policy']` + 审计）；
#   * reevaluate     ：立即评估一次（`Risk::DashboardAlert` —— 审计留痕是它的职责）。
#
# 数据全部来自 `Risk::DashboardReport` / `DashboardThreshold` / 审计留痕 —— 本控制器**零资金副作用**、
# 零 provider 调用；看板读路径不写库（只有策略保存与「立即评估」的告警留痕会写）。
module PallasTrade
  module Admin
    class PaymentRiskController < BaseController
      WINDOW_OPTIONS = [7, 30, 60, 90].freeze
      ALERT_LIMIT = 20

      # 不可判定/未配置的原因 → i18n 后缀（未知原因回落 unknown，不静默）
      REASON_KEYS = {
        'no_denominator' => 'no_denominator',
        'no_data' => 'no_data',
        'thresholds_not_configured' => 'thresholds_not_configured',
        'value_unavailable' => 'value_unavailable',
        'report_unavailable' => 'report_unavailable',
        'report_degraded' => 'report_degraded'
      }.freeze

      helper_method :metric_label, :metric_unit_label, :status_badge_class, :metric_display,
                    :threshold_display, :metric_hint, :drill_down_path, :severity_rank

      # 面包屑由导航自动推导（P6）：Orders > Payment Risk。控制器不再手写
      # 模块/子页 crumb（2026-09-18 修复重复层级）。

      # GET /admin/payment_risk
      def index
        authorize! :read, PallasTrade::PaymentRiskAssessment

        load_page
      end

      # PATCH /admin/payment_risk/policy
      def update_policy
        authorize! :update, PallasTrade::PaymentRiskAssessment

        policy, errors = PallasTrade::Risk::DashboardPolicy.storable(raw: policy_params)
        if errors.present?
          flash[:error] = errors.map { |error| "#{error[:field]}: #{error[:message]}" }.join('；')
          return redirect_to PallasTrade.admin_payment_risk_path, status: :see_other
        end

        metadata = current_store.private_metadata || {}
        before_policy = metadata[PallasTrade::Risk::DashboardPolicy::KEY]
        current_store.update_columns(
          private_metadata: metadata.merge(PallasTrade::Risk::DashboardPolicy::KEY => policy.raw)
        )
        PallasTrade::Audit.record(
          action: 'store_payment_risk_dashboard_policy_updated',
          actor: audit_actor,
          resource: current_store,
          before: { policy: before_policy },
          after: { policy: policy.raw }
        )

        flash[:success] = PallasTrade.t('admin.payment_risk.policy_saved')
        redirect_to PallasTrade.admin_payment_risk_path, status: :see_other
      end

      # POST /admin/payment_risk/reevaluate
      def reevaluate
        authorize! :update, PallasTrade::PaymentRiskAssessment

        outcome = PallasTrade::Risk::DashboardAlert.call(store: current_store)
        if outcome.success?
          recorded = Array(outcome.value[:recorded]).size
          flash[:success] = PallasTrade.t('admin.payment_risk.reevaluated', count: recorded)
        else
          flash[:error] = PallasTrade.t('admin.payment_risk.reevaluate_failed')
        end
        redirect_to PallasTrade.admin_payment_risk_path, status: :see_other
      end

      private

      def load_page
        @window_days = window_param
        outcome = PallasTrade::Risk::DashboardReport.call(store: current_store, window_days: @window_days)
        @report = outcome.success? ? outcome.value : {}
        @policy = PallasTrade::Risk::DashboardPolicy.for(current_store)
        @rows = PallasTrade::Risk::DashboardThreshold.classify(metrics: Array(@report[:metrics]), policy: @policy)
        @degraded = Array(@report[:degraded])
        @alerts = recent_alerts
      end

      def window_param
        requested = params[:window_days].presence&.to_i
        return requested if WINDOW_OPTIONS.include?(requested)

        PallasTrade::Risk::DashboardPolicy.for(current_store).window_days
      end

      def recent_alerts
        PallasTrade::AuditLog
          .where(action: PallasTrade::Risk::DashboardAlert::AUDIT_ACTION,
                 resource_type: PallasTrade::Risk::DashboardAlert::RESOURCE_TYPE,
                 resource_id: current_store.id)
          .order(id: :desc)
          .limit(ALERT_LIMIT)
      end

      def policy_params
        raw = params[:policy]
        return nil if raw.blank?

        permitted = raw.respond_to?(:permit) ? raw.permit(:window_days, metrics: {}).to_h : raw
        permitted.merge('metrics' => nested_metric_params(raw))
      end

      # 逐指标收集（只收已知指标键；缺失的指标保持策略原值，避免"保存一次清空其它指标"）
      def nested_metric_params(raw)
        source = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : (raw || {})
        metrics = (source['metrics'] || source[:metrics] || {})
        metrics = metrics.to_unsafe_h if metrics.respond_to?(:to_unsafe_h)
        return {} unless metrics.is_a?(Hash)

        existing = PallasTrade::Risk::DashboardPolicy.for(current_store).raw['metrics']

        PallasTrade::Risk::DashboardPolicy.metric_keys.each_with_object({}) do |key, acc|
          entry = metrics[key] || metrics[key.to_sym] || {}
          entry = entry.to_unsafe_h if entry.respond_to?(:to_unsafe_h)
          entry = {} unless entry.is_a?(Hash)

          fallback = existing[key] || existing[key.to_sym] || {}
          enabled = entry.key?('enabled') || entry.key?(:enabled) ? entry['enabled'] || entry[:enabled] : fallback['enabled']

          acc[key] = {
            'enabled' => enabled == '1' || enabled == true || enabled == 'true',
            'warning' => presence_or_fallback(entry['warning'] || entry[:warning], fallback['warning']),
            'critical' => presence_or_fallback(entry['critical'] || entry[:critical], fallback['critical'])
          }
        end
      end

      def presence_or_fallback(value, fallback)
        string = value.to_s.strip
        string.present? ? string : fallback
      end

      # ---- 视图辅助 ----

      def metric_label(key)
        PallasTrade.t("admin.payment_risk.metrics.#{key}")
      end

      def metric_unit_label(unit)
        PallasTrade.t("admin.payment_risk.units.#{unit}")
      end

      def metric_display(row)
        return PallasTrade.t('admin.payment_risk.unavailable') if row[:value].nil?

        case row[:unit]
        when 'bps' then "#{(row[:value].to_d / 100).round(2)}%"
        when 'minutes' then PallasTrade.t('admin.payment_risk.minutes_short', count: row[:value])
        else row[:value].to_s
        end
      end

      def threshold_display(threshold, unit)
        return '—' if threshold.blank?

        format_value = lambda do |value|
          unit == 'bps' ? "#{(value.to_d / 100).round(2)}%" : PallasTrade.t('admin.payment_risk.minutes_short', count: value)
        end
        "#{format_value.call(threshold[:warning])} / #{format_value.call(threshold[:critical])}"
      end

      def status_badge_class(status)
        case status.to_s
        when 'breached' then 'badge-danger'
        when 'approaching' then 'badge-warning'
        when 'ok' then 'badge-success'
        else 'badge-light'
        end
      end

      def severity_rank(status)
        PallasTrade::Risk::DashboardThreshold.severity(status)
      end

      def metric_hint(row)
        reason = row[:reason].to_s
        return nil if reason.blank?

        suffix = REASON_KEYS.fetch(reason) { REASON_KEYS.fetch(reason.split(':').first, 'unknown') }
        PallasTrade.t("admin.payment_risk.reasons.#{suffix}")
      end

      def drill_down_path(key)
        case key.to_s
        when 'risky_orders' then PallasTrade.admin_risk_rules_path
        when 'three_ds_challenge_rate' then PallasTrade.edit_admin_store_path(current_store)
        when 'dispute_rate' then PallasTrade.admin_dispute_rates_path
        when 'refund_rate' then PallasTrade.admin_refunds_path
        when 'review_queue_duration' then PallasTrade.admin_transactions_path
        end
      end

      def audit_actor
        user = try_pallastrade_current_user
        if user.respond_to?(:id)
          { type: user.class.name, id: user.id, label: user.respond_to?(:email) ? user.email : nil }
        else
          'system'
        end
      end
    end
  end
end
