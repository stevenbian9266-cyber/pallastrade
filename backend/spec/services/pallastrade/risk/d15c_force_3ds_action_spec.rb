# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-checkout-d15-切片3（D15 切片3，规则动作 force_3ds）
#   AC-006 ← FR-003：发布门接受 force_3ds（非法动作仍拒）；严重度 allow<review<force_3ds<block；
#                    force_3ds 覆盖 review、不覆盖 block；白名单 allow 仍短路
#   AC-007 ← FR-003：留痕接受 force_3ds 且属 flagged；signals 记录动作与 3DS 判定
RSpec.describe 'Risk rules force_3ds action (D15c)', type: :service do
  let(:store) { @default_store }
  let(:suffix) { SecureRandom.hex(4) }
  let(:order) do
    create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: 200, shipment_cost: 0)
      .tap do |o|
        o.update_columns(email: "d15c-force-#{suffix}@example.com", total: 200, item_total: 200, payment_total: 0)
      end
      .reload
  end
  let(:now) { Time.current.change(usec: 0) }

  def build_rule_set(code:, action:, conditions: { 'amount_gte' => 100 })
    rule_set = create(:risk_rule_set, code: code, store: store)
    rules = [{ 'code' => "#{code}_rule", 'priority' => 10, 'action' => action, 'conditions' => conditions,
               'note' => nil }]
    version = create(:risk_rule_version, rule_set: rule_set, version: 1, state: 'published', rules: rules,
                                         published_at: Time.current)
    rule_set.update!(active_version_id: version.id)
    rule_set
  end

  # AC-006（发布门）
  it 'accepts force_3ds at the publish gate and keeps rejecting unknown actions' do
    accepted = PallasTrade::Risk::Rules::Schema.call(
      rules: [{ 'code' => 'force', 'action' => 'force_3ds', 'conditions' => { 'amount_gte' => 10 } }]
    )
    rejected = PallasTrade::Risk::Rules::Schema.call(
      rules: [{ 'code' => 'nope', 'action' => 'challenge', 'conditions' => { 'amount_gte' => 10 } }]
    )

    expect(accepted).to be_success
    expect(accepted.value.first['action']).to eq('force_3ds')
    expect(rejected).not_to be_success
    expect(rejected.error.to_s).to include('action')
  end

  # AC-006（严重度序：allow < review < force_3ds < block）
  it 'places force_3ds strictly between review and block' do
    severity = PallasTrade::Risk::Assess::DECISION_SEVERITY

    expect(severity['allow']).to be < severity['review']
    expect(severity['review']).to be < severity['force_3ds']
    expect(severity['force_3ds']).to be < severity['block']
    expect(PallasTrade::RiskRuleVersion::ACTIONS).to include('force_3ds')
    expect(PallasTrade::PaymentRiskAssessment::DECISIONS).to include('force_3ds')
    expect(PallasTrade::PaymentRiskAssessment::FLAGGED_DECISIONS).to include('force_3ds')
  end

  # AC-006 / AC-007（规则 force_3ds 成为最终决策，并写入两份留痕）
  it 'turns a force_3ds rule into the decision and records the authentication requirement' do
    rule_set = build_rule_set(code: "force_#{suffix}", action: 'force_3ds')

    result = PallasTrade::Risk::Assess.call(order: order, now: now)

    expect(result.value[:decision]).to eq('force_3ds')
    engine = result.value[:signals]['rule_engine']
    expect(engine).to include('consulted' => true, 'rule_set_id' => rule_set.id, 'action' => 'force_3ds')

    assessment = result.value[:assessment]
    expect(assessment.decision).to eq('force_3ds')
    expect(assessment).to be_flagged
    expect(assessment.force_3ds?).to be(true)
    expect(assessment.signals['three_d_secure']).to include(
      'evaluated' => true, 'required' => true, 'source' => 'risk_rule', 'risk_action' => 'force_3ds'
    )
  end

  def with_denylist_action(action)
    previous = PallasTrade::Config[:risk_denylist_action]
    PallasTrade::Config[:risk_denylist_action] = action
    yield
  ensure
    PallasTrade::Config[:risk_denylist_action] = previous
  end

  def deny!(email)
    PallasTrade::Risk::Lists::Upsert.call(
      store: store, actor: 'system', list_type: 'denylist', subject_type: 'email', value: email, reason: 'fraud'
    )
  end

  # AC-006（取最严者：force_3ds 覆盖 review）
  it 'lets force_3ds win over a review denylist decision' do
    build_rule_set(code: "force_over_review_#{suffix}", action: 'force_3ds')
    deny!(order.email)

    result = PallasTrade::Risk::Assess.call(order: order, now: now)

    expect(result.value[:decision]).to eq('force_3ds')
    expect(result.value[:signals]['denylist_action']).to eq('review')
    expect(result.value[:signals]['rule_action']).to eq('force_3ds')
  end

  # AC-006（block 不被 force_3ds 放宽）
  it 'never relaxes a block decision' do
    build_rule_set(code: "force_vs_block_#{suffix}", action: 'force_3ds')
    deny!(order.email)

    with_denylist_action('block') do
      result = PallasTrade::Risk::Assess.call(order: order, now: now)

      expect(result.value[:decision]).to eq('block')
      expect(result.value[:signals]['decision_source']).to eq('denylist')
      expect(result.value[:assessment].signals['three_d_secure']['required']).to be(false)
    end
  end

  # AC-006（白名单 allow 仍短路：force_3ds 规则不得覆盖人工白名单）
  it 'still short-circuits on an allowlist hit' do
    build_rule_set(code: "force_short_#{suffix}", action: 'force_3ds')
    PallasTrade::Risk::Lists::Upsert.call(
      store: store, actor: 'system', list_type: 'allowlist', subject_type: 'email', value: order.email
    )

    result = PallasTrade::Risk::Assess.call(order: order, now: now)

    expect(result.value[:decision]).to eq('allow')
    expect(result.value[:signals]['rule_engine_overridden_by']).to eq('allowlist')
    expect(result.value[:assessment].signals['three_d_secure']['required']).to be(false)
  end
end
