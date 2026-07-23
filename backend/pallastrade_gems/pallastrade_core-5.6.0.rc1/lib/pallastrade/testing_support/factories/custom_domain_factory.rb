if defined?(PallasTrade::CustomDomain)
  FactoryBot.define do
    factory :custom_domain, class: PallasTrade::CustomDomain do
      url { FFaker::Internet.domain_name }
      association :store, factory: :store
      default { true }
    end
  end
end
