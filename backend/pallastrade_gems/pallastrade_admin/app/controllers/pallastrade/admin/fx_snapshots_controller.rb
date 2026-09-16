# frozen_string_literal: true

require 'csv'

# PALLAS-CUSTOM: D13 切片4（PRD-20260916-payments-d13d-fx-snapshot；业务方案 §70.4）——
# Admin 汇率快照（Orders → 汇率快照，position 63）：
#   * index ：状态 / 币种对 / 期间筛选 + **与筛选同源**计数 + 汇总（锁定/已比对/匹配/差异/平均偏差 bips）+ 明细；
#   * recompare：对当前筛选集合**重新比对结算汇率**（结算单修正后复算；差异恢复一致会自动销案）；
#   * export：CSV 导出（快照与偏差；**不含**任何凭证/卡号）。
#
# 数据来自 `Currencies::Fx::Compare`（只读事实 + 只写快照对比结果/案例/审计）—— 零资金副作用、零外呼。
module PallasTrade
  module Admin
    class FxSnapshotsController < BaseController
      STATUS_FILTERS = %w[all pending matched mismatch undetermined].freeze
      PER_PAGE = 100
      RECOMPARE_LIMIT = 500

      helper_method :fx_amount, :fx_rate_value, :fx_bips

      before_action :add_fx_breadcrumbs

      # GET /admin/fx_snapshots
      def index
        authorize! :manage, PallasTrade::CurrencyRate

        @filters = filters
        scope = base_scope
        @page = [params[:page].to_i, 1].max
        @total = scope.count
        @snapshots = scope.recent_first.limit(PER_PAGE).offset((@page - 1) * PER_PAGE).to_a
        @pages = [(@total.to_f / PER_PAGE).ceil, 1].max
        @counts = counts_for
        @summary = summary_for
        @status_filters = STATUS_FILTERS
        @currency_pairs = currency_pairs
      end

      # POST /admin/fx_snapshots/recompare
      def recompare
        authorize! :manage, PallasTrade::CurrencyRate

        snapshots = base_scope.recent_first.limit(RECOMPARE_LIMIT).to_a
        if snapshots.empty?
          flash[:error] = PallasTrade.t('admin.fx_snapshots.recompare_empty')
          return redirect_to PallasTrade.admin_fx_snapshots_path(filters.compact), status: :see_other
        end

        outcome = PallasTrade::Currencies::Fx::Compare.call(
          store: current_store, snapshots: snapshots, now: Time.current
        )

        unless outcome.success?
          flash[:error] = "#{PallasTrade.t('admin.fx_snapshots.recompare_failed')}: #{outcome.error}"
          return redirect_to PallasTrade.admin_fx_snapshots_path(filters.compact), status: :see_other
        end

        value = outcome.value
        PallasTrade::Audit.record(
          action: 'fx_snapshots_recompared',
          actor: audit_actor,
          resource: current_store,
          after: {
            scanned: value[:scanned], matched: value[:matched], mismatched: value[:mismatched],
            pending: value[:pending], undetermined: value[:undetermined],
            opened: Array(value.dig(:cases, :opened)).size, closed: Array(value.dig(:cases, :closed)).size
          }
        )

        flash[:success] = PallasTrade.t(
          'admin.fx_snapshots.recompare_success',
          scanned: value[:scanned], matched: value[:matched], mismatched: value[:mismatched],
          pending: value[:pending], undetermined: value[:undetermined]
        )
        redirect_to PallasTrade.admin_fx_snapshots_path(filters.compact), status: :see_other
      end

      # GET /admin/fx_snapshots/export
      def export
        authorize! :manage, PallasTrade::CurrencyRate

        rows = base_scope.recent_first.limit(RECOMPARE_LIMIT).to_a
        PallasTrade::Audit.record(
          action: 'fx_snapshots_exported',
          actor: audit_actor,
          resource: current_store,
          after: { rows: rows.size, filters: filters.compact }
        )

        send_data csv_payload(rows),
                  filename: "fx-snapshots-#{Time.current.strftime('%Y%m%d%H%M%S')}.csv",
                  type: 'text/csv; charset=utf-8'
      end

      private

      def add_fx_breadcrumbs
        add_breadcrumb PallasTrade.t(:orders), PallasTrade.admin_orders_path
        add_breadcrumb PallasTrade.t('admin.fx_snapshots.title'), PallasTrade.admin_fx_snapshots_path
      end

      def audit_actor
        user = try_pallastrade_current_user
        if user.respond_to?(:id)
          { type: user.class.name, id: user.id, label: user.respond_to?(:email) ? user.email : nil }
        else
          user || 'admin'
        end
      end

      # 页面/计数/导出共用的筛选口径（唯一）
      def filters
        @filters ||= {
          variance_status: STATUS_FILTERS.include?(params[:variance_status].to_s) &&
            params[:variance_status].to_s != 'all' ? params[:variance_status].to_s : nil,
          base_currency: params[:base_currency].to_s.strip.presence&.upcase,
          quote_currency: params[:quote_currency].to_s.strip.presence&.upcase,
          from: parse_date(params[:from]),
          to: parse_date(params[:to])
        }
      end

      def parse_date(value)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def base_scope
        scope = PallasTrade::FxSnapshot.filter_by(
          store: current_store,
          variance_status: filters[:variance_status],
          base_currency: filters[:base_currency],
          quote_currency: filters[:quote_currency]
        )
        if filters[:from].present? && filters[:to].present?
          scope = scope.locked_between(filters[:from], filters[:to] + 1.day)
        end
        scope
      end

      # 计数与列表**同源 scope**（同一 filter_by 口径，只改 variance_status）
      def counts_for
        base = {
          store: current_store, base_currency: filters[:base_currency], quote_currency: filters[:quote_currency]
        }
        STATUS_FILTERS.index_with do |status_filter|
          scope = PallasTrade::FxSnapshot.filter_by(
            **base, variance_status: status_filter == 'all' ? nil : status_filter
          )
          if filters[:from].present? && filters[:to].present?
            scope = scope.locked_between(filters[:from], filters[:to] + 1.day)
          end
          scope.count
        end
      end

      def summary_for
        scope = base_scope
        compared = scope.where.not(compared_at: nil).count
        bips = scope.where.not(variance_bips: nil).pluck(:variance_bips)
        {
          locked: scope.count,
          compared: compared,
          average_bips: bips.any? ? (bips.sum.to_d / bips.size).round(2) : nil,
          open_cases: PallasTrade::ReconciliationCase.where(kind: 'fx', store_id: current_store&.id)
                                                     .open_queue.count
        }
      end

      def currency_pairs
        PallasTrade::FxSnapshot.for_store(current_store).distinct.pluck(:base_currency, :quote_currency)
      end

      def csv_payload(rows)
        # `PallasTrade::CSV` 命名空间会遮蔽 Ruby 标准库 CSV → 一律用 `::CSV`
        ::CSV.generate(headers: true) do |csv|
          csv << [
            PallasTrade.t('admin.fx_snapshots.csv.locked_at'),
            PallasTrade.t('admin.fx_snapshots.csv.order'),
            PallasTrade.t('admin.fx_snapshots.csv.pair'),
            PallasTrade.t('admin.fx_snapshots.csv.display_rate'),
            PallasTrade.t('admin.fx_snapshots.csv.up_charge'),
            PallasTrade.t('admin.fx_snapshots.csv.effective_rate'),
            PallasTrade.t('admin.fx_snapshots.csv.settlement_rate'),
            PallasTrade.t('admin.fx_snapshots.csv.settlement_source'),
            PallasTrade.t('admin.fx_snapshots.csv.settled_amount'),
            PallasTrade.t('admin.fx_snapshots.csv.variance_bips'),
            PallasTrade.t('admin.fx_snapshots.csv.status'),
            PallasTrade.t('admin.fx_snapshots.csv.signals')
          ]

          rows.each do |row|
            csv << [
              row.locked_at&.iso8601,
              row.metadata['order_number'],
              "#{row.base_currency}/#{row.quote_currency}",
              row.display_rate.to_s,
              row.up_charge_percent.to_s,
              row.effective_rate.to_s,
              row.settlement_rate&.to_s,
              row.settlement_source,
              row.settled_gross_amount&.to_s,
              row.variance_bips,
              row.variance_status,
              row.signal_list.join('|')
            ]
          end
        end
      end

      def fx_amount(value, currency = nil)
        return '-' if value.nil?

        formatted = value.to_d.round(2).to_s('F')
        currency.present? ? "#{formatted} #{currency}" : formatted
      end

      def fx_rate_value(value)
        return '-' if value.nil?

        value.to_d.round(6).to_s('F')
      end

      def fx_bips(value)
        return '-' if value.nil?

        "#{value} bips"
      end
    end
  end
end
