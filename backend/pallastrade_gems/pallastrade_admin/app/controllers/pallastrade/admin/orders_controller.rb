module PallasTrade
  module Admin
    class OrdersController < PallasTrade::Admin::ResourceController
      include PallasTrade::Admin::OrderConcern
      include PallasTrade::Admin::OrdersFiltersHelper
      include PallasTrade::Admin::TableConcern

      before_action :initialize_order_events
      before_action :load_order, only: %i[show edit cancel resend destroy split split_create]
      before_action :load_order_items, only: %i[show split]
      before_action :load_user, only: [:index]

      helper_method :manual_split_enabled?

      # GET /admin/orders/new
      def new
        @order = current_store.orders.new
      end

      # POST /admin/orders
      def create
        @order = current_store.orders.new(permitted_resource_params)
        @order.created_by = try_pallastrade_current_user
        if @order.save
          flash[:success] = flash_message_for(@order, :successfully_created)
          redirect_to PallasTrade.edit_admin_order_path(@order)
        else
          render :new, status: :unprocessable_content
        end
      end

      # GET /admin/orders/:id
      def show
        unless @order.completed?
          add_breadcrumb PallasTrade.t(:draft_orders), :admin_checkouts_path
        end

        add_breadcrumb @order.number, PallasTrade.admin_order_path(@order)
      end

      # GET /admin/orders/:id/edit
      def edit
        redirect_to PallasTrade.admin_order_path(@order)
      end

      # GET /admin/orders
      def index; end

      # GET /admin/orders/:id/split
      # P6 (2026-08-28)：手动拆单表单页（flag 灰度）——勾选行项目拆出为一个子订单。
      def split
        unless manual_split_enabled?
          flash[:error] = PallasTrade.t(:authorization_failure)
          return redirect_to(PallasTrade.admin_order_path(@order))
        end

        add_breadcrumb @order.number, PallasTrade.admin_order_path(@order)
        add_breadcrumb PallasTrade.t(:split_order), PallasTrade.split_admin_order_path(@order)
      end

      # POST /admin/orders/:id/split
      # P6 (2026-08-28)：执行手动拆单（复用 P2 Orders::Splitter + P6 ManualSplit 编排）。
      def split_create
        unless manual_split_enabled?
          flash[:error] = PallasTrade.t(:authorization_failure)
          return redirect_to(PallasTrade.admin_order_path(@order))
        end

        result = PallasTrade::Orders::ManualSplit.call(
          order: @order,
          groups: { manual: Array(split_params[:line_item_ids]) }
        )

        if result.success?
          flash[:success] = PallasTrade.t(:order_split_success)
          redirect_to PallasTrade.admin_order_path(@order.reload)
        else
          flash[:error] = result.error.to_s
          redirect_to PallasTrade.split_admin_order_path(@order)
        end
      end

      # PUT /admin/orders/:id/cancel
      def cancel
        result = @order.canceled_by(try_pallastrade_current_user)
        if result.success?
          flash[:success] = PallasTrade.t(:order_canceled)
        else
          flash[:error] = result.error.to_s
        end
        redirect_back fallback_location: PallasTrade.edit_admin_order_url(@order)
      end

      # POST /admin/orders/:id/resend
      def resend
        if @order.completed?
          PallasTrade::Events.publish('order.resend_confirmation_email', { 'id' => @order.id })
          flash[:success] = PallasTrade.t(:order_email_resent)
        else
          flash[:error] = PallasTrade.t(:order_email_resent_error)
        end

        redirect_back fallback_location: PallasTrade.edit_admin_order_url(@order)
      end

      # DELETE /admin/orders/:id
      def destroy
        @order.destroy
        flash[:success] = flash_message_for(@order, :successfully_removed)

        if @order.completed?
          redirect_to PallasTrade.admin_orders_path
        else
          redirect_to PallasTrade.admin_checkouts_path
        end
      end

      private

      def scope
        base_scope = current_store.orders.accessible_by(current_ability, :index)

        if action_name == 'index'
          base_scope.complete
        else
          base_scope
        end.includes(collection_includes)
      end

      def collection_default_sort
        'completed_at desc'
      end

      def collection_includes
        { user: [], payments: [], refunds: [], shipments: :stock_location }
      end

      def order_params
        params[:created_by_id] = try_pallastrade_current_user.try(:id)
        params.permit(:created_by_id, :user_id, :store_id, :channel, tag_list: [])
      end

      # P6：手动拆单 flag——store preference 覆盖 Config，默认关闭
      def manual_split_enabled?
        current_store.preferred_manual_split_enabled.presence || PallasTrade::Config[:admin_manual_split_enabled]
      end

      def split_params
        params.permit(line_item_ids: [])
      end

      def load_order
        @order = scope.includes(:adjustments).find_by_prefix_id!(params[:id])
        authorize! authorization_action, @order
      end

      # P6：手动拆单动作映射到 :update 授权（与 Admin API 一致，兼容 function 权限只授 update 的角色）
      def authorization_action
        %i[split split_create].include?(action_name.to_sym) ? :update : action
      end

      # Used for extensions which need to provide their own custom event links on the order details view.
      def initialize_order_events
        @order_events = %w{approve cancel resume}
      end

      def model_class
        PallasTrade::Order
      end

      # needed to show the delete button in the content header
      def object_url
        PallasTrade.admin_order_path(@order)
      end

      def permitted_resource_params
        params.require(:order).permit(permitted_order_attributes)
      end

      def update_turbo_stream_enabled?
        true
      end
    end
  end
end
