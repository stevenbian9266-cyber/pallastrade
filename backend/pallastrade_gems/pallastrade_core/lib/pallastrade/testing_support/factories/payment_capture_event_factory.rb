FactoryBot.define do
  factory :payment_capture_event, class: PallasTrade::PaymentCaptureEvent do
    payment
    amount { 10.0 }
  end
end
