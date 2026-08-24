module PallasTrade
  module Admin
    module OrderConcern
      extend ActiveSupport::Concern

      included do
        rescue_from ActiveRecord::RecordNotFound, with: :resource_not_found
      end

      protected

      def load_order
        @order = current_store.orders.find_by_prefix_id!(params[:order_id])
        authorize! action, @order
        @order
      end

      def load_order_items
        @line_items = @order.line_items.includes(variant: [:product, :option_values])
        @shipments = @order.shipments.includes(:inventory_units, :selected_shipping_rate,
                                               shipping_rates: [:shipping_method, :tax_rate]).order(:created_at)
        @payments = @order.payments.includes(:payment_method, :source).order(:created_at)
        @refunds = @order.refunds

        # PALLAS-CUSTOM: 父订单售后汇总（PRD-20260824 FR-036）— 含其下全部子订单的售后记录
        @return_authorizations = PallasTrade::ReturnAuthorization.where(order_id: [@order.id] + @order.children.ids).includes(:return_items, :order)
        @customer_returns = @order.customer_returns.distinct

        @order_promotions = @order.order_promotions.includes(promotion: :promotion_actions)
        @tax_adjustments = @order.all_adjustments.tax.includes(:source, :adjustable)

        # PALLAS-CUSTOM: 子订单发货进度（PRD-20260824 FR-032）— 父订单视图展示各子订单发货状态
        @child_orders = @order.children.includes(:shipments).order(:created_at)
      end

      def resource_not_found
        flash[:error] = flash_message_for(PallasTrade::Order.new, :not_found)
        redirect_to PallasTrade.admin_orders_path
      end
    end
  end
end
