# frozen_string_literal: true

require 'rails_helper'

# PRD-20260918-api-deepseek-structured-output — DeepSeek model catalogue.
#
# DeepSeek's own `GET /models` returns `deepseek-flash` and `deepseek-v4-pro`;
# the catalogue shipped `deepseek-v4-flash`, which does not exist, so selecting
# it always produced a 400 "model not found".
#
# Two places declare these models. `Catalogs::DeepSeek::MODELS` is the readable
# catalogue, but provisioning actually reads the provider registry's inline
# `recommended_models` (`ProvisionModels` uses `entry.recommended_models`).
# Both are asserted here so the next edit cannot silently fix only the copy that
# nothing reads.
RSpec.describe PallasTrade::AI::Catalogs::DeepSeek do
  let(:expected_model_ids) { %w[deepseek-flash deepseek-v4-pro] }

  before do
    Rails.application.reloader.reload! unless PallasTrade::AI.providers.registered?(:deepseek)
  end

  describe 'MODELS' do
    it 'uses the model ids DeepSeek actually serves (# PRD-20260918-api-deepseek-structured-output AC-010)' do
      ids = described_class::MODELS.map { |model| model[:provider_model_id] }

      expect(ids).to contain_exactly(*expected_model_ids)
    end
  end

  describe 'provider registry recommended models' do
    it 'stays in sync with the catalogue provisioning reads (# PRD-20260918-api-deepseek-structured-output AC-010)' do
      entry = PallasTrade::AI.providers[:deepseek]

      expect(entry).not_to be_nil
      ids = entry.recommended_models.map { |model| model[:provider_model_id] }
      expect(ids).to contain_exactly(*expected_model_ids)
    end
  end
end
