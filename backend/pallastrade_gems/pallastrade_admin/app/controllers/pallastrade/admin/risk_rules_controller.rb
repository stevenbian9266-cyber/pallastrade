# frozen_string_literal: true

# PALLAS-CUSTOM: D15 切片2（PRD-20260917-payments-d15b-risk-rules；业务方案 §72.2）——
# Admin 风控规则工作台（Orders → 风控规则）：
#   * index  ：规则集列表（作用域 / 状态 / 生效版 / 金丝雀）+ **与筛选同源**的计数 + 建集入口；
#   * show   ：版本历史 + 生效版规则表 + 金丝雀状态 + 四个动作（发草稿 / 发布 / 金丝雀 / **回滚** / 停用）；
#   * preview：对某个订单**试算**（零写入、零审计）——「这条规则会不会命中这个订单」。
#
# 唯一写入口：`Risk::Rules::Versioning`（本控制器不直接写版本，避免口径分叉）。
# 铁律：规则配置不改订单/支付、不调 provider、零资金副作用；回滚 reason 必填。
module PallasTrade
  module Admin
    class RiskRulesController < BaseController
      PER_PAGE = 50
      MAX_RULES_PAYLOAD_BYTES = 256.kilobytes
      SCOPE_FILTERS = %w[all global store].freeze
      STATUS_FILTERS = %w[all active inactive].freeze

      helper_method :risk_rule_scope_label, :risk_rule_status_label, :risk_rule_version_state_label,
                    :risk_rule_action_label, :risk_rule_condition_summary

      before_action :add_risk_rule_breadcrumbs
      before_action :load_rule_set, only: %i[show create_version publish canary rollback toggle]

      # GET /admin/risk_rules
      def index
        @filters = filters
        scope = base_scope
        @page = [params[:page].to_i, 1].max
        @total = scope.count
        @rule_sets = scope.recent_first.limit(PER_PAGE).offset((@page - 1) * PER_PAGE).to_a
        @pages = [(@total.to_f / PER_PAGE).ceil, 1].max
        @counts = counts_for
        @rule_set = PallasTrade::RiskRuleSet.new(status: 'active', canary_percent: 0)
        @scope_filters = SCOPE_FILTERS
        @status_filters = STATUS_FILTERS
      end

      # POST /admin/risk_rules —— 新建规则集容器（版本为空时引擎不参与评估）
      def create
        authorize! :manage, PallasTrade::RiskRuleSet

        rule_set = PallasTrade::RiskRuleSet.new(
          code: params.dig(:risk_rule_set, :code).to_s.strip.downcase,
          name: params.dig(:risk_rule_set, :name).to_s.strip,
          description: params.dig(:risk_rule_set, :description).to_s.strip.presence,
          store: target_store
        )

        if rule_set.save
          flash[:success] = PallasTrade.t('admin.risk_rules.create_success', code: rule_set.code)
          redirect_to PallasTrade.admin_risk_rule_path(rule_set)
        else
          flash[:error] = "#{PallasTrade.t('admin.risk_rules.create_failed')}: " \
                          "#{rule_set.errors.full_messages.join(', ')}"
          redirect_to PallasTrade.admin_risk_rules_path(filters.compact)
        end
      end

      # GET /admin/risk_rules/:id
      def show
        @versions = @rule_set.versions.recent_first.to_a
        @active_version = @rule_set.active_version
        @canary_version = @rule_set.canary_version
        @active_rules = sorted_rules(Array(@active_version&.rules))
        @canary_rules = sorted_rules(Array(@canary_version&.rules))
      end

      # POST /admin/risk_rules/:id/versions —— 新建草稿（校验不过**不落库**）
      def create_version
        authorize! :manage, PallasTrade::RiskRuleSet

        outcome = PallasTrade::Risk::Rules::Versioning.create_draft(
          rule_set: @rule_set, rules: rules_payload, reason: params[:reason], actor: audit_actor
        )

        if outcome.success?
          flash[:success] = PallasTrade.t('admin.risk_rules.version_created', version: outcome.value.version)
        else
          flash[:error] = "#{PallasTrade.t('admin.risk_rules.version_create_failed')}: #{outcome.error}"
        end

        redirect_to PallasTrade.admin_risk_rule_path(@rule_set), status: :see_other
      end

      # POST /admin/risk_rules/:id/publish —— 发布某个版本为生效版（旧生效版归档）
      def publish
        authorize! :manage, PallasTrade::RiskRuleSet

        outcome = PallasTrade::Risk::Rules::Versioning.publish(
          rule_set: @rule_set, version: params[:version], reason: params[:reason], actor: audit_actor
        )
        flash_for(outcome, 'admin.risk_rules.publish_success', 'admin.risk_rules.publish_failed',
                  version: outcome.value&.version)
        redirect_to PallasTrade.admin_risk_rule_path(@rule_set), status: :see_other
      end

      # POST /admin/risk_rules/:id/canary —— 设置金丝雀版本与流量百分比（0 = 关闭）
      def canary
        authorize! :manage, PallasTrade::RiskRuleSet

        outcome = PallasTrade::Risk::Rules::Versioning.set_canary(
          rule_set: @rule_set, version: params[:version], percent: params[:percent], actor: audit_actor
        )
        flash_for(outcome, 'admin.risk_rules.canary_success', 'admin.risk_rules.canary_failed',
                  percent: @rule_set.canary_percent, version: @rule_set.canary_version&.version)
        redirect_to PallasTrade.admin_risk_rule_path(@rule_set), status: :see_other
      end

      # POST /admin/risk_rules/:id/rollback —— 回滚（以历史版本内容生成**新版本**；原因必填）
      def rollback
        authorize! :manage, PallasTrade::RiskRuleSet

        outcome = PallasTrade::Risk::Rules::Versioning.rollback(
          rule_set: @rule_set, to_version: params[:version], reason: params[:reason], actor: audit_actor
        )
        flash_for(outcome, 'admin.risk_rules.rollback_success', 'admin.risk_rules.rollback_failed',
                  version: outcome.value&.version, source_version: outcome.value&.source_version)
        redirect_to PallasTrade.admin_risk_rule_path(@rule_set), status: :see_other
      end

      # POST /admin/risk_rules/:id/toggle —— 停用 / 启用规则集
      def toggle
        authorize! :manage, PallasTrade::RiskRuleSet

        outcome = if @rule_set.status == 'active'
                    PallasTrade::Risk::Rules::Versioning.deactivate(rule_set: @rule_set, actor: audit_actor)
                  else
                    PallasTrade::Risk::Rules::Versioning.activate(rule_set: @rule_set, actor: audit_actor)
                  end
        flash_for(outcome, 'admin.risk_rules.toggle_success', 'admin.risk_rules.toggle_failed',
                  status: @rule_set.reload.status)
        redirect_to PallasTrade.admin_risk_rule_path(@rule_set), status: :see_other
      end

      # GET /admin/risk_rules/preview?order_number=or_xxx —— 试算（**零写入、零审计**）
      def preview
        authorize! :manage, PallasTrade::RiskRuleSet

        @order_number = params[:order_number].to_s.strip
        @order = find_order(@order_number)
        @result = @order && PallasTrade::Risk::Rules::Evaluate.call(order: @order).value
      end

      private

      def model_class
        PallasTrade::RiskRuleSet
      end

      def add_risk_rule_breadcrumbs
        add_breadcrumb PallasTrade.t(:orders), PallasTrade.admin_orders_path
        add_breadcrumb PallasTrade.t('admin.risk_rules.title'), PallasTrade.admin_risk_rules_path
      end

      def load_rule_set
        @rule_set = PallasTrade::RiskRuleSet.find(params[:id])
      end

      # 页面/计数共用的筛选口径（唯一）
      def filters
        @filters ||= {
          scope_filter: SCOPE_FILTERS.include?(params[:scope_filter].to_s) ? params[:scope_filter].to_s : 'all',
          status_filter: STATUS_FILTERS.include?(params[:status_filter].to_s) ? params[:status_filter].to_s : 'all'
        }
      end

      def base_scope
        scope = scope_without_status
        filters[:status_filter] == 'all' ? scope : scope.where(status: filters[:status_filter])
      end

      # 计数与列表**同源**（同一个 scope_without_status，只换 status_filter）
      def counts_for
        scope = scope_without_status
        STATUS_FILTERS.index_with do |status_filter|
          status_filter == 'all' ? scope.count : scope.where(status: status_filter).count
        end
      end

      # 作用域口径（唯一）：all = 全局 + 本店；global = 仅全局；store = 仅本店
      def scope_without_status
        case filters[:scope_filter]
        when 'global' then PallasTrade::RiskRuleSet.global
        when 'store' then PallasTrade::RiskRuleSet.where(store_id: current_store&.id)
        else PallasTrade::RiskRuleSet.for_store(current_store)
        end
      end

      # 写目标：`store_scope == 'global'` → 全局规则集（store_id = nil），否则本店规则集
      def target_store
        return nil if params[:store_scope].to_s == 'global' || params.dig(:risk_rule_set, :store_scope).to_s == 'global'

        current_store
      end

      # 规则 JSON 载荷（有界：避免超大 body 拖垮请求）
      def rules_payload
        payload = params[:rules].to_s
        return '' if payload.bytesize > MAX_RULES_PAYLOAD_BYTES

        payload
      end

      def sorted_rules(rules)
        rules.each_with_index.sort_by { |rule, index| [rule['priority'].to_i, index] }.map(&:first)
      end

      def find_order(number)
        return nil if number.blank?

        PallasTrade::Order.for_store(current_store).find_by_param(number)
      rescue StandardError
        nil
      end

      def flash_for(outcome, success_key, failure_key, **locals)
        if outcome.success?
          flash[:success] = PallasTrade.t(success_key, **locals)
        else
          flash[:error] = "#{PallasTrade.t(failure_key)}: #{outcome.error}"
        end
      end

      # 审计 actor（与 risk_lists / payouts 等既有控制台同一约定）
      def audit_actor
        user = try_pallastrade_current_user
        if user.respond_to?(:id)
          { type: user.class.name, id: user.id, label: user.respond_to?(:email) ? user.email : nil }
        else
          user || 'admin'
        end
      end

      # === 展示口径（页面唯一） ===

      def risk_rule_scope_label(rule_set)
        rule_set.store_id.present? ? (rule_set.store&.name || rule_set.store_id.to_s) :
          PallasTrade.t('admin.risk_rules.scope_global')
      end

      def risk_rule_status_label(rule_set)
        PallasTrade.t("admin.risk_rules.status_#{rule_set.status}")
      end

      def risk_rule_version_state_label(version)
        PallasTrade.t("admin.risk_rules.state_#{version.state}")
      end

      def risk_rule_action_label(action)
        PallasTrade.t("admin.risk_rules.action_#{action}", default: action.to_s)
      end

      # 条件摘要（人可读；未知键原样显示，便于排查历史数据）
      def risk_rule_condition_summary(conditions)
        Array(conditions).map do |key, value|
          operator = PallasTrade.t("admin.risk_rules.condition_#{key}", default: key.to_s)
          rendered = value.is_a?(Array) ? value.join('/') : value.to_s
          "#{operator} #{rendered}".strip
        end.join(' · ')
      end
    end
  end
end
