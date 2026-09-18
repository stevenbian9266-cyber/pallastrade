# frozen_string_literal: true

require 'csv'

# PALLAS-CUSTOM: D13 切片1（PRD-20260916-payments-d13-reconciliation-cases；业务方案 §70.1）——
# Admin 对账差异队列工作台（Orders → 对账队列）：
#   * index：筛选（状态/类型/严重级/provider/责任人/搜索）+ 计数 + 分页；
#   * show：案例事实 + 关联交易/支付/退款 + 原因码 + 备注时间线 + 审计轨迹；
#   * 动作：assign / note / mark_explained / mark_fixed / dismiss（必填原因）/ reopen —— 全部写审计；
#   * export：当前筛选的 CSV（有界，附列头）。
#
# 铁律（与 P4 §44/§46 + runbook 一致）：**零资金副作用** —— 只写案例表 + AuditLog；
# 绝不修改 Payment/Refund/Transaction/Journal/订单/库存，绝不触发 provider 调用或自动资金动作。
module PallasTrade
  module Admin
    class ReconciliationCasesController < BaseController
      PER_PAGE = 50
      EXPORT_LIMIT = 10_000

      # 面包屑由导航自动推导（P6）：Orders > Reconciliation Cases。控制器不再手写
      # 模块/子页 crumb（2026-09-18 修复重复层级）。
      before_action :load_case, only: %i[show assign note mark_investigating mark_explained mark_fixed dismiss reopen]

      # GET /admin/reconciliation_cases
      def index
        @filters = filters
        scope = filtered_scope

        @page = [params[:page].to_i, 1].max
        @total = scope.count
        @cases = scope.recent_first.limit(PER_PAGE).offset((@page - 1) * PER_PAGE).to_a
        @status_counts = counts_by_status
        @providers = base_scope.distinct.pluck(:provider).compact.sort
        @assignees = assignee_options
      end

      # GET /admin/reconciliation_cases/:id
      def show
        @notes = @case.notes.chronological.to_a
        @audits = safe_value { audits_for(@case) } || []
        @commerce_transaction = @case.commerce_transaction
        @orders = safe_value { orders_for(@commerce_transaction) } || []
        @assignee_options_for_form = assignable_users
      end

      # GET /admin/reconciliation_cases/export.csv —— 导出当前筛选（口径与 index 一致）
      def export
        scope = filtered_scope.recent_first
        total = scope.count
        rows = scope.limit(EXPORT_LIMIT).to_a

        if total > EXPORT_LIMIT
          Rails.logger.warn(
            message: 'admin.reconciliation_cases.export_truncated',
            total: total,
            exported: EXPORT_LIMIT,
            filters: filters.compact
          )
        end

        send_data csv_for(rows),
                  filename: "reconciliation_cases-#{Time.current.strftime('%Y%m%d%H%M%S')}.csv",
                  type: 'text/csv; charset=utf-8',
                  disposition: 'attachment'
      end

      # POST /admin/reconciliation_cases/:id/assign
      def assign
        authorize! :update, @case
        assignee = resolve_assignee

        if params[:assignee_id].present? && assignee.blank?
          flash[:error] = PallasTrade.t('admin.reconciliation_cases.assignee_not_found')
          return redirect_to PallasTrade.admin_reconciliation_case_path(@case), status: :see_other
        end

        @case.assign_to!(assignee)
        audit('reconciliation_case_assigned', assignee: assignee&.id)
        flash[:success] = if assignee.present?
                            PallasTrade.t('admin.reconciliation_cases.assigned',
                                          name: assignee_label(assignee))
                          else
                            PallasTrade.t('admin.reconciliation_cases.unassigned')
                          end
        redirect_to PallasTrade.admin_reconciliation_case_path(@case), status: :see_other
      end

      # POST /admin/reconciliation_cases/:id/note —— 追加备注（留痕，不覆盖历史）
      def note
        authorize! :update, @case
        body = params[:body].to_s.strip

        if body.blank?
          flash[:error] = PallasTrade.t('admin.reconciliation_cases.note_required')
          return redirect_to PallasTrade.admin_reconciliation_case_path(@case), status: :see_other
        end

        @case.notes.create!(body: body, author: current_admin_user_for_notes)
        audit('reconciliation_case_note_added', body_length: body.length)
        flash[:success] = PallasTrade.t('admin.reconciliation_cases.note_added')
        redirect_to PallasTrade.admin_reconciliation_case_path(@case), status: :see_other
      end

      # POST /admin/reconciliation_cases/:id/mark_investigating —— 进入「排查中」（仍在队列，未关闭）
      def mark_investigating
        authorize! :update, @case
        @case.update!(status: 'investigating')
        audit('reconciliation_case_investigating')
        flash[:success] = PallasTrade.t('admin.reconciliation_cases.investigating')
        redirect_to PallasTrade.admin_reconciliation_case_path(@case), status: :see_other
      end

      # POST /admin/reconciliation_cases/:id/mark_explained | mark_fixed
      def mark_explained
        close_with('explained')
      end

      def mark_fixed
        close_with('fixed')
      end

      # POST /admin/reconciliation_cases/:id/dismiss —— 忽略（**必须填原因**）
      def dismiss
        authorize! :update, @case
        reason = params[:reason].to_s.strip

        if reason.blank?
          flash[:error] = PallasTrade.t('admin.reconciliation_cases.dismiss_reason_required')
          return redirect_to PallasTrade.admin_reconciliation_case_path(@case), status: :see_other
        end

        close_case('dismissed', note: reason)
      end

      # POST /admin/reconciliation_cases/:id/reopen
      def reopen
        authorize! :update, @case
        @case.reopen!
        audit('reconciliation_case_reopened')
        flash[:success] = PallasTrade.t('admin.reconciliation_cases.reopened')
        redirect_to PallasTrade.admin_reconciliation_case_path(@case), status: :see_other
      end

      helper_method :reconciliation_status_class, :reconciliation_severity_class, :case_amount_label

      private

      # 授权锚点：`can :manage, PallasTrade::ReconciliationCase`（配置管理权限集）。
      def model_class
        PallasTrade::ReconciliationCase
      end

      def load_case
        @case = PallasTrade::ReconciliationCase.find(params[:id])
      end

      def base_scope
        PallasTrade::ReconciliationCase.where(store_id: current_store.id)
      end

      def filter_params
        {
          scope_filter: params[:scope].presence,
          kind: params[:kind].presence,
          difference_type: params[:difference_type].presence,
          severity: params[:severity].presence,
          provider: params[:provider].presence,
          assignee_id: params[:assignee_id].presence,
          search: params[:search].presence
        }
      end

      # 筛选参数（index / export 共用同一份 —— 保证两处口径一致）。
      def filters
        @filters ||= filter_params
      end

      def filtered_scope
        base_scope.filter_by(store_id: current_store.id, **filters)
      end

      def counts_by_status
        base_scope.group(:status).count
      end

      def assignee_options
        ids = base_scope.where.not(assignee_id: nil).distinct.pluck(:assignee_id)
        klass = PallasTrade.admin_user_class
        return [] unless klass

        klass.where(id: ids).map { |user| [assignee_label(user), user.id] }
      end

      # 指派下拉：全部后台用户（有界 200，按 id 升序稳定）。
      def assignable_users
        klass = PallasTrade.admin_user_class
        return [] if klass.blank?

        klass.order(:id).limit(200).map { |user| [assignee_label(user), user.id] }
      end

      def assignee_label(user)
        return '' if user.blank?

        user.respond_to?(:email) && user.email.present? ? user.email : user.to_s
      end

      # 指派目标：显式 assignee_id（校验存在）或 `assignee_id=self`（指派给自己）。
      def resolve_assignee
        raw = params[:assignee_id].to_s
        return current_admin_user_for_notes if raw == 'self'

        klass = PallasTrade.admin_user_class
        return nil if klass.blank? || raw.blank?

        klass.find_by(id: raw)
      end

      def current_admin_user_for_notes
        user = try_pallastrade_current_user
        user if user.respond_to?(:id)
      end

      def close_with(status)
        authorize! :update, @case
        close_case(status)
      end

      def close_case(status, note: nil)
        @case.close!(status: status, source: 'human', note: note.presence || params[:note])
        audit("reconciliation_case_#{status}", note: note.presence || params[:note])
        flash[:success] = PallasTrade.t("admin.reconciliation_cases.#{status}")
        redirect_to PallasTrade.admin_reconciliation_case_path(@case), status: :see_other
      end

      def audit(action, **metadata)
        PallasTrade::Audit.record(
          action: action,
          actor: audit_actor,
          resource: @case,
          metadata: metadata.compact
        )
      end

      # 与 disputes_ops / webhook_events 同口径的审计 actor 构造。
      def audit_actor
        user = try_pallastrade_current_user
        if user.respond_to?(:id)
          { type: user.class.name, id: user.id, label: user.respond_to?(:email) ? user.email : nil }
        else
          user || 'admin'
        end
      end

      def safe_value
        yield
      rescue StandardError => e
        Rails.logger.warn(
          message: 'admin.reconciliation_cases.degraded',
          error: e.class.name,
          detail: e.message.to_s.truncate(200)
        )
        nil
      end

      def audits_for(kase)
        PallasTrade::AuditLog
          .where(resource_type: kase.class.name, resource_id: kase.id)
          .order(occurred_at: :desc)
          .limit(20)
          .to_a
      end

      def orders_for(transaction)
        return [] if transaction.blank?

        transaction.orders.to_a
      end

      # CSV：列口径 = 队列可读字段（不含任何凭证/敏感数据）。
      def csv_for(rows)
        ::CSV.generate do |csv|
          csv << %w[id dedupe_key kind status severity difference_type provider currency
                    expected_amount observed_amount reason_codes occurrences
                    detected_at last_seen_at assignee resolved_at resolution_source
                    resolution_note transaction]
          rows.each do |kase|
            csv << [
              kase.id, kase.dedupe_key, kase.kind, kase.status, kase.severity, kase.difference_type,
              kase.provider, kase.currency, kase.expected_amount, kase.observed_amount,
              Array(kase.reason_codes).join('|'), kase.occurrences,
              kase.detected_at&.iso8601, kase.last_seen_at&.iso8601, assignee_label(kase.assignee),
              kase.resolved_at&.iso8601, kase.resolution_source, kase.resolution_note,
              kase.commerce_transaction&.prefixed_id
            ]
          end
        end
      end

      # -- 视图辅助 --

      def reconciliation_status_class(status)
        case status.to_s
        when 'open' then 'badge-danger'
        when 'investigating' then 'badge-warning'
        when 'fixed' then 'badge-success'
        when 'explained' then 'badge-info'
        else 'badge-secondary'
        end
      end

      def reconciliation_severity_class(severity)
        case severity.to_s
        when 'critical' then 'badge-danger'
        when 'attention' then 'badge-warning'
        else 'badge-info'
        end
      end

      def case_amount_label(value)
        value.present? ? value.to_s : '—'
      end
    end
  end
end
