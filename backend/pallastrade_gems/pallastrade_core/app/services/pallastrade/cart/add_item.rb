module PallasTrade
  module Cart
    class AddItem
      prepend PallasTrade::ServiceModule::Base

      def call(order:, variant:, quantity: nil, metadata: {}, public_metadata: {}, private_metadata: {}, options: {})
        ApplicationRecord.transaction do
          run :add_to_line_item
          run :handle_stock_reservations
          run PallasTrade.cart_recalculate_service
        end
      end

      private

      def add_to_line_item(order:, variant:, quantity: nil, metadata: {}, public_metadata: {}, private_metadata: {}, options: {})
        options ||= {}
        quantity ||= 1

        return failure(variant, "#{variant.name} is not available in #{order.currency}") if variant.amount_in(order.currency).nil?

        line_item = PallasTrade.line_item_by_variant_finder.new.execute(order: order, variant: variant, options: options)

        line_item_created = line_item.nil?
        if line_item.nil?
          opts = ::PallasTrade::PermittedAttributes.line_item_attributes.flatten.each_with_object({}) do |attribute, result|
            result[attribute] = options[attribute]
          end.merge(currency: order.currency).delete_if { |_key, value| value.nil? }

          line_item = order.line_items.new(quantity: quantity,
                                           variant: variant,
                                           options: opts)
        else
          line_item.quantity += quantity.to_i
        end

        line_item.target_shipment = options[:shipment] if options.key? :shipment

        # `metadata` is the primary API param (maps to private_metadata).
        # Legacy `public_metadata`/`private_metadata` params kept for backward compatibility.
        resolved_metadata = metadata.presence || private_metadata
        line_item.metadata = resolved_metadata.to_h if resolved_metadata.present?
        line_item.public_metadata = public_metadata.to_h if public_metadata.present?

        return failure(line_item) unless line_item.save

        line_item.reload.recalculate_price

        ::PallasTrade::TaxRate.adjust(order, [line_item]) if line_item_created
        success(order: order, line_item: line_item, line_item_created: line_item_created, options: options)
      end

      def handle_stock_reservations(order:, line_item:, line_item_created:, options:)
        if order.in_checkout?
          result = PallasTrade::StockReservations::Reserve.call(order: order, validate_only: validate_only_reservations?)
          return failure(line_item, result.error) if result.failure?
        end

        success(order: order, line_item: line_item, line_item_created: line_item_created, options: options)
      end

      # P8：:payment 锁存模式——cart 操作只校验不落 reservation（支付确认后由 Carts::Complete 锁定）
      def validate_only_reservations?
        PallasTrade::Config[:stock_reservation_strategy].to_s == 'payment'
      end
    end
  end
end
