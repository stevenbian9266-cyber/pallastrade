FactoryBot.define do
  # F-5 (PRD-20260916-catalog-batch-f5-helpful-vote). `store` follows the review
  # so a vote can never be attributed to a different store than its review.
  factory :review_vote, class: PallasTrade::ReviewVote do
    association :review, factory: :review
    association :user, factory: :user
    store { review.store }
  end
end
