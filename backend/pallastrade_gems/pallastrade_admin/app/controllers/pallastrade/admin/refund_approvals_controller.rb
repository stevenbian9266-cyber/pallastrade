# frozen_string_literal: true

# PALLAS-CUSTOM: D14 切片1（PRD-20260916-payments-d14-refund-approval；业务方案 §71.1）——
# Admin 退款审批工作台（Orders → 退款审批）：
#   * index  ：待批队列（金额/币种/发起人/阈值快照/时间）+ 状态筛选 + 计数 + 分页 + 策略卡；
#   * policy ：保存店铺级退款策略（enabled / auto_approve_limit / currency）+ 审计；
#   * approve / reject：**第二人**决策（服务层强制「不能自批」；拒绝必填原因）。
#
# 铁律：页面动作只改审批记录 + 入队/撤销退款 —— **零资金副作用**（provider I/O 仍只发生在
# ExecuteJob；页面不调 provider、不改金额）。
module PallasTrade
  module Admin
    class RefundApprovalsController < BaseController
      PER_PAGE = 50
      POLICY_KEY = PallasTrade::Refunds::Policy::KEY

      before_action :add_refund_approval_breadcrumbs
      before_action :load_approval, only: %i[approve reject]

      # GET /admin/refund_approvals
      def index
        @filters = filters
        scope = filtered_scope

        @page = [params[:page].to_i, 1].max
        @total = scope.count
        @approvals = scope.recent_first.limit(PER_PAGE).offset((@page - 1) * PER_PAGE).to_a
        @pages = [(@total.to_f / PER_PAGE).ceil, 1].max
        @counts = base_scope.group(:status).count
        @policy = PallasTrade::Refunds::Policy.for(current_store)
        @current_actor_id = actor_id
      end

      # PATCH /admin/refund_approvals/policy —— 保存店铺级退款策略（审计 + 归一化）
      def policy
        store = current_store
        return head(:not_found) if store.nil?

        authorize! :update, PallasTrade::Store

        normalized = normalized_policy
        before = (store.private_metadata || {})[POLICY_KEY]
        metadata = (store.private_metadata || {}).merge(POLICY_KEY => normalized)
        store.update_columns(private_metadata: metadata)

        PallasTrade::Audit.record(
          actor: audit_actor,
          action: 'refund_policy_updated',
          resource: store,
          before: { POLICY_KEY => before },
          after: { POLICY_KEY => normalized }
        )

        flash[:success] = PallasTrade.t('admin.refund_approvals.policy_saved')
        redirect_to PallasTrade.admin_refund_approvals_path, status: :see_other
      rescue CanCan::AccessDenied
        flash[:error] = PallasTrade.t('admin.refund_approvals.policy_denied')
        redirect_to PallasTrade.admin_refund_approvals_path, status: :see_other
      rescue StandardError => e
        Rails.logger.warn(message: 'admin.refund_approvals.policy_failed', error: e.class.name,
                          detail: e.message.to_s.truncate(200))
        flash[:error] = PallasTrade.t('admin.refund_approvals.policy_failed')
        redirect_to PallasTrade.admin_refund_approvals_path, status: :see_other
      end

      # POST /admin/refund_approvals/:id/approve
      def approve
        authorize! :update, PallasTrade::Refund
        outcome = PallasTrade::Refunds::Approvals::Approve.call(
          approval: @approval, approver_id: actor_id, note: params[:note], actor: audit_actor
        )

        if outcome.success?
          flash[:success] = PallasTrade.t('admin.refund_approvals.approved_flash')
        else
          flash[:error] = decision_error_message(outcome, 'admin.refund_approvals.approve_failed')
        end

        redirect_to PallasTrade.admin_refund_approvals_path, status: :see_other
      end

      # POST /admin/refund_approvals/:id/reject
      def reject
        authorize! :update, PallasTrade::Refund
        outcome = PallasTrade::Refunds::Approvals::Reject.call(
          approval: @approval, approver_id: actor_id, note: params[:note], actor: audit_actor
        )

        if outcome.success?
          flash[:success] = PallasTrade.t('admin.refund_approvals.rejected_flash')
        else
          flash[:error] = decision_error_message(outcome, 'admin.refund_approvals.reject_failed')
        end

        redirect_to PallasTrade.admin_refund_approvals_path, status: :see_other
      end

      helper_method :refund_approval_status_class, :same_actor?

      private

      # 授权锚点：`can :manage, PallasTrade::RefundApproval`（configuration_management）
      def model_class
        PallasTrade::RefundApproval
      end

      def add_refund_approval_breadcrumbs
        add_breadcrumb PallasTrade.t(:orders), PallasTrade.admin_orders_path
        add_breadcrumb PallasTrade.t('admin.refund_approvals.title'), PallasTrade.admin_refund_approvals_path
      end

      def load_approval
        @approval = base_scope.find(params[:id])
      end

      def base_scope
        PallasTrade::RefundApproval.where(store_id: current_store&.id).includes(:refund, :requester, :approver)
      end

      def filter_params
        {
          scope_filter: params[:status].presence || 'pending',
          from: parse_boundary(params[:from]),
          to: parse_boundary(params[:to], end_of_day: true)
        }
      end

      def filters
        @filters ||= filter_params
      end

      def filtered_scope
        base_scope.filter_by(store_id: current_store&.id, **filters)
      end

      def parse_boundary(value, end_of_day: false)
        return nil if value.blank?

        time = Time.zone.parse(value.to_s)
        return nil if time.nil?
        return time unless value.to_s.strip.length <= 10

        end_of_day ? time.end_of_day : time.beginning_of_day
      rescue ArgumentError, TypeError
        nil
      end

      # 策略归一化（写库前）：只保留已知键，阈值缺失/非法 → 空串（引擎侧按「全部需审批」处理）
      def normalized_policy
        raw_limit = params[:auto_approve_limit].to_s.strip
        {
          'enabled' => ActiveModel::Type::Boolean.new.cast(params[:enabled]).present?,
          'auto_approve_limit' => raw_limit,
          'currency' => params[:currency].to_s.strip.upcase.presence
        }
      end

      def decision_error_message(outcome, fallback_key)
        code = outcome.error&.to_s
        key = "admin.refund_approvals.errors.#{code}"
        translated = PallasTrade.t(key, default: nil)
        translated.presence || "#{PallasTrade.t(fallback_key)}: #{code}"
      end

      def actor_id
        user = try_pallastrade_current_user
        user.respond_to?(:id) ? user.id : nil
      end

      def audit_actor
        user = try_pallastrade_current_user
        if user.respond_to?(:id)
          { type: user.class.name, id: user.id, label: user.respond_to?(:email) ? user.email : nil }
        else
          user || 'admin'
        end
      end

      def same_actor?(approval)
        approval.requester?(actor_id)
      end

      def refund_approval_status_class(status)
        case status.to_s
        when 'approved' then 'badge-success'
        when 'rejected' then 'badge-danger'
        else 'badge-warning'
        end
      end
    end
  end
end
