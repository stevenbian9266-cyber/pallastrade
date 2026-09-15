module PallasTrade
  module Api
    module V3
      module Admin
        class PaymentMethodSerializer < V3::PaymentMethodSerializer
          typelize active: :boolean,
                   auto_capture: [:boolean, nullable: true],
                   storefront_visible: :boolean,
                   position: :number,
                   optionized: :boolean,
                   options: 'Array<{ kind: string; name: string; frontend_kind: string; ' \
                            'active: boolean; position: number; ' \
                            'rule_set: Record<string, unknown> | null; scope_summary: string }>',
                   metadata: 'Record<string, unknown>',
                   preferences: 'Record<string, unknown>',
                   preference_schema: "Array<{ key: string; type: string; default: unknown }>"

          attributes :metadata, :active, :auto_capture, :storefront_visible, :position,
                     created_at: :iso8601, updated_at: :iso8601

          attribute :preferences, &:serialized_preferences
          attribute :preference_schema, &:serialized_preference_schema

          # PALLAS-CUSTOM: PAY-OPT-1（PRD-20260915 切片2）—— 后台「支付方式」页签的数据源：
          # 该 provider 的生效入口目录（kind / 前台显示名 / 前端形态 / 启停 / 排序）。
          # optionized = 是否已转为选项化（决定「0 入口」语义，供后台提示）。
          attribute :optionized do |payment_method|
            payment_method.optionized?
          end

          attribute :options do |payment_method|
            payment_method.effective_payment_options.each_with_index.map do |option, index|
              {
                kind: option['kind'],
                name: option['display_name'].presence || option['kind'],
                frontend_kind: option['frontend_kind'],
                active: option['active'] != false,
                position: option['position'].to_i.zero? ? index : option['position'].to_i,
                # PALLAS-CUSTOM: D8（PRD-20260915-payments-d8 切片2）—— 入口适用范围（归一后）与后台摘要
                rule_set: PallasTrade::Payments::Availability::RuleSet.normalize(option['rule_set']),
                scope_summary: payment_method.payment_option_scope_summary(option['kind'])
              }
            end
          end
        end
      end
    end
  end
end
