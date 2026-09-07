# frozen_string_literal: true

require 'spec_helper'

# PRD-REV-P6-3 FR-R63-101 —— POST /api/v3/admin/orders/:order_id/refunds 可选冻结参数
# payment_split_id / target_order_id：创建即冻结 ownership；split 归属不匹配 → 422；
# target 非本单/本组合 → 422；响应（admin serializer）暴露 payment_split_id / target_order_id。
RSpec.describe '/api/v3/admin/orders/:order_id/refunds', type: :request do
  include_context 'API v3 Admin authenticated'

  let(:store) { @default_store }
  let(:user) { create(:user) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:order) do
    create(:order, store: store, state: 'complete', completed_at: Time.current,
                   item_total: 100, total: 100, payment_state: 'paid')
  end
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: 100,
                     state: 'completed', source: nil, skip_source_requirement: true)
  end
  let(:reason) { create(:refund_reason) }

  def post_refund(params = {})
    post "/api/v3/admin/orders/#{order.prefixed_id}/refunds",
         params: { payment_id: payment.prefixed_id,
                   refund_reason_id: reason.prefixed_id,
                   amount: '60' }.merge(params),
         headers: headers
  end

  before do
    # REV-P6-2 async 契约：入队由 ExecuteJob 承担，不出现在请求断言里（真实 Sidekiq adapter）
    allow(PallasTrade::Refunds::ExecuteJob).to receive(:perform_later).and_return(true)
    order.update_columns(payment_state: 'paid', state: 'complete', completed_at: Time.current)
  end

  it 'FR-R63-101: 不带冻结参数 → 201 requested，冻结字段为 null（向后兼容）' do
    post_refund

    expect(response).to have_http_status(:created)
    body = json_response
    expect(body[:state]).to eq('requested')
    # admin 端点序列化为扁平 JSON（顶层属性）——冻结列已暴露
    expect(body).to have_key(:payment_split_id)
    expect(body).to have_key(:target_order_id)
    expect(body[:payment_split_id]).to be_nil
    # 未显式冻结时 target_order 列本身为 nil（只回显冻结列，不做链推导）
    expect(body[:target_order_id]).to be_nil
  end

  it 'FR-R63-101: target_order_id = 本单 → 冻结 target_order 并回显' do
    post_refund(target_order_id: order.prefixed_id)

    expect(response).to have_http_status(:created)
    refund = PallasTrade::Refund.last
    expect(refund.target_order).to eq(order)
    expect(json_response[:target_order_id]).to eq(order.prefixed_id)
  end

  it 'FR-R63-101: 跨 store 的 target_order_id → 422，不创建' do
    other_store = create(:store, code: "other_#{SecureRandom.hex(4)}")
    other_order = create(:order, store: other_store)

    expect { post_refund(target_order_id: other_order.prefixed_id) }
      .not_to change(PallasTrade::Refund, :count)

    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'FR-R63-101: payment_split_id 不属于该 payment → 422，不创建' do
    other_order = create(:order, store: store, state: 'complete', completed_at: Time.current,
                                 item_total: 50, total: 50, payment_state: 'paid')
    other_payment = create(:payment, order: other_order, payment_method: payment_method, amount: 50,
                                     state: 'completed', source: nil, skip_source_requirement: true)
    combo = create(:payment_combination, store: store, customer: user, amount: 50)
    foreign_split = create(:payment_split, payment_combination: combo, order: other_order,
                                           payment: other_payment,
                                           authorized_amount: 50, captured_amount: 50)

    expect { post_refund(payment_split_id: foreign_split.prefixed_id) }
      .not_to change(PallasTrade::Refund, :count)

    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'FR-R63-101: 冻结 split 金额超 split 上限 → 422（创建期校验，AC-6011）' do
    combo = create(:payment_combination, store: store, customer: user, amount: 50)
    split = create(:payment_split, payment_combination: combo, order: order, payment: payment,
                                   authorized_amount: 50, captured_amount: 50)
    # payment 全局 capacity 充足（100），但冻结 split 上限 50 → 60 被拒
    expect(PallasTrade::Refunds::ExecuteJob).not_to receive(:perform_later)

    expect { post_refund(payment_split_id: split.prefixed_id, amount: '60') }
      .not_to change(PallasTrade::Refund, :count)

    expect(response).to have_http_status(:unprocessable_content)
  end
end
