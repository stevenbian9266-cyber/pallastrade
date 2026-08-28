# frozen_string_literal: true

# PALLAS-CUSTOM: 黑名单规则（PRD-20260828 P8）——users.blacklisted_at 命中即拒绝下单。
module PallasTrade
  module Risk
    class BlacklistRule
      def call(order:, user:, store:)
        return nil if user.blank? || user.blacklisted_at.blank?

        { code: 'user_blacklisted', message: 'Account is blacklisted' }
      end
    end
  end
end
