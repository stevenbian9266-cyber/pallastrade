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

      # GET /admin/transactions
      def index
        super
        @txn_metrics = txn_metrics
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

      # recover 不是 CanCan 标准 action（RolePermission 只到 update/manage）——
      # 控制器级把 recover 按 :update 授权（仅可更新交易的角色/超管可用）。
      def authorize_admin
        authorize! :admin, model_class
        effective_action = action == :recover ? :update : action
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
