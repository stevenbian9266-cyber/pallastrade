module PallasTrade
  module CouponCodes
    class BulkGenerate
      prepend PallasTrade::ServiceModule::Base

      def call(promotion:, quantity: 10)
        coupon_codes = []

        PallasTrade::CouponCode.transaction do
          quantity.times do
            coupon_codes << coupon_attributes(promotion).merge(code: create_code(promotion.code_prefix, promotion))
          end
          PallasTrade::CouponCode.insert_all coupon_codes
        end

        success(promotion.reload.coupon_codes)
      end

      private

      # PRD-20260909-promo-batch1 AC-P3-4: avoid codes that collide either with
      # an existing generated code or with a single-code promotion in the same
      # store (they share the customer input space).
      def create_code(prefix = nil, promotion = nil)
        loop do
          code = "#{prefix}#{SecureRandom.hex(8)}".downcase
          break code unless code_taken?(code, promotion)
        end
      end

      def code_taken?(code, promotion)
        return true if PallasTrade::CouponCode.exists?(code: code)
        return false unless promotion && promotion.store_id.present?

        PallasTrade::Promotion.
          where(store_id: promotion.store_id, kind: :coupon_code).
          where.not(multi_codes: true).
          where('lower(btrim(code)) = ?', code).
          exists?
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
