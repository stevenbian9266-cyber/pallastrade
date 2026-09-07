module PallasTrade
  module Api
    module V3
      module Admin
        class RefundSerializer < V3::RefundSerializer
          typelize payment_id: [:string, nullable: true],
                   refund_reason_id: [:string, nullable: true],
                   reimbursement_id: [:string, nullable: true],
                   state: :string,
                   last_error_message: [:string, nullable: true],
                   metadata: 'Record<string, unknown>'

          # REV-P6-1：admin 展示退款生命周期与失败信息（FR-R61-701/REV-P6-8 底座）
          attributes :metadata,
                     :state,
                     :last_error_message,
                     :requested_at, :processing_at, :succeeded_at, :failed_at, :ambiguous_at,
                     created_at: :iso8601, updated_at: :iso8601

          # REV-P6-3 (FR-R63-102)：组合退款冻结 ownership —— payment_split_id / target_order_id
          attribute :payment_split_id do |refund|
            refund.payment_split&.prefixed_id
          end

          attribute :target_order_id do |refund|
            refund.target_order&.prefixed_id
          end

          attribute :requested_at do |refund|
            refund.requested_at&.iso8601
          end

          attribute :processing_at do |refund|
            refund.processing_at&.iso8601
          end

          attribute :succeeded_at do |refund|
            refund.succeeded_at&.iso8601
          end

          attribute :failed_at do |refund|
            refund.failed_at&.iso8601
          end

          attribute :ambiguous_at do |refund|
            refund.ambiguous_at&.iso8601
          end

          one :payment,
              resource: proc { PallasTrade.api.admin_payment_serializer },
              if: proc { expand?('payment') }

          one :reimbursement,
              resource: proc { PallasTrade.api.admin_reimbursement_serializer },
              if: proc { expand?('reimbursement') }
        end
      end
    end
  end
end
