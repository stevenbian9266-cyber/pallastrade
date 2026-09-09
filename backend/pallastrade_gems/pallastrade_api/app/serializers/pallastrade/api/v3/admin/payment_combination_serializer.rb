module PallasTrade
  module Api
    module V3
      module Admin
        # REV-P6-8l（FR-R68L-101/102；8g 数据面 API 化）
        # Admin PaymentCombination 只读 serializer：
        #   - index 轻量：status/amount/currency/member_count/refunded_total/created_at
        #   - show 经 expand 展开：members（payment_splits：成员订单 + captured/refunded/credit_allowed）、
        #     payments（组合 Payment）、transaction（CommerceTransaction 摘要）
        # 全部金额为 decimal string（v3 惯例）；prefixed ids；无整型 PK。
        class PaymentCombinationSerializer < BaseSerializer
          typelize status: :string, amount: :string, currency: :string,
                   member_count: :number, refunded_total: :string,
                   created_at: [:string, nullable: true]

          attributes :status, :currency, created_at: :iso8601

          attribute :member_count do |combination|
            combination.payment_splits.size
          end

          attribute :amount do |combination|
            combination.amount.to_s
          end

          # 已退合计 = 各成员 split refunded_amount 之和
          attribute :refunded_total do |combination|
            combination.payment_splits.sum { |split| split.refunded_amount.to_f }.to_s
          end

          # expand=members：逐成员 split（8g show 数据面）
          attribute :members, if: proc { expand?('members') } do |combination|
            combination.payment_splits.map do |split|
              {
                id: split.prefixed_id,
                order_id: split.order&.prefixed_id,
                order_number: split.order&.number,
                currency: combination.currency,
                captured_amount: split.captured_amount.to_s,
                refunded_amount: split.refunded_amount.to_s,
                credit_allowed: split.credit_allowed.to_s
              }
            end
          end

          # expand=payments：组合 Payment（order_id=nil 亦可达）
          attribute :payments, if: proc { expand?('payments') } do |combination|
            combination.payments.map do |payment|
              {
                id: payment.prefixed_id,
                state: payment.state,
                amount: payment.amount.to_s,
                currency: payment.currency,
                credit_allowed: payment.respond_to?(:credit_allowed) ? payment.credit_allowed.to_s : nil,
                payment_method: payment.payment_method&.name
              }
            end
          end

          # expand=transaction：关联 CommerceTransaction 摘要
          attribute :transaction, if: proc { expand?('transaction') } do |combination|
            txn = combination.commerce_transaction
            next nil if txn.nil?

            {
              id: txn.prefixed_id,
              state: txn.state,
              amount: txn.amount.to_s,
              currency: txn.currency
            }
          end
        end
      end
    end
  end
end
