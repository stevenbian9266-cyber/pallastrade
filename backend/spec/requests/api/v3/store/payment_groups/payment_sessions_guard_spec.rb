require 'rails_helper'

# PRD-20260824-checkout-正向订单-逆向订单链路重构或优化
# AC-002/004 — 下单前置校验服务端强制执行：黑名单用户创建支付会话被拦截
RSpec.describe 'POST /api/v3/store/payment_groups/:id/payment_sessions — checkout guard', type: :request do
  include_context 'API v3 Store authenticated'

  let(:store) { @default_store }
  let(:path) { "/api/v3/store/payment_groups/#{payment_group.prefixed_id}/payment_sessions" }

  let!(:unpaid_order) do
    create(:order_with_line_items, store: store, user: user, currency: 'USD',
                                   status: 'placed', payment_state: 'balance_due', completed_at: nil)
  end
  let!(:payment_group) { create(:payment_group, store: store, customer: user) }
  let!(:stripe_gateway) { create(:stripe_gateway, store: store) }

  before do
    unpaid_order.update_column(:payment_group_id, payment_group.id)
    # 测试环境无有效 Stripe key：stub 网关网络调用
    allow_any_instance_of(PallasTradeStripe::Gateway).to receive(:register_domain).and_return(true)
    allow_any_instance_of(PallasTradeStripe::Gateway).to receive(:fetch_or_create_customer).and_return(nil)
  end

  it 'AC-002: 黑名单用户创建支付会话被拦截（403 + code）' do
    user.update_column(:blacklisted_at, Time.current)
    expect(user).to be_blacklisted

    post path, params: { payment_method_id: stripe_gateway.prefixed_id }, headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(json_response.dig('error', 'code')).to eq('user_blacklisted')
    expect(json_response.dig('error', 'message')).to be_present
  end

  it 'AC-004: 正常用户通过前置校验（不返回 403，进入支付方式处理）' do
    # stub 支付方式创建，避免真实 Stripe 调用（测试环境无有效 key）
    fake_session = create(:stripe_payment_session,
                          order: unpaid_order, payment_group: payment_group,
                          payment_method: stripe_gateway, amount: unpaid_order.total, currency: 'USD')
    allow_any_instance_of(PallasTradeStripe::Gateway)
      .to receive(:create_payment_session).and_return(fake_session)

    post path, params: { payment_method_id: stripe_gateway.prefixed_id }, headers: headers
    expect(response).not_to have_http_status(:forbidden)
    expect(response).to have_http_status(:created)
  end
end
