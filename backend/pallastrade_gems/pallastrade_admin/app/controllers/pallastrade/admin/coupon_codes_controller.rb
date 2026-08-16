module PallasTrade
  module Admin
    class CouponCodesController < ResourceController
      belongs_to 'pallastrade/promotion', find_by: :prefix_id

      # 面包屑由导航自动推导（P3）：Promotions

      def index
        params[:q] ||= {}
        params[:q][:promotion_id_eq] ||= parent.id
        super
      end
    end
  end
end
