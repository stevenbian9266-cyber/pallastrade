# frozen_string_literal: true

FactoryBot.define do
  factory :config_item, class: PallasTrade::ConfigItem do
    store
    sequence(:key) { |i| "config.key_#{i}" }
    group { 'general' }
    value_type { 'string' }
    value { 'test-value' }
    description { 'Test config item' }
  end
end
