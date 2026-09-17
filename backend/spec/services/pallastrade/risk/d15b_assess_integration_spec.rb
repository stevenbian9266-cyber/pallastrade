# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-payments-d15b-risk-rules（D15 切片2，与名单的决策合并）
#   AC-007 ← FR-004：白名单短路优先；否则「名单动作 vs 规则动作」取**最严**者
#   AC-008 ← FR-004：留痕记录规则集/版本/金丝雀/桶/命中规则；命中 review/block 走既有审计
#   AC-015 ← FR-004：零副作用（评估前后订单/支付状态与计数全等），且 D15 切片1 语义不变
RSpec.describe 'Risk::Assess + Risk::Rules integration', type: :service do
  let(:store) { @default_store }
  let(:suffix) { SecureRandom.hex(4) }
  let(:order) do
    create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: 200, shipment_cost: 0)
      .tap { |o| o.update_columns(email: "d15b-assess-#{suffix}@example.com", total: 200,
                                  item_total: 200, payment_total: 0) }
      .reload
  end
  let(:now) { Time.current.change(usec: 0) }

  def build_rule_set(code:, action:, conditions: { 'amount_gte' => 100 }, **attrs)
    rule_set = create(:risk_rule_set, code: code, store: store, **attrs)
    rules = [{ 'code' => "#{code}_rule", 'priority' => 10, 'action' => action, 'conditions' => conditions,
               'note' => nil }]
    version = create(:risk_rule_version, rule_set: rule_set, version: 1, state: 'published', rules: rules,
                                         published_at: Time.current)
    rule_set.update!(active_version_id: version.id)
    rule_set
  end

  def upsert(attrs)
    PallasTrade::Risk::Lists::Upsert.call({ store: store, actor: 'system' }.merge(attrs))
  end

  # AC-007 / AC-008
  it 'turns a rule hit into the decision and records which version decided' do
    rule_set = build_rule_set(code: "rule_review_#{suffix}", action: 'review')

    result = PallasTrade::Risk::Assess.call(order: order, now: now)

    expect(result.value[:decision]).to eq('review')
    engine = result.value[:signals]['rule_engine']
    expect(engine).to include('consulted' => true, 'rule_set_id' => rule_set.id,
                              'rule_set_code' => rule_set.code, 'version' => 1,
                              'canary' => false, 'rule_code' => "#{rule_set.code}_rule",
                              'action' => 'review')

    assessment = result.value[:assessment]
    expect(assessment.decision).to eq('review')
    expect(assessment.metadata['rule_engine']).to include('rule_code' => "#{rule_set.code}_rule")
    expect(assessment.metadata['rule_engine']['bucket']).to eq(engine['bucket'])
  end

  # AC-007（最严者胜：规则不放宽名单，名单也不放宽规则）
  it 'keeps the strictest action between the list and the rule engine' do
    upsert(list_type: 'denylist', subject_type: 'email', value: order.email, reason: 'fraud')

    build_rule_set(code: "rule_allow_#{suffix}", action: 'allow')
    expect(PallasTrade::Risk::Assess.call(order: order, now: now).value[:decision]).to eq('review')

    PallasTrade::RiskRuleSet.find_by(code: "rule_allow_#{suffix}").update!(status: 'inactive')
    build_rule_set(code: "rule_block_#{suffix}", action: 'block')
    expect(PallasTrade::Risk::Assess.call(order: order, now: now + 1.minute).value[:decision]).to eq('block')
  end

  # AC-007（白名单短路优先于规则）
  it 'lets the allowlist short-circuit a blocking rule' do
    upsert(list_type: 'allowlist', subject_type: 'email', value: order.email, reason: 'VIP')
    build_rule_set(code: "rule_block_vip_#{suffix}", action: 'block')

    result = PallasTrade::Risk::Assess.call(order: order, now: now)

    expect(result.value[:decision]).to eq('allow')
    expect(result.value[:allowlisted]).to be(true)
    expect(result.value[:signals]['rule_engine_overridden_by']).to eq('allowlist')
  end

  # AC-015（兼容：没有规则集时与 D15 切片1 行为一致）
  it 'stays on the slice-1 behaviour when no rule set is configured' do
    result = PallasTrade::Risk::Assess.call(order: order, now: now)

    expect(result.value[:decision]).to eq('allow')
    expect(result.value[:signals]['rule_engine']).to eq('consulted' => false)
    expect(result.value[:signals]['denylisted']).to be(false)
  end

  # AC-008（审计沿用既有动作名）
  it 'records the existing risk_order_flagged audit when a rule flags the order' do
    build_rule_set(code: "rule_audit_#{suffix}", action: 'review')

    PallasTrade::Risk::Assess.call(order: order, now: now)

    audits = PallasTrade::AuditLog.where(action: 'risk_order_flagged').where(resource_id: order.id)
    expect(audits.count).to eq(1)
    expect(audits.last.after['decision']).to eq('review')
    expect(audits.last.after['signals']['rule_engine']['consulted']).to be(true)
  end

  # AC-015（零副作用）
  it 'does not touch money, orders or payments while evaluating rules' do
    build_rule_set(code: "rule_no_side_effect_#{suffix}", action: 'block')
    # 先强制建单（`let` 惰性求值：否则基线快照会早于订单创建）
    order.reload
    snapshot = lambda do
      {
        payments: PallasTrade::Payment.count,
        orders: PallasTrade::Order.count,
        payment_state: PallasTrade::Payment.reorder(nil).group(:state).count,
        order_state: PallasTrade::Order.reorder(nil).group(:state).count,
        order_total: order.reload.total.to_s,
        order_state_value: order.state,
        payment_total: order.payment_total.to_s
      }
    end
    before = snapshot.call

    PallasTrade::Risk::Assess.call(order: order, now: now)

    expect(snapshot.call).to eq(before)
  end
end
