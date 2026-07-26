require 'rails_helper'

RSpec.describe 'Admin AI pages', type: :request do
  let(:admin) { PallasTrade::AdminUser.first || create(:admin_user, password: 'secret', password_confirmation: 'secret') }

  before do
    sign_in admin
  end

  describe 'GET /admin/ai' do
    it 'renders the AI overview page with breadcrumb' do
      get '/admin/ai'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('AI Tools')
    end
  end

  describe 'GET /admin/ai/providers' do
    it 'renders the providers page with breadcrumb chain' do
      get '/admin/ai/providers'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Providers')
    end
  end

  describe 'GET /admin/ai/models' do
    it 'renders the models page with breadcrumb' do
      get '/admin/ai/models'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Models')
    end
  end

  describe 'GET /admin/ai/capabilities' do
    it 'renders the capabilities page' do
      get '/admin/ai/capabilities'
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /admin/ai/runs' do
    it 'renders the runs page' do
      get '/admin/ai/runs'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Runs')
    end
  end
end
