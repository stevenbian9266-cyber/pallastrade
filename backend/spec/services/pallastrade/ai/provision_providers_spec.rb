require 'rails_helper'

RSpec.describe PallasTrade::AI::ProvisionProviders, type: :service do
  let(:store) { create(:store) }
  let(:other_store) { create(:store) }

  before do
    # Ensure the provider registry (DeepSeek/OpenAI) is loaded
    Rails.application.reloader.reload! unless PallasTrade::AI.providers.registered?(:deepseek)
  end

  describe '.call' do
    it 'creates one store-scoped Integration per registered provider' do
      expect {
        described_class.call(store: store)
      }.to change(PallasTrade::Integration, :count).by(PallasTrade::AI.providers.all.size)

      PallasTrade::AI.providers.all.each do |entry|
        integration = store.integrations.find_by(type: entry.integration_class)
        expect(integration).to be_present
        expect(integration.name).to eq(entry.display_name)
      end    end

    it 'creates providers as inactive by default' do
      described_class.call(store: store)

      store.integrations.where(type: PallasTrade::AI.providers.all.map(&:integration_class)).each do |integration|
        expect(integration.active).to be false
      end
    end

    it 'is scoped to the given store' do
      described_class.call(store: store)

      expect(other_store.integrations.where(type: PallasTrade::AI.providers.all.map(&:integration_class)).count).to eq(0)

      expect {
        described_class.call(store: other_store)
      }.to change(other_store.integrations, :count).by(PallasTrade::AI.providers.all.size)
    end

    context 'idempotency' do
      it 'does not duplicate providers on repeated calls' do
        described_class.call(store: store)

        expect {
          described_class.call(store: store)
        }.not_to change(store.integrations, :count)
      end

      it 'does not overwrite an existing provider (active preserved)' do
        described_class.call(store: store)

        existing = store.integrations.find_by(type: 'PallasTrade::AI::Integrations::DeepSeek')
        existing.update!(active: true)

        described_class.call(store: store)
        existing.reload

        expect(existing.active).to be true
      end
    end
  end
end
