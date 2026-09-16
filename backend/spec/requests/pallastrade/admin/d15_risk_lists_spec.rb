# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-payments-d15-risk-lists（D15 切片1，后台）
#   AC-008 ← FR-007：名单工作台（计数与筛选同源 / 新增 / 撤销 / 导入 / 导出 / 权限）
#   AC-009 ← FR-008：订单页风控卡（最近评估 + 脱敏）；无评估不渲染
RSpec.describe 'Admin risk lists (D15)', type: :request do
  let!(:store) do
    create(:store, code: "d15_admin_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD',
                   name: 'D15 Risk Store', url: 'https://d15-risk.example.com',
                   mail_from_address: 'no-reply@d15-risk.example.com')
  end
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }
  let(:suffix) { SecureRandom.hex(4) }

  def sign_in_as_admin
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  # 仓库既有范式（refunds_ops_spec）：后台请求 spec 里 current_store 解析不稳定 → 直接固定
  def stub_order_page_store!
    allow_any_instance_of(PallasTrade::Admin::OrdersController).to receive(:current_store).and_return(store)
  end

  def upsert(attrs)
    PallasTrade::Risk::Lists::Upsert.call({ store: store, actor: 'system' }.merge(attrs))
  end

  # AC-008
  it 'renders the workbench with counts sourced from the same filters' do
    sign_in_as_admin
    upsert(list_type: 'denylist', subject_type: 'email', value: "d15-admin-#{suffix}@example.com")
    upsert(list_type: 'allowlist', subject_type: 'ip', value: '203.0.113.5')
    upsert(list_type: 'denylist', subject_type: 'email', value: "d15-admin-old-#{suffix}@example.com",
           expires_at: 1.hour.ago)
    upsert(list_type: 'denylist', subject_type: 'email', value: "d15-admin-rev-#{suffix}@example.com", revoke: true)

    get '/admin/risk_lists'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(PallasTrade.t('admin.risk_lists.title'))
    expect(response.body).to include('d***@example.com')
    expect(response.body).not_to include("d15-admin-#{suffix}@example.com")

    # 计数与筛选**同源**：四个状态卡的数字必须等于同一 filter_by 口径的计数
    %w[all active expired revoked].each do |scope|
      expected = PallasTrade::PaymentRiskList.filter_by(
        store: store, scope_filter: scope == 'all' ? nil : scope
      ).count
      expect(response.body).to include(%(data-count-scope="#{scope}">#{expected}</h3>))
    end
  end

  # AC-008（筛选生效）
  it 'filters the list by list type and subject type' do
    sign_in_as_admin
    upsert(list_type: 'denylist', subject_type: 'email', value: "d15-filter-#{suffix}@example.com")
    upsert(list_type: 'allowlist', subject_type: 'ip', value: '198.51.100.4')

    get '/admin/risk_lists', params: { list_type: 'allowlist', subject_type: 'ip' }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('198.51.100.4'.split('.').first(2).join('.') + '.*.*')
    expect(response.body).not_to include('d***@example.com')
  end

  # AC-008（新增 + 续期幂等）
  it 'creates an entry through the workbench and renews it on a second submit' do
    sign_in_as_admin

    post '/admin/risk_lists', params: { payment_risk_list: {
      list_type: 'denylist', subject_type: 'email', value: "D15-Form-#{suffix}@Example.com",
      reason: 'form', store_scope: 'all'
    } }
    expect(response).to have_http_status(:see_other)
    expect(PallasTrade::PaymentRiskList.where(value: "d15-form-#{suffix}@example.com").count).to eq(1)

    post '/admin/risk_lists', params: { payment_risk_list: {
      list_type: 'denylist', subject_type: 'email', value: "d15-form-#{suffix}@example.com",
      reason: 'renewed', expires_at: '2027-01-31', store_scope: 'all'
    } }
    expect(PallasTrade::PaymentRiskList.where(value: "d15-form-#{suffix}@example.com").count).to eq(1)
    expect(PallasTrade::PaymentRiskList.find_by(value: "d15-form-#{suffix}@example.com").reason).to eq('renewed')
  end

  # AC-008（撤销）
  it 'revokes an entry without deleting it' do
    sign_in_as_admin
    entry = upsert(list_type: 'denylist', subject_type: 'email', value: "d15-revoke-#{suffix}@example.com").value

    post "/admin/risk_lists/#{entry.id}/revoke"

    expect(response).to have_http_status(:see_other)
    expect(entry.reload.status).to eq('revoked')
    expect(PallasTrade::PaymentRiskList.where(id: entry.id).count).to eq(1)
    expect(PallasTrade::AuditLog.where(action: 'risk_list_entry_changed').where(resource_id: entry.id).count).to eq(2)
  end

  # AC-008（导入 + 导出）
  it 'imports pasted CSV and exports the filtered rows' do
    sign_in_as_admin

    post '/admin/risk_lists/import', params: {
      csv: "list_type,subject_type,value,expires_at,reason\n" \
           "denylist,email,d15-import-#{suffix}@example.com,,bulk\n" \
           "denylist,shoe_size,42,,bad row\n"
    }

    expect(response).to have_http_status(:see_other)
    expect(PallasTrade::PaymentRiskList.where(value: "d15-import-#{suffix}@example.com")).to be_present

    get '/admin/risk_lists/export', params: { subject_type: 'email' }
    expect(response).to have_http_status(:ok)
    expect(response.headers['Content-Type']).to include('text/csv')
    expect(response.body.lines.first.strip).to eq('list_type,subject_type,value,expires_at,reason')
    expect(response.body).to include("d15-import-#{suffix}@example.com")
  end

  # AC-008（权限）
  it 'denies the workbench without the permission' do
    other_admin = create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
    sign_in other_admin

    get '/admin/risk_lists'
    expect(response).not_to have_http_status(:ok)
  end

  # AC-009
  it 'shows the latest assessment on the order page with masked matches' do
    sign_in_as_admin
    stub_order_page_store!
    order = create(:order_with_line_items, store: store)
    order.update_columns(email: "d15-card-#{suffix}@example.com", considered_risky: false)
    upsert(list_type: 'denylist', subject_type: 'email', value: "d15-card-#{suffix}@example.com")
    PallasTrade::Risk::Assess.call(order: order.reload)

    get "/admin/orders/#{order.prefixed_id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(PallasTrade.t('admin.risk_lists.assessment_title'))
    expect(response.body).to include('d***@example.com')
    expect(response.body).not_to include("d15-card-#{suffix}@example.com")
  end

  # AC-009（无评估不渲染）
  it 'renders no assessment card when the order was never assessed' do
    sign_in_as_admin
    stub_order_page_store!
    order = create(:order_with_line_items, store: store)

    get "/admin/orders/#{order.prefixed_id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(PallasTrade.t('admin.risk_lists.assessment_title'))
  end
end
