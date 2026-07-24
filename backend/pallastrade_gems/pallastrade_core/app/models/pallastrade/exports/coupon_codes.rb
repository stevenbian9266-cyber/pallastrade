module PallasTrade
  module Exports
    class CouponCodes < PallasTrade::Export
      def self.required_scope
        :promotions
      end

      def csv_headers
        PallasTrade::CSV::CouponCodePresenter::HEADERS
      end

      def scope_includes
        [:promotion, :order]
      end

      def scope
        model_class.where(promotion: store.promotions).accessible_by(current_ability, :show)
      end
    end
  end
end
