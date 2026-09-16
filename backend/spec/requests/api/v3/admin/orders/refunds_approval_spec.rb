# frozen_string_literal: true

require 'spec_helper'

# PRD-20260916-payments-d14-refund-approval（切片1，Admin API）
#   AC-007 ← FR-006：退款创建走策略门（超阈值 → 201 + approval_status=pending 且不入队执行）；
#            阈值内 → 入队执行 + approval_status=null；request_key 幂等复用既有退款。
RSpec.describe '/api/v3/admin/orders/:order_id/refunds (D14 approval gate)', type: :request do
  include_context 'API v3 Admin authenticated'

  let(:store) { @default_store }
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

  def enable_policy(limit:, currency: nil)
    store.update_columns(private_metadata: (store.private_metadata || {}).merge(
      'refund_policy' => { 'enabled' => true, 'auto_approve_limit' => limit.to_s, 'currency' => currency }
    ))
    store.reload
  end

  before do
    # 入队由 ExecuteJob 承担（异步契约）；本 spec 只断言「是否入队」
    allow(PallasTrade::Refunds::ExecuteJob).to receive(:perform_later).and_return(true)
    order.update_columns(payment_state: 'paid', state: 'complete', completed_at: Time.current)
  end

  # PRD-20260916-payments-d14-refund-approval AC-007
  it 'queues execution and reports no approval when the policy is off' do
    post_refund

    expect(response).to have_http_status(:created)
    body = json_response
    expect(body[:state]).to eq('requested')
    expect(body).to have_key(:approval_status)
    expect(body[:approval_status]).to be_nil
    expect(PallasTrade::Refunds::ExecuteJob).to have_received(:perform_later).once
  end

  # PRD-20260916-payments-d14-refund-approval AC-007
  it 'holds a refund above the limit: pending approval, no execution' do
    enable_policy(limit: 10, currency: 'USD')

    post_refund(amount: '60')

    expect(response).to have_http_status(:created)
    body = json_response
    expect(body[:state]).to eq('requested')
    expect(body[:approval_status]).to eq('pending')
    expect(PallasTrade::Refunds::ExecuteJob).not_to have_received(:perform_later)

    approval = PallasTrade::RefundApproval.sole
    expect(approval.status).to eq('pending')
    expect(approval.store_id).to eq(store.id)
    expect(approval.amount.to_d).to eq(60.to_d)
  end

  # PRD-20260916-payments-d14-refund-approval AC-007（阈值内）
  it 'executes a refund at or below the limit and audits the auto approval' do
    enable_policy(limit: 60, currency: 'USD')

    post_refund(amount: '60')

    expect(response).to have_http_status(:created)
    expect(json_response[:approval_status]).to be_nil
    expect(PallasTrade::Refunds::ExecuteJob).to have_received(:perform_later).once
    expect(PallasTrade::AuditLog.find_by(action: 'refund_auto_approved')).to be_present
  end

  # PRD-20260916-payments-d14-refund-approval AC-005（API 幂等键）
  it 'reuses the same refund for a repeated request_key' do
    enable_policy(limit: 10)

    expect do
      post_refund(amount: '60', request_key: 'rk_d14_api')
      expect(response).to have_http_status(:created)
    end.to change(PallasTrade::Refund, :count).by(1)

    first_id = json_response[:id]

    expect do
      post_refund(amount: '60', request_key: 'rk_d14_api')
      expect(response).to have_http_status(:created)
    end.not_to change(PallasTrade::Refund, :count)

    expect(json_response[:id]).to eq(first_id)
    expect(PallasTrade::RefundApproval.count).to eq(1)
  end
end
