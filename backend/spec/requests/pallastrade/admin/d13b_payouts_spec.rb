# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13b-payout-ledger（切片2，admin）
#   AC-006 ← FR-006：列表（筛选/汇总/分页）+ 详情（行明细/匹配摘要/审计）渲染
#   AC-007 ← FR-006/FR-007：导入（上传 / 粘贴）+ 重新匹配动作接线；无权限被拒
RSpec.describe 'Admin payouts (D13b)', type: :request do
  let!(:store) do
    create(:store, code: "d13b_admin_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD',
                   name: 'D13b Store', url: 'https://d13b.example.com')
  end
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', item_total: 100, total: 100,
                   payment_state: 'balance_due')
  end

  def sign_in_as_admin
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  def build_payout(**attrs)
    PallasTrade::Payout.create!(
      { store: store, provider: 'stripe', reference: "po_#{SecureRandom.hex(4)}", currency: 'USD',
        status: 'settled', settled_at: Time.zone.parse('2026-09-10'), imported_at: Time.current,
        gross_total: 100, fee_total: 3, net_total: 97 }.merge(attrs)
    )
  end

  def build_line(payout, **attrs)
    PallasTrade::PayoutLine.create!(
      { payout: payout, kind: 'charge', provider_reference: "ch_#{SecureRandom.hex(4)}", currency: 'USD',
        gross_amount: 100, fee_amount: 0, net_amount: 100, match_status: 'matched' }.merge(attrs)
    )
  end

  def report_csv(rows)
    "payout_reference,kind,provider_reference,gross,fee,net,currency,arrived_on\n#{rows.join("\n")}\n"
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-006
  it 'renders the ledger with filters and summary totals' do
    sign_in_as_admin
    kept = build_payout(gross_total: 120.50, fee_total: 3.20, net_total: 117.30)
    other = build_payout(provider: 'adyen', status: 'in_transit', settled_at: nil, gross_total: 10)

    get '/admin/payouts'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(PallasTrade.t('admin.payouts.title'))
    expect(response.body).to include(PallasTrade.admin_payout_path(kept))
    expect(response.body).to include('120.50')

    get '/admin/payouts', params: { provider: 'adyen' }

    expect(response.body).to include(PallasTrade.admin_payout_path(other))
    expect(response.body).not_to include(PallasTrade.admin_payout_path(kept))

    get '/admin/payouts', params: { status: 'difference' }
    expect(response.body).not_to include(PallasTrade.admin_payout_path(kept))

    get '/admin/payouts', params: { from: '2026-09-01', to: '2026-09-30' }
    expect(response.body).to include(PallasTrade.admin_payout_path(kept))
    expect(response.body).not_to include(PallasTrade.admin_payout_path(other))
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-006
  it 'renders a ledger detail with its lines, match summary and audit trail' do
    sign_in_as_admin
    payout = build_payout(status: 'difference')
    build_line(payout, provider_reference: 'ch_detail', gross_amount: 95, match_status: 'amount_mismatch',
                      match_details: { 'reason' => 'amount_mismatch', 'difference' => '5.0' })
    build_line(payout, provider_reference: 'fee_detail', kind: 'fee', gross_amount: 3, match_status: 'matched')

    get "/admin/payouts/#{payout.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(payout.reference)
    expect(response.body).to include('ch_detail')
    expect(response.body).to include(PallasTrade.t('admin.payouts.match_amount_mismatch'))
    expect(response.body).to include(PallasTrade.t('admin.payouts.match_matched'))
    expect(response.body).to include(PallasTrade.match_admin_payout_path(payout))
    expect(response.body).to include(PallasTrade.t('admin.payouts.no_audits'))
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-007
  it 'imports a pasted report, matches it automatically and queues the differences' do
    sign_in_as_admin
    create(:payment, order: order, amount: 100, state: 'completed', response_code: 'ch_api_1')

    post '/admin/payouts/import', params: {
      provider: 'stripe',
      source: 'admin_paste',
      csv: report_csv(['po_api,charge,ch_api_1,100.00,0,100.00,USD,2026-09-12',
                       'po_api,charge,ch_api_missing,20.00,0,20.00,USD,'])
    }

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(PallasTrade.admin_payouts_path)
    follow_redirect!
    expect(response.body).to include(PallasTrade.t('admin.payouts.title'))

    payout = PallasTrade::Payout.find_by(reference: 'po_api')
    expect(payout.status).to eq('difference')
    expect(payout.gross_total.to_d).to eq(120.to_d)
    expect(payout.settled_at).to eq(Time.zone.parse('2026-09-12').beginning_of_day)
    expect(payout.lines.find_by(provider_reference: 'ch_api_1').match_status).to eq('matched')
    expect(payout.lines.find_by(provider_reference: 'ch_api_missing').match_status).to eq('unmatched')

    kase = PallasTrade::ReconciliationCase.where(kind: 'payout').sole
    expect(kase.difference_type).to eq('payout_unmatched')
    expect(kase.status).to eq('open')
    expect(kase.store_id).to eq(store.id)
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-007
  it 'accepts an uploaded file and re-matches on demand' do
    sign_in_as_admin
    create(:payment, order: order, amount: 100, state: 'completed', response_code: 'ch_upload')
    file = Tempfile.new(['payout_report', '.csv'])
    file.write(report_csv(['po_upload,charge,ch_upload,100.00,0,100.00,USD,2026-09-13']))
    file.rewind
    upload = Rack::Test::UploadedFile.new(file.path, 'text/csv', original_filename: 'stripe_2026_09_13.csv')

    post '/admin/payouts/import', params: { provider: 'stripe', file: upload }

    expect(response).to have_http_status(:see_other)
    payout = PallasTrade::Payout.find_by(reference: 'po_upload')
    expect(payout.import_source).to end_with('.csv')
    expect(payout.lines.sole.match_status).to eq('matched')
    expect(payout.status).to eq('settled')

    payout.lines.sole.update!(match_status: 'unmatched')
    post "/admin/payouts/#{payout.id}/match"

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(PallasTrade.admin_payout_path(payout))
    expect(payout.lines.sole.reload.match_status).to eq('matched')
    expect(PallasTrade::ReconciliationCase.where(kind: 'payout').count).to eq(0)
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-007
  it 'reports import failures back to the import form without writing a ledger row' do
    sign_in_as_admin

    post '/admin/payouts/import', params: { provider: 'stripe', csv: "payout_reference,kind\npo,charge\n" }

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(PallasTrade.new_admin_payout_path)
    expect(PallasTrade::Payout.count).to eq(0)
  end

  # PRD-20260916-payments-d13b-payout-ledger AC-007
  it 'denies access without the configuration management permission' do
    build_payout(reference: 'po_denied')

    get '/admin/payouts'

    expect(response).not_to have_http_status(:ok)
  end
end
