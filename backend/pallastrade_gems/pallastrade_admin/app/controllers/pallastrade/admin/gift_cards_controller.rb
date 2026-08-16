module PallasTrade
  module Admin
    class GiftCardsController < ResourceController
      prepend_before_action :set_user_id_filter, only: :index
      prepend_before_action :load_user
      before_action :add_breadcrumbs
      before_action :load_orders, only: :show

      private

      def permitted_resource_params
        @permitted_resource_params ||= begin
          params_hash = params.require(:gift_card).permit(permitted_gift_card_attributes)

          if @user.present?
            params_hash.merge(user_id: @user.id)
          else
            params_hash
          end
        end
      end

      def collection_includes
        [:user, :created_by]
      end

      def set_user_id_filter
        return if @user.blank?

        params[:q] ||= {}
        params[:q][:user_id_eq] = @user.id
      end

      def location_after_destroy
        if @user.present?
          PallasTrade.admin_user_path(@user)
        else
          PallasTrade.admin_gift_cards_path
        end
      end

      def location_after_save
        PallasTrade.admin_gift_card_path(@object)
      end

      def load_user
        @user = PallasTrade.user_class.find_by_prefix_id(params[:user_id]) if params[:user_id].present?
      end

      def add_breadcrumbs
        # 默认面包屑（Promotions > Gift Cards）由导航自动推导（P3）；
        # 仅用户上下文需要追加：Customers > 用户名
        return unless @user.present?

        @breadcrumb_icon = 'users'
        add_breadcrumb PallasTrade.t(:customers), :admin_users_path
        add_breadcrumb @user.name, PallasTrade.admin_user_path(@user)
      end

      def load_orders
        @orders = @object.orders.includes(:user).order(created_at: :desc)
      end
    end
  end
end
