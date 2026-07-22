module PallasTrade
  module Api
    module V2
      module Platform
        class RefundSerializer < BaseSerializer
          include ResourceSerializerConcern

          belongs_to :refunder, serializer: PallasTrade.api.platform_admin_user_serializer
          belongs_to :payment, serializer: PallasTrade.api.platform_payment_serializer
          belongs_to :reimbursement, serializer: PallasTrade.api.platform_reimbursement_serializer
          belongs_to :refund_reason, object_method_name: :reason, serializer: PallasTrade.api.platform_refund_reason_serializer
          has_many :log_entries, serializer: PallasTrade.api.platform_log_entry_serializer
        end
      end
    end
  end
end
