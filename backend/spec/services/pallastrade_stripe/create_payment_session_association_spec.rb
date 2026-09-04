# frozen_string_literal: true

require 'spec_helper'

# P0-1 (2026-09-02)：cs_ Checkout Session 模式 → Payment 创建时
# payment_session_id 必须指向 originating session（不依赖 response_code == external_id）。
RSpec.describe 'Stripe CreatePayment cs_ session association', type: :service do
  let(:store) { @default_store }
  let(:user) { create(:user) }
  let(:order) do
    create(:order, store: store, user: user, state: 'pending', status: 'placed',
                   submitted_at: Time.current, item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end
  let(:gateway) { create(:stripe_gateway, store: store, active: true) }
  let(:session) do
    PallasTrade::PaymentSessions::Stripe.new(
      order: order,
      payment_method: gateway,
      amount: 100,
      currency: 'USD',
      status: 'pending',
      external_id: 'cs_test_checkout_session_123',
      external_data: { 'client_secret' => 'cs_test_secret' }
    ).tap(&:save!)
  end

  # cs_ 模式下底层 PaymentIntent 是 pi_；session.external_id 是 cs_（二者不同）
  let(:fake_intent) do
    Struct.new(:id, :payment_method).new('pi_test_underlying_456',
                                         Struct.new(:id).new('pm_test_card_123'))
  end

  let!(:credit_card) do
    create(:credit_card, user: user, payment_method: gateway,
                         gateway_payment_profile_id: 'pm_test_card_123')
  end

  before do
    # Payment#after_save :create_payment_profile 会触发真实 Stripe Customer API；
    # 本测试只验证 FK 关联，stub 该方法避免任何网络。
    allow_any_instance_of(PallasTrade::Payment).to receive(:create_payment_profile)
    # CreatePayment 内不触发网络：直接 stub session 的 duck-type 接口
    allow(session).to receive(:stripe_payment_intent).and_return(fake_intent)
    allow(session).to receive(:stripe_charge).and_return(nil)
    allow(session).to receive(:charge_not_required?).and_return(true)
    # stub CreateSource：返回已建 credit_card，避免构造完整 Stripe charge 细节
    allow(PallasTradeStripe::CreateSource).to receive(:new)
      .and_return(instance_double(PallasTradeStripe::CreateSource, call: credit_card))
  end

  it 'creates the Payment with payment_session_id pointing to the cs_ session and response_code = pi_' do
    payment = PallasTradeStripe::CreatePayment.new(
      order: order,
      payment_intent: session,
      gateway: gateway,
      amount: 100
    ).call

    expect(payment.payment_session_id).to eq(session.id)
    expect(payment.response_code).to eq('pi_test_underlying_456')
    expect(payment.response_code).not_to eq(session.external_id)
    expect(session.reload.payment).to eq(payment)
    # 业务不变量：重复调用复用同一 Payment（不重复建）
    again = PallasTradeStripe::CreatePayment.new(
      order: order,
      payment_intent: session,
      gateway: gateway,
      amount: 100
    ).call
    expect(again.id).to eq(payment.id)
    expect(order.payments.count).to eq(1)
  end
end
