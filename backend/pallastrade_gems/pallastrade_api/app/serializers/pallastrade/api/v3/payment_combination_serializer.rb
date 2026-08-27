module PallasTrade
  module Api
    module V3
      # Store/Admin Order Combination Serializer (P5, 2026-08-27)
      # 合并支付组合：状态/金额/币种 + 成员订单 + 支付会话（供收银台跳转）
      class PaymentCombinationSerializer < BaseSerializer
        typelize status: :string, amount: :string, currency: :string,
                 expires_at: [:string, nullable: true], completed_at: [:string, nullable: true]

        attributes :status, :currency,
                   expires_at: :iso8601, completed_at: :iso8601

        attribute :amount do |combination|
          combination.amount.to_s
        end

        # 成员订单（expand=orders 时展开）
        many :orders, resource: proc { PallasTrade.api.order_serializer },
                      if: proc { expand?('orders') }

        # 支付会话（挂 primary order，含 client_secret 供 Stripe Elements 使用）
        one :payment_session, resource: proc { PallasTrade.api.payment_session_serializer },
                              if: proc { |combination| combination.payment_session.present? }
      end
    end
  end
end
