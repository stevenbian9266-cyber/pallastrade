# frozen_string_literal: true

module PallasTrade
  module Payments
    # P0-6 (PRD FR-062): Canonical Failure Mapping —— 只做「映射层」，不改状态机。
    #
    # 语义：对外/前端只暴露 canonical code + safe message；provider 原始错误码与
    # 原始 message 保留在服务端日志/审计（Trace/FR-063），不落到前端。
    #
    # canonical（内部语义）:
    #   :declined / :insufficient_funds / :expired_card / :invalid_card /
    #   :authentication_failed / :processing_error / :provider_error
    module ErrorCodes
      CANONICAL = %i[
        declined insufficient_funds expired_card invalid_card
        authentication_failed processing_error provider_error
      ].freeze

      SAFE_MESSAGES = {
        declined: 'Payment was declined.',
        insufficient_funds: 'Insufficient funds.',
        expired_card: 'Card has expired.',
        invalid_card: 'Card is invalid.',
        authentication_failed: 'Authentication failed.',
        processing_error: 'Payment could not be processed.',
        provider_error: 'Payment provider error.'
      }.freeze

      module_function

      # 从 provider 原始信息映射 canonical code。
      # @param provider_code [String, nil] provider decline/error code（如 Stripe 'card_declined'）
      # @param message [String, nil] 原始 message（仅参与启发式匹配）
      # @return [Symbol] canonical（未知一律 :provider_error，绝不外泄原始细节）
      def map(provider_code: nil, message: nil)
        haystack = [provider_code, message].compact.join(' ').downcase

        case haystack
        when /insufficient_funds|insufficient funds/
          :insufficient_funds
        when /expired_card|card.*expired/
          :expired_card
        when /invalid_card|invalid card|card.*not.*support/
          :invalid_card
        when /authentication_required|authentication failed|3ds|requires_action/
          :authentication_failed
        when /processing_error|try again later/
          :processing_error
        when /card_declined|declined|do_not_honor|generic_decline/
          :declined
        else
          :provider_error
        end
      end

      # 前端安全文案（不含 provider 细节）。
      def safe_message(code)
        SAFE_MESSAGES.fetch(code, SAFE_MESSAGES[:provider_error])
      end
    end
  end
end
