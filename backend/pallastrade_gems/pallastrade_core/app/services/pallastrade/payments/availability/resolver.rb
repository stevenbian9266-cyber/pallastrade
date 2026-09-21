# frozen_string_literal: true

# PALLAS-CUSTOM: D8（PRD-20260915-payments-d8 切片1）—— 入口可用性**单一求值点**。
#
# 前台/后台列表与 `PaymentSessions::Start` 必须使用同一份求值（业务方案 §66.5 同源硬约束，
# 修「选得上、付不了」）：
#
#   Resolver.available_options(order:, payment_method:)   # 该 provider 下通过规则的入口
#   Resolver.provider_available?(order:, payment_method:) # 任一入口可用
#   Resolver.providers(order:, scope:)                    # 入口级过滤后的 provider 列表
#   Resolver.evaluate(order:, payment_method:)            # 逐入口判定 + 原因（调试/测试）
#
module PallasTrade
  module Payments
    module Availability
      class Resolver
        class << self
          # @return [Array<Hash>] 通过范围规则的入口（保持 effective_payment_options 的既有顺序）
          def available_options(order:, payment_method:, context: nil)
            ctx = context || Context.for_order(order)

            payment_method.effective_payment_options.select do |option|
              option_allowed?(payment_method, option, ctx)
            end
          end

          def available_option_kinds(order:, payment_method:, context: nil)
            available_options(order: order, payment_method: payment_method, context: context).
              map { |option| option['kind'] }
          end

          def provider_available?(order:, payment_method:, context: nil)
            available_options(order: order, payment_method: payment_method, context: context).any?
          end

          def option_available?(order:, payment_method:, kind:, context: nil)
            kind = kind.to_s
            available_options(order: order, payment_method: payment_method, context: context).
              any? { |option| option['kind'] == kind }
          end

          # provider 列表级过滤（Order 投影使用；scope: :frontend / :back_end）
          def providers(order:, scope:, context: nil)
            ctx = context || Context.for_order(order)
            relation = order.store.payment_methods.active
            relation = scope == :back_end ? relation.available_on_back_end : relation.available_on_front_end
            # D9（PRD-20260915-payments-d9 切片1）：test 环境 provider 不进前台（业务方案 §68.1）；
            # 后台录单（back_end）不受限，便于沙箱/培训。
            relation = relation.where.not(environment: 'test') unless scope == :back_end

            relation.select { |payment_method| provider_available?(order: order, payment_method: payment_method, context: ctx) }
          end

          # 逐入口判定 + 原因（后台调试/规格断言）
          # @return [Array<Hash>] [{ 'kind' =>, 'allowed' =>, 'reasons' => [...] }]
          def evaluate(order:, payment_method:, context: nil)
            ctx = context || Context.for_order(order)

            payment_method.effective_payment_options.map do |option|
              reasons = []
              # D15 切片3：认证需求导致的排除也作为独立 reason 暴露（“为什么这个入口没出现”可读）
              if authentication_rejects?(payment_method, option, ctx)
                reasons << { 'dimension' => 'three_d_secure', 'reason' => 'authentication_required' }
              end

              {
                'kind' => option['kind'],
                'allowed' => !capability_rejects?(payment_method, option, ctx) &&
                             !authentication_rejects?(payment_method, option, ctx),
                'reasons' => reasons
              }
            end
          end

          private

          def option_allowed?(payment_method, option, context)

            # D15 切片3（PRD-20260917-checkout-d15-切片3）：本单要求 3DS/SCA 时，
            # 只有**声明可强制认证**的入口可用（钱包/一键等拿不到强认证的入口直接消失）。
            return false if authentication_rejects?(payment_method, option, context)


            !capability_rejects?(payment_method, option, context)
          end

          # D15 切片3：认证闸门。要求认证时，仅 `three_d_secure: 'supported'` 的入口可用；
          # 未声明能力的入口按**不支持**处理（不猜）。要求为假时零影响（零回归）。
          def authentication_rejects?(payment_method, option, context)
            return false unless context.respond_to?(:authentication_required) && context.authentication_required

            !PallasTrade::Payments::ThreeDSecure::ProviderHint.option_supported?(payment_method, option['kind'])
          end

          # FR-010：能力目录（Capability）可声明 currencies / countries → 商家只能收窄（§0.1-9）。
          # 未声明 = 不限制；上下文未知时不收窄（把可用性判定留给规则层，避免误隐藏）。
          def capability_rejects?(payment_method, option, context)
            capability = payment_method.payment_option_catalog.find { |entry| entry['kind'] == option['kind'] }
            return false if capability.blank?

            currencies = Array(capability['currencies']).map { |value| value.to_s.upcase }
            countries = Array(capability['countries']).map { |value| value.to_s.upcase }

            (context.currency.present? && currencies.any? && !currencies.include?(context.currency)) ||
              (context.country_iso.present? && countries.any? && !countries.include?(context.country_iso))
          end
        end
      end
    end
  end
end
