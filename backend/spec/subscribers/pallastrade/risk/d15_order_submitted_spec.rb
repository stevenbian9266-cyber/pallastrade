# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d15-risk-lists（D15 切片1，订阅者接线）
#   AC-006 ← FR-006：order.submitted → 评估 → 命中则复用既有 `considered_risky` 标记；
#            未命中零改动；已审批订单不重复标记；异常不阻断；payload 三种形态兼容。
RSpec.describe PallasTrade::Risk::OrderSubmittedSubscriber, type: :subscriber do
  let(:store) { @default_store }
  let(:suffix) { SecureRandom.hex(4) }
  let(:subscriber) { described_class.new }
  let(:order) do
    create(:order_with_line_items, store: store).tap do |o|
      o.update_columns(email: "d15-sub-#{suffix}@example.com", last_ip_address: '203.0.113.9',
                       considered_risky: false, approved_at: nil)
    end
  end

  def event(payload)
    Struct.new(:name, :payload).new('order.submitted', payload)
  end

  def deny_email!
    PallasTrade::Risk::Lists::Upsert.call(list_type: 'denylist', subject_type: 'email',
                                          value: "d15-sub-#{suffix}@example.com", store: store, actor: 'system')
  end

  # AC-006
  it 'flags an order whose subject is on the denylist' do
    deny_email!
    subscriber.handle(event({ 'order_id' => order.prefixed_id }))

    expect(order.reload.considered_risky).to be(true)
    expect(PallasTrade::PaymentRiskAssessment.where(order_id: order.id).count).to eq(1)
    expect(PallasTrade::AuditLog.where(action: 'risk_order_flagged').where(resource_id: order.id).count).to eq(1)
  end

  # AC-006（payload 三种形态）
  it 'accepts the nested payload shape the cart publishes today' do
    deny_email!
    subscriber.handle(event({ 'payload' => { 'order_id' => order.prefixed_id } }))

    expect(order.reload.considered_risky).to be(true)
  end

  it 'accepts a raw id payload' do
    deny_email!
    subscriber.handle(event({ 'id' => order.id }))

    expect(order.reload.considered_risky).to be(true)
  end

  # AC-006（未命中 / 白名单 → 零改动）
  it 'leaves the order untouched when the assessment allows it' do
    allowlist = PallasTrade::Risk::Lists::Upsert.call(list_type: 'allowlist', subject_type: 'email',
                                                      value: "d15-sub-#{suffix}@example.com", store: store, actor: 'system')
    deny_email!
    expect(allowlist).to be_success

    subscriber.handle(event({ 'order_id' => order.prefixed_id }))

    expect(order.reload.considered_risky).to be(false)
    expect(PallasTrade::AuditLog.where(action: 'risk_order_flagged').where(resource_id: order.id).count).to eq(0)
    expect(PallasTrade::PaymentRiskAssessment.where(order_id: order.id).count).to eq(1)
  end

  # AC-006（已审批订单不重复标记）
  it 'never re-flags an approved order' do
    deny_email!
    order.update_columns(approved_at: Time.current, considered_risky: false)

    subscriber.handle(event({ 'order_id' => order.prefixed_id }))

    expect(order.reload.considered_risky).to be(false)
  end

  # AC-006（健壮性：不阻断、不抛）
  it 'swallows bad payloads and unknown orders without raising' do
    expect { subscriber.handle(event({})) }.not_to raise_error
    expect { subscriber.handle(event({ 'order_id' => 'or_missing_000' })) }.not_to raise_error
    expect { subscriber.handle(event({ 'order_id' => 'not-a-prefixed-id' })) }.not_to raise_error
    expect(PallasTrade::PaymentRiskAssessment.count).to eq(0)
  end

  # AC-006（重复投递幂等）
  it 'does not create a second assessment when the event is delivered twice' do
    deny_email!
    payload = { 'order_id' => order.prefixed_id }

    subscriber.handle(event(payload))
    subscriber.handle(event(payload))

    expect(PallasTrade::PaymentRiskAssessment.where(order_id: order.id).count).to eq(1)
    expect(order.reload.considered_risky).to be(true)
  end
end
