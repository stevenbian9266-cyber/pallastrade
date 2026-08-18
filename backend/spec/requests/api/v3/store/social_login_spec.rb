# frozen_string_literal: true

require 'spec_helper'

# PRD-20260818-other-p1-1-社交登录-google-facebook
# AC-003：store_authentication_strategies 含 google/facebook；未配置时返回明确错误
RSpec.describe 'Store social login API', type: :request do
  include_context 'API v3 Store guest'

  describe 'POST /api/v3/store/auth/login with provider dispatch' do
    it 'registers google and facebook in the store strategy registry' do
      keys = PallasTrade.store_authentication_strategies.keys
      expect(keys).to include(:google, :facebook)
      expect(PallasTrade.admin_authentication_strategies.keys).not_to include(:google, :facebook)
    end

    it 'returns a clear error when google is not configured' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('GOOGLE_CLIENT_ID').and_return(nil)

      post '/api/v3/store/auth/login', params: { provider: 'google', id_token: 'x' }, headers: api_key_headers
      expect(response).to have_http_status(:unauthorized)
      expect(json_response[:error]).to be_present
    end

    it 'returns invalid_provider for an unsupported provider' do
      post '/api/v3/store/auth/login', params: { provider: 'unknown_provider', token: 'x' }, headers: api_key_headers
      expect(response).to have_http_status(:bad_request)
    end

    it 'still authenticates with email provider' do
      user = create(:user, password: 'secret123', password_confirmation: 'secret123')
      post '/api/v3/store/auth/login', params: { provider: 'email', email: user.email, password: 'secret123' }, headers: api_key_headers
      expect(response).to have_http_status(:ok)
      expect(json_response[:token]).to be_present
    end
  end
end
