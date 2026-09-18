# frozen_string_literal: true

require 'rails_helper'

# PRD-20260918-admin-ai-output-validation AC-009 —— 适配器的错误码映射。
#
# 输出不合格是**确定性**失败：模型答了，只是没按约定答。它既不是供应商故障，
# 重试同一提示也不会变好。此前它落进 `normalize_error` 的 `else` 分支，
# 被报成 `ai_provider_unavailable` —— 把排查方向直接带偏。
RSpec.describe 'AI provider adapters normalize_error' do
  let(:adapters) do
    [
      PallasTrade::AI::Providers::DeepSeek.new,
      PallasTrade::AI::Providers::OpenAI.new
    ]
  end

  it 'maps an output validation error to ai_output_invalid on every adapter (AC-009)' do
    error = PallasTrade::AI::Errors::OutputValidationError.new(
      'catalog.product_description: output does not match the schema'
    )

    adapters.each do |adapter|
      normalized = adapter.normalize_error(error)

      expect(normalized[:code]).to eq('ai_output_invalid'),
                                   "#{adapter.class} 把输出问题报成了 #{normalized[:code]}"
      expect(normalized[:retryable]).to be false
      expect(normalized[:message]).to include('catalog.product_description')
    end
  end

  it 'keeps provider failures on the provider code (AC-009)' do
    adapters.each do |adapter|
      normalized = adapter.normalize_error(Faraday::TimeoutError.new('timed out'))

      expect(normalized[:code]).to eq('ai_provider_unavailable')
      expect(normalized[:retryable]).to be true
    end
  end
end
