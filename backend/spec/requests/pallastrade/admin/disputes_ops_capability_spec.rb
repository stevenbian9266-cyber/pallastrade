# frozen_string_literal: true

require 'rails_helper'

# PRD-20260913-payments-dsp-p7-9-partial-and-multi-dispute-semantics
# AC-P79-09/10 —— 控制台只读卡片：能力矩阵 + 支付级聚合 + partial 标记；不支持 → 降级（不渲染写表单语义）。
RSpec.describe 'Admin Disputes Ops capability & exposure (DSP-P7-9)', type: :request do
  let!(:store) { create(:store, code: "p79_ops_#{SecureRandom.hex(4)}", default: true) }
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }
  let(:payment_method) { create(:bogus_payment_method, store: store, active: true) }

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::DisputesOpsController).to receive(:current_store).and_return(store)
  end

  def sign_in_as_no_permission
    sign_in admin
    role = create(:role, name: "P79Limited_#{SecureRandom.hex(4)}")
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::DisputesOpsController).to receive(:current_store).and_return(store)
  end

  def make_dispute(amount: 12.34)
    order = create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                           item_total: 100, total: 100, payment_state: 'paid',
                           currency: store.default_currency, email: 'p79ops@example.com')
    payment = create(:payment, order: order, payment_method: payment_method, amount: 100,
                               state: 'completed', response_code: "pi_p79o_#{SecureRandom.hex(4)}",
                               source: nil, skip_source_requirement: true)
    PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: "dp_p79o_#{SecureRandom.hex(4)}",
      state: 'needs_response', amount: amount, currency: 'usd',
      store_id: store.id, payment: payment, order: order
    )
  end

  def stub_capabilities(capabilities)
    allow_any_instance_of(payment_method.class).to receive(:dispute_capabilities).and_return(capabilities)
  end

  it 'AC-P79-09/10 支持写契约时：渲染能力矩阵（含证据键计数）与支付级聚合' do
    sign_in_as_superuser
    dispute = make_dispute(amount: 12.34)
    stub_capabilities(
      supported: true, reason: nil, evidence_submission: true, accept_dispute: true, fee_capture: true,
      evidence_text_keys: %w[customer_name], evidence_file_keys: %w[receipt]
    )

    get PallasTrade.admin_dispute_path(dispute)

    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include(PallasTrade.t('admin.orders.disputes_capability_title'))
    expect(body).to include(PallasTrade.t('admin.orders.disputes_capability_supported'))
    expect(body).to include(PallasTrade.t('admin.orders.disputes_partial'))
    expect(body).to include(PallasTrade.t('admin.orders.disputes_payment_summary'))
    expect(body).to include('12.34')
    expect(body).to include('100.00')
  end

  it 'AC-P79-09 无写契约时：降级为 UNSUPPORTED 并给出原因文案' do
    sign_in_as_superuser
    dispute = make_dispute
    stub_capabilities(supported: false, reason: 'unsupported_provider')

    get PallasTrade.admin_dispute_path(dispute)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('unsupported_provider')
    expect(response.body).to include(PallasTrade.t('admin.orders.disputes_capability_unsupported'))
  end

  it 'AC-P79-09 能力矩阵异常 → 页面不 500（降级为 unavailable）' do
    sign_in_as_superuser
    dispute = make_dispute
    allow_any_instance_of(payment_method.class).to receive(:dispute_capabilities)
      .and_raise(StandardError, 'matrix boom')

    get PallasTrade.admin_dispute_path(dispute)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('unavailable')
  end

  it 'AC-P79-10 无读权限 → 不渲染只读卡片（302 拒绝）' do
    sign_in_as_no_permission
    dispute = make_dispute

    get PallasTrade.admin_dispute_path(dispute)

    expect(response).to have_http_status(:found)
  end
end
