require 'rails_helper'

RSpec.describe PallasTrade::AI::ProvisionProviders, type: :service do
  let(:store) { create(:store) }
  let(:other_store) { create(:store) }

  before do
    # Ensure the provider registry (DeepSeek/OpenAI) is loaded
    Rails.application.reloader.reload! unless PallasTrade::AI.providers.registered?(:deepseek)
  end

  describe '.call' do
    it 'creates one store-scoped Provider per registered provider' do
      expect {
        described_class.call(store: store)
      }.to change(PallasTrade::AI::Provider, :count).by(PallasTrade::AI.providers.all.size)

      PallasTrade::AI.providers.all.each do |entry|
        provider = store.ai_providers.find_by(type: entry.provider_class)
        expect(provider).to be_present
        expect(provider.name).to eq(entry.display_name)
      end
    end

    it 'creates providers as inactive by default' do
      described_class.call(store: store)

      store.ai_providers.where(type: PallasTrade::AI.providers.all.map(&:provider_class)).each do |provider|
        expect(provider.active).to be false
      end
    end

    it 'is scoped to the given store' do
      described_class.call(store: store)

      expect(other_store.ai_providers.where(type: PallasTrade::AI.providers.all.map(&:provider_class)).count).to eq(0)

      expect {
        described_class.call(store: other_store)
      }.to change(other_store.ai_providers, :count).by(PallasTrade::AI.providers.all.size)
    end

    context 'idempotency' do
      it 'does not duplicate providers on repeated calls' do
        described_class.call(store: store)

        expect {
          described_class.call(store: store)
        }.not_to change(store.ai_providers, :count)
      end

      it 'does not overwrite an existing provider (active preserved)' do
        described_class.call(store: store)

        existing = store.ai_providers.find_by(type: 'PallasTrade::AI::Provider::DeepSeek')
        existing.update!(active: true)

        described_class.call(store: store)
        existing.reload

        expect(existing.active).to be true
      end
    end
  end
end
