# frozen_string_literal: true

# PALLAS-CUSTOM: REV-P6-8a (PRD-20260908-payments-rev-p6-8a-refund-admin-ops; 源 P6 §63)
#
# Admin Refund Ops —— durable Refund inspection（Orders → Refunds，纯只读）。
# index：store 作用域退款列表（Refund.for_store：单订单 ∪ 组合退款）+ Ransack 过滤/排序；
# show：§63 全字段下钻（state/时间戳/原支付/ownership/Provider 引用与幂等键/Journal 事实/
#       Reconciliation 只读在线/Restock 五态/Recovery/审计日志）。
# 不变式：零资金副作用、零 provider mutation、不改 state machine；ReconcileRefund 沿用 P4
# 只读语义（仅 show 页在线一次，异常降级 nil 不 500）。Manual Review/Retry 动作归 REV-P6-8b。
module PallasTrade
  module Admin
    class RefundsOpsController < ResourceController
      include PallasTrade::Admin::TableConcern

      # GET /admin/refunds
      def index
        super
      end

      # GET /admin/refunds/:id
      def show
        refund = @refund || @object
        # ReconcileRefund 只读（P4 §44/AC-4023）返回 ServiceModule::Result(success → SourceResult)；
        # provider 异常被内部捕获为 NEEDS_ATTENTION，此处兜底 rescue 保证页面永不因对账失败 500
        # （FR-R68A-103 / AC-R68A-06）。降级时 @reconciliation = nil → 视图显示 degraded。
        @reconciliation = begin
          outcome = PallasTrade::Reconciliations::ReconcileRefund.call(refund: refund)
          outcome.success? ? outcome.value : nil
        rescue StandardError
          nil
        end
      end

      # POST /admin/refunds/:id/retry —— REV-P6-8b 人工同键确定性重试（危险资金操作：turbo_confirm）。
      # 资金执行只经 ExecuteJob（同键 → provider 去重），AP-010。服务内 with_lock 守卫并发。
      def retry
        outcome = PallasTrade::Refunds::ManualRetry.call(refund: @refund, actor: audit_actor)
        if outcome.success?
          flash[:success] = PallasTrade.t('admin.orders.refunds_retried')
        else
          flash[:error] = outcome.error&.to_s.presence || PallasTrade.t('admin.orders.refunds_retry_failed')
        end
        redirect_to PallasTrade.admin_refund_path(@refund), status: :see_other
      end

      # POST /admin/refunds/:id/mark_review —— REV-P6-8b 人工标记复核（无资金副作用）
      def mark_review
        outcome = PallasTrade::Refunds::MarkManualReview.call(refund: @refund, actor: audit_actor)
        if outcome.success?
          flash[:success] = PallasTrade.t('admin.orders.refunds_marked_review')
        else
          flash[:error] = outcome.error&.to_s.presence || PallasTrade.t('admin.orders.refunds_mark_review_failed')
        end
        redirect_to PallasTrade.admin_refund_path(@refund), status: :see_other
      end

      private

      def model_class
        PallasTrade::Refund
      end

      # base ResourceController scope 已按 model_class.for_store(current_store) 处理；
      # object_name 让实例变量/URL helper 落在 @refund / admin_refund_path。
      def object_name
        'refund'
      end

      def collection_includes
        [:payment, :reason, :reimbursement]
      end

      def collection_default_sort
        'created_at desc'
      end

      # retry/mark_review 非 CanCan 标准 action → 按 :update 授权（可更新退款的角色/超管可用）
      def authorize_admin
        authorize! :admin, model_class
        effective_action = %i[retry mark_review].include?(action) ? :update : action
        authorize! effective_action, model_class
      end

      def audit_actor
        user = try_pallastrade_current_user
        if user.respond_to?(:id)
          { type: user.class.name, id: user.id, label: user.respond_to?(:email) ? user.email : nil }
        else
          user || 'admin'
        end
      end
    end
  end
end
