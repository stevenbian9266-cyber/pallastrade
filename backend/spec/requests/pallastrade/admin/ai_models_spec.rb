require 'rails_helper'

RSpec.describe 'Admin AI Models page', type: :request do
  let(:store) { create(:store) }
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret') }

  before do
    sign_in admin
    allow_any_instance_of(PallasTrade::Admin::AIController).to receive(:current_store).and_return(store)

    # Create providers
    create(:integration, store: store, type: 'PallasTrade::AI::Integrations::DeepSeek', active: false)
    create(:integration, store: store, type: 'PallasTrade::AI::Integrations::OpenAI', active: false)
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

    it 'shows breadcrumb with AI Tools > Models' do
      get '/admin/ai/models'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Models')
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
end
