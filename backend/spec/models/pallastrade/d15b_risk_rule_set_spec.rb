# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-payments-d15b-risk-rules（D15 切片2，模型层）
#   AC-001 ← FR-001：版本号唯一、规则集 code 在两个作用域内唯一、
#                    发布后规则内容不可改写、engine_ready?/canary_active? 判定、for_store 作用域
RSpec.describe PallasTrade::RiskRuleSet, type: :model do
  let(:store) { @default_store }
  let(:suffix) { SecureRandom.hex(4) }

  def other_store
    create(:store, code: "d15b-b-#{suffix}", name: 'D15b B', default: false, default_currency: 'USD',
                   url: "https://d15b-b-#{suffix}.example.com",
                   mail_from_address: "no-reply@d15b-b-#{suffix}.example.com")
  end

  describe 'validations' do
    # AC-001
    it 'requires a lowercase code and a name' do
      rule_set = build(:risk_rule_set, code: 'BAD CODE', name: nil)

      expect(rule_set).not_to be_valid
      expect(rule_set.errors[:code]).to include('must be lowercase letters, digits, dash or underscore')
      expect(rule_set.errors[:name]).to include("can't be blank")
    end

    # AC-001
    it 'keeps the code unique per scope (global and per store)' do
      code = "scope_#{suffix}"
      create(:risk_rule_set, code: code, store: nil)

      expect(build(:risk_rule_set, code: code, store: nil)).not_to be_valid
      expect(build(:risk_rule_set, code: code, store: store)).to be_valid

      create(:risk_rule_set, code: code, store: store)
      expect(build(:risk_rule_set, code: code, store: store)).not_to be_valid
      expect(build(:risk_rule_set, code: code, store: other_store)).to be_valid
    end

    # AC-001
    it 'validates status and canary percent range' do
      rule_set = build(:risk_rule_set, code: "range_#{suffix}", status: 'weird', canary_percent: 101)

      expect(rule_set).not_to be_valid
      expect(rule_set.errors[:status]).to be_present
      expect(rule_set.errors[:canary_percent]).to be_present
    end
  end

  describe 'version immutability' do
    # AC-001
    it 'does not allow changing the rules of a published version' do
      rule_set = create(:risk_rule_set, code: "immutable_#{suffix}")
      version = create(:risk_rule_version, :published, rule_set: rule_set, version: 1)
      original = version.rules

      version.rules = [{ 'code' => 'changed', 'priority' => 1, 'action' => 'allow',
                         'conditions' => { 'amount_gte' => 1 } }]

      expect(version).not_to be_valid
      expect(version.errors[:rules]).to include('cannot be changed once the version leaves draft')
      expect(version.reload.rules).to eq(original)
    end

    # AC-001
    it 'allows editing a draft version' do
      rule_set = create(:risk_rule_set, code: "draft_edit_#{suffix}")
      version = create(:risk_rule_version, rule_set: rule_set, version: 1, state: 'draft')

      version.rules = [{ 'code' => 'edited', 'priority' => 5, 'action' => 'block',
                         'conditions' => { 'amount_gte' => 10 } }]

      expect(version).to be_valid
      expect(version.save).to be(true)
      expect(version.reload.rules.first['code']).to eq('edited')
    end

    # AC-001
    it 'enforces one version number per rule set' do
      rule_set = create(:risk_rule_set, code: "uniq_version_#{suffix}")
      create(:risk_rule_version, rule_set: rule_set, version: 1)

      duplicate = build(:risk_rule_version, rule_set: rule_set, version: 1)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:version]).to include('has already been taken')
    end
  end

  describe '#engine_ready? / #canary_active?' do
    # AC-005（前置：无生效版本不参与评估）
    it 'requires an active status and an active version' do
      rule_set = create(:risk_rule_set, code: "ready_#{suffix}")
      expect(rule_set.engine_ready?).to be(false)

      rule_set = create(:risk_rule_set, :with_published_version, code: "ready2_#{suffix}")
      expect(rule_set.engine_ready?).to be(true)
      expect(rule_set.canary_active?).to be(false)

      rule_set.update!(canary_version_id: rule_set.active_version_id, canary_percent: 10)
      expect(rule_set.canary_active?).to be(true)

      rule_set.update!(status: 'inactive')
      expect(rule_set.engine_ready?).to be(false)
      expect(rule_set.canary_active?).to be(false)
    end
  end

  describe '.for_store' do
    # AC-005（作用域口径）
    it 'includes global rule sets plus the current store only' do
      mine = create(:risk_rule_set, code: "mine_#{suffix}", store: store)
      global = create(:risk_rule_set, code: "global_#{suffix}", store: nil)
      foreign = create(:risk_rule_set, code: "foreign_#{suffix}", store: other_store)

      scoped = described_class.for_store(store)

      expect(scoped).to include(mine, global)
      expect(scoped).not_to include(foreign)
    end
  end
end
