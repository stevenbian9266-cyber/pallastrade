# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13c-fee-cost-report（D13 切片3，后台）
#   AC-12 ← FR-6：成本报表页（汇总 + 入口排名 + 下钻 + CSV 导出不含卡号）+ 权限
RSpec.describe 'Admin payment costs (D13c)', type: :request do
  let!(:store) do
    create(:store, code: "d13c_costs_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD',
                   name: 'D13c Cost Store', url: 'https://d13c-cost.example.com',
                   mail_from_address: 'no-reply@d13c-cost.example.com')
  end
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }
  let!(:provider) do
    create(:check_payment_method, store: store, active: true, display_on: 'both',
                                  name: "d13c-cost-pm-#{SecureRandom.hex(3)}",
                                  metadata: { 'optionized' => true,
                                              'options' => [{ 'kind' => 'card', 'active' => true, 'position' => 0,
                                                              'display_name' => 'Card' }] })
  end

  let(:paid_at) { Time.zone.parse('2026-09-10 10:00:00') }

  def sign_in_as_admin
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  def stub_store!
    allow_any_instance_of(PallasTrade::Admin::PaymentCostsController).to receive(:current_store).and_return(store)
    allow_any_instance_of(PallasTrade::Admin::PaymentFeePoliciesController).to receive(:current_store).and_return(store)
  end

  def build_paid_order(amount: 100)
    order = create(:order_with_line_items, store: store, currency: 'USD', line_items_count: 1,
                                           line_items_price: [amount.to_d, 100.to_d].max * 2, shipment_cost: 0)
    payment = create(:payment, order: order, payment_method: provider, amount: amount, state: 'completed',
                               source: nil, skip_source_requirement: true)
    payment.update_columns(created_at: paid_at, updated_at: paid_at)
    payment
  end

  before do
    create(:payment_fee_policy, store: store, name: 'd13c-cost-fallback', scope_type: 'global',
                                percent_fee: 2.9, fixed_fee: 0.3)
    create(:payment_fee_policy, store: store, name: 'd13c-cost-entry', scope_type: 'method', scope_id: 'card',
                                percent_fee: 1, fixed_fee: 0)
  end

  it 'renders the report with totals, entry ranking and drill-down' do
    sign_in_as_admin
    stub_store!
    build_paid_order(amount: 100)
    build_paid_order(amount: 300)

    get '/admin/payment_costs', params: { from: '2026-09-01', to: '2026-10-01' }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(PallasTrade.t('admin.payment_costs.title'))
    # 2 × (100 + 300) × 1% = 4.0
    expect(response.body).to match(/data-cost-metric="fee">\s*4\.0/)
    expect(response.body).to include(%(data-cost-table="by_entry"))
    expect(response.body).to include(%(data-cost-table="detail"))
    expect(response.body).to match(/data-cost-metric="orders">\s*2/)

    # 下钻：入口过滤后只保留该入口的行
    get '/admin/payment_costs', params: { from: '2026-09-01', to: '2026-10-01', method_key: 'card' }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(data-cost-table="detail"))
    expect(response.body.scan(/data-payment-id=/).size).to eq(2)
  end

  it 'filters by provider and currency' do
    sign_in_as_admin
    stub_store!
    build_paid_order(amount: 100)

    get '/admin/payment_costs', params: { from: '2026-09-01', to: '2026-10-01', currency: 'EUR' }

    expect(response).to have_http_status(:ok)
    expect(response.body).to match(/data-cost-metric="fee">\s*0\.0/)

    get '/admin/payment_costs', params: { from: '2026-09-01', to: '2026-10-01', currency: 'USD' }
    expect(response.body).to match(/data-cost-metric="fee">\s*1\.0/)
  end

  it 'exports a CSV with the detail rows and no card data' do
    sign_in_as_admin
    stub_store!
    build_paid_order(amount: 250)

    expect do
      get '/admin/payment_costs/export', params: { from: '2026-09-01', to: '2026-10-01' }
    end.to change { PallasTrade::AuditLog.where(action: 'payment_cost_report_exported').count }.by(1)

    expect(response).to have_http_status(:ok)
    expect(response.headers['Content-Type']).to include('text/csv')
    expect(response.body).to include('2.5') # 250 × 1%
    expect(response.body).to include('card')
    expect(response.body).not_to include('4242')
    expect(response.body).not_to include('sk_')
  end

  it 'denies the report without the permission' do
    other_admin = create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
    sign_in other_admin
    stub_store!

    get '/admin/payment_costs'

    expect(response).not_to have_http_status(:ok)
  end
end
