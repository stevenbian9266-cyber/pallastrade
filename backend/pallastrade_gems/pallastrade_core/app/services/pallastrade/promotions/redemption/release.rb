# frozen_string_literal: true

# PRD-20260910-promotions-promo-batch3a-redemption-ledger (FR-006, FR-014)
#
# reserved|committed → released（幂等）。释放时回退一次性码（model#release!），
# 并发布 `promotion.redemption_released` 事件。
module PallasTrade
  module Promotions
    module Redemption
      class Release
        DEFAULT_REASON = 'manual'

        def self.call(redemption, reason: DEFAULT_REASON)
          new(redemption, reason: reason).call
        end

        def initialize(redemption, reason: DEFAULT_REASON)
          @redemption = redemption
          @reason = reason.to_s.presence || DEFAULT_REASON
        end

        def call
          return redemption if redemption.redemption_released?

          redemption.release!(reason: reason)
          publish_event
          redemption
        end

        private

        attr_reader :redemption, :reason

        def publish_event
          redemption.publish_event(
            'promotion.redemption_released',
            'id' => redemption.prefixed_id,
            'order_id' => redemption.order.prefixed_id,
            'promotion_id' => redemption.promotion.prefixed_id,
            'coupon_code' => redemption.coupon_code&.code,
            'release_reason' => redemption.release_reason,
            'released_at' => redemption.released_at&.iso8601
          )
        end
      end
    end
  end
end
