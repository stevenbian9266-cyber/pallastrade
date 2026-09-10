# frozen_string_literal: true

# PRD-20260910-promotions-promo-batch3c (AC-001/002): 核销台账只读序列化（Admin API）。
module PallasTrade
  module Api
    module V3
      module Admin
        class PromotionRedemptionSerializer < BaseSerializer
          typelize state: :string,
                   promotion_id: [:string, { nullable: true }], order_id: [:string, { nullable: true }],
                   user_id: [:string, { nullable: true }], coupon_code: [:string, { nullable: true }],
                   amount: [:string, { nullable: true }], display_amount: [:string, { nullable: true }],
                   currency: [:string, { nullable: true }],
                   reserved_at: [:string, { nullable: true }], reserved_until: [:string, { nullable: true }],
                   committed_at: [:string, { nullable: true }], released_at: [:string, { nullable: true }],
                   release_reason: [:string, { nullable: true }]

          attributes :state, :currency, :release_reason

          attribute(:promotion_id) { |record| record.promotion&.prefixed_id }
          attribute(:order_id) { |record| record.order&.prefixed_id }
          attribute(:user_id) { |record| record.user&.try(:prefixed_id) }
          attribute(:coupon_code) { |record| record.coupon_code&.code }
          attribute(:amount) { |record| record.amount&.to_s }
          attribute(:display_amount) do |record|
            next nil if record.amount.nil?

            PallasTrade::Money.new(record.amount, currency: record.currency.presence || 'USD').to_s
          end
          attribute(:reserved_at) { |record| record.reserved_at&.iso8601 }
          attribute(:reserved_until) { |record| record.reserved_until&.iso8601 }
          attribute(:committed_at) { |record| record.committed_at&.iso8601 }
          attribute(:released_at) { |record| record.released_at&.iso8601 }

          attributes created_at: :iso8601, updated_at: :iso8601
        end
      end
    end
  end
end
