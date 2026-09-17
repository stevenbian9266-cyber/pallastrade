# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-checkout-d15-切片3（D15 切片3，前台契约）
#   AC-011 ← FR-005：checkout 投影暴露 `requires_authentication`；列表仍只含可用入口
#                    （隐藏 = 不出现 —— 前端零筛选逻辑）
RSpec.describe 'Order checkout authentication flag (Store API)', type: :request do
  include_context 'API v3 Store authenticated'

  def submitted_order(owner: user)
    order = create(:order_with_line_items, store: store, user: owner,
                                           line_items_price: 100, shipment_cost: 0)
    order.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current,
                         completed_at: nil, payment_state: 'balance_due', payment_total: 0)
    PallasTrade::OrderUpdater.new(order).update
    order.reload
  end

  def provider(kinds: %w[card apple_pay])
    create(:stripe_gateway, store: store, active: true, display_on: 'front_end',
                            name: "D15c api #{SecureRandom.hex(3)}",
                            metadata: {
                              'optionized' => true,
                              'options' => kinds.each_with_index.map do |kind, index|
                                { 'kind' => kind, 'active' => true, 'position' => index + 1 }
                              end
                            })
  end

  def require_authentication!(order)
    # ⚠️ `store` 来自 `@default_store`（跨 example 共享的同一 Ruby 对象，事务回滚不会把它
    #   在内存里的值一并回滚）→ 必须先 `reload`，否则「写入值 == 内存里的旧值」会被 AR 判为
    #   无变化而**不发 UPDATE**，DB 保持空，后一个 example 会凭空看到未配置策略。
    store.reload
    store.update!(private_metadata: (store.private_metadata || {}).merge(
      PallasTrade::Payments::ThreeDSecure::Policy::STORE_METADATA_KEY => { 'mode' => 'always' }
    ))
    order.reload
    PallasTrade::Payments::ThreeDSecure::Required.reset_cache_for(order)
  end

  def payment_methods_for(order)
    get "/api/v3/store/orders/#{order.prefixed_id}/checkout", headers: headers
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body).dig('payment', 'available_payment_methods')
  end

  # AC-011（不要求认证：仍列出全部入口，flag 为 false）
  it 'exposes requires_authentication=false and the full set of entries by default' do
    order = submitted_order
    provider(kinds: %w[card apple_pay])

    methods = payment_methods_for(order)

    expect(methods.size).to eq(1)
    expect(methods.first['requires_authentication']).to be(false)
    expect(methods.first['method_key']).to eq('card')
  end

  # AC-011（要求认证：flag 为 true，且只剩可认证入口）
  it 'exposes requires_authentication=true and only the capable entries' do
    order = submitted_order
    provider(kinds: %w[card apple_pay])
    require_authentication!(order)

    methods = payment_methods_for(order)

    expect(methods.size).to eq(1)
    expect(methods.first['requires_authentication']).to be(true)
    expect(methods.first['method_key']).to eq('card')
  end

  # AC-011（全部入口都不可认证 → 列表为空 + flag 为 true：前端据此提示，而不是静默空白）
  it 'returns an empty list with the flag set when no entry can authenticate' do
    order = submitted_order
    provider(kinds: %w[apple_pay])
    require_authentication!(order)

    expect(payment_methods_for(order)).to eq([])
  end
end
