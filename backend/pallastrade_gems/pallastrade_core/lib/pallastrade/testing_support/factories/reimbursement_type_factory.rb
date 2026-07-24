FactoryBot.define do
  factory :reimbursement_type, class: PallasTrade::ReimbursementType do
    sequence(:name) { |n| "Reimbursement Type #{n}" }
    active          { true }
    mutable         { true }
  end
end
