require 'rails_helper'

# # PRD-20260814-admin-统一配置中心
RSpec.describe PallasTrade::ConfigItem, type: :model do
  let(:store) { create(:store) }

  describe 'validations' do
    it 'requires a unique key per store' do
      create(:config_item, store: store, key: 'site.name')
      item = build(:config_item, store: store, key: 'site.name')
      expect(item).not_to be_valid
      expect(item.errors[:key]).to be_present
    end

    it 'allows the same key across different stores' do
      other = create(:store)
      create(:config_item, store: store, key: 'site.name')
      item = build(:config_item, store: other, key: 'site.name')
      expect(item).to be_valid
    end

    it 'rejects unknown value_type' do
      item = build(:config_item, store: store, key: 'a.b', value_type: 'weird')
      expect(item).not_to be_valid
    end

    it 'normalizes key to lowercase dotted form' do
      item = create(:config_item, store: store, key: '  OSS.AccessKey_ID ')
      expect(item.reload.key).to eq('oss.accesskey_id')
    end
  end

  describe 'plain (non-secret) items' do
    it 'stores value as plaintext and returns it' do
      item = create(:config_item, store: store, key: 'site.name', value_type: 'string', value: 'Shop')
      expect(item.reload.value).to eq('Shop')
      expect(item.raw_value).to eq('Shop')
      expect(item.typed_value).to eq('Shop')
    end

    it 'coerces boolean values' do
      item = create(:config_item, store: store, key: 'f.flag', value_type: 'boolean', value: 'true')
      expect(item.typed_value).to eq(true)
    end

    it 'coerces number values' do
      item = create(:config_item, store: store, key: 'n.min', value_type: 'number', value: '12.5')
      expect(item.typed_value).to eq(12.5)
    end

    it 'does not expose secret-only fields' do
      item = create(:config_item, store: store, key: 'site.name', value_type: 'string', value: 'Shop')
      expect(item.credential_summary).to be_nil
      expect(item.secret?).to be(false)
    end

    it 'maps key to ENV-style name' do
      item = build(:config_item, store: store, key: 'oss.access_key_id')
      expect(item.env_key).to eq('OSS_ACCESS_KEY_ID')
    end
  end

  describe 'secret items' do
    it 'is secret' do
      item = build(:config_item, store: store, key: 'stripe.secret', value_type: 'secret')
      expect(item.secret?).to be(true)
    end

    it 'fails closed when Active Record Encryption is not configured (AC-002)' do
      # 本地测试环境无 ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY → secret 写入必须失败
      item = build(:config_item, store: store, key: 'stripe.secret', value_type: 'secret')
      item.assign_value('sk_test_1234567890abcdef')
      expect(item.save).to be(false)
      expect(item.errors[:secret_value]).to be_present
      expect(PallasTrade::ConfigItem.where(key: 'stripe.secret', store: store)).not_to exist
    end

    it 'computes masked key hint without leaking plaintext (AC-001)' do
      item = build(:config_item, store: store, key: 'stripe.secret', value_type: 'secret')
      item.assign_value('sk_test_1234567890abcdef')
      item.send(:set_key_hint)
      item.send(:set_rotated_at)

      expect(item.key_hint).to eq('sk_te::cdef')
      expect(item.rotated_at).not_to be_nil
      display = item.key_hint_display
      expect(display).to include('sk_te')
      expect(display).not_to include('1234567890abcdef')
    end

    it 'reports credential summary without plaintext (AC-004)' do
      item = build(:config_item, store: store, key: 'stripe.secret', value_type: 'secret')
      item.assign_value('sk_test_1234567890abcdef')
      item.send(:set_key_hint)
      item.send(:set_rotated_at)

      summary = item.credential_summary
      expect(summary[:configured]).to be(true)
      expect(summary[:hint]).to include('sk_te')
      expect(summary[:hint]).not_to include('123456')
      expect(summary[:rotated_at]).not_to be_nil
      expect(item.raw_value).to eq('sk_test_1234567890abcdef') # 内部读取明文（仅服务端）
    end
  end
end
