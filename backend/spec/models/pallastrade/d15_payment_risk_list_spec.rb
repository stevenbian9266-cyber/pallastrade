# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d15-risk-lists（D15 切片1，模型）
#   AC-001 ← FR-001：归一化唯一口径 / 唯一键幂等 / `active` scope（排除撤销与过期）/ 脱敏
#   AC-011 ← §74.1：表名列名与规划一致 + `PallasTrade::Config[:risk_denylist_action]` 默认 review
RSpec.describe PallasTrade::PaymentRiskList, type: :model do
  let(:store) { @default_store }
  let(:suffix) { SecureRandom.hex(4) }

  def build_entry(attrs = {})
    described_class.new({ list_type: 'denylist', subject_type: 'email',
                          value: "d15-model-#{suffix}@example.com", reason: 'spec' }.merge(attrs))
  end

  def create_entry(attrs = {})
    build_entry(attrs).tap(&:save!)
  end

  describe 'normalization (唯一口径)' do
    it 'normalises emails, countries, BINs, card fingerprints, IPs and addresses' do
      expect(described_class.normalize_value('email', '  Foo@Example.COM ')).to eq('foo@example.com')
      expect(described_class.normalize_value('country', ' us ')).to eq('US')
      expect(described_class.normalize_value('bin', '4242 42-42')).to eq('42424242')
      expect(described_class.normalize_value('card_fingerprint', ' AbC 123 ')).to eq('abc123')
      expect(described_class.normalize_value('ip', ' 203.0.113.9 ')).to eq('203.0.113.9')
      expect(described_class.normalize_value('address', "  12   Main   St  ")).to eq('12 main st')
      expect(described_class.normalize_value('device', 'Device-AB')).to eq('device-ab')
    end
  end

  describe 'normalised identity (AC-001)' do
    it 'stores the normalised value and a stable hash' do
      entry = create_entry(value: "  D15-Model-#{suffix}@Example.com  ")

      expect(entry.value).to eq("d15-model-#{suffix}@example.com")
      expect(entry.value_hash).to eq(described_class.value_hash_for(list_type: 'denylist', subject_type: 'email',
                                                                   value: "d15-model-#{suffix}@EXAMPLE.com"))
      expect(entry.value_hash.length).to eq(64)
    end

    it 'rejects a second row for the same normalised identity' do
      create_entry(value: "d15-dup-#{suffix}@example.com")
      duplicate = build_entry(value: "D15-DUP-#{suffix}@example.com")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:value_hash]).to be_present
    end

    it 'allows the same value on a different list type or subject type' do
      create_entry(list_type: 'denylist', subject_type: 'email', value: "d15-both-#{suffix}@example.com")
      other = build_entry(list_type: 'allowlist', subject_type: 'email', value: "d15-both-#{suffix}@example.com")

      expect(other).to be_valid
    end
  end

  describe 'active scope (AC-001)' do
    let!(:active_entry) { create_entry(value: "d15-active-#{suffix}@example.com") }
    let!(:expired_entry) do
      create_entry(value: "d15-expired-#{suffix}@example.com", expires_at: 1.hour.ago)
    end
    let!(:revoked_entry) do
      create_entry(value: "d15-revoked-#{suffix}@example.com", status: 'revoked')
    end
    let!(:future_entry) do
      create_entry(value: "d15-future-#{suffix}@example.com", expires_at: 1.day.from_now)
    end

    it 'includes only entries in force' do
      in_force = described_class.active.where(id: [active_entry.id, future_entry.id, expired_entry.id,
                                                   revoked_entry.id]).pluck(:id)

      expect(in_force).to contain_exactly(active_entry.id, future_entry.id)
    end

    it 'reports expired? and effective? consistently' do
      expect(active_entry.expired?).to be(false)
      expect(active_entry.effective?).to be(true)
      expect(expired_entry.expired?).to be(true)
      expect(expired_entry.effective?).to be(false)
      expect(revoked_entry.effective?).to be(false)
    end

    it 'exposes expired scope separately from revoked' do
      expect(described_class.expired).to include(expired_entry)
      expect(described_class.expired).not_to include(revoked_entry)
      expect(described_class.revoked).to include(revoked_entry)
    end
  end

  describe 'store scoping (AC-007 前置)' do
    it 'for_store returns global rows plus the given store rows only' do
      other_store = create(:store, code: "d15-other-#{suffix}", name: 'D15 Other', default: false,
                                   default_currency: 'USD', url: "https://d15-other-#{suffix}.example.com",
                                   mail_from_address: "no-reply@d15-other-#{suffix}.example.com")
      global = create_entry(value: "d15-global-#{suffix}@example.com", store_id: nil)
      mine = create_entry(value: "d15-mine-#{suffix}@example.com", store_id: store.id)
      theirs = create_entry(value: "d15-theirs-#{suffix}@example.com", store_id: other_store.id)

      scope = described_class.for_store(store)
      expect(scope).to include(global, mine)
      expect(scope).not_to include(theirs)
    end
  end

  describe 'masked_value (AC-009 脱敏)' do
    it 'masks emails, IPs, BINs and fingerprints' do
      expect(create_entry(subject_type: 'email', value: 'masked@example.com').masked_value).to eq('m***@example.com')
      expect(create_entry(subject_type: 'ip', value: '203.0.113.9').masked_value).to eq('203.0.*.*')
      expect(create_entry(subject_type: 'bin', value: '42424242').masked_value).to eq('4242***')
      expect(create_entry(subject_type: 'card_fingerprint', value: 'abcdef123456').masked_value).to eq('abcd***3456')
    end
  end

  describe 'config default (AC-011)' do
    it 'keeps the conservative default decision' do
      expect(PallasTrade::Config[:risk_denylist_action].to_s).to eq('review')
    end
  end
end
