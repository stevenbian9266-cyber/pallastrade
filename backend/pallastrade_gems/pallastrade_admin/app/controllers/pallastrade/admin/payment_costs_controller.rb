# frozen_string_literal: true

require 'csv'

# PALLAS-CUSTOM: D13 切片3（PRD-20260916-payments-d13c-fee-cost-report；业务方案 §70.3 报表）——
# Admin 支付成本报表（Orders → 支付成本）：
#   * index ：期间 + 维度（支付方式 / 币种 / 入口）筛选 → 汇总卡 + **按入口成本排名**（可下钻）+ 逐笔明细 + 未定价提示；
#   * export：CSV 导出（与页面**同源**报表结果，逐笔明细口径；**不含**任何凭证/卡号）。
#
# 数据全部来自 `Payments::Costs::Report`（只读）—— 本控制器**零资金副作用**、不调 provider。
module PallasTrade
  module Admin
    class PaymentCostsController < BaseController
      DEFAULT_PERIOD_DAYS = PallasTrade::Payments::Costs::Report::DEFAULT_PERIOD_DAYS
      DETAIL_LIMIT = PallasTrade::Payments::Costs::Report::DETAIL_LIMIT

      helper_method :cost_amount, :cost_rate

      before_action :add_cost_breadcrumbs

      # GET /admin/payment_costs
      def index
        authorize! :manage, PallasTrade::PaymentFeePolicy

        load_report
      end

      # GET /admin/payment_costs/export
      def export
        authorize! :manage, PallasTrade::PaymentFeePolicy

        outcome = load_report
        return redirect_to(PallasTrade.admin_payment_costs_path, status: :see_other) unless outcome

        PallasTrade::Audit.record(
          action: 'payment_cost_report_exported',
          actor: audit_actor,
          resource: current_store,
          after: {
            from: @report[:period][:from].iso8601,
            to: @report[:period][:to].iso8601,
            rows: @report[:detail].size,
            fee_amount: @report[:totals][:fee_amount].to_s,
            filters: @report[:filters]
          }
        )

        send_data csv_payload(@report),
                  filename: "payment-costs-#{Time.current.strftime('%Y%m%d%H%M%S')}.csv",
                  type: 'text/csv; charset=utf-8'
      end

      private

      def load_report
        @filters = cost_filters
        outcome = PallasTrade::Payments::Costs::Report.call(
          store: current_store,
          from: @filters[:from],
          to: @filters[:to],
          payment_method_id: @filters[:payment_method_id],
          currency: @filters[:currency],
          method_key: @filters[:method_key],
          limit: DETAIL_LIMIT
        )

        unless outcome.success?
          flash[:error] = outcome.error
          return nil
        end

        @report = outcome.value
        @payment_methods = PallasTrade::PaymentMethod.order(:name).pluck(:id, :name)
        @currencies = PallasTrade::Order.where(store_id: current_store&.id).distinct.pluck(:currency).compact
        @method_keys = @report[:by_entry].map { |entry| entry[:method_key] }.compact.uniq
        outcome
      end

      def cost_filters
        to = parse_time(params[:to]) || Time.current
        from = parse_time(params[:from]) || (to - DEFAULT_PERIOD_DAYS.days)

        {
          from: from,
          to: to,
          payment_method_id: params[:payment_method_id].presence,
          currency: params[:currency].to_s.strip.presence&.upcase,
          method_key: params[:method_key].to_s.strip.presence
        }
      end

      def parse_time(value)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def csv_payload(report)
        # `PallasTrade::CSV` 命名空间会遮蔽 Ruby 标准库 CSV → 一律用 `::CSV`
        ::CSV.generate(headers: true) do |csv|
          csv << [
            PallasTrade.t('admin.payment_costs.csv.paid_at'),
            PallasTrade.t('admin.payment_costs.csv.order_number'),
            PallasTrade.t('admin.payment_costs.csv.provider'),
            PallasTrade.t('admin.payment_costs.csv.entry'),
            PallasTrade.t('admin.payment_costs.csv.entry_key'),
            PallasTrade.t('admin.payment_costs.csv.currency'),
            PallasTrade.t('admin.payment_costs.csv.amount'),
            PallasTrade.t('admin.payment_costs.csv.percent_fee'),
            PallasTrade.t('admin.payment_costs.csv.platform_fee'),
            PallasTrade.t('admin.payment_costs.csv.cross_border_fee'),
            PallasTrade.t('admin.payment_costs.csv.conversion_fee'),
            PallasTrade.t('admin.payment_costs.csv.adjustment'),
            PallasTrade.t('admin.payment_costs.csv.fixed_fee'),
            PallasTrade.t('admin.payment_costs.csv.fee_amount'),
            PallasTrade.t('admin.payment_costs.csv.net_amount'),
            PallasTrade.t('admin.payment_costs.csv.actual_fee'),
            PallasTrade.t('admin.payment_costs.csv.variance'),
            PallasTrade.t('admin.payment_costs.csv.policy'),
            PallasTrade.t('admin.payment_costs.csv.signals')
          ]

          report[:detail].each do |row|
            csv << [
              row[:paid_at]&.iso8601,
              row[:order_number],
              row[:provider_label],
              row[:entry_label],
              row[:method_key],
              row[:order_currency],
              row[:amount].to_s,
              row[:percent_fee].to_s,
              row[:platform_fee].to_s,
              row[:cross_border_fee].to_s,
              row[:conversion_fee].to_s,
              row[:adjustment].to_s,
              row[:fixed_fee].to_s,
              row[:fee_amount].to_s,
              row[:net_amount].to_s,
              row[:actual_fee_amount].to_s,
              row[:variance_amount].to_s,
              row[:policy_name],
              row[:signals].join('|')
            ]
          end
        end
      end

      def add_cost_breadcrumbs
        add_breadcrumb PallasTrade.t(:orders), PallasTrade.admin_orders_path
        add_breadcrumb PallasTrade.t('admin.payment_costs.title'), PallasTrade.admin_payment_costs_path
      end

      def audit_actor
        user = try_pallastrade_current_user
        if user.respond_to?(:id)
          { type: user.class.name, id: user.id, label: user.respond_to?(:email) ? user.email : nil }
        else
          user || 'admin'
        end
      end

      def cost_amount(value, currency = nil)
        return '-' if value.nil?

        formatted = value.to_d.round(2).to_s('F')
        currency.present? ? "#{formatted} #{currency}" : formatted
      end

      def cost_rate(value)
        return '-' if value.nil?

        "#{ActiveSupport::NumberHelper.number_to_rounded(value, precision: 2)}%"
      end
    end
  end
end
