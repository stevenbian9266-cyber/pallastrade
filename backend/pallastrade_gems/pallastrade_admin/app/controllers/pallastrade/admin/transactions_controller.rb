# frozen_string_literal: true

# PALLAS-CUSTOM: TXN-P2-7 slice2 (REQ-20260905-txn-p2-7-admin-sweeper)
#
# Admin Transactions —— durable CommerceTransaction inspection (Orders → Transactions)。
# index：store 作用域列表 + metrics 汇总卡（recovery_required/manual_review/stuck）；
# show：trace 读模型（CommerceTransaction#trace，只读零副作用）；
# recover：仅 recovery_required/finalizing（Recover::RECOVERABLE_STATES）enqueue
# Transactions::RecoverJob（异步、resolver 判定幂等）；manual_review 永不自动（AC-2014）。
module PallasTrade
  module Admin
    class TransactionsController < ResourceController
      include PallasTrade::Admin::TableConcern

      # D2 人工裁决失败码 → i18n 后缀（未知码回落 generic，不静默）
      REVIEW_ERROR_KEYS = {
        'reason_required' => 'reason_required',
        'transaction_not_reviewable' => 'not_reviewable',
        'no_pending_authorization' => 'no_pending_authorization',
        'capture_failed' => 'capture_failed',
        'capture_not_completed' => 'capture_failed',
        'finalize_failed' => 'finalize_failed',
        'paid_payment_present' => 'paid_payment_present',
        'release_failed' => 'release_failed'
      }.freeze

      # GET /admin/transactions
      def index
        super
        @txn_metrics = txn_metrics
      end

      # POST /admin/transactions/:id/approve_and_capture
      # D2（§78-D2 / §60.2-3）：人工裁决「通过并捕获」——provider 捕获 + 既有 Finalize 闭环。
      def approve_and_capture
        review_transaction('capture')
      end

      # POST /admin/transactions/:id/release_and_cancel
      # D2：人工裁决「拒绝并释放」——不捕获、void 授权、释放库存、取消订单（零退款）。
      def release_and_cancel
        review_transaction('release')
      end

      # POST /admin/transactions/:id/recover
      def recover
        @object = find_object
        unless PallasTrade::Transactions::Recover::RECOVERABLE_STATES.include?(@object.state)
          flash[:error] = PallasTrade.t('admin.orders.transaction_not_recoverable')
          redirect_to PallasTrade.admin_transaction_path(@object), status: :see_other
          return
        end

        PallasTrade::Transactions::RecoverJob.perform_later(@object.prefixed_id)
        flash[:success] = PallasTrade.t('admin.orders.transaction_recovery_queued')
        redirect_to PallasTrade.admin_transaction_path(@object), status: :see_other
      end

      private

      # 人工裁决唯一调用点（Transactions::Review 是纯人工服务；job/sweeper 不得调用）。
      def review_transaction(decision)
        @object = find_object
        result = PallasTrade::Transactions::Review.call(
          transaction: @object,
          decision: decision,
          reason: params[:reason],
          actor: try_pallastrade_current_user || 'admin'
        )
        if result.success?
          flash[:success] = PallasTrade.t("admin.orders.transaction_review_#{decision}_done")
        else
          flash[:error] = review_error_message(result)
        end
        redirect_to PallasTrade.admin_transaction_path(@object), status: :see_other
      end

      # 失败原因直译 i18n（未知码回落通用文案，不静默）
      def review_error_message(result)
        code = result.error.respond_to?(:value) ? result.error.value[:code] : nil
        suffix = REVIEW_ERROR_KEYS.fetch(code.to_s, 'generic')
        PallasTrade.t("admin.orders.transaction_review_error_#{suffix}")
      end

      def model_class
        PallasTrade::CommerceTransaction
      end

      def scope
        current_store.commerce_transactions.order(updated_at: :desc)
      end

      def object_name
        'transaction'
      end

      def find_object
        scope.find_by_prefix_id!(params[:id])
      end

      # 人工裁决/recover 不是 CanCan 标准 action（RolePermission 只到 update/manage）——
      # 控制器级把三者绕按 :update 授权（仅可更新交易的角色/超管可用）。
      def authorize_admin
        authorize! :admin, model_class
        effective_action = %i[recover approve_and_capture release_and_cancel].include?(action) ? :update : action
        authorize! effective_action, model_class
      end

      def txn_metrics
        base = current_store.commerce_transactions
        stuck_before = Time.current - 1.hour
        {
          recovery_required: base.where(state: 'recovery_required').count,
          manual_review: base.where(state: 'manual_review').count,
          stuck: base.where(state: PallasTrade::CommerceTransaction::STUCK_STATES).
                 where(PallasTrade::CommerceTransaction.arel_table[:updated_at].lt(stuck_before)).count
        }
      end
    end
  end
end
