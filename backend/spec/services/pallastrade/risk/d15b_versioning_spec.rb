# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-payments-d15b-risk-rules（D15 切片2，版本流转与回滚）
#   AC-003 ← FR-002：发布校验（未知键/类型错/非法动作/空条件/超 50 条）→ 拒绝且**不落库**
#   AC-009 ← FR-005：草稿 → 发布 → 金丝雀 → 停用；版本号单调；旧生效版归档
#   AC-010 ← FR-005：**回滚**（锚点）——以历史版内容生成新版本并生效、源版本不可改写、理由必填
#   AC-011 ← FR-005：事件 `risk.rule_version_published` / `risk.rule_version_rolled_back`
RSpec.describe PallasTrade::Risk::Rules::Versioning, type: :service do
  let(:suffix) { SecureRandom.hex(4) }
  let(:store) { @default_store }
  let(:rule_set) { create(:risk_rule_set, code: "versioning_#{suffix}", store: store) }

  def valid_rules
    [{ 'code' => 'amount_review', 'priority' => 20, 'action' => 'review',
       'conditions' => { 'amount_gte' => 300 } }]
  end

  def capture_events
    published = []
    allow(PallasTrade::Events).to receive(:enabled?).and_return(true)
    allow(PallasTrade::Events).to receive(:publish) { |name, payload| published << [name, payload] }
    published
  end

  def audit_count(action)
    PallasTrade::AuditLog.where(action: action).where(resource_id: rule_set.id).count
  end

  describe '#create_draft' do
    # AC-009
    it 'stores a normalized draft with a monotonically increasing version number' do
      outcome = described_class.create_draft(
        rule_set: rule_set, actor: 'admin',
        rules: [{ 'code' => 'Mixed_Case', 'action' => 'review', 'conditions' => { 'country_in' => %w[kp] } }]
      )

      expect(outcome).to be_success
      version = outcome.value
      expect(version.version).to eq(1)
      expect(version.state).to eq('draft')
      expect(version.rules.first['code']).to eq('mixed_case')
      expect(version.rules.first['priority']).to eq(100)
      expect(version.rules.first['conditions']).to eq('country_in' => %w[KP])

      second = described_class.create_draft(rule_set: rule_set, rules: valid_rules).value
      expect(second.version).to eq(2)
      expect(audit_count(described_class::AUDIT_VERSION_CREATED)).to eq(2)
    end

    # AC-003
    it 'rejects unsupported condition keys without storing a version' do
      outcome = described_class.create_draft(
        rule_set: rule_set,
        rules: [{ 'code' => 'bin_rule', 'action' => 'block', 'conditions' => { 'bin_in' => %w[411111] } }]
      )

      expect(outcome).not_to be_success
      expect(outcome.error.to_s).to include('bin_in')
      expect(rule_set.versions.count).to eq(0)
    end

    # AC-003
    it 'rejects invalid json, invalid actions, empty conditions and oversized payloads' do
      expect(described_class.create_draft(rule_set: rule_set, rules: '{oops')).not_to be_success
      expect(described_class.create_draft(rule_set: rule_set,
                                          rules: [{ 'code' => 'x', 'action' => 'nuke',
                                                    'conditions' => { 'amount_gte' => 1 } }])).not_to be_success
      expect(described_class.create_draft(rule_set: rule_set,
                                          rules: [{ 'code' => 'x', 'action' => 'allow', 'conditions' => {} }])).not_to be_success
      too_many = Array.new(51) do |index|
        { 'code' => "rule_#{index}", 'action' => 'allow', 'conditions' => { 'amount_gte' => index } }
      end
      expect(described_class.create_draft(rule_set: rule_set, rules: too_many)).not_to be_success

      expect(rule_set.versions.count).to eq(0)
    end

    # AC-003
    it 'rejects duplicate rule codes inside one version' do
      outcome = described_class.create_draft(
        rule_set: rule_set,
        rules: [{ 'code' => 'dup', 'action' => 'allow', 'conditions' => { 'amount_gte' => 1 } },
                { 'code' => 'dup', 'action' => 'block', 'conditions' => { 'amount_gte' => 2 } }]
      )

      expect(outcome).not_to be_success
      expect(outcome.error.to_s).to include('duplicate rule code')
    end
  end

  describe '#publish' do
    # AC-009
    it 'publishes a version and archives the previously active one' do
      first = described_class.create_draft(rule_set: rule_set, rules: valid_rules).value
      described_class.publish(rule_set: rule_set, version: first.version, actor: 'admin')
      expect(rule_set.reload.active_version_id).to eq(first.id)

      second = described_class.create_draft(
        rule_set: rule_set,
        rules: [{ 'code' => 'block_kp', 'action' => 'block', 'conditions' => { 'country_in' => %w[KP] } }]
      ).value
      described_class.publish(rule_set: rule_set, version: second.version, actor: 'admin')

      expect(rule_set.reload.active_version_id).to eq(second.id)
      expect(first.reload.state).to eq('archived')
      expect(second.reload.state).to eq('published')
      expect(second.published_at).to be_present
      expect(audit_count(described_class::AUDIT_VERSION_PUBLISHED)).to eq(2)
    end

    # AC-009
    it 'fails for an unknown version' do
      outcome = described_class.publish(rule_set: rule_set, version: 99)

      expect(outcome).not_to be_success
      expect(rule_set.reload.active_version_id).to be_nil
    end

    # AC-011
    it 'publishes one event per publish with a PII-free payload' do
      published = capture_events
      version = described_class.create_draft(rule_set: rule_set, rules: valid_rules).value
      described_class.publish(rule_set: rule_set, version: version.version, actor: 'admin')

      events = published.select { |name, _payload| name == described_class::EVENT_VERSION_PUBLISHED }
      expect(events.size).to eq(1)
      expect(events.first.last).to include('rule_set_id' => rule_set.id, 'code' => rule_set.code,
                                           'version' => 1, 'previous_version' => nil)
    end
  end

  describe '#set_canary' do
    # AC-009（修复后语义：金丝雀与稳定版**并存**）
    it 'publishes a draft as the canary without touching the active version' do
      stable = described_class.create_draft(rule_set: rule_set, rules: valid_rules).value
      described_class.publish(rule_set: rule_set, version: stable.version)
      canary_candidate = described_class.create_draft(
        rule_set: rule_set,
        rules: [{ 'code' => 'block_kp', 'action' => 'block', 'conditions' => { 'country_in' => %w[KP] } }]
      ).value

      outcome = described_class.set_canary(rule_set: rule_set, version: canary_candidate.version, percent: 25,
                                           actor: 'admin')

      expect(outcome).to be_success
      rule_set.reload
      expect(rule_set.canary_version_id).to eq(canary_candidate.id)
      expect(rule_set.canary_percent).to eq(25)
      # 稳定版**不变**，金丝雀候选被发布但**没有**成为生效版
      expect(rule_set.active_version_id).to eq(stable.id)
      expect(canary_candidate.reload.state).to eq('published')
      expect(stable.reload.state).to eq('published')
    end

    # AC-009
    it 'validates the percent range and refuses unknown or archived versions' do
      stable = described_class.create_draft(rule_set: rule_set, rules: valid_rules).value
      described_class.publish(rule_set: rule_set, version: stable.version)

      expect(described_class.set_canary(rule_set: rule_set, version: stable.version, percent: 101)).not_to be_success
      expect(described_class.set_canary(rule_set: rule_set, version: stable.version, percent: 'abc')).not_to be_success
      expect(described_class.set_canary(rule_set: rule_set, version: 99, percent: 10)).not_to be_success

      newer = described_class.create_draft(
        rule_set: rule_set,
        rules: [{ 'code' => 'newer', 'action' => 'allow', 'conditions' => { 'amount_gte' => 1 } }]
      ).value
      described_class.publish(rule_set: rule_set, version: newer.version)
      expect(stable.reload.state).to eq('archived')
      expect(described_class.set_canary(rule_set: rule_set, version: stable.version, percent: 10)).not_to be_success
      expect(rule_set.reload.canary_version_id).to be_nil
    end

    # AC-009（0 = 关闭）
    it 'clears the canary at zero percent' do
      stable = described_class.create_draft(rule_set: rule_set, rules: valid_rules).value
      described_class.publish(rule_set: rule_set, version: stable.version)
      described_class.set_canary(rule_set: rule_set, version: stable.version, percent: 50)

      described_class.set_canary(rule_set: rule_set, percent: 0)

      expect(rule_set.reload.canary_version_id).to be_nil
      expect(rule_set.canary_percent).to eq(0)
      expect(audit_count(described_class::AUDIT_CANARY_UPDATED)).to eq(2)
    end

    # AC-009（发布新版本时清理指向已归档版本的金丝雀）
    it 'clears a canary that points at a version archived by a later publish' do
      stable = described_class.create_draft(rule_set: rule_set, rules: valid_rules).value
      described_class.publish(rule_set: rule_set, version: stable.version)
      described_class.set_canary(rule_set: rule_set, version: stable.version, percent: 40)

      newer = described_class.create_draft(
        rule_set: rule_set,
        rules: [{ 'code' => 'newer', 'action' => 'block', 'conditions' => { 'amount_gte' => 1 } }]
      ).value
      described_class.publish(rule_set: rule_set, version: newer.version)

      expect(rule_set.reload.canary_version_id).to be_nil
      expect(rule_set.canary_percent).to eq(0)
    end

    # AC-009（金丝雀自己变成生效版后，灰度设置不再成立 → 清空，避免「生效版 == 金丝雀」重复）
    it 'clears the canary when the canary version itself becomes the active version' do
      stable = described_class.create_draft(rule_set: rule_set, rules: valid_rules).value
      described_class.publish(rule_set: rule_set, version: stable.version)
      canary_candidate = described_class.create_draft(
        rule_set: rule_set,
        rules: [{ 'code' => 'block_kp', 'action' => 'block', 'conditions' => { 'country_in' => %w[KP] } }]
      ).value
      described_class.set_canary(rule_set: rule_set, version: canary_candidate.version, percent: 30)
      expect(rule_set.reload.canary_version_id).to eq(canary_candidate.id)

      described_class.publish(rule_set: rule_set, version: canary_candidate.version)

      rule_set.reload
      expect(rule_set.active_version_id).to eq(canary_candidate.id)
      expect(rule_set.canary_version_id).to be_nil
      expect(rule_set.canary_percent).to eq(0)
      expect(stable.reload.state).to eq('archived')
    end
  end

  describe '#rollback' do
    # AC-010（锚点）
    it 'rolls back by creating a new version from the old content without rewriting history' do
      v1_rules = [{ 'code' => 'amount_review', 'priority' => 10, 'action' => 'review',
                    'conditions' => { 'amount_gte' => 300 } }]
      v2_rules = [{ 'code' => 'block_everything', 'priority' => 10, 'action' => 'block',
                    'conditions' => { 'amount_gte' => 1 } }]
      v1 = described_class.create_draft(rule_set: rule_set, rules: v1_rules).value
      described_class.publish(rule_set: rule_set, version: v1.version)
      v2 = described_class.create_draft(rule_set: rule_set, rules: v2_rules).value
      described_class.publish(rule_set: rule_set, version: v2.version)
      v2_content_before_rollback = v2.reload.rules

      published = capture_events
      outcome = described_class.rollback(rule_set: rule_set, to_version: v1.version,
                                         reason: 'v2 blocked legitimate orders', actor: 'admin')

      expect(outcome).to be_success
      rolled = outcome.value
      expect(rolled.version).to eq(3)
      expect(rolled.rolled_back).to be(true)
      expect(rolled.source_version).to eq(1)
      expect(rolled.reason).to eq('v2 blocked legitimate orders')
      expect(rolled.state).to eq('published')
      expect(rolled.rules).to eq(v1.reload.rules)

      expect(rule_set.reload.active_version_id).to eq(rolled.id)
      expect(v1.reload.state).to eq('archived')
      expect(v2.reload.state).to eq('archived')
      # 源版本（被回滚的那个版本）内容**一字不改**
      expect(v2.reload.rules).to eq(v2_content_before_rollback)
      expect(v2.rules.first['code']).to eq('block_everything')

      events = published.select { |name, _payload| name == described_class::EVENT_VERSION_ROLLED_BACK }
      expect(events.size).to eq(1)
      expect(events.first.last).to include('version' => 3, 'source_version' => 1,
                                           'previous_version' => 2, 'reason' => 'v2 blocked legitimate orders')
      expect(audit_count(described_class::AUDIT_VERSION_ROLLED_BACK)).to eq(1)
    end

    # AC-010（理由必填）
    it 'requires a reason and refuses to roll back to a draft' do
      v1 = described_class.create_draft(rule_set: rule_set, rules: valid_rules).value
      described_class.publish(rule_set: rule_set, version: v1.version)
      draft = described_class.create_draft(rule_set: rule_set, rules: valid_rules).value

      expect(described_class.rollback(rule_set: rule_set, to_version: v1.version, reason: '  ')).not_to be_success
      expect(described_class.rollback(rule_set: rule_set, to_version: draft.version, reason: 'nope')).not_to be_success
      expect(rule_set.reload.active_version_id).to eq(v1.id)
      expect(rule_set.versions.count).to eq(2)
    end
  end

  describe '#activate / #deactivate' do
    # AC-009
    it 'toggles the rule set status and audits it' do
      described_class.deactivate(rule_set: rule_set, actor: 'admin')
      expect(rule_set.reload.status).to eq('inactive')

      described_class.activate(rule_set: rule_set, actor: 'admin')
      expect(rule_set.reload.status).to eq('active')

      expect(audit_count(described_class::AUDIT_SET_DEACTIVATED)).to eq(1)
      expect(audit_count(described_class::AUDIT_SET_ACTIVATED)).to eq(1)
    end
  end
end
