# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d13d-fx-snapshot（D13 切片4，后台）
#   AC-11 ← FR-7：汇率表（计数与筛选同源 + 新增/幂等更新 + 软撤销 + 审计 + 权限）
RSpec.describe 'Admin currency rates (D13d)', type: :request do
  let!(:store) do
    create(:store, code: "d13d_admin_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD',
                   supported_currencies: 'USD,CNY,EUR', name: 'D13d FX Store',
                   url: 'https://d13d-fx.example.com', mail_from_address: 'no-reply@d13d-fx.example.com')
  end
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }
  let(:suffix) { SecureRandom.hex(4) }

  def sign_in_as_admin
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  def stub_current_store!
    allow_any_instance_of(PallasTrade::Admin::CurrencyRatesController)
      .to receive(:current_store).and_return(store)
    allow_any_instance_of(PallasTrade::Admin::FxSnapshotsController)
      .to receive(:current_store).and_return(store)
  end

  it 'renders the list with counts sourced from the same filters' do
    sign_in_as_admin
    stub_current_store!
    create(:currency_rate, store: store, base_currency: 'USD', quote_currency: 'CNY', source: 'manual')
    revoked = create(:currency_rate, store: store, base_currency: 'USD', quote_currency: 'EUR', source: 'manual')
    revoked.revoke!(actor: 'spec')

    get '/admin/currency_rates'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(PallasTrade.t('admin.currency_rates.title'))
    expect(response.body).to include('USD') && include('CNY')

    %w[all active revoked].each do |status_filter|
      expected = PallasTrade::CurrencyRate.filter_by(
        store: store, status_filter: status_filter == 'all' ? nil : status_filter
      ).count
      expect(response.body).to include(%(data-count-scope="#{status_filter}">#{expected}</h3>))
    end
  end

  it 'creates a rate through the workbench and is idempotent on a second submit' do
    sign_in_as_admin
    stub_current_store!

    expect do
      post '/admin/currency_rates', params: { currency_rate: {
        base_currency: 'USD', quote_currency: 'CNY', rate: '7.15', source: 'manual', note: "first-#{suffix}"
      } }
    end.to change(PallasTrade::CurrencyRate, :count).by(1)

    expect(response).to have_http_status(:see_other)

    expect do
      post '/admin/currency_rates', params: { currency_rate: {
        base_currency: 'usd', quote_currency: 'cny', rate: '7.20', source: 'manual'
      } }
    end.not_to change(PallasTrade::CurrencyRate, :count)

    row = PallasTrade::CurrencyRate.last
    expect(row.rate.to_d).to eq(BigDecimal('7.2'))
    expect(row.store_id).to eq(store.id)
    expect(PallasTrade::AuditLog.where(action: 'currency_rate_changed').count).to be >= 1
  end

  it 'revokes a rate without deleting the row' do
    sign_in_as_admin
    stub_current_store!
    row = create(:currency_rate, store: store, base_currency: 'USD', quote_currency: 'CNY')

    expect { post "/admin/currency_rates/#{row.id}/revoke" }.not_to change(PallasTrade::CurrencyRate, :count)

    expect(response).to have_http_status(:see_other)
    expect(row.reload.status).to eq('revoked')
    expect(PallasTrade::AuditLog.where(action: 'currency_rate_revoked').count).to eq(1)
  end

  it 'denies the page without the permission' do
    other_admin = create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
    sign_in other_admin
    stub_current_store!

    get '/admin/currency_rates'

    expect(response).not_to have_http_status(:ok)
  end
end
