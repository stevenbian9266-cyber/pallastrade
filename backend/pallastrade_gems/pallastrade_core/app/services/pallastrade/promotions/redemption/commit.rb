# frozen_string_literal: true

# PRD-20260910-promotions-promo-batch3a-redemption-ledger (FR-005, FR-014)
#
# reserved → committed（幂等）。已 committed 直接返回；released 行拒绝提交
# （释放后再提交会让 usage_limit 口径与事实脱节）。
# 状态迁移成功时发布 `promotion.redemption_committed` 事件。
module PallasTrade
  module Promotions
    module Redemption
      class Commit
        def self.call(redemption)
          new(redemption).call
        end

        def initialize(redemption)
          @redemption = redemption
        end

        def call
          raise ArgumentError, 'cannot commit a released redemption' if redemption.redemption_released?
          return redemption if redemption.redemption_committed?

          redemption.update!(state: 'committed', committed_at: Time.current)
          publish_event
          redemption
        end

        private

        attr_reader :redemption

        def publish_event
          redemption.publish_event(
            'promotion.redemption_committed',
            'id' => redemption.prefixed_id,
            'order_id' => redemption.order.prefixed_id,
            'promotion_id' => redemption.promotion.prefixed_id,
            'coupon_code' => redemption.coupon_code&.code,
            'amount' => redemption.amount&.to_s,
            'currency' => redemption.currency,
            'committed_at' => redemption.committed_at&.iso8601
          )
        end
      end
    end
  end
end
