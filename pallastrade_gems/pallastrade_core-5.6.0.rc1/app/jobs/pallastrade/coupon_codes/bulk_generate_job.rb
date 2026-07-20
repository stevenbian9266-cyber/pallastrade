module PallasTrade
  module CouponCodes
    class BulkGenerateJob < PallasTrade::BaseJob
      queue_as PallasTrade.queues.coupon_codes

      def perform(promotion_id, quantity)
        promotion = PallasTrade::Promotion.find(promotion_id)
        return unless promotion.present?

        PallasTrade::CouponCodes::BulkGenerate.call(
          promotion: promotion,
          quantity: quantity
        )
      end
    end
  end
end
