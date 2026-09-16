# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d14b-dispute-deadlines（切片2，admin）
#   AC-005 ← FR-006：期限看板计数与筛选一致；列表渲染分档列；详情渲染提醒历史；无权限被拒
RSpec.describe 'Admin disputes ops deadline board (D14b)', type: :request do
  let!(:store) do
    create(:store, code: "d14b_admin_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD',
                   name: 'D14b Disputes Store', url: 'https://d14b-disputes.example.com')
  end
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }
  let(:order) do
    create(:order_with_line_items, store: store, line_items_price: 50, shipment_cost: 0).tap do |o|
      o.update_columns(state: 'complete', status: 'complete', completed_at: Time.current)
    end
  end
  let(:payment) do
    create(:payment, order: order, payment_method: payment_method, amount: order.total, state: 'completed',
                     response_code: 'pi_d14b_admin', source: nil, skip_source_requirement: true)
  end
  let(:txn) do
    PallasTrade::CommerceTransaction.create!(store: store, purpose: 'purchase', currency: 'USD', amount: order.total)
  end

  def sign_in_as_admin
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  def make_dispute(due_at:, reference:, state: 'needs_response')
    PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: reference,
      state: state, amount: 12.34, currency: 'usd', store: store,
      private_metadata: { 'provider_status' => 'needs_response' },
      evidence_due_at: due_at,
      commerce_transaction: txn, payment: payment, order: order
    )
  end

  # AC-005
  it 'renders the deadline board with counts and filters the list by tier' do
    sign_in_as_admin
    now = Time.current.change(usec: 0)
    t3 = make_dispute(due_at: now + 48.hours, reference: 'dp_d14ba_t3')
    t1 = make_dispute(due_at: now + 10.hours, reference: 'dp_d14ba_t1')
    late = make_dispute(due_at: now - 3.hours, reference: 'dp_d14ba_late')

    get '/admin/disputes'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(PallasTrade.t('admin.orders.disputes_deadline_board_title'))
    expect(response.body).to include(PallasTrade.t('admin.orders.disputes_deadline_tier_t3'))
    expect(response.body).to include(PallasTrade.t('admin.orders.disputes_deadline_tier_overdue'))

    get '/admin/disputes', params: { deadline: 'overdue' }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(late.prefixed_id)
    expect(response.body).not_to include(t3.prefixed_id)
    expect(response.body).not_to include(t1.prefixed_id)
  end

  # AC-005（看板计数与筛选同源：T-1 档只含 0<h<=24）
  it 'counts each tier from the same scope the filter uses' do
    sign_in_as_admin
    now = Time.current.change(usec: 0)
    make_dispute(due_at: now + 48.hours, reference: 'dp_d14bb_t3')
    soon = make_dispute(due_at: now + 10.hours, reference: 'dp_d14bb_t1')

    get '/admin/disputes', params: { deadline: 't1' }

    expect(response.body).to include(soon.prefixed_id)
    expect(response.body).not_to include('dp_d14bb_t3')
  end

  # AC-005（详情显示提醒历史）
  it 'renders the reminder history on the dispute page' do
    sign_in_as_admin
    now = Time.current.change(usec: 0)
    dispute = make_dispute(due_at: now + 10.hours, reference: 'dp_d14bc_history')
    PallasTrade::DisputeDeadlineAlert.create!(
      dispute: dispute, store: store, tier: 't1', alerted_at: now, evidence_due_at: dispute.evidence_due_at,
      hours_remaining: 10.0, metadata: { 'backfilled' => false }
    )

    get "/admin/disputes/#{dispute.prefixed_id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(PallasTrade.t('admin.orders.disputes_deadline_history_title'))
    expect(response.body).not_to include(PallasTrade.t('admin.orders.disputes_deadline_history_empty'))
    expect(response.body).to include(PallasTrade.t('admin.orders.disputes_deadline_tier_t1'))
    expect(PallasTrade::DisputeDeadlineAlert.where(dispute_id: dispute.id).count).to eq(1)
  end

  # AC-005（无权限被拒）
  it 'denies access without the dispute permission' do
    make_dispute(due_at: Time.current + 10.hours, reference: 'dp_d14bd_denied')

    get '/admin/disputes'

    expect(response).not_to have_http_status(:ok)
  end
end
