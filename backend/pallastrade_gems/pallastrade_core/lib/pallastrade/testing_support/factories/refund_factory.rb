FactoryBot.define do
  sequence(:refund_transaction_id) { |n| "fake-refund-transaction-#{n}" }

  factory :refund, class: PallasTrade::Refund do
    amount         { 100.00 }
    transaction_id { generate(:refund_transaction_id) }
    # REV-P6-1：factory 默认代表"历史已成功退款"（succeeded + provider reference）。
    # 需要 in-flight/失败退款测试请显式覆盖 state/transaction_id。
    state          { 'succeeded' }
    succeeded_at   { Time.current }
    association(:payment, state: 'completed')
    association(:reason, factory: :refund_reason)
  end

  factory :default_refund_reason, class: PallasTrade::RefundReason do
    name    { 'Return processing' }
    active  { true }
    mutable { false }
  end

  factory :refund_reason, class: PallasTrade::RefundReason do
    sequence(:name) { |n| "Refund for return #{n}" }
    active  { true }
    mutable { false }
  end
end
