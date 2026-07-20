module PallasTrade
  class PaymentCaptureEvent < PallasTrade.base_class
    has_prefix_id :pce

    belongs_to :payment, class_name: 'PallasTrade::Payment'

    def display_amount
      PallasTrade::Money.new(amount, currency: payment.currency)
    end
  end
end
