# PALLAS-CUSTOM: 多订单合并支付（PRD-20260823-checkout-多订单拆分与合并支付）
#
# Admin read-only view of payment groups (combined payment).
module PallasTrade
  module Admin
    class PaymentGroupsController < ResourceController
      before_action :load_payment_group, only: :show

      # GET /admin/payment_groups
      def index; end

      # GET /admin/payment_groups/:id
      def show; end

      private

      def collection
        current_store.payment_groups.includes(:orders, :payment_sessions)
      end

      def load_payment_group
        @payment_group = collection.find_by_prefix_id!(params[:id])
        authorize! :show, @payment_group
      end

      def model_class
        PallasTrade::PaymentGroup
      end
    end
  end
end
