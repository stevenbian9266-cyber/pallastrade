# frozen_string_literal: true

# PALLAS-CUSTOM: D13 切片3（PRD-20260916-payments-d13c-fee-cost-report；业务方案 §70.3 费率模型）——
# Admin 费率策略维护（Orders → 费率策略）：
#   * index ：scope / 状态 / 币种筛选 + **与筛选同源**的计数 + 分页；
#   * create / update：费率策略新增与修改（表单只暴露 global / provider / method 三种适用范围，
#     `store` 级保留给平台侧多店维护）；
#   * revoke：软撤销（`status='revoked'`，**保留历史行**，历史报表可复算）。
#
# 铁律：费率是**只读核算的输入** —— 本控制器不触碰支付/退款/账本/库存，也不调 provider。
module PallasTrade
  module Admin
    class PaymentFeePoliciesController < BaseController
      # 表单可选项：`store` 级由平台侧维护（单店后台不暴露，避免与「兜底」语义混淆）
      FORM_SCOPE_TYPES = %w[global provider method].freeze
      STATUS_FILTERS = %w[all active revoked].freeze
      PER_PAGE = 50

      helper_method :fee_policy_scope_label

      # 面包屑由导航自动推导（P6）：Orders > Payment Fee Policies。控制器不再手写
      # 模块/子页 crumb（2026-09-18 修复重复层级）。
      before_action :load_policy, only: %i[edit update revoke]

      # GET /admin/payment_fee_policies
      def index
        authorize! :manage, PallasTrade::PaymentFeePolicy

        @filters = filters
        scope = base_scope
        @page = [params[:page].to_i, 1].max
        @total = scope.count
        @policies = scope.recent_first.limit(PER_PAGE).offset((@page - 1) * PER_PAGE).to_a
        @pages = [(@total.to_f / PER_PAGE).ceil, 1].max
        @counts = counts_for
        @policy = build_policy
        @scope_types = FORM_SCOPE_TYPES
        @status_filters = STATUS_FILTERS
        @payment_methods = payment_methods
      end

      # GET /admin/payment_fee_policies/new
      def new
        authorize! :manage, PallasTrade::PaymentFeePolicy

        @policy = build_policy
        @scope_types = FORM_SCOPE_TYPES
        @payment_methods = payment_methods
        render :new
      end

      # POST /admin/payment_fee_policies
      def create
        authorize! :manage, PallasTrade::PaymentFeePolicy

        @policy = build_policy(policy_params)

        if @policy.save
          record_audit('payment_fee_policy_changed', @policy, before: nil, after: snapshot(@policy))
          flash[:success] = PallasTrade.t('admin.payment_fee_policies.create_success', name: @policy.name)
          redirect_to PallasTrade.admin_payment_fee_policies_path, status: :see_other
        else
          @scope_types = FORM_SCOPE_TYPES
          @payment_methods = payment_methods
          flash.now[:error] = PallasTrade.t('admin.payment_fee_policies.save_failed')
          render :new, status: :unprocessable_entity
        end
      end

      # GET /admin/payment_fee_policies/:id/edit
      def edit
        authorize! :manage, PallasTrade::PaymentFeePolicy

        @scope_types = FORM_SCOPE_TYPES
        @payment_methods = payment_methods
      end

      # PATCH /admin/payment_fee_policies/:id
      def update
        authorize! :manage, PallasTrade::PaymentFeePolicy

        before = snapshot(@policy)

        if @policy.update(policy_params)
          record_audit('payment_fee_policy_changed', @policy, before: before, after: snapshot(@policy))
          flash[:success] = PallasTrade.t('admin.payment_fee_policies.update_success', name: @policy.name)
          redirect_to PallasTrade.admin_payment_fee_policies_path, status: :see_other
        else
          @scope_types = FORM_SCOPE_TYPES
          @payment_methods = payment_methods
          flash.now[:error] = PallasTrade.t('admin.payment_fee_policies.save_failed')
          render :edit, status: :unprocessable_entity
        end
      end

      # POST /admin/payment_fee_policies/:id/revoke
      def revoke
        authorize! :manage, PallasTrade::PaymentFeePolicy

        before = snapshot(@policy)
        @policy.revoke!(actor: audit_actor)
        record_audit('payment_fee_policy_revoked', @policy, before: before, after: snapshot(@policy))

        flash[:success] = PallasTrade.t('admin.payment_fee_policies.revoke_success', name: @policy.name)
        redirect_to PallasTrade.admin_payment_fee_policies_path(filters.compact), status: :see_other
      end

      private

      def model_class
        PallasTrade::PaymentFeePolicy
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

      def load_policy
        @policy = base_scope.find(params[:id])
      end

      def filters
        @filters ||= {
          scope_type: FORM_SCOPE_TYPES.include?(params[:scope_type].to_s) ? params[:scope_type].to_s : nil,
          status_filter: STATUS_FILTERS.include?(params[:status_filter].to_s) ? params[:status_filter].to_s : 'all',
          currency: params[:currency].to_s.strip.presence&.upcase
        }
      end

      def base_scope
        PallasTrade::PaymentFeePolicy.filter_by(
          store: current_store,
          scope_type: filters[:scope_type],
          status_filter: filters[:status_filter] == 'all' ? nil : filters[:status_filter],
          currency: filters[:currency]
        )
      end

      # 计数与列表**同源 scope**（同一 filter_by 口径，只改 status_filter）
      def counts_for
        base = { store: current_store, scope_type: filters[:scope_type], currency: filters[:currency] }
        STATUS_FILTERS.index_with do |status_filter|
          PallasTrade::PaymentFeePolicy.filter_by(
            **base, status_filter: status_filter == 'all' ? nil : status_filter
          ).count
        end
      end

      def payment_methods
        PallasTrade::PaymentMethod.order(:name).pluck(:id, :name)
      end

      def build_policy(attrs = {})
        PallasTrade::PaymentFeePolicy.new({ store_id: current_store&.id, scope_type: 'global' }.merge(attrs))
      end

      def policy_params
        params.require(:payment_fee_policy).permit(
          :name, :scope_type, :scope_id, :currency, :card_type, :region,
          :percent_fee, :fixed_fee, :cross_border_percent, :cross_border_fixed,
          :currency_conversion_percent, :platform_percent, :min_fee, :max_fee,
          :home_country, :settlement_currency, :effective_from, :effective_until
        )
      end

      # 审计快照：只含费率策略字段（**不含**任何凭证；本模型本就不持有密钥）
      def snapshot(policy)
        {
          name: policy.name,
          scope_type: policy.scope_type,
          scope_id: policy.scope_id,
          currency: policy.currency,
          card_type: policy.card_type,
          region: policy.region,
          percent_fee: policy.percent_fee.to_s,
          fixed_fee: policy.fixed_fee.to_s,
          cross_border_percent: policy.cross_border_percent.to_s,
          cross_border_fixed: policy.cross_border_fixed.to_s,
          currency_conversion_percent: policy.currency_conversion_percent.to_s,
          platform_percent: policy.platform_percent.to_s,
          min_fee: policy.min_fee&.to_s,
          max_fee: policy.max_fee&.to_s,
          home_country: policy.home_country,
          settlement_currency: policy.settlement_currency,
          status: policy.status,
          effective_from: policy.effective_from&.iso8601,
          effective_until: policy.effective_until&.iso8601
        }
      end

      def record_audit(action, policy, before:, after:)
        PallasTrade::Audit.record(
          action: action,
          actor: audit_actor,
          resource: policy,
          before: before,
          after: after
        )
      end

      def fee_policy_scope_label(policy)
        PallasTrade.t("admin.payment_fee_policies.scope_#{policy.scope_type}")
      end
    end
  end
end
