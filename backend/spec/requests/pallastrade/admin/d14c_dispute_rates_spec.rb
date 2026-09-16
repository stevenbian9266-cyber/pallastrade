# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d14c-dispute-rate-board（D14 切片3，后台）
#   AC-011 卡指纹脱敏（页面/CSV）+ CSV 无凭证
#   AC-012 页面：计数与列表同源、筛选、权限
#   AC-013 阈值保存（非法不写库 / 合法写策略 + 审计 / 应用建议值）
#   AC-015 一键加黑（写 D15 名单 + 审计 + 权限；非法输入友好失败）
RSpec.describe 'Admin dispute rates (D14c)', type: :request do
  let!(:store) do
    create(:store, code: "d14c_admin_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD',
                   supported_currencies: 'USD', name: 'D14c Rate Store',
                   url: 'https://d14c-rate.example.com', mail_from_address: 'no-reply@d14c-rate.example.com')
  end
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }
  let(:suffix) { SecureRandom.hex(4) }
  let(:us) do
    PallasTrade::Country.find_by(iso: 'US') ||
      create(:country, iso: 'US', name: 'United States', iso_name: 'UNITED STATES', iso3: 'USA', numcode: 840)
  end
  let(:visa_fingerprint) { "fp_visa_#{suffix}" }

  def sign_in_as_admin
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  def stub_current_store!
    allow_any_instance_of(PallasTrade::Admin::DisputeRatesController)
      .to receive(:current_store).and_return(store)
  end

  def configure_thresholds(policy)
    store.update_columns(private_metadata: (store.private_metadata || {}).merge(
      PallasTrade::Disputes::RatePolicy::KEY => policy
    ))
    store.reload
  end

  def build_order(email:, at: 5.days.ago, amount: 100)
    order = create(:order_with_line_items, store: store, currency: 'USD', email: email,
                                           line_items_count: 1, line_items_price: amount, shipment_cost: 0)
    address = create(:address, country: us)
    order.update_columns(bill_address_id: address.id, email: email, total: amount, item_total: amount,
                         payment_total: 0, created_at: at, updated_at: at)
    order.reload
  end

  def build_card_payment(order:, amount: 100, brand: 'visa', fingerprint: nil, at: 5.days.ago)
    method = create(:credit_card_payment_method, stores: [store])
    card = create(:credit_card, cc_type: brand, payment_method: method,
                                fingerprint: fingerprint || visa_fingerprint)
    payment = create(:payment, order: order, payment_method: method, source: card,
                               amount: amount, state: 'completed')
    payment.update_columns(created_at: at, updated_at: at)
    payment.reload
  end

  def build_dispute(payment:, amount: 100, at: 4.days.ago)
    dispute = PallasTrade::Dispute.create!(
      provider: 'stripe', provider_dispute_reference: "dp_#{SecureRandom.hex(6)}",
      state: 'needs_response', kind: 'chargeback', amount: amount, currency: 'USD',
      payment: payment, order: payment.order, store: store
    )
    dispute.update_columns(created_at: at, updated_at: at)
    dispute
  end

  def seed_rate_data(disputes: 1, transactions: 1)
    payment = nil
    transactions.times do |index|
      current = build_card_payment(order: build_order(email: "rate-#{index}-#{suffix}@example.com",
                                                      at: (index + 1).days.ago),
                                   at: (index + 1).days.ago)
      payment ||= current
    end
    disputes.times { build_dispute(payment: payment) }
    payment
  end

  # AC-012
  it 'renders the board with cards, drill-down and the alert ledger' do
    sign_in_as_admin
    stub_current_store!
    configure_thresholds('networks' => { 'visa' => { 'count_bps' => 1_000 } })
    seed_rate_data(disputes: 1, transactions: 1)
    alert = PallasTrade::Disputes::RateAlert.call(store: store, evaluated_on: Date.current).value[:recorded].first
    PallasTrade::DisputeRateAlert.find(alert).update!(tier: PallasTrade::DisputeRateAlert::BREACHED)

    get '/admin/dispute_rates'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(PallasTrade.t('admin.dispute_rates.title'))
    expect(response.body).to include('data-rate-totals')
    expect(response.body).to include(%(data-rate-network="visa"))
    expect(response.body).to include(%(data-rate-status="breached"))
    expect(response.body).to include(%(data-rate-metric="count"))
    expect(response.body).to include('data-rate-breakdown="card_fingerprint"')
    expect(response.body).to include('data-rate-alerts-table')
    expect(response.body).to include(%(data-count-scope="breached"))
    expect(response.body).to match(/data-count-scope="breached">\s*1/)
    expect(response.body).to match(/data-count-scope="all">\s*1/)
    # 卡指纹脱敏（页面绝不出现原始指纹）
    expect(response.body).not_to include(visa_fingerprint)
    expect(response.body).to include(PallasTrade::Admin::DisputeRatesHelper.masked(visa_fingerprint))
  end

  # AC-012（筛选：维度切换 + 台账档位筛选；计数与列表同一 scope）
  it 'filters by dimension and ledger tier' do
    sign_in_as_admin
    stub_current_store!
    configure_thresholds('networks' => { 'visa' => { 'count_bps' => 1_000 } })
    seed_rate_data(disputes: 1, transactions: 1)
    PallasTrade::Disputes::RateAlert.call(store: store, evaluated_on: Date.current)
    create(:dispute_rate_alert, store: store, network: 'master', tier: 'approach'[0, 0] + 'approaching',
                                evaluated_on: Date.current - 1.day)
    create(:dispute_rate_alert, store: store, network: 'visa', tier: 'approaching',
                                evaluated_on: Date.current - 2.days)

    get '/admin/dispute_rates', params: { dimension: 'country', tier: 'breached' }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-rate-breakdown="country"')
    expect(response.body).to include(%(data-bucket-masked="US"))
    expect(response.body).to match(/data-count-scope="approaching">\s*2/)
    expect(response.body).to match(/data-count-scope="breached">\s*1/)
    expect(response.body).to match(/data-alert-tier="breached"/)
    expect(response.body).not_to include(%(data-alert-tier="approaching"))
  end

  # AC-013（保存合法阈值 → 写策略 + 审计）
  it 'saves the threshold policy with an audit trail' do
    sign_in_as_admin
    stub_current_store!

    patch '/admin/dispute_rates/policy', params: {
      dispute_rate_policy: { enabled: '1', window_days: '60', warning_ratio: '0.9',
                             networks: { 'visa' => { count_bps: '80', amount_bps: '120' } } }
    }

    expect(response).to have_http_status(:see_other)
    policy = PallasTrade::Disputes::RatePolicy.for(store.reload)
    expect(policy.enabled?).to be(true)
    expect(policy.window_days).to eq(60)
    expect(policy.warning_ratio).to eq(0.9)
    expect(policy.thresholds_for('visa')).to eq(count_bps: 80, amount_bps: 120)
    expect(
      PallasTrade::AuditLog.where(action: 'dispute_rate_policy_updated').where(resource_id: store.id).count
    ).to eq(1)
  end

  # AC-013（非法输入不写库：非法值被保守归一，不会变成「无窗口/无阈值」）
  it 'keeps unusable input out of the policy by normalizing it' do
    sign_in_as_admin
    stub_current_store!

    patch '/admin/dispute_rates/policy', params: {
      dispute_rate_policy: { window_days: 'nope', warning_ratio: '9',
                             networks: { 'visa' => { count_bps: '0', amount_bps: 'x' } } }
    }

    policy = PallasTrade::Disputes::RatePolicy.for(store.reload)
    expect(policy.window_days).to eq(30)
    expect(policy.warning_ratio).to eq(0.8)
    expect(policy.configured_networks).to eq([])
    expect(response).to have_http_status(:see_other)
  end

  # AC-013（应用建议值 = 显式动作）
  it 'applies the suggested template only when explicitly asked' do
    sign_in_as_admin
    stub_current_store!

    patch '/admin/dispute_rates/policy', params: {
      apply_suggested: '1',
      dispute_rate_policy: { window_days: '30', warning_ratio: '0.8' }
    }

    policy = PallasTrade::Disputes::RatePolicy.for(store.reload)
    expect(policy.configured_networks).to include('visa', 'master')
    expect(policy.thresholds_for('visa')).to eq(
      count_bps: PallasTrade::Disputes::RatePolicy::SUGGESTED['visa']['count_bps'],
      amount_bps: PallasTrade::Disputes::RatePolicy::SUGGESTED['visa']['amount_bps']
    )
  end

  # AC-012（立即评估 → 写台账 + 审计 + flash）
  it 're-evaluates on demand and records the outcome' do
    sign_in_as_admin
    stub_current_store!
    configure_thresholds('networks' => { 'visa' => { 'count_bps' => 1_000 } })
    seed_rate_data(disputes: 1, transactions: 1)

    post '/admin/dispute_rates/reevaluate'

    expect(response).to have_http_status(:see_other)
    expect(PallasTrade::DisputeRateAlert.count).to eq(1)
    expect(
      PallasTrade::AuditLog.where(action: 'dispute_rates_reevaluated').where(resource_id: store.id).count
    ).to eq(1)
  end

  # AC-015（一键加黑：页面只提交脱敏值 → 服务端唯一反解 → 写 D15 名单 + 审计）
  it 'adds a drilled-down card fingerprint to the risk denylist' do
    sign_in_as_admin
    stub_current_store!
    configure_thresholds('networks' => { 'visa' => { 'count_bps' => 1_000 } })
    seed_rate_data(disputes: 1, transactions: 1)

    post '/admin/dispute_rates/add_to_denylist',
         params: { masked_fingerprint: PallasTrade::Admin::DisputeRatesHelper.masked(visa_fingerprint),
                   reason: 'High dispute rate' }

    expect(response).to have_http_status(:see_other)
    entry = PallasTrade::PaymentRiskList.last
    expect(entry.list_type).to eq('denylist')
    expect(entry.subject_type).to eq('card_fingerprint')
    expect(entry.value).to eq(visa_fingerprint)
    expect(entry.store_id).to eq(store.id)
    expect(entry.reason).to eq('High dispute rate')
  end

  # AC-015（脱敏后无法唯一反解 → 拒绝写入，不猜）
  it 'refuses an ambiguous masked fingerprint' do
    sign_in_as_admin
    stub_current_store!
    configure_thresholds('networks' => { 'visa' => { 'count_bps' => 1_000 } })
    build_card_payment(order: build_order(email: "amb-a-#{suffix}@example.com"),
                       fingerprint: 'AAAA1111222233334444')
    build_card_payment(order: build_order(email: "amb-b-#{suffix}@example.com"),
                       fingerprint: 'AAAA9999222233334444')

    masked = PallasTrade::Admin::DisputeRatesHelper.masked('AAAA1111222233334444')
    expect(PallasTrade::Admin::DisputeRatesHelper.masked('AAAA9999222233334444')).to eq(masked)

    post '/admin/dispute_rates/add_to_denylist', params: { masked_fingerprint: masked }

    expect(response).to have_http_status(:see_other)
    expect(PallasTrade::PaymentRiskList.count).to eq(0)
    expect(flash[:error]).to be_present
  end

  # AC-015（未知桶/空值：友好失败，不写名单）
  it 'refuses unusable fingerprints without writing anything' do
    sign_in_as_admin
    stub_current_store!

    post '/admin/dispute_rates/add_to_denylist', params: { masked_fingerprint: 'unknown' }

    expect(response).to have_http_status(:see_other)
    expect(PallasTrade::PaymentRiskList.count).to eq(0)
    expect(flash[:error]).to be_present
  end

  # AC-011（CSV：脱敏 + 无凭证；写审计）
  it 'exports a masked CSV without credentials and audits the export' do
    sign_in_as_admin
    stub_current_store!
    configure_thresholds('networks' => { 'visa' => { 'count_bps' => 1_000 } })
    seed_rate_data(disputes: 1, transactions: 1)
    PallasTrade::Disputes::RateAlert.call(store: store, evaluated_on: Date.current)

    get '/admin/dispute_rates/export'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Section')
    expect(response.body).to include('visa')
    expect(response.body).not_to include(visa_fingerprint)
    expect(response.body).to include(PallasTrade::Admin::DisputeRatesHelper.masked(visa_fingerprint))
    expect(response.body).not_to match(/\d{12,}/)
    expect(
      PallasTrade::AuditLog.where(action: 'dispute_rates_exported').where(resource_id: store.id).count
    ).to eq(1)
  end

  # AC-012（权限）
  it 'denies the board without the permission' do
    other_admin = create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
    sign_in other_admin
    stub_current_store!

    get '/admin/dispute_rates'

    expect(response).not_to have_http_status(:ok)
  end
end
