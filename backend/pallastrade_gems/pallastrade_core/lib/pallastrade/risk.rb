# frozen_string_literal: true

# PALLAS-CUSTOM: 风控规则引擎（PRD-20260828 P8，flag 灰度）
#
# 下单前置校验的可扩展规则引擎：规则类实现 #call(order:, user:, store:)，
# 返回 nil（未命中）或 { code:, message: }（命中）。注册方式：
#   PallasTrade::Risk.rules << MyRule
# 内置规则：BlacklistRule（用户黑名单）、OrderFrequencyRule（防刷单）。
# 由 PallasTrade::Checkout::Preflight 在下单前置评估（flag 控制）。
module PallasTrade
  module Risk
    mattr_accessor :rules
    self.rules = []

    class << self
      # @param order [PallasTrade::Order]
      # @param user [Object, nil] 缺省取 order.user
      # @param store [PallasTrade::Store, nil] 缺省取 order.store
      # @return [Hash{Symbol => String}, nil] 首个命中的 { code:, message: } 或 nil
      def evaluate(order:, user: nil, store: nil)
        user ||= order&.user
        store ||= order&.store
        rules.each do |rule_class|
          result = rule_class.new.call(order: order, user: user, store: store)
          return result if result.is_a?(Hash) && result[:code].present?
        end
        nil
      end
    end
  end
end
