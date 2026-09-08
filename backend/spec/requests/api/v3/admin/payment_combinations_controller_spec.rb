# frozen_string_literal: true

require 'spec_helper'

# PRD-20260908-payments-rev-p6-8f-combination-level-cancel-orchestration AC-R68F-07
# POST /api/v3/admin/payment_combinations/:id/cancel —— 组合级取消编排端点：
#  succeeded 组合 → 200 {data} 聚合；current_store 作用域（跨店 → 404）；非 succeeded → 422；
#  成员子集 member_ids 只取消指定成员。响应不暴露原始整型 PK（只回 prefixed id + 单号）。
RSpec.describe '/api/v3/admin/payment_combinations/:id/cancel', type: :request do
  include_context 'API v3 Admin authenticated'

  let(:store) { @default_store }
  let(:user) { create(:user) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:combination) do
    create(:payment_combination, store: store, customer: user, amount: 20.0, status: 'succeeded')
  end
  let!(:combo_payment) do
    create(:payment, order: nil, payment_combination: combination, payment_method: payment_method,
                     amount: 20, state: 'completed', source: nil, skip_source_requirement: true)
  end

  let(:member_a) do
    create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                   item_total: 10, total: 10, payment_state: 'paid', payment_total: 10,
                   currency: store.default_currency, email: 'cana@example.com')
  end
  let(:member_b) do
    create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                   item_total: 10, total: 10, payment_state: 'paid', payment_total: 10,
                   currency: store.default_currency, email: 'canb@example.com')
  end

  before do
    allow(PallasTrade::Refunds::ExecuteJob).to receive(:perform_later).and_return(true)
    create(:payment_split, payment_combination: combination, order: member_a, payment: combo_payment,
                           authorized_amount: 10, captured_amount: 10, refunded_amount: 0)
    create(:payment_split, payment_combination: combination, order: member_b, payment: combo_payment,
                           authorized_amount: 10, captured_amount: 10, refunded_amount: 0)
  end

  def post_cancel(combination:, params: {})
    post "/api/v3/admin/payment_combinations/#{combination.prefixed_id}/cancel",
         params: params, headers: headers
  end

  it 'AC-R68F-07: succeeded 组合全组取消 → 200 {data} 聚合（prefixed id，无整型 PK）' do
    post_cancel(combination: combination, params: { reason: 'staff' })

    expect(response).to have_http_status(:ok)
    data = json_response[:data]
    expect(data[:id]).to eq(combination.prefixed_id)
    expect(data[:type]).to eq('payment_combination')
    attrs = data[:attributes]
    expect(attrs[:status]).to eq('succeeded')
    expect(attrs[:members]).to eq('total' => 2, 'canceled' => 2, 'skipped' => 0, 'failed' => 0)
    expect(attrs[:canceled].map { |m| m[:order_id] }).to contain_exactly(member_a.prefixed_id, member_b.prefixed_id)
    # 无原始整型 PK 泄漏
    expect(json_response.to_s).not_to include("\"#{member_a.id}\"")
    expect(member_a.reload.state).to eq('canceled')
    expect(member_b.reload.state).to eq('canceled')
  end

  it 'AC-R68F-07: member_ids 子集 → 只取消指定成员' do
    post_cancel(combination: combination, params: { member_ids: [member_a.prefixed_id] })

    expect(response).to have_http_status(:ok)
    attrs = json_response[:data][:attributes]
    expect(attrs[:members]).to eq('total' => 1, 'canceled' => 1, 'skipped' => 0, 'failed' => 0)
    expect(member_a.reload.state).to eq('canceled')
    expect(member_b.reload.state).to eq('pending')
  end

  it 'AC-R68F-07: 非 succeeded 组合 → 422' do
    pending_combo = create(:payment_combination, store: store, customer: user, amount: 10.0, status: 'pending')

    post_cancel(combination: pending_combo, params: { reason: 'staff' })

    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'AC-R68F-07: 跨 store 组合（current_store 作用域外）→ 404' do
    other_store = create(:store, code: "other_combo_#{SecureRandom.hex(4)}")
    other_combo = create(:payment_combination, store: other_store, amount: 10.0, status: 'succeeded')

    post_cancel(combination: other_combo)

    expect(response).to have_http_status(:not_found)
  end

  it 'AC-R68F-07: 不存在的组合 → 404' do
    post '/api/v3/admin/payment_combinations/pcom_nonexistent0000/cancel', params: {}, headers: headers

    expect(response).to have_http_status(:not_found)
  end
end
