# frozen_string_literal: true

require 'spec_helper'

# PRD-REV-P6-4 AC-R64-06 —— PATCH /api/v3/admin/orders/:id/cancel 决策参数透传
# refund_payments：缺省=auto（PAID 默认退款，兼容旧行为）/ false=显式不退款；
# 响应序列化订单状态（state=canceled）。
RSpec.describe '/api/v3/admin/orders/:id/cancel', type: :request do
  include_context 'API v3 Admin authenticated'

  let(:store) { @default_store }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                   item_total: 100, total: 100, payment_state: 'paid')
  end
  let!(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: 100,
                     state: 'completed', source: nil, skip_source_requirement: true)
  end

  before do
    # REV-P6-4：Orchestrator 在事务提交后 enqueue ExecuteJob（真实 Sidekiq adapter）
    allow(PallasTrade::Refunds::ExecuteJob).to receive(:perform_later).and_return(true)
  end

  def patch_cancel(params = {})
    patch "/api/v3/admin/orders/#{order.prefixed_id}/cancel",
          params: params, headers: headers
  end

  it 'AC-R64-06: 缺省参数（auto）→ 201/200 canceled + durable requested Refund（兼容旧语义）' do
    patch_cancel

    expect(response).to have_http_status(:ok)
    expect(order.reload.state).to eq('canceled')
    refund = PallasTrade::Refund.find_by(payment_id: payment.id)
    expect(refund).to be_present
    expect(refund.state).to eq('requested')
    expect(refund.amount.to_f).to eq(100.0)
    expect(order.reload.cancellations.last.refund_payments).to be(true)
  end

  it 'AC-R64-06: refund_payments=false → canceled + 无 Refund（payment 保持 completed）' do
    patch_cancel(refund_payments: 'false')

    expect(response).to have_http_status(:ok)
    expect(order.reload.state).to eq('canceled')
    expect(payment.reload).to be_completed
    expect(PallasTrade::Refund.where(payment_id: payment.id)).to be_empty
    expect(order.reload.cancellations.last.refund_payments).to be(false)
  end

  it 'AC-R64-06: refund_amount 透传 → requested Refund.amount = 指定值' do
    patch_cancel(refund_amount: '40')

    expect(response).to have_http_status(:ok)
    expect(order.reload.state).to eq('canceled')
    refund = PallasTrade::Refund.find_by(payment_id: payment.id)
    expect(refund).to be_present
    expect(refund.amount.to_f).to eq(40.0)
  end
end
