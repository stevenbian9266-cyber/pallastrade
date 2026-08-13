require 'rails_helper'

# # PRD-20260813-storefront-裁剪-admin-storefront-页面-vercel-集成-ui-并优化已连接-origins-展示
RSpec.describe 'Admin Storefront page', type: :request do
  let(:store) { create(:store) }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end

  before do
    sign_in admin
    # RoleUser is store-scoped; bind the admin role to the test store so the
    # CanCanCan ability (which scopes roles by store) grants :admin.
    admin_role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: admin_role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::StorefrontController).to receive(:current_store).and_return(store)
  end

  describe 'GET /admin/storefront' do
    it 'renders the storefront setup page with core credentials (# AC-002)' do
      get '/admin/storefront'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Setup Storefront')
      expect(response.body).to include('Store API URL')
      expect(response.body).to include('Publishable API key')
      expect(response.body).to include('Storefront URL')
    end

    it 'does not render any Vercel deployment UI (# PRD-20260813-storefront AC-001)' do
      get '/admin/storefront'

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('Deploy to Vercel')
      expect(response.body).not_to include('vercel-deploy-button')
      expect(response.body).not_to include('View on Vercel')
      expect(response.body).not_to include('loopback_warning')
    end

    it 'renders Connected storefronts when a non-loopback origin exists (# AC-005)' do
      create(:allowed_origin, store: store, origin: 'https://dev.pallastrade.cn')

      get '/admin/storefront'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Connected storefronts')
      expect(response.body).to include('https://dev.pallastrade.cn')
    end

    it 'does not render an empty Connected storefronts card when only loopback origins exist (# AC-005)' do
      create(:allowed_origin, store: store, origin: 'http://localhost')

      get '/admin/storefront'

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('Connected storefronts')
    end
  end

  describe 'dead code cleanup (# AC-003 / AC-004)' do
    it 'removes the Vercel-only storefront helper file' do
      helper_file = Rails.root.join('pallastrade_gems/pallastrade_admin/app/helpers/pallastrade/admin/storefront_helper.rb')
      expect(File.exist?(helper_file)).to be(false)
    end

    it 'removes Vercel i18n keys from admin en.yml' do
      en_yml = Rails.root.join('pallastrade_gems/pallastrade_admin/config/locales/en.yml').read
      %w[deploy_button deploy_copy deploy_finish_hint deploy_title loopback_warning view_on_vercel].each do |key|
        expect(en_yml).not_to match(/\b#{key}:/)
      end
    end
  end
end
