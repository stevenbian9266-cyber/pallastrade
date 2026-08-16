module PallasTrade
  module Admin
    class GiftCardBatchesController < ResourceController
      # 面包屑由导航自动推导（P3）：Promotions → Gift Cards

      private

      def location_after_save
        PallasTrade.admin_gift_cards_path(q: { batch_prefix_eq: @object.prefix })
      end

      def collection_url
        PallasTrade.admin_gift_cards_path
      end

      def permitted_resource_params
        params.require(:gift_card_batch).permit(permitted_gift_card_batch_attributes)
      end
    end
  end
end
