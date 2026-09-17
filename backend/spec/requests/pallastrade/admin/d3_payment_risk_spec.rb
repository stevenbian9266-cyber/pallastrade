# frozen_string_literal: true

# PRD-20260917-payments-d3-risk-dashboard-threshold-alerts AC-011
# 后台看板：5 卡渲染 / 策略保存与拒绝 / 立即评估 / 权限拒绝零写入
require 'rails_helper'

RSpec.describe 'Admin payment risk dashboard', type: :request do
  let!(:store) { create(:store, code: "d3_admin_#{SecureRandom.hex(4)}", default: true) }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::PaymentRiskController).
      to receive(:current_store).and_return(store)
  end

  def configure_policy(target: store, warning: 60, critical: 120)
    policy, = PallasTrade::Risk::DashboardPolicy.storable(raw: {
      'window_days' => 30,
      'metrics' => { 'review_queue_duration' => { 'enabled' => '1', 'warning' => warning, 'critical' => critical } }
    })
    target.update_columns(
      private_metadata: (target.private_metadata || {}).merge(PallasTrade::Risk::DashboardPolicy::KEY => policy.raw)
    )
    target.reload
  end

  def manual_review_transaction(target: store, wait_minutes: 500)
    tx = PallasTrade::CommerceTransaction.create!(store: target, purpose: 'purchase',
                                                  currency: target.default_currency.to_s, amount: 10)
    tx.start_payment!
    tx.confirm_payment!
    tx.mark_recovery_required!
    tx.manual_review!
    tx.update_columns(manual_review_at: wait_minutes.minutes.ago)
    tx.reload
  end

  def alerts_of(target)
    PallasTrade::AuditLog.where(action: PallasTrade::Risk::DashboardAlert::AUDIT_ACTION,
                                resource_type: PallasTrade::Risk::DashboardAlert::RESOURCE_TYPE,
                                resource_id: target.id)
  end

  describe 'GET /admin/payment_risk' do
    it 'renders the five metric rows, the policy block and the alerts block (scoped selectors)' do
      sign_in_as_superuser
      configure_policy
      manual_review_transaction(wait_minutes: 200)
      PallasTrade::Risk::DashboardAlert.call(store: store) # 留痕一条越线

      get '/admin/payment_risk'

      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      rows = doc.css('[data-testid^="payment-risk-metric-"]')
      expect(rows.size).to eq(5)
      expect(rows.map { |row| row['data-testid'] }).to include('payment-risk-metric-review_queue_duration')
      expect(doc.at_css('[data-testid="payment-risk-policy"]')).to be_present
      alerts = doc.at_css('[data-testid="payment-risk-alerts"]')
      expect(alerts).to be_present
      expect(alerts.css('tbody tr').size).to eq(1)
      expect(doc.at_css('[data-testid="payment-risk-metric-review_queue_duration"]')['data-metric-status']).to eq('breached')
      # 未配置阈值的指标不应显示为 0（不可判定 ≠ 健康）
      expect(doc.at_css('[data-testid="payment-risk-metric-refund_rate"]')['data-metric-status']).to eq('unavailable')
    end

    it 'renders an empty-state alert block when nothing was alerted yet' do
      sign_in_as_superuser

      get '/admin/payment_risk'

      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      expect(doc.css('[data-testid="payment-risk-alerts"]')).to be_empty
      expect(response.body).to include(PallasTrade.t('admin.payment_risk.alerts_empty'))
    end
  end

  describe 'PATCH /admin/payment_risk/policy' do
    it 'persists a valid policy and writes an audit row' do
      sign_in_as_superuser

      patch '/admin/payment_risk/policy', params: {
        policy: { window_days: 45, metrics: { refund_rate: { enabled: '1', warning: '300', critical: '600' } } }
      }

      expect(response).to have_http_status(:see_other)
      policy = PallasTrade::Risk::DashboardPolicy.for(store.reload)
      expect(policy.window_days).to eq(45)
      expect(policy.threshold_for('refund_rate')).to eq(warning: 300, critical: 600)
      expect(PallasTrade::AuditLog.where(action: 'store_payment_risk_dashboard_policy_updated',
                                         resource_id: store.id).count).to eq(1)
    end

    it 'refuses an invalid policy without persisting it' do
      sign_in_as_superuser

      patch '/admin/payment_risk/policy', params: {
        policy: { metrics: { refund_rate: { enabled: '1', warning: '900', critical: '600' } } }
      }

      expect(response).to have_http_status(:see_other)
      expect(flash[:error]).to be_present
      policy = PallasTrade::Risk::DashboardPolicy.for(store.reload)
      expect(policy.configured?('refund_rate')).to be(false)
      expect(PallasTrade::AuditLog.where(action: 'store_payment_risk_dashboard_policy_updated',
                                         resource_id: store.id).count).to eq(0)
    end
  end

  describe 'POST /admin/payment_risk/reevaluate' do
    it 'records the breach on demand' do
      sign_in_as_superuser
      configure_policy
      manual_review_transaction(wait_minutes: 500)

      post '/admin/payment_risk/reevaluate'

      expect(response).to have_http_status(:see_other)
      expect(flash[:success]).to be_present
      expect(alerts_of(store).count).to eq(1)
    end

    it 'denies without update permission and writes nothing' do
      sign_in admin
      allow_any_instance_of(PallasTrade::Admin::PaymentRiskController).
        to receive(:current_store).and_return(store)
      configure_policy
      manual_review_transaction(wait_minutes: 500)

      post '/admin/payment_risk/reevaluate'

      expect(response).not_to have_http_status(:ok)
      expect(alerts_of(store).count).to eq(0)
    end
  end
end
