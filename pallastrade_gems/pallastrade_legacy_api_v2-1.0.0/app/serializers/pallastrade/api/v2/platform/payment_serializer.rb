module PallasTrade
  module Api
    module V2
      module Platform
        class PaymentSerializer < BaseSerializer
          include ResourceSerializerConcern

          belongs_to :order, serializer: PallasTrade.api.platform_order_serializer
          belongs_to :payment_method, serializer: PallasTrade.api.platform_payment_method_serializer
          belongs_to :source, polymorphic: true, serializer: PallasTrade.api.platform_payment_source_serializer

          has_many :log_entries, serializer: PallasTrade.api.platform_log_entry_serializer
          has_many :state_changes, serializer: PallasTrade.api.platform_state_change_serializer
          has_many :payment_capture_events, object_method_name: :capture_events,
                                            id_method_name: :capture_event_ids,
                                            serializer: PallasTrade.api.platform_payment_capture_event_serializer
          has_many :refunds, serializer: PallasTrade.api.platform_refund_serializer
        end
      end
    end
  end
end
