# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-payments-d15b-risk-rules（D15 切片2，规则求值 + 灰度分桶）
#   AC-004 ← FR-003/004：priority 升序首个命中；无命中 → 仍记录被求值的版本
#   AC-005 ← FR-003：未启用 / 无生效版本 → 不参与（nil）；店铺规则集优先于全局
#   AC-006 ← FR-003：灰度分桶（0/100 边界、桶 == percent 归稳定版）
#   AC-016 ← FR-003：同订单同桶跨 now 恒定（可复算）
RSpec.describe PallasTrade::Risk::Rules::Evaluate, type: :service do
  let(:store) { @default_store }
  let(:suffix) { SecureRandom.hex(4) }
  let(:order) do
    create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: 200, shipment_cost: 0)
      .tap { |o| o.update_columns(total: 200, item_total: 200, payment_total: 0) }
      .reload
  end

  def rule(code:, action: 'review', priority: 100, conditions: { 'amount_gte' => 100 })
    { 'code' => code, 'priority' => priority, 'action' => action, 'conditions' => conditions }
  end

  def build_rule_set(code:, rules:, store: nil, state: 'published')
    rule_set = create(:risk_rule_set, code: code, store: store)
    version = create(:risk_rule_version, rule_set: rule_set, version: 1, state: state, rules: rules,
                                         published_at: Time.current)
    rule_set.update!(active_version_id: version.id)
    rule_set
  end

  def evaluate(target = order, now: Time.current)
    described_class.call(order: target, now: now).value
  end

  def bucket_for(rule_set, target = order)
    ::Digest::SHA256.hexdigest("#{rule_set.id}:#{target.prefixed_id}")[0, 8].to_i(16) % 100
  end

  describe 'participation rules' do
    # AC-005
    it 'returns nil when there is no rule set at all' do
      expect(evaluate).to be_nil
    end

    # AC-005
    it 'returns nil when the rule set is inactive or has no active version' do
      build_rule_set(code: "inactive_#{suffix}", rules: [rule(code: 'r1')], state: 'draft').update!(status: 'inactive')

      expect(evaluate).to be_nil
    end

    # AC-005
    it 'returns nil when the active version id is missing' do
      create(:risk_rule_set, code: "noversion_#{suffix}", store: store)

      expect(evaluate).to be_nil
    end
  end

  describe 'rule selection' do
    # AC-004
    it 'takes the first match by priority and reports what decided' do
      rule_set = build_rule_set(code: "priority_#{suffix}", store: store, rules: [
                                  rule(code: 'low_priority_block', action: 'block', priority: 200),
                                  rule(code: 'high_priority_review', action: 'review', priority: 10)
                                ])

      result = evaluate

      expect(result[:rule_set_id]).to eq(rule_set.id)
      expect(result[:rule_set_code]).to eq(rule_set.code)
      expect(result[:version]).to eq(1)
      expect(result[:canary]).to be(false)
      expect(result[:rule_code]).to eq('high_priority_review')
      expect(result[:action]).to eq('review')
      expect(result[:matched_conditions]).to eq('amount_gte' => 100)
      expect(result[:bucket]).to eq(bucket_for(rule_set))
    end

    # AC-004
    it 'keeps the array order for equal priorities' do
      build_rule_set(code: "order_#{suffix}", store: store, rules: [
                       rule(code: 'first_allow', action: 'allow', priority: 50),
                       rule(code: 'second_block', action: 'block', priority: 50)
                     ])

      expect(evaluate[:rule_code]).to eq('first_allow')
    end

    # AC-004
    it 'reports the consulted version even when nothing matches' do
      build_rule_set(code: "nomatch_#{suffix}", store: store,
                     rules: [rule(code: 'too_big', conditions: { 'amount_gte' => 10_000 })])

      result = evaluate

      expect(result[:version]).to eq(1)
      expect(result[:rule_code]).to be_nil
      expect(result[:action]).to be_nil
      expect(result[:matched_conditions]).to be_nil
    end

    # AC-005（店铺优先）
    it 'prefers the store rule set over the global one' do
      build_rule_set(code: "global_pref_#{suffix}", rules: [rule(code: 'global_block', action: 'block')])
      build_rule_set(code: "store_pref_#{suffix}", store: store, rules: [rule(code: 'store_review', action: 'review')])

      expect(evaluate[:rule_code]).to eq('store_review')
    end
  end

  describe 'canary rollout' do
    # AC-006
    it 'uses the stable version when the canary is off' do
      rule_set = build_rule_set(code: "canary_off_#{suffix}", store: store, rules: [rule(code: 'stable')])
      canary = create(:risk_rule_version, rule_set: rule_set, version: 2, state: 'published',
                                          rules: [rule(code: 'canary', action: 'block')], published_at: Time.current)
      rule_set.update!(canary_version_id: canary.id, canary_percent: 0)

      result = evaluate

      expect(result[:canary]).to be(false)
      expect(result[:version]).to eq(1)
      expect(result[:rule_code]).to eq('stable')
    end

    # AC-006
    it 'always uses the canary version at 100 percent' do
      rule_set = build_rule_set(code: "canary_full_#{suffix}", store: store, rules: [rule(code: 'stable')])
      canary = create(:risk_rule_version, rule_set: rule_set, version: 2, state: 'published',
                                          rules: [rule(code: 'canary', action: 'block')], published_at: Time.current)
      rule_set.update!(canary_version_id: canary.id, canary_percent: 100)

      result = evaluate

      expect(result[:canary]).to be(true)
      expect(result[:version]).to eq(2)
      expect(result[:rule_code]).to eq('canary')
    end

    # AC-006（边界：桶 == percent → 仍走稳定版）
    it 'treats a bucket equal to the percent as the stable version' do
      rule_set = build_rule_set(code: "canary_boundary_#{suffix}", store: store, rules: [rule(code: 'stable')])
      canary = create(:risk_rule_version, rule_set: rule_set, version: 2, state: 'published',
                                          rules: [rule(code: 'canary', action: 'block')], published_at: Time.current)
      bucket = bucket_for(rule_set)

      rule_set.update!(canary_version_id: canary.id, canary_percent: bucket)
      expect(evaluate[:canary]).to be(false)

      rule_set.update!(canary_percent: bucket + 1)
      expect(evaluate[:canary]).to be(true)
    end

    # AC-016（可复算 + 跨 now 恒定）
    it 'buckets the same order identically across evaluations and days' do
      rule_set = build_rule_set(code: "canary_stable_#{suffix}", store: store, rules: [rule(code: 'stable')])

      first = evaluate(now: Time.current)
      second = evaluate(now: Time.current + 3.days)

      expect(first[:bucket]).to eq(second[:bucket])
      expect(first[:bucket]).to eq(bucket_for(rule_set))
    end
  end
end
