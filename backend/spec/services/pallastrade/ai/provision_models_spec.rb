require 'rails_helper'

RSpec.describe PallasTrade::AI::ProvisionModels, type: :service do
  let(:store) { create(:store) }
  let(:deepseek_provider) do
    # Instantiate the STI subclass directly so #key resolves via the registry.
    PallasTrade::AI::Provider::DeepSeek.create!(store: store, active: false)
  end
  let(:openai_provider) do
    PallasTrade::AI::Provider::OpenAI.create!(store: store, active: false)
  end

  before do
    # Ensure provider registry is loaded
    Rails.application.reloader.reload! unless PallasTrade::AI.providers.registered?(:deepseek)
  end

  describe '.call' do
    context 'with a DeepSeek provider' do
      it 'creates catalog models from the registry' do
        expect {
          described_class.call(provider: deepseek_provider)
        }.to change(PallasTrade::AI::Model, :count).by(2)

        models = PallasTrade::AI::Model.where(provider: deepseek_provider).order(:position)
        expect(models.pluck(:provider_model_id)).to contain_exactly(
          'deepseek-v4-flash', 'deepseek-v4-pro'
        )
      end

      it 'marks models as built_in and inactive by default' do
        described_class.call(provider: deepseek_provider)

        models = PallasTrade::AI::Model.where(provider: deepseek_provider)
        models.each do |model|
          expect(model.built_in).to be true
          expect(model.active).to be false
        end
      end

      it 'sets model attributes from catalog' do
        described_class.call(provider: deepseek_provider)

        flash_model = PallasTrade::AI::Model.find_by(
          provider: deepseek_provider,
          provider_model_id: 'deepseek-v4-flash'
        )
        expect(flash_model.name).to eq('DeepSeek V4 Flash')
        expect(flash_model.kind).to eq('text')
        expect(flash_model.capabilities).to include('text', 'structured_output')
        expect(flash_model.default_parameters).to include(
          'max_output_tokens' => 8192,
          'temperature' => 0.7
        )
      end
    end

    context 'with an OpenAI provider' do
      it 'creates all catalog models' do
        expect {
          described_class.call(provider: openai_provider)
        }.to change(PallasTrade::AI::Model, :count).by(3)

        models = PallasTrade::AI::Model.where(provider: openai_provider)
        expect(models.pluck(:provider_model_id)).to contain_exactly(
          'gpt-5.6-sol', 'gpt-5.6-terra', 'gpt-5.6-luna'
        )
      end
    end

    context 'idempotency' do
      it 'does not create duplicate models on repeated calls' do
        described_class.call(provider: deepseek_provider)

        expect {
          described_class.call(provider: deepseek_provider)
        }.not_to change(PallasTrade::AI::Model, :count)
      end

      it 'does not overwrite existing model attributes' do
        described_class.call(provider: deepseek_provider)

        flash = PallasTrade::AI::Model.find_by(
          provider: deepseek_provider,
          provider_model_id: 'deepseek-v4-flash'
        )
        flash.update!(active: true, name: 'Custom Name')

        described_class.call(provider: deepseek_provider)
        flash.reload

        expect(flash.active).to be true
        expect(flash.name).to eq('Custom Name')
      end
    end

    context 'with nil or missing registry entry' do
      it 'does not raise when provider has no registry entry' do
        fake_provider = double('Provider', key: 'nonexistent')
        allow(PallasTrade::AI.providers).to receive(:[]).with(:nonexistent).and_return(nil)

        expect {
          described_class.call(provider: fake_provider)
        }.not_to raise_error
      end

      it 'does nothing when recommended_models is empty' do
        fake_provider = double('Provider', key: 'empty_provider')
        empty_entry = double('Entry', recommended_models: [])
        allow(PallasTrade::AI.providers).to receive(:[]).with(:empty_provider).and_return(empty_entry)

        expect {
          described_class.call(provider: fake_provider)
        }.not_to change(PallasTrade::AI::Model, :count)
      end
    end
  end
end
