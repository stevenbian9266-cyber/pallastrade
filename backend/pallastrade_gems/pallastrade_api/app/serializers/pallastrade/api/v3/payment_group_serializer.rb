# PALLAS-CUSTOM: 多订单合并支付（PRD-20260823-checkout-多订单拆分与合并支付）
module PallasTrade
  module Api
    module V3
      class PaymentGroupSerializer < BaseSerializer
        typelize status: :string, amount: :string, currency: :string,
                 completed_at: [:string, nullable: true]

        attributes :status, :currency
        attribute :amount do |group|
          group.amount&.to_s
        end
        attribute :completed_at do |group|
          group.completed_at&.iso8601
        end

        many :orders, resource: proc { PallasTrade.api.order_serializer },
             if: proc { expand?('orders') }
        many :payment_sessions, resource: proc { PallasTrade.api.payment_session_serializer },
             if: proc { expand?('payment_sessions') }
      end
    end
  end
end
