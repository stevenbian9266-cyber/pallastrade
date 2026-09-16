# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d15-risk-lists（D15 切片1，评估）
#   AC-005 ← FR-005：决策矩阵（白名单短路 / 黑名单默认 review、配置 block / 无命中 allow / 主体不足 allow+signal）+ 留痕幂等
#   AC-007 ← FR-009：跨店隔离（A 店名单不命中 B 店订单；全局名单命中所有店铺）
#   AC-010 ← FR-010：零资金副作用
RSpec.describe PallasTrade::Risk::Assess, type: :service do
  let(:store) { @default_store }
  let(:suffix) { SecureRandom.hex(4) }
  let(:order) do
    create(:order_with_line_items, store: store).tap do |o|
      o.update_columns(email: "d15-assess-#{suffix}@example.com", last_ip_address: '203.0.113.9')
    end
  end
  let(:now) { Time.current.change(usec: 0) }

  def upsert(attrs)
    PallasTrade::Risk::Lists::Upsert.call({ store: store, actor: 'system' }.merge(attrs))
  end

  def other_store
    create(:store, code: "d15-b-#{suffix}", name: 'D15 B', default: false, default_currency: 'USD',
                   url: "https://d15-b-#{suffix}.example.com",
                   mail_from_address: "no-reply@d15-b-#{suffix}.example.com")
  end

  def with_denylist_action(action)
    previous = PallasTrade::Config[:risk_denylist_action]
    PallasTrade::Config[:risk_denylist_action] = action
    yield
  ensure
    PallasTrade::Config[:risk_denylist_action] = previous
  end

  # AC-005
  it 'allows an order that matches nothing and records the assessment' do
    result = described_class.call(order: order.reload, now: now)

    expect(result).to be_success
    expect(result.value[:decision]).to eq('allow')
    expect(result.value[:matched]).to be_empty
    expect(result.value[:signals]['insufficient_subject']).to be(false)

    assessment = result.value[:assessment]
    expect(assessment.decision).to eq('allow')
    expect(assessment.order_id).to eq(order.id)
    expect(assessment.store_id).to eq(store.id)
  end

  # AC-005（denylist 默认 review；显式配置才 block）
  it 'flags a denied email as review by default and as block only when configured' do
    upsert(list_type: 'denylist', subject_type: 'email', value: "D15-Assess-#{suffix}@Example.com", reason: 'fraud')

    result = described_class.call(order: order.reload, now: now)
    expect(result.value[:decision]).to eq('review')
    expect(result.value[:matched].size).to eq(1)
    expect(result.value[:matched_summary].first['masked']).to eq("d***@example.com")
    expect(result.value[:signals]['denylisted']).to be(true)

    with_denylist_action('block') do
      blocked = described_class.call(order: order.reload, now: now + 1.minute)
      expect(blocked.value[:decision]).to eq('block')
    end

    with_denylist_action('nonsense') do
      fallback = described_class.call(order: order.reload, now: now + 2.minutes)
      expect(fallback.value[:decision]).to eq('review')
    end
  end

  # AC-005（白名单优先：denylist 也命中时仍然 allow）
  it 'short-circuits on an allowlist hit even when the denylist also matches' do
    upsert(list_type: 'denylist', subject_type: 'email', value: "d15-assess-#{suffix}@example.com")
    upsert(list_type: 'denylist', subject_type: 'ip', value: '203.0.113.9')
    upsert(list_type: 'allowlist', subject_type: 'email', value: "d15-assess-#{suffix}@example.com")

    result = described_class.call(order: order.reload, now: now)

    expect(result.value[:decision]).to eq('allow')
    expect(result.value[:allowlisted]).to be(true)
    expect(result.value[:denylisted]).to be(false)
    expect(result.value[:matched].size).to eq(1)
    expect(result.value[:signals]['allowlisted']).to be(true)
  end

  # AC-005（撤销 / 过期不再命中）
  it 'ignores revoked and expired entries' do
    revoked = upsert(list_type: 'denylist', subject_type: 'email', value: "d15-assess-#{suffix}@example.com").value
    upsert({ list_type: 'denylist', subject_type: 'email', value: "d15-assess-#{suffix}@example.com", revoke: true })

    expect(described_class.call(order: order.reload, now: now).value[:decision]).to eq('allow')

    upsert(list_type: 'denylist', subject_type: 'email', value: "d15-assess-#{suffix}@example.com")
    PallasTrade::PaymentRiskList.where(id: revoked.id).update_all(expires_at: 1.minute.ago)

    expect(described_class.call(order: order.reload, now: now + 1.minute).value[:decision]).to eq('allow')
  end

  # AC-005（主体不足 → allow + signal，不猜）
  it 'allows and marks insufficient subject when the order carries nothing to compare' do
    bare = create(:order_with_line_items, store: store).tap do |o|
      o.update_columns(email: nil, last_ip_address: nil, user_id: nil, bill_address_id: nil)
    end

    result = described_class.call(order: bare.reload, now: now)

    expect(result.value[:decision]).to eq('allow')
    expect(result.value[:signals]['insufficient_subject']).to be(true)
    expect(result.value[:signals]['subject_count']).to eq(0)
  end

  # AC-005（留痕幂等：重复投递复用；决策变化或窗口之外才新增）
  it 'reuses the assessment for repeat deliveries and records a new row when things change' do
    first = described_class.call(order: order.reload, now: now)
    second = described_class.call(order: order.reload, now: now)
    later = described_class.call(order: order.reload, now: now + 1.minute)

    expect(second.value[:assessment].id).to eq(first.value[:assessment].id)
    expect(later.value[:assessment].id).to eq(first.value[:assessment].id)
    expect(PallasTrade::PaymentRiskAssessment.where(order_id: order.id).count).to eq(1)

    # 命中集变化（新增黑名单）→ 新决策 → 新留痕行
    upsert(list_type: 'denylist', subject_type: 'email', value: "d15-assess-#{suffix}@example.com")
    changed = described_class.call(order: order.reload, now: now + 2.minutes)
    expect(changed.value[:decision]).to eq('review')
    expect(changed.value[:assessment].id).not_to eq(first.value[:assessment].id)
    expect(PallasTrade::PaymentRiskAssessment.where(order_id: order.id).count).to eq(2)

    # 窗口之外的同决策（真正的再次评估）→ 仍然新留痕，审计不丢
    # 注意：唯一键 (order_id, evaluated_at) 仍在，回推时间时必须逐行错开
    PallasTrade::PaymentRiskAssessment.where(order_id: order.id).order(:id).each_with_index do |row, index|
      row.update_columns(evaluated_at: (2.hours + index.minutes).ago)
    end
    replay = described_class.call(order: order.reload, now: now + 3.minutes)
    expect(replay.value[:assessment].id).not_to eq(changed.value[:assessment].id)
    expect(PallasTrade::PaymentRiskAssessment.where(order_id: order.id).count).to eq(3)
  end

  # AC-007
  it 'never applies one store list to another store order' do
    theirs = other_store
    PallasTrade::Risk::Lists::Upsert.call(list_type: 'denylist', subject_type: 'email',
                                          value: "d15-assess-#{suffix}@example.com", store: theirs, actor: 'system')

    mine = described_class.call(order: order.reload, now: now)
    expect(mine.value[:decision]).to eq('allow')

    global = PallasTrade::Risk::Lists::Upsert.call(list_type: 'denylist', subject_type: 'email',
                                                   value: "d15-assess-#{suffix}@example.com", store: nil, actor: 'system')
    expect(global).to be_success

    after_global = described_class.call(order: order.reload, now: now + 1.minute)
    expect(after_global.value[:decision]).to eq('review')
  end

  # AC-010
  it 'touches no money, order state or inventory' do
    upsert(list_type: 'denylist', subject_type: 'email', value: "d15-assess-#{suffix}@example.com")
    order.reload
    before = {
      payments: PallasTrade::Payment.count, refunds: PallasTrade::Refund.count,
      ledger: PallasTrade::FinancialLedgerEntry.count, orders: PallasTrade::Order.count,
      inventory: PallasTrade::InventoryUnit.count,
      state: order.state, total: order.total.to_d, considered_risky: order.considered_risky
    }

    described_class.call(order: order.reload, now: now)

    order.reload
    expect(PallasTrade::Payment.count).to eq(before[:payments])
    expect(PallasTrade::Refund.count).to eq(before[:refunds])
    expect(PallasTrade::FinancialLedgerEntry.count).to eq(before[:ledger])
    expect(PallasTrade::Order.count).to eq(before[:orders])
    expect(PallasTrade::InventoryUnit.count).to eq(before[:inventory])
    expect(order.total.to_d).to eq(before[:total])
    expect(order.state).to eq(before[:state])
    # 评估本身**只留痕**，不改订单标记（标记由订阅者决定）
    expect(order.considered_risky).to eq(before[:considered_risky])
  end
end
