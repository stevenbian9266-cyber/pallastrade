# frozen_string_literal: true

require 'csv'

# PALLAS-CUSTOM: D14 切片3（PRD-20260916-payments-d14c-dispute-rate-board；业务方案 §71.3 + §72.5）——
# Admin 拒付率看板（Orders → 拒付率看板）：
#   * index          ：窗口 + 卡组织 + 档位筛选 → 阈值设置 + 各组织卡片（笔数比/金额比 × 阈值 × 状态）
#                      + **下钻**（卡指纹/国家/入口/客群）+ 预警台账；
#   * update_policy  ：保存阈值策略（写 `Store#private_metadata['dispute_rate_policy']` + 审计）；
#   * reevaluate     ：立即评估一次（`Disputes::RateAlert`）并回显结果（审计）；
#   * add_to_denylist：把下钻出的**卡指纹**加入风控黑名单（复用 D15 `Risk::Lists::Upsert`，权限 + 审计）；
#   * export         ：CSV（汇总 + 下钻 + 台账；卡指纹脱敏，不含凭证/PII，写审计）。
#
# 数据全部来自 `Disputes::RateReport` / `Disputes::RateAlert`（只读统计 + 台账）——
# 本控制器**零资金副作用**、零 provider 调用、不改争议状态。
module PallasTrade
  module Admin
    class DisputeRatesController < BaseController
      WINDOW_OPTIONS = [30, 60, 90].freeze
      DIMENSIONS = PallasTrade::Disputes::RateReport::DIMENSIONS
      DEFAULT_DIMENSION = PallasTrade::Disputes::RateReport::DEFAULT_DIMENSION
      ALERT_LIMIT = 50
      UNKNOWN = PallasTrade::Disputes::RateReport::UNKNOWN
      BUCKET_LIMIT = 50

      helper_method :rate_percent, :bps_percent, :bucket_label, :alert_scope

      before_action :add_dispute_rate_breadcrumbs

      # GET /admin/dispute_rates
      def index
        authorize! :manage, PallasTrade::DisputeRateAlert

        load_page
      end

      # GET /admin/dispute_rates/export
      def export
        authorize! :manage, PallasTrade::DisputeRateAlert

        load_page
        PallasTrade::Audit.record(
          action: 'dispute_rates_exported',
          actor: audit_actor,
          resource: current_store,
          after: { window_days: @window_days, dimension: @dimension, network: @network_filter,
                   tier: @tier_filter, alerts: @alerts.size }
        )

        send_data csv_payload,
                  filename: "dispute-rates-#{Time.current.strftime('%Y%m%d%H%M%S')}.csv",
                  type: 'text/csv; charset=utf-8'
      end

      # PATCH /admin/dispute_rates/policy
      def update_policy
        authorize! :manage, PallasTrade::DisputeRateAlert

        raw = policy_params
        previous = PallasTrade::Disputes::RatePolicy.for(current_store)
        metadata = (current_store.private_metadata || {}).merge(
          PallasTrade::Disputes::RatePolicy::KEY => raw
        )
        current_store.update!(private_metadata: metadata)
        updated = PallasTrade::Disputes::RatePolicy.for(current_store.reload)

        PallasTrade::Audit.record(
          action: 'dispute_rate_policy_updated',
          actor: audit_actor,
          resource: current_store,
          before: { window_days: previous.window_days, warning_ratio: previous.warning_ratio,
                    networks: previous.networks },
          after: { window_days: updated.window_days, warning_ratio: updated.warning_ratio,
                   networks: updated.networks }
        )

        flash[:success] = PallasTrade.t('admin.dispute_rates.policy_saved')
        redirect_to PallasTrade.admin_dispute_rates_path(filter_redirect_params), status: :see_other
      rescue ActiveRecord::RecordInvalid => e
        flash[:error] = e.record.errors.full_messages.to_sentence
        redirect_to PallasTrade.admin_dispute_rates_path, status: :see_other
      end

      # POST /admin/dispute_rates/reevaluate
      def reevaluate
        authorize! :manage, PallasTrade::DisputeRateAlert

        outcome = PallasTrade::Disputes::RateAlert.call(store: current_store, evaluated_on: Date.current)
        if outcome.success?
          PallasTrade::Audit.record(
            action: 'dispute_rates_reevaluated',
            actor: audit_actor,
            resource: current_store,
            after: outcome.value.except(:events)
          )
          flash[:success] = PallasTrade.t(
            'admin.dispute_rates.reevaluated',
            recorded: Array(outcome.value[:recorded]).size,
            escalated: Array(outcome.value[:escalated]).size
          )
        else
          flash[:error] = outcome.error&.to_s || PallasTrade.t('admin.dispute_rates.reevaluate_failed')
        end

        redirect_to PallasTrade.admin_dispute_rates_path(filter_redirect_params), status: :see_other
      end

      # POST /admin/dispute_rates/add_to_denylist
      # 页面只提交**脱敏值**（原始卡指纹不出现于 HTML）；服务端在**当前窗口的下钻结果**里反解，
      # 且必须**唯一命中**才写入 —— 不唯一则拒绝（不猜）。
      def add_to_denylist
        authorize! :manage, PallasTrade::PaymentRiskList

        masked = params[:masked_fingerprint].to_s.strip
        if masked.blank? || masked.include?(UNKNOWN)
          flash[:error] = PallasTrade.t('admin.dispute_rates.denylist_invalid')
          return redirect_to PallasTrade.admin_dispute_rates_path(filter_redirect_params),
                             status: :see_other
        end

        fingerprint = resolve_fingerprint(masked)
        if fingerprint.nil?
          flash[:error] = PallasTrade.t('admin.dispute_rates.denylist_ambiguous')
          return redirect_to PallasTrade.admin_dispute_rates_path(filter_redirect_params),
                             status: :see_other
        end

        outcome = PallasTrade::Risk::Lists::Upsert.call(
          list_type: 'denylist',
          subject_type: 'card_fingerprint',
          value: fingerprint,
          store: current_store,
          reason: params[:reason].to_s.strip.presence || PallasTrade.t('admin.dispute_rates.denylist_default_reason'),
          actor: audit_actor
        )

        if outcome.success?
          flash[:success] = PallasTrade.t('admin.dispute_rates.denylist_added')
        else
          flash[:error] = outcome.error&.to_s || PallasTrade.t('admin.dispute_rates.denylist_failed')
        end

        redirect_to PallasTrade.admin_dispute_rates_path(filter_redirect_params), status: :see_other
      end

      private

      def load_page
        @filters = page_filters
        @window_days = @filters[:window_days]
        @dimension = @filters[:dimension]
        @network_filter = @filters[:network]
        @tier_filter = @filters[:tier]

        @report = PallasTrade::Disputes::RateReport.call(
          store: current_store,
          window_days: @window_days,
          dimension: @dimension,
          network: @network_filter,
          limit: BUCKET_LIMIT
        ).value

        @policy = PallasTrade::Disputes::RatePolicy.for(current_store)
        @suggested = PallasTrade::Disputes::RatePolicy.suggested_networks
        @suggested_note = PallasTrade::Disputes::RatePolicy.suggested_source_note
        @policy_networks = (@policy.configured_networks + @suggested.keys).uniq.sort
        @window_options = WINDOW_OPTIONS
        @dimensions = DIMENSIONS
        @tiers = PallasTrade::DisputeRateAlert::TIERS
        @alert_counts = alert_counts
        @alerts = alert_scope(@tier_filter).recent_first.limit(ALERT_LIMIT).to_a
        @network_options = (@report[:networks].map { |row| row[:network] } + @policy.configured_networks).uniq.sort
      end

      # 台账 scope（**唯一口径**：卡片计数与列表共用；tier 只影响列表）
      def alert_scope(tier = nil)
        PallasTrade::DisputeRateAlert.filter_by(
          store_id: current_store&.id,
          network: @network_filter,
          tier: tier.presence,
          from: nil,
          to: nil
        )
      end

      def alert_counts
        base = alert_scope
        counts = PallasTrade::DisputeRateAlert::TIERS.index_with { |tier| base.for_tier(tier).count }
        counts.merge('all' => base.count)
      end

      def page_filters
        window = params[:window].to_i
        {
          window_days: WINDOW_OPTIONS.include?(window) ? window : PallasTrade::Disputes::RatePolicy::DEFAULT_WINDOW_DAYS,
          dimension: DIMENSIONS.include?(params[:dimension].to_s) ? params[:dimension].to_s : DEFAULT_DIMENSION,
          network: params[:network].to_s.strip.downcase.presence,
          tier: PallasTrade::DisputeRateAlert::TIERS.include?(params[:tier].to_s) ? params[:tier].to_s : nil
        }
      end

      def filter_redirect_params
        { window: @window_days || params[:window], dimension: params[:dimension], network: params[:network],
          tier: params[:tier] }.compact
      end

      # 阈值策略参数（后端再归一，非法值不写库由 RatePolicy 兜底为默认）
      def policy_params
        raw = params.fetch(:dispute_rate_policy, {})
        permitted = raw.permit(:enabled, :window_days, :warning_ratio, networks: {}).to_h

        # 「应用建议值」：用模板覆盖 networks（显式动作，模板本身不自动生效）
        if params[:apply_suggested].present?
          return {
            'enabled' => true,
            'window_days' => permitted['window_days'],
            'warning_ratio' => permitted['warning_ratio'],
            'networks' => PallasTrade::Disputes::RatePolicy.suggested_networks
          }
        end

        networks = (permitted['networks'] || {}).each_with_object({}) do |(network, values), acc|
          values = values.respond_to?(:permit) ? values.permit(:count_bps, :amount_bps).to_h : values.to_h
          acc[network.to_s] = { 'count_bps' => values['count_bps'], 'amount_bps' => values['amount_bps'] }
        end

        {
          'enabled' => permitted.key?('enabled') ? permitted['enabled'] : false,
          'window_days' => permitted['window_days'],
          'warning_ratio' => permitted['warning_ratio'],
          'networks' => networks
        }
      end

      def csv_payload
        # `PallasTrade::CSV` 命名空间会遮蔽 Ruby 标准库 CSV → 一律用 `::CSV`
        ::CSV.generate(headers: true) do |csv|
          csv << [PallasTrade.t('admin.dispute_rates.csv.section'),
                  PallasTrade.t('admin.dispute_rates.csv.network'),
                  PallasTrade.t('admin.dispute_rates.csv.key'),
                  PallasTrade.t('admin.dispute_rates.csv.transactions_count'),
                  PallasTrade.t('admin.dispute_rates.csv.disputes_count'),
                  PallasTrade.t('admin.dispute_rates.csv.count_ratio'),
                  PallasTrade.t('admin.dispute_rates.csv.amount_ratio'),
                  PallasTrade.t('admin.dispute_rates.csv.status'),
                  PallasTrade.t('admin.dispute_rates.csv.evaluated_on')]

          @report[:networks].each do |row|
            csv << ['network', row[:network], '', row[:transactions_count], row[:disputes_count],
                    rate_cell(row[:count_ratio]), rate_cell(row[:amount_ratio]), row[:status], '']
          end

          @report[:breakdown][:rows].each do |row|
            csv << ['breakdown', @report[:breakdown][:dimension], masked_bucket(row[:key]),
                    row[:transactions_count], row[:disputes_count],
                    rate_cell(row[:count_ratio]), '', '', '']
          end

          @alerts.each do |alert|
            csv << ['alert', alert.network, alert.evaluated_on.iso8601, alert.transactions_count,
                    alert.disputes_count, alert.count_ratio_percent, alert.amount_ratio_percent,
                    alert.tier, alert.detected_at&.iso8601]
          end
        end
      end

      def rate_cell(ratio)
        return '' if ratio.nil?

        (ratio.to_d * 100).round(4).to_s
      end

      def masked_bucket(key)
        return key.to_s if @report[:breakdown][:dimension] != 'card_fingerprint'

        PallasTrade::Admin::DisputeRatesHelper.masked(key)
      end

      # 用脱敏值在当前窗口的下钻结果里反解原始卡指纹；必须唯一命中（否则返回 nil）
      # @return [String, nil]
      def resolve_fingerprint(masked)
        report = PallasTrade::Disputes::RateReport.call(
          store: current_store, window_days: @window_days || params[:window], dimension: 'card_fingerprint',
          limit: PallasTrade::Disputes::RateReport::MAX_LIMIT
        ).value
        matches = report[:breakdown][:rows].map { |row| row[:key].to_s }
                        .reject { |key| key == UNKNOWN }
                        .select { |key| PallasTrade::Admin::DisputeRatesHelper.masked(key) == masked }
                        .uniq

        matches.size == 1 ? matches.first : nil
      end

      # 审计操作者（`BaseController` 不提供 —— 本仓惯例：需要审计的控制器各自定义）
      def audit_actor
        user = try_pallastrade_current_user
        if user.respond_to?(:id)
          { type: user.class.name, id: user.id, label: user.respond_to?(:email) ? user.email : nil }
        else
          user || 'admin'
        end
      end

      def add_dispute_rate_breadcrumbs
        add_breadcrumb PallasTrade.t('admin.dispute_rates.title'), PallasTrade.admin_dispute_rates_path
      end

      # 百分比展示（比率 → %；nil → 破折号由视图处理）
      def rate_percent(ratio)
        return nil if ratio.nil?

        (ratio.to_d * 100).round(3)
      end

      def bps_percent(bps)
        return nil if bps.nil?

        (bps.to_d / 100).round(3)
      end

      def bucket_label(key)
        return PallasTrade.t('admin.dispute_rates.unknown_bucket') if key.to_s == UNKNOWN

        case @report[:breakdown][:dimension]
        when 'card_fingerprint' then PallasTrade::Admin::DisputeRatesHelper.masked(key)
        when 'segment' then PallasTrade.t("admin.dispute_rates.segments.#{key}", default: key.to_s)
        when 'entry' then PallasTrade.t("admin.dispute_rates.entries.#{key}", default: key.to_s)
        else key.to_s
        end
      end
    end
  end
end
