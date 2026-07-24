module PallasTrade
  module Admin
    module PromotionsHelper
      def promotion_status(promotion)
        if promotion.active?
          PallasTrade.t(:active)
        elsif promotion.expired?
          PallasTrade.t(:expired)
        elsif promotion.inactive?
          PallasTrade.t(:inactive)
        end
      end
    end
  end
end
