# frozen_string_literal: true

require 'rails_helper'

# PRD-20260915-payments-d12-webhook-governance（切片3，admin）
#   AC-007 ← FR-007：事件流 index（筛选/分页/健康/清单）与详情 show 可访问；三个处置动作可用；
#                    动作写审计；导航子项与 tabs 一致（navigation_consistency 回归另行覆盖）
RSpec.describe 'Admin webhook events (D12)', type: :request do
  let!(:store) do
    create(:store, code: "d12_admin_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD', name: 'D12 Store')
  end
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true, display_on: 'both') }

  def sign_in_as_admin
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  def build_event(provider_event_id: 'evt_admin', action: 'captured', **attrs)
    PallasTrade::PaymentWebhookEvent.create_unique(
      provider: 'stripe', provider_event_id: provider_event_id,
      payment_method_id: payment_method.id, action: action, **attrs
    ).first
  end

  # PRD-20260915-payments-d12-webhook-governance AC-007
  it 'renders the event stream with health and checklist blocks' do
    sign_in_as_admin
    event = build_event(provider_event_id: 'evt_index')

    get '/admin/webhook_events'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(PallasTrade.t('admin.webhook_events.title'))
    expect(response.body).to include(PallasTrade.t('admin.webhook_events.health_inbound'))
    expect(response.body).to include(PallasTrade.t('admin.webhook_events.checklist_heading'))
    expect(response.body).to include(PallasTrade.admin_webhook_event_path(event))
  end

  # PRD-20260915-payments-d12-webhook-governance AC-007
  it 'filters the stream by provider, action and status' do
    sign_in_as_admin
    kept = build_event(provider_event_id: 'evt_kept', action: 'captured')
    build_event(provider_event_id: 'evt_failed', action: 'failed')

    get '/admin/webhook_events', params: { provider: 'stripe', event_action: 'captured', status: 'received' }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(PallasTrade.admin_webhook_event_path(kept))
    expect(response.body).not_to include("/admin/webhook_events/#{PallasTrade::PaymentWebhookEvent.find_by(provider_event_id: 'evt_failed').id}\"")
  end

  # PRD-20260915-payments-d12-webhook-governance AC-007
  it 'renders the detail page with payload, order link and audit trail' do
    sign_in_as_admin
    order = create(:order_with_line_items, store: store)
    session = create(:bogus_payment_session, order: order)
    event = build_event(provider_event_id: 'evt_show', payment_session_id: session.id,
                        payload: { 'id' => 'evt_show', 'type' => 'payment_intent.succeeded' })

    get "/admin/webhook_events/#{event.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('payment_intent.succeeded')
    expect(response.body).to include(order.number)
    expect(response.body).to include(PallasTrade.t('admin.webhook_events.actions_heading'))
  end

  # PRD-20260915-payments-d12-webhook-governance AC-007
  it 'quarantines an event with a reason and audits the action' do
    sign_in_as_admin
    event = build_event(provider_event_id: 'evt_quarantine')

    post "/admin/webhook_events/#{event.id}/quarantine", params: { reason: 'unknown event type' }

    expect(response).to have_http_status(:found)
    expect(event.reload.status).to eq('quarantined')
    expect(PallasTrade::AuditLog.where(action: 'webhook_quarantine').count).to eq(1)
  end

  # PRD-20260915-payments-d12-webhook-governance AC-007
  it 'marks an event processed without replaying it' do
    sign_in_as_admin
    event = build_event(provider_event_id: 'evt_mark')
    event.mark_failed!(StandardError.new('boom'))

    post "/admin/webhook_events/#{event.id}/mark_processed", params: { note: 'verified in provider dashboard' }

    expect(response).to have_http_status(:found)
    expect(event.reload.status).to eq('processed')
    expect(PallasTrade::AuditLog.where(action: 'webhook_mark_processed').count).to eq(1)
  end

  # PRD-20260915-payments-d12-webhook-governance AC-007
  it 'replays a failed event (audited) and refuses to replay a quarantined one' do
    sign_in_as_admin
    event = build_event(provider_event_id: 'evt_replay')
    event.mark_failed!(StandardError.new('boom'))

    post "/admin/webhook_events/#{event.id}/replay"

    expect(response).to have_http_status(:found)
    audit = PallasTrade::AuditLog.where(action: 'webhook_replay').last
    expect(audit).to be_present
    expect(audit.resource_id).to eq(event.id)

    # 隔离事件不可重放（服务层守卫 + 页面不显示按钮）
    event.mark_quarantined!(reason: 'triage')
    post "/admin/webhook_events/#{event.id}/replay"

    expect(response).to have_http_status(:found)
    expect(PallasTrade::AuditLog.where(action: 'webhook_replay').count).to eq(1)
    expect(flash[:error]).to be_present
  end

  # PRD-20260915-payments-d12-webhook-governance AC-007
  it 'denies access to an admin without the webhook permission' do
    sign_in create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)

    get '/admin/webhook_events'

    expect(response.status).to be_in([302, 303, 403])
  end
end
