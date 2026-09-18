# frozen_string_literal: true

require 'csv'

# PALLAS-CUSTOM: D15 切片1（PRD-20260916-payments-d15-risk-lists；业务方案 §72.3 名单 / §72.2 底座）——
# Admin 风控名单（Orders → 风控名单）：
#   * index ：list_type / subject_type / 生效状态筛选 + **与筛选同源**的计数 + 分页（展示一律脱敏）；
#   * create：新增 / **续期**（同一归一化值再次提交即更新原行，幂等）；
#   * revoke：撤销（`status='revoked'`，**保留历史行**）；
#   * import：CSV 批量导入（粘贴或上传）→ 逐行幂等 upsert + 错误收集；
#   * export：CSV 导出（筛选同源；保留原值 → 权限 + 审计）。
#
# 唯一写入口：`Risk::Lists::{Upsert,ImportCSV}`（本控制器不直接写模型，避免口径分叉）。
# 铁律：名单是运营事实 —— 不阻断流程、不调 provider、零资金副作用。
module PallasTrade
  module Admin
    class RiskListsController < BaseController
      PER_PAGE = 50
      SUBJECT_TYPES = PallasTrade::PaymentRiskList::SUBJECT_TYPES
      LIST_TYPES = PallasTrade::PaymentRiskList::LIST_TYPES
      SCOPE_FILTERS = %w[all active expired revoked].freeze
      MAX_TEXTAREA_BYTES = 5.megabytes

      helper_method :risk_list_status_label, :risk_list_status_class, :risk_list_scope_label

      # 面包屑由导航自动推导（P6）：Orders > Risk Lists。控制器不再手写
      # 模块/子页 crumb（2026-09-18 修复重复层级）。
      before_action :load_entry, only: %i[revoke]

      # GET /admin/risk_lists
      def index
        @filters = filters
        scope = base_scope

        @page = [params[:page].to_i, 1].max
        @total = scope.count
        @entries = scope.recent_first.limit(PER_PAGE).offset((@page - 1) * PER_PAGE).to_a
        @pages = [(@total.to_f / PER_PAGE).ceil, 1].max
        @counts = counts_for
        @entry = PallasTrade::PaymentRiskList.new(list_type: 'denylist', subject_type: 'email')
        @list_types = LIST_TYPES
        @subject_types = SUBJECT_TYPES
        @scope_filters = SCOPE_FILTERS
      end

      # POST /admin/risk_lists —— 新增 / 续期（同一归一化值 = 更新原行）
      def create
        authorize! :manage, PallasTrade::PaymentRiskList

        outcome = PallasTrade::Risk::Lists::Upsert.call(
          list_type: entry_params[:list_type],
          subject_type: entry_params[:subject_type],
          value: entry_params[:value],
          store: target_store,
          expires_at: entry_params[:expires_at],
          reason: entry_params[:reason],
          actor: audit_actor
        )

        if outcome.success?
          flash[:success] = PallasTrade.t('admin.risk_lists.create_success', value: outcome.value.masked_value)
        else
          flash[:error] = "#{PallasTrade.t('admin.risk_lists.create_failed')}: #{outcome.error}"
        end

        redirect_to redirect_target, status: :see_other
      end

      # POST /admin/risk_lists/:id/revoke —— 撤销（保留历史行，不物理删除）
      def revoke
        authorize! :manage, PallasTrade::PaymentRiskList

        outcome = PallasTrade::Risk::Lists::Upsert.call(
          list_type: @entry.list_type,
          subject_type: @entry.subject_type,
          value: @entry.value,
          store: @entry.store,
          expires_at: @entry.expires_at,
          reason: @entry.reason,
          actor: audit_actor,
          revoke: true
        )

        if outcome.success?
          flash[:success] = PallasTrade.t('admin.risk_lists.revoke_success', value: outcome.value.masked_value)
        else
          flash[:error] = "#{PallasTrade.t('admin.risk_lists.revoke_failed')}: #{outcome.error}"
        end

        redirect_to PallasTrade.admin_risk_lists_path(filters.compact), status: :see_other
      end

      # POST /admin/risk_lists/import —— CSV 批量导入（逐行幂等 + 错误收集）
      def import
        authorize! :manage, PallasTrade::PaymentRiskList

        csv = csv_payload
        if csv.blank?
          flash[:error] = PallasTrade.t('admin.risk_lists.import_empty')
          return redirect_to PallasTrade.admin_risk_lists_path, status: :see_other
        end

        outcome = PallasTrade::Risk::Lists::ImportCSV.call(
          csv: csv,
          store: target_store,
          actor: audit_actor,
          source: params[:source].presence || import_source
        )

        if outcome.success?
          flash[:success] = PallasTrade.t(
            'admin.risk_lists.import_success',
            created: outcome.value[:created], updated: outcome.value[:updated],
            errors: outcome.value[:errors].size
          )
          if outcome.value[:errors].any?
            flash[:warning] = PallasTrade.t('admin.risk_lists.import_errors',
                                            rows: outcome.value[:errors].first(5).map { |e| "##{e[:row]} #{e[:message]}" }.join('; '))
          end
        else
          flash[:error] = "#{PallasTrade.t('admin.risk_lists.import_failed')}: #{outcome.error}"
        end

        redirect_to PallasTrade.admin_risk_lists_path, status: :see_other
      end

      # GET /admin/risk_lists/export —— CSV 导出（列与导入同构，可再导入）
      def export
        authorize! :manage, PallasTrade::PaymentRiskList

        outcome = PallasTrade::Risk::Lists::Export.call(
          store: filters[:store_scope] == 'global' ? nil : current_store,
          list_type: filters[:list_type],
          subject_type: filters[:subject_type],
          scope_filter: filters[:scope_filter] == 'all' ? nil : filters[:scope_filter],
          actor: audit_actor
        )

        return redirect_to(PallasTrade.admin_risk_lists_path, status: :see_other) unless outcome.success?

        send_data outcome.value[:csv],
                  filename: "risk-lists-#{Time.current.strftime('%Y%m%d%H%M%S')}.csv",
                  type: 'text/csv; charset=utf-8'
      end

      private

      # 授权锚点：`can :manage, PallasTrade::PaymentRiskList`
      def model_class
        PallasTrade::PaymentRiskList
      end

      # 审计 actor（与 payouts / refund_approvals 等既有控制台同一约定）
      def audit_actor
        user = try_pallastrade_current_user
        if user.respond_to?(:id)
          { type: user.class.name, id: user.id, label: user.respond_to?(:email) ? user.email : nil }
        else
          user || 'admin'
        end
      end

      def load_entry
        @entry = base_scope.find(params[:id])
      end

      # 页面/导出/计数共用的筛选口径（唯一）
      def filters
        @filters ||= {
          list_type: LIST_TYPES.include?(params[:list_type].to_s) ? params[:list_type].to_s : nil,
          subject_type: SUBJECT_TYPES.include?(params[:subject_type].to_s) ? params[:subject_type].to_s : nil,
          scope_filter: SCOPE_FILTERS.include?(params[:scope_filter].to_s) ? params[:scope_filter].to_s : 'all',
          store_scope: params[:store_scope].to_s == 'global' ? 'global' : 'all'
        }
      end

      def base_scope
        store = filters[:store_scope] == 'global' ? nil : current_store
        PallasTrade::PaymentRiskList.filter_by(
          store: store,
          list_type: filters[:list_type],
          subject_type: filters[:subject_type],
          scope_filter: filters[:scope_filter] == 'all' ? nil : filters[:scope_filter]
        )
      end

      # 计数与列表**同源 scope**（同一 filter_by 口径，只改 scope_filter）
      def counts_for
        base = { store: filters[:store_scope] == 'global' ? nil : current_store,
                 list_type: filters[:list_type], subject_type: filters[:subject_type] }
        SCOPE_FILTERS.index_with do |scope_filter|
          PallasTrade::PaymentRiskList.filter_by(**base, scope_filter: scope_filter == 'all' ? nil : scope_filter).count
        end
      end

      def entry_params
        permitted = %i[list_type subject_type value expires_at reason store_scope]
        params.fetch(:payment_risk_list, {}).permit(*permitted)
      end

      # 写目标：`store_scope == 'global'` → 全局名单（store_id = nil），否则本店名单
      def target_store
        return nil if entry_params[:store_scope].to_s == 'global' || params[:store_scope].to_s == 'global'

        current_store
      end

      def redirect_target
        PallasTrade.admin_risk_lists_path(filters.compact)
      end

      def csv_payload
        upload = params[:csv_file]
        text = upload.respond_to?(:read) ? upload.read : params[:csv].to_s
        return '' if text.blank?
        return '' if text.bytesize > MAX_TEXTAREA_BYTES

        text
      rescue StandardError => e
        Rails.logger.warn("[RiskListsController#import] csv read failed: #{e.class} #{e.message}")
        ''
      end

      def import_source
        params[:csv_file].respond_to?(:original_filename) ? params[:csv_file].original_filename : 'pasted'
      end

      # 状态标签（active / expired / revoked 三态，展示唯一口径）
      def risk_list_status_label(entry)
        return PallasTrade.t('admin.risk_lists.status_revoked') if entry.status == 'revoked'
        return PallasTrade.t('admin.risk_lists.status_expired') if entry.expired?

        PallasTrade.t('admin.risk_lists.status_active')
      end

      def risk_list_status_class(entry)
        return 'badge-secondary' if entry.status == 'revoked'
        return 'badge-warning' if entry.expired?

        'badge-complete'
      end

      def risk_list_scope_label(entry)
        entry.store_id.present? ? (entry.store&.name || entry.store_id.to_s) : PallasTrade.t('admin.risk_lists.scope_global')
      end
    end
  end
end
