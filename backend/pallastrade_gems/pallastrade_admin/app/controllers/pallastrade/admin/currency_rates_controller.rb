# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片4（PRD-20260916-payments-d13d-fx-snapshot；业务方案 §70.4）——
# Admin 汇率表（Orders → 汇率表，position 62）：
#   * index ：币种对 / 来源 / 状态筛选 + **与筛选同源**的计数 + 分页；
#   * create：新增（同一身份键 = 更新原行，幂等）；
#   * revoke：软撤销（保留历史行，历史快照可复算）。
#
# 唯一写入口：`Currencies::Rates::Upsert`（控制器不直接写模型，避免口径分叉）。
# 铁律：汇率只用于结算差核算 —— 不改订单/支付金额、不写资金流水、不外呼。
module PallasTrade
  module Admin
    class CurrencyRatesController < BaseController
      SOURCES = PallasTrade::CurrencyRate::SOURCES
      STATUS_FILTERS = %w[all active revoked].freeze
      PER_PAGE = 50

      helper_method :currency_rate_source_label, :rate_value

      before_action :add_currency_rate_breadcrumbs
      before_action :load_rate, only: %i[revoke]

      # GET /admin/currency_rates
      def index
        authorize! :manage, PallasTrade::CurrencyRate

        @filters = filters
        scope = base_scope
        @page = [params[:page].to_i, 1].max
        @total = scope.count
        @policies = scope.recent_first.limit(PER_PAGE).offset((@page - 1) * PER_PAGE).to_a
        @pages = [(@total.to_f / PER_PAGE).ceil, 1].max
        @counts = counts_for
        @rate = PallasTrade::CurrencyRate.new(base_currency: current_store&.default_currency.presence,
                                             quote_currency: 'USD', source: 'manual')
        @sources = SOURCES
        @status_filters = STATUS_FILTERS
      end

      # POST /admin/currency_rates
      def create
        authorize! :manage, PallasTrade::CurrencyRate

        outcome = PallasTrade::Currencies::Rates::Upsert.call(
          base_currency: rate_params[:base_currency],
          quote_currency: rate_params[:quote_currency],
          rate: rate_params[:rate],
          source: rate_params[:source].presence || 'manual',
          priority: rate_params[:priority].presence,
          effective_from: rate_params[:effective_from],
          effective_until: rate_params[:effective_until],
          note: rate_params[:note],
          store: target_store,
          actor: audit_actor
        )

        if outcome.success?
          flash[:success] = PallasTrade.t(
            'admin.currency_rates.create_success',
            base: outcome.value[:rate].base_currency, quote: outcome.value[:rate].quote_currency
          )
        else
          flash[:error] = "#{PallasTrade.t('admin.currency_rates.create_failed')}: #{outcome.error}"
        end

        redirect_to PallasTrade.admin_currency_rates_path(filters.compact), status: :see_other
      end

      # POST /admin/currency_rates/:id/revoke
      def revoke
        authorize! :manage, PallasTrade::CurrencyRate

        outcome = PallasTrade::Currencies::Rates::Upsert.call(
          base_currency: @rate.base_currency,
          quote_currency: @rate.quote_currency,
          rate: @rate.rate,
          source: @rate.source,
          effective_from: @rate.effective_from,
          store: @rate.store,
          actor: audit_actor,
          revoke: true
        )

        if outcome.success?
          flash[:success] = PallasTrade.t('admin.currency_rates.revoke_success', base: @rate.base_currency,
                                                                                 quote: @rate.quote_currency)
        else
          flash[:error] = "#{PallasTrade.t('admin.currency_rates.revoke_failed')}: #{outcome.error}"
        end

        redirect_to PallasTrade.admin_currency_rates_path(filters.compact), status: :see_other
      end

      private

      def model_class
        PallasTrade::CurrencyRate
      end

      # 审计 actor（与 risk_lists / payouts / refund_approvals 等既有控制台同一约定）
      def audit_actor
        user = try_pallastrade_current_user
        if user.respond_to?(:id)
          { type: user.class.name, id: user.id, label: user.respond_to?(:email) ? user.email : nil }
        else
          user || 'admin'
        end
      end

      def add_currency_rate_breadcrumbs
        add_breadcrumb PallasTrade.t(:orders), PallasTrade.admin_orders_path
        add_breadcrumb PallasTrade.t('admin.currency_rates.title'), PallasTrade.admin_currency_rates_path
      end

      def load_rate
        @rate = base_scope.find(params[:id])
      end

      def target_store
        params[:store_scope].to_s == 'global' ? nil : current_store
      end

      # 页面/计数共用的筛选口径（唯一）
      def filters
        @filters ||= {
          base_currency: params[:base_currency].to_s.strip.presence&.upcase,
          quote_currency: params[:quote_currency].to_s.strip.presence&.upcase,
          source: SOURCES.include?(params[:source].to_s) ? params[:source].to_s : nil,
          status_filter: STATUS_FILTERS.include?(params[:status_filter].to_s) ? params[:status_filter].to_s : 'all',
          store_scope: params[:store_scope].to_s == 'global' ? 'global' : 'all'
        }
      end

      def base_scope
        PallasTrade::CurrencyRate.filter_by(
          store: filters[:store_scope] == 'global' ? nil : current_store,
          base_currency: filters[:base_currency],
          quote_currency: filters[:quote_currency],
          source: filters[:source],
          status_filter: filters[:status_filter] == 'all' ? nil : filters[:status_filter]
        )
      end

      # 计数与列表**同源 scope**（同一 filter_by 口径，只改 status_filter）
      def counts_for
        base = {
          store: filters[:store_scope] == 'global' ? nil : current_store,
          base_currency: filters[:base_currency],
          quote_currency: filters[:quote_currency],
          source: filters[:source]
        }
        STATUS_FILTERS.index_with do |status_filter|
          PallasTrade::CurrencyRate.filter_by(
            **base, status_filter: status_filter == 'all' ? nil : status_filter
          ).count
        end
      end

      def rate_params
        params.require(:currency_rate).permit(
          :base_currency, :quote_currency, :rate, :source, :priority, :effective_from, :effective_until, :note
        )
      end

      def currency_rate_source_label(source)
        PallasTrade.t("admin.currency_rates.source_#{source}")
      end

      # 汇率展示（10 位小数，去尾零）
      def rate_value(value)
        return '-' if value.nil?

        value.to_d.round(6).to_s('F')
      end
    end
  end
end
