# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13d-fx-snapshot（D13 切片4，后台）
#   AC-12 ← FR-7：汇率快照工作台（汇总/筛选/明细/偏差/重新比对/CSV 无凭证）+ 权限
RSpec.describe 'Admin FX snapshots (D13d)', type: :request do
  let!(:store) do
    create(:store, code: "d13d_fx_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD',
                   supported_currencies: 'USD,CNY', name: 'D13d Snap Store',
                   url: 'https://d13d-snap.example.com', mail_from_address: 'no-reply@d13d-snap.example.com')
  end
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }
  let(:suffix) { SecureRandom.hex(4) }

  def sign_in_as_admin
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  def stub_current_store!
    allow_any_instance_of(PallasTrade::Admin::FxSnapshotsController)
      .to receive(:current_store).and_return(store)
    allow_any_instance_of(PallasTrade::Admin::CurrencyRatesController)
      .to receive(:current_store).and_return(store)
  end

  def locked_order(amount:, paid_at: Time.current)
    order = create(:order_with_line_items, store: store, currency: 'CNY', line_items_count: 1,
                                           line_items_price: amount, shipment_cost: 0)
    snapshot = create(:fx_snapshot, order: order, store: store, base_currency: 'USD', quote_currency: 'CNY',
                                    display_rate: BigDecimal('7.1'), effective_rate: BigDecimal('7.1'),
                                    locked_at: paid_at, metadata: { 'order_number' => order.number })
    [order, snapshot]
  end

  it 'renders the workbench with counts, summary and drillable rows' do
    sign_in_as_admin
    stub_current_store!
    _order, pending = locked_order(amount: 1000)
    _other, mismatched = locked_order(amount: 2000)
    mismatched.update!(variance_status: 'mismatch', variance_bips: 563, settlement_rate: BigDecimal('7.5'),
                       settlement_source: 'implied', settled_gross_amount: 15_000, settlement_currency: 'USD',
                       compared_at: Time.current)

    get '/admin/fx_snapshots', params: { from: 1.day.ago.to_date.to_s, to: 1.day.from_now.to_date.to_s }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(PallasTrade.t('admin.fx_snapshots.title'))
    expect(response.body).to include(%(data-fx-snapshot-table))
    expect(response.body).to include(%(data-variance-bips="#{mismatched.id}"))
    expect(response.body).to include('563 bips')
    expect(response.body).to match(/data-count-scope="mismatch">\s*1/)
    expect(response.body).to match(/data-count-scope="pending">\s*1/)
    expect(response.body).to include(%(data-fx-summary="average_bips"))
    expect(pending.reload.variance_status).to eq('pending')
  end

  it 'filters by variance status' do
    sign_in_as_admin
    stub_current_store!
    _order, mismatched = locked_order(amount: 2000)
    mismatched.update!(variance_status: 'mismatch', variance_bips: 563, compared_at: Time.current)
    _other, pending = locked_order(amount: 1000)

    get '/admin/fx_snapshots', params: { variance_status: 'mismatch' }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(data-fx-snapshot-id="#{mismatched.id}"))
    expect(response.body).not_to include(%(data-fx-snapshot-id="#{pending.id}"))
  end

  it 'recompares the filtered snapshots and audits the run' do
    sign_in_as_admin
    stub_current_store!
    order, snapshot = locked_order(amount: 1000)
    payment = create(:payment, order: order, payment_method: create(:check_payment_method, store: store),
                               amount: 1000, state: 'completed', source: nil, skip_source_requirement: true)
    payout = PallasTrade::Payout.create!(store: store, provider: 'stripe', reference: "po_d13d_adm_#{suffix}",
                                         currency: 'USD', status: 'settled', settled_at: Time.current,
                                         imported_at: Time.current, gross_total: 7500, fee_total: 0,
                                         net_total: 7500)
    PallasTrade::PayoutLine.create!(payout: payout, payment: payment, kind: 'charge',
                                    provider_reference: "ch_#{suffix}", currency: 'USD', gross_amount: 7500,
                                    fee_amount: 0, net_amount: 7500, match_status: 'matched', raw: {})

    expect do
      post '/admin/fx_snapshots/recompare', params: { variance_status: 'pending' }
    end.to change { PallasTrade::AuditLog.where(action: 'fx_snapshots_recompared').count }.by(1)

    expect(response).to have_http_status(:see_other)
    expect(snapshot.reload.variance_status).to eq('mismatch')
    expect(PallasTrade::ReconciliationCase.where(kind: 'fx').count).to eq(1)
  end

  it 'exports a CSV with the variance facts and no credentials' do
    sign_in_as_admin
    stub_current_store!
    _order, snapshot = locked_order(amount: 1000)
    snapshot.update!(variance_status: 'mismatch', variance_bips: 563, settlement_rate: BigDecimal('7.5'),
                     settlement_source: 'implied', settled_gross_amount: 7500, settlement_currency: 'USD',
                     compared_at: Time.current)

    expect do
      get '/admin/fx_snapshots/export'
    end.to change { PallasTrade::AuditLog.where(action: 'fx_snapshots_exported').count }.by(1)

    expect(response).to have_http_status(:ok)
    expect(response.headers['Content-Type']).to include('text/csv')
    expect(response.body).to include('USD/CNY')
    expect(response.body).to include('563')
    expect(response.body).not_to include('sk_')
    expect(response.body).not_to include('4242')
  end

  it 'denies the workbench without the permission' do
    other_admin = create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
    sign_in other_admin
    stub_current_store!

    get '/admin/fx_snapshots'

    expect(response).not_to have_http_status(:ok)
  end
end
