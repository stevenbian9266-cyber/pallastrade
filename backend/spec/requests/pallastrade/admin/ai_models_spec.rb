require 'rails_helper'

RSpec.describe 'Admin AI Models page', type: :request do
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
    allow_any_instance_of(PallasTrade::Admin::AIController).to receive(:current_store).and_return(store)

    # Create providers
    create(:ai_provider, store: store, type: 'PallasTrade::AI::Provider::DeepSeek', active: false)
    create(:ai_provider, store: store, type: 'PallasTrade::AI::Provider::OpenAI', active: false)
  end

  describe 'GET /admin/ai/models' do
    it 'renders the models page with catalog models auto-provisioned' do
      get '/admin/ai/models'

      expect(response).to have_http_status(:ok)
      # After auto-provisioning, should have 5 models (2 DeepSeek + 3 OpenAI)
      expect(response.body).to include('deepseek-v4-flash')
      expect(response.body).to include('deepseek-v4-pro')
      expect(response.body).to include('gpt-5.6-sol')
      expect(response.body).to include('gpt-5.6-terra')
      expect(response.body).to include('gpt-5.6-luna')
    end

    it 'shows breadcrumb with AI Tools > Models (no duplicate base crumb, P3 auto-derive)' do
      get '/admin/ai/models'

      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      crumb_text = doc.at_css('nav[aria-label="breadcrumb"]')&.text.to_s
      expect(crumb_text).to include('Models')
      expect(crumb_text).to include('AI tools')
      # P3 自动推导接管 base crumb 后不得出现重复的 AI Tools 项
      expect(crumb_text.scan(/AI tools|AI Tools/).size).to eq(1)
    end
  end

  describe 'GET /admin/ai (overview)' do
    it 'shows correct model count after provisioning' do
      # Visit models page first to trigger provisioning
      get '/admin/ai/models'
      get '/admin/ai'

      expect(response).to have_http_status(:ok)
      # Should show 0 active / 5 total (all models are inactive by default)
      expect(response.body).to include('0 / 5')
    end
  end

  describe 'PATCH /admin/ai/models/:id' do
    before { get '/admin/ai/models' } # auto-provision catalog models

    it 'updates active via turbo_stream without redirect (# PRD-20260808-admin-ai-tools-page-optimization AC-003/004)' do
      model = PallasTrade::AI::Model.find_by(provider_model_id: 'deepseek-v4-flash')
      expect(model.active).to be false

      patch "/admin/ai/models/#{model.id}", params: { active: '1' }, as: :turbo_stream

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include("ai_model_row_#{model.id}")
      expect(model.reload.active).to be true
    end

    it 'persists active state across requests (# PRD-20260808-admin-ai-tools-page-optimization AC-005)' do
      model = PallasTrade::AI::Model.find_by(provider_model_id: 'deepseek-v4-flash')

      patch "/admin/ai/models/#{model.id}", params: { active: '1' }, as: :turbo_stream
      get '/admin/ai/models'

      expect(response.body).to include('deepseek-v4-flash')
      expect(model.reload.active).to be true
    end

    it 'supports html fallback with redirect' do
      model = PallasTrade::AI::Model.find_by(provider_model_id: 'deepseek-v4-flash')

      patch "/admin/ai/models/#{model.id}", params: { active: '1' }

      expect(response).to have_http_status(:found)
      expect(model.reload.active).to be true
    end

    it 'turns off when active is false (# PRD-20260808-admin-ai-tools-page-optimization AC-004)' do
      model = PallasTrade::AI::Model.find_by(provider_model_id: 'deepseek-v4-flash')
      model.update!(active: true)

      patch "/admin/ai/models/#{model.id}", params: { active: '0' }, as: :turbo_stream

      expect(model.reload.active).to be false
    end

    it 'turns off when active param is missing (unchecked checkbox, no 500)' do
      model = PallasTrade::AI::Model.find_by(provider_model_id: 'deepseek-v4-flash')
      model.update!(active: true)

      patch "/admin/ai/models/#{model.id}", params: {}, as: :turbo_stream

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(model.reload.active).to be false
    end
  end
end
