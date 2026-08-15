# frozen_string_literal: true

require 'rails_helper'

# PRD-20260815-catalog-邮件管理整合 AC-001 / AC-002 / AC-003 / AC-005 / AC-006
RSpec.describe 'Admin Email management pages', type: :request do
  let(:store) { create(:store, code: 'emails_admin_test') }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end

  before do
    sign_in admin
    admin_role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: admin_role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::EmailsController).to receive(:current_store).and_return(store)
    allow_any_instance_of(PallasTrade::Admin::StoresController).to receive(:current_store).and_return(store)
    allow_any_instance_of(PallasTrade::Admin::EmailTemplatesController).to receive(:current_store).and_return(store)
    allow_any_instance_of(PallasTrade::Admin::EmailLogsController).to receive(:current_store).and_return(store)
    allow_any_instance_of(PallasTrade::Admin::ContactMessagesController).to receive(:current_store).and_return(store)
    allow_any_instance_of(PallasTrade::Admin::EmailNotificationScenariosController).to receive(:current_store).and_return(store)
  end

  describe 'GET /admin/emails (Email → Settings)' do
    it 'renders the email settings page' do
      get '/admin/emails'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Email Settings')
      expect(response.body).to include('mail_from_address')
    end

    it 'renders with the full admin layout (not the settings submenu layout)' do
      get '/admin/emails'
      # The Email menu lives in the top-level sidebar; the page must NOT use
      # the admin_settings layout (body class would contain "admin-settings").
      expect(response.body).not_to include('admin-settings')
    end
  end

  describe 'PATCH /admin/emails' do
    it 'saves the reply switch preference' do
      patch '/admin/emails', params: {
        store: { mail_from_address: 'orders@example.com', preferred_allow_email_replies: '1' }
      }
      expect(response).to have_http_status(:found)
      expect(store.reload.prefers_allow_email_replies?).to be(true)
    end
  end

  describe 'GET /admin/email_templates' do
    it 'renders the templates list with a created template' do
      create(:email_template, store: store, name: 'Welcome Email')
      get '/admin/email_templates'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Welcome Email')
    end
  end

  describe 'POST /admin/email_templates' do
    it 'creates a template' do
      post '/admin/email_templates', params: {
        email_template: { key: 'order.confirm_email', name: 'Confirm', subject: 'Order {order_number}', body_html: '<p>hi</p>', active: '1' }
      }
      expect(response).to have_http_status(:see_other)
      expect(store.email_templates.find_by(key: 'order.confirm_email')).to be_present
    end
  end

  describe 'GET /admin/email_notification_scenarios' do
    it 'renders the notification scenarios page' do
      get '/admin/email_notification_scenarios'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('order.confirm_email')
    end
  end

  describe 'GET /admin/email_logs' do
    it 'renders the send log with a recorded email' do
      create(:email_log, store: store, to: 'customer@example.com', subject: 'Order confirmation')
      get '/admin/email_logs'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('customer@example.com')
    end
  end

  describe 'GET /admin/contact_messages' do
    it 'renders the inbox with a complaint' do
      create(:contact_message, store: store, kind: 'complaint', email: 'angry@example.com', body: 'Broken!')
      get '/admin/contact_messages'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('angry@example.com')
    end
  end

  describe 'POST /admin/contact_messages/:id/resolve' do
    it 'marks a message resolved' do
      msg = create(:contact_message, store: store, status: 'pending')
      post "/admin/contact_messages/#{msg.prefixed_id}/resolve"
      expect(response).to have_http_status(:found)
      expect(msg.reload.status).to eq('resolved')
    end
  end

  # 优化：Email 菜单整合 — 旧设置入口重定向到新 Email 菜单
  describe 'legacy store email settings redirect' do
    it 'redirects GET /admin/store/edit?section=emails to /admin/emails' do
      get '/admin/store/edit', params: { section: 'emails' }
      expect(response).to have_http_status(:found)
      expect(response.location).to end_with('/admin/emails')
    end

    it 'redirects GET /admin/store/edit_emails to /admin/emails' do
      get '/admin/store/edit_emails'
      expect(response).to have_http_status(:found)
      expect(response.location).to end_with('/admin/emails')
    end
  end

  # 优化：SMTP 测试发送按钮 — POST /admin/emails/test_send
  describe 'POST /admin/emails/test_send (SMTP test button)' do
    it 'sends a test email via TestMailer and redirects back' do
      mailer = double(deliver_now: true)
      expect(PallasTrade::TestMailer).to receive(:test_email) do |opts|
        expect(opts[:to]).to eq('admin@example.com')
        expect(opts[:subject]).to include('Test email')
        mailer
      end

      post '/admin/emails/test_send', params: { to_email: 'admin@example.com' }
      expect(response).to have_http_status(:found)
      expect(response.location).to end_with('/admin/emails')
    end

    it 'falls back to the admin user email when to_email is blank' do
      mailer = double(deliver_now: true)
      expect(PallasTrade::TestMailer).to receive(:test_email) do |opts|
        expect(opts[:to]).to eq(admin.email)
        mailer
      end

      post '/admin/emails/test_send'
      expect(response).to have_http_status(:found)
    end

    it 'shows an error flash when delivery raises' do
      expect(PallasTrade::TestMailer).to receive(:test_email).and_raise(StandardError, 'SMTP boom')
      post '/admin/emails/test_send', params: { to_email: 'admin@example.com' }
      expect(response).to have_http_status(:found)
    end
  end

  # 优化：通知场景测试发送完善 — every scenario can send via TestMailer
  describe 'POST /admin/email_notification_scenarios/test (scenario test send)' do
    it 'sends a scenario test email even without business data' do
      mailer = double(deliver_now: true)
      expect(PallasTrade::TestMailer).to receive(:test_email).and_return(mailer)

      post '/admin/email_notification_scenarios/test', params: { key: 'order.cancel_email' }
      expect(response).to have_http_status(:found)
      expect(response.location).to end_with('/admin/email_notification_scenarios')
    end

    it 'reports an unknown scenario' do
      post '/admin/email_notification_scenarios/test', params: { key: 'unknown.scenario' }
      expect(response).to have_http_status(:found)
    end

    it 'renders the linked template when one exists' do
      create(:email_template, store: store, key: 'order.cancel_email', subject: 'Order {order_number} canceled', body_html: '<p>{order_number}</p>')
      mailer = double(deliver_now: true)
      expect(PallasTrade::TestMailer).to receive(:test_email) do |opts|
        expect(opts[:subject]).to eq('Order R123456789 canceled')
        expect(opts[:body_html]).to include('R123456789')
        mailer
      end

      post '/admin/email_notification_scenarios/test', params: { key: 'order.cancel_email' }
      expect(response).to have_http_status(:found)
    end
  end
end
