# frozen_string_literal: true

# # PRD-20260813-admin-移除管理后台-integrations-菜单及相关逻辑
# # AI 模块解耦：独立 Provider 工厂（替代已删除的 :integration 工厂）
FactoryBot.define do
  factory :ai_provider, class: PallasTrade::AI::Provider do
    type { 'PallasTrade::AI::Provider' }
    store { PallasTrade::Store.default }
    active { false }
  end

  factory :ai_provider_deepseek, class: PallasTrade::AI::Provider::DeepSeek do
    type { 'PallasTrade::AI::Provider::DeepSeek' }
    store { PallasTrade::Store.default }
    active { false }
  end

  factory :ai_provider_openai, class: PallasTrade::AI::Provider::OpenAI do
    type { 'PallasTrade::AI::Provider::OpenAI' }
    store { PallasTrade::Store.default }
    active { false }
  end
end
