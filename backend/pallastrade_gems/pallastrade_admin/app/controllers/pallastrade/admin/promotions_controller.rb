module PallasTrade
  module Admin
    class PromotionsController < ResourceController
      # 面包屑由导航自动推导（P3）：Promotions；对象页追加促销名
      before_action :add_breadcrumb_for_promotion
      before_action :load_form_data, except: :index

      # GET /admin/promotions/select_options
      def select_options
        q = params[:q]
        ransack_params = q.is_a?(String) ? { name_i_cont: q } : q
        promotions = current_store.promotions.applied.accessible_by(current_ability).ransack(ransack_params).result.order(:name).limit(25)

        render json: promotions.pluck(:id, :name).map { |id, name| { id: id, name: name } }
      end

      # POST /admin/promotions/:id/clone
      def clone
        promotion = current_store.promotions.find_by_prefix_id!(params[:id])
        duplicator = PallasTrade::PromotionHandler::PromotionDuplicator.new(promotion)

        @new_promo = duplicator.duplicate

        if @new_promo.errors.empty?
          flash[:success] = PallasTrade.t('promotion_cloned')
          redirect_to PallasTrade.admin_promotion_path(@new_promo)
        else
          flash[:error] = PallasTrade.t('promotion_not_cloned', error: @new_promo.errors.full_messages.to_sentence)
          redirect_to PallasTrade.admin_promotions_path
        end
      end

      private

      # 对象页面包屑：Promotions > 促销名（P3，原 PromotionsBreadcrumbConcern）
      def add_breadcrumb_for_promotion
        return unless @promotion.present?
        return if @promotion.new_record?

        add_breadcrumb @promotion.name, PallasTrade.admin_promotion_path(@promotion)
      end

      protected

      def location_after_save
        PallasTrade.admin_promotion_path(@promotion)
      end

      def load_form_data
        @promotion_rules = PallasTrade.promotions.rules
        @rule_types = @promotion_rules.map do |promotion_rule|
          [PallasTrade.t("promotion_rule_types.#{promotion_rule.to_s.demodulize.underscore}.name"), promotion_rule.to_s]
        end
      end

      def collection_includes
        [:promotion_actions]
      end

      def permitted_resource_params
        attrs = params.require(:promotion).permit(permitted_promotion_attributes)
        parse_datetime_in_store_timezone(attrs, :starts_at, :expires_at)
        attrs
      end
    end
  end
end
