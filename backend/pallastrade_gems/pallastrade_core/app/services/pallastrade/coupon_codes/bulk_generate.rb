module PallasTrade
  module CouponCodes
    class BulkGenerate
      prepend PallasTrade::ServiceModule::Base

      def call(promotion:, quantity: 10)
        coupon_codes = []

        PallasTrade::CouponCode.transaction do
          quantity.times do
            coupon_codes << coupon_attributes(promotion).merge(code: create_code(promotion.code_prefix))
          end
          PallasTrade::CouponCode.insert_all coupon_codes
        end

        success(promotion.reload.coupon_codes)
      end

      private

      def create_code(prefix = nil)
        loop do
          code = "#{prefix}#{SecureRandom.hex(8)}".downcase
          break code unless PallasTrade::CouponCode.exists?(code: code)
        end
      end

      def coupon_attributes(promotion)
        {
          promotion_id: promotion.id,
          created_at: Time.current,
          updated_at: Time.current
        }
      end
    end
  end
end
