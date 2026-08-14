require 'rails_helper'

# # PRD-20260814-admin-统一配置中心
RSpec.describe PallasTrade::ConfigCenter do
  let(:store) { create(:store) }

  describe '.get' do
    it 'returns the Config Item value when configured (AC-005)' do
      create(:config_item, store: store, key: 'site.name', value_type: 'string', value: 'Shop')
      expect(described_class.get('site.name', store: store)).to eq('Shop')
    end

    it 'falls back to ENV when no Config Item exists (AC-005)' do
      stub_const('ENV', ENV.to_h.merge('SITE_NAME' => 'FromEnv'))
      expect(described_class.get('site.name', store: store)).to eq('FromEnv')
    end

    it 'falls back to default when neither exists' do
      expect(described_class.get('missing.key', store: store, default: 'fallback')).to eq('fallback')
      expect(described_class.get('missing.key', store: store)).to be_nil
    end

    it 'uses Store.current when store not given' do
      allow(PallasTrade::Store).to receive(:current).and_return(store)
      create(:config_item, store: store, key: 'site.name', value_type: 'string', value: 'Shop')
      expect(described_class.get('site.name')).to eq('Shop')
    end
  end

  describe '.fetch_secret' do
    it 'returns the configured value (server-internal read)' do
      create(:config_item, store: store, key: 'stripe.secret', value_type: 'string', value: 'sk_live_abcdef123456')
      expect(described_class.fetch_secret('stripe.secret', store: store)).to eq('sk_live_abcdef123456')
    end

    it 'falls back to ENV when not configured' do
      stub_const('ENV', ENV.to_h.merge('STRIPE_SECRET' => 'sk_env'))
      expect(described_class.fetch_secret('stripe.secret', store: store)).to eq('sk_env')
    end
  end

  describe '.sync_env!' do
    it 'injects configured items into ENV (Config Center precedence) (AC-005)' do
      create(:config_item, store: store, key: 'oss.access_key_id', value_type: 'string', value: 'LTAI123')
      described_class.sync_env!(store: store)
      expect(ENV['OSS_ACCESS_KEY_ID']).to eq('LTAI123')
    end

    it 'respects env_precedence flag' do
      ENV['OSS_ACCESS_KEY_ID'] = 'from-dotenv'
      create(:config_item, store: store, key: 'oss.access_key_id', value_type: 'string', value: 'from-center')
      described_class.sync_env!(store: store, env_precedence: true)
      expect(ENV['OSS_ACCESS_KEY_ID']).to eq('from-dotenv')
    end
  end

  describe '.env_key' do
    it 'maps dotted keys to ENV-style names' do
      expect(described_class.env_key('oss.access_key_id')).to eq('OSS_ACCESS_KEY_ID')
    end
  end

  describe '.invalidate!' do
    it 'clears cached lookups so subsequent reads see updated values' do
      create(:config_item, store: store, key: 'site.name', value_type: 'string', value: 'Shop')
      expect(described_class.get('site.name', store: store)).to eq('Shop')

      # Update the DB directly (bypassing the cache), then invalidate.
      store.config_items.find_by(key: 'site.name').update!(value: 'Renamed')
      described_class.invalidate!

      expect(described_class.get('site.name', store: store)).to eq('Renamed')
    end
  end
end
