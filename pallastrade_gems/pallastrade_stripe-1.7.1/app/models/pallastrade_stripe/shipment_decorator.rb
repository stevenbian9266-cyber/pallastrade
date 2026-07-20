module PallasTradeStripe
  module ShipmentDecorator
    def self.prepended(base)
      base.state_machine.after_transition to: :shipped, do: :create_tax_transaction_async
    end

    private

    def create_tax_transaction_async
      return unless order.fully_shipped?
      return if order.stripe_tax_calculation_id.blank?

      payment_intent = order.payment_intents.last
      return if payment_intent.blank?

      PallasTradeStripe::CreateTaxTransactionJob.perform_later(order.store_id, payment_intent.stripe_id, order.stripe_tax_calculation_id)
    end
  end
end

PallasTrade::Shipment.prepend(PallasTradeStripe::ShipmentDecorator) if PallasTrade::Shipment.included_modules.exclude?(PallasTradeStripe::ShipmentDecorator)
