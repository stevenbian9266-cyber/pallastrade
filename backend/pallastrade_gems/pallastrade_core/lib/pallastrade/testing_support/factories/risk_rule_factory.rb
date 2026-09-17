# frozen_string_literal: true

# PALLAS-CUSTOM: D15 切片2（PRD-20260917-payments-d15b-risk-rules；业务方案 §72.2）——
# 工厂：规则集 + 版本（含便捷 trait：带一条已发布规则的规则集）
FactoryBot.define do
  factory :risk_rule_set, class: 'PallasTrade::RiskRuleSet' do
    sequence(:code) { |n| "rules_#{n}" }
    sequence(:name) { |n| "Risk rules #{n}" }
    status { 'active' }
    canary_percent { 0 }
    store { nil }

    trait :for_store do
      store
    end

    trait :inactive do
      status { 'inactive' }
    end

    # 带一个已发布版本（可直接参与评估）：默认一条「金额 ≥ 100 → review」规则
    trait :with_published_version do
      transient do
        rules do
          [{
            'code' => 'high_amount_review',
            'priority' => 10,
            'action' => 'review',
            'conditions' => { 'amount_gte' => 100 }
          }]
        end
      end

      after(:create) do |rule_set, evaluator|
        version = rule_set.versions.create!(
          version: 1, state: 'published', rules: evaluator.rules, published_at: Time.current
        )
        rule_set.update!(active_version_id: version.id)
      end
    end
  end

  factory :risk_rule_version, class: 'PallasTrade::RiskRuleVersion' do
    rule_set { association(:risk_rule_set) }
    sequence(:version) { |n| n }
    state { 'draft' }
    rules do
      [{ 'code' => 'draft_rule', 'priority' => 100, 'action' => 'review',
         'conditions' => { 'amount_gte' => 100 } }]
    end

    trait :published do
      state { 'published' }
      published_at { Time.current }
    end

    trait :archived do
      state { 'archived' }
      published_at { Time.current }
    end
  end
end
