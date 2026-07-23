FactoryBot.define do
  factory :promotion_rule, class: PallasTrade::PromotionRule do
    association :promotion
  end

  factory :promotion_rule_user, class: PallasTrade::Promotion::Rules::User do
    association :promotion
  end

  factory :promotion_rule_product, class: PallasTrade::Promotion::Rules::Product do
    association :promotion
  end

  factory :promotion_rule_taxon, class: PallasTrade::Promotion::Rules::Taxon do
    association :promotion
  end

  factory :promotion_rule_option_value, class: PallasTrade::Promotion::Rules::OptionValue do
    association :promotion
  end

  factory :promotion_rule_customer_group, class: PallasTrade::Promotion::Rules::CustomerGroup do
    association :promotion

    after(:build) do |rule, evaluator|
      rule.preferred_customer_group_ids = evaluator.customer_group_ids if evaluator.respond_to?(:customer_group_ids)
    end

    transient do
      customer_group_ids { [] }
    end
  end

  factory :promotion_rule_channel, class: PallasTrade::Promotion::Rules::Channel do
    association :promotion

    after(:build) do |rule, evaluator|
      rule.preferred_channel_ids = evaluator.channel_ids if evaluator.respond_to?(:channel_ids)
    end

    transient do
      channel_ids { [] }
    end
  end

  factory :promotion_rule_market, class: PallasTrade::Promotion::Rules::Market do
    association :promotion

    after(:build) do |rule, evaluator|
      rule.preferred_market_ids = evaluator.market_ids if evaluator.respond_to?(:market_ids)
    end

    transient do
      market_ids { [] }
    end
  end
end
