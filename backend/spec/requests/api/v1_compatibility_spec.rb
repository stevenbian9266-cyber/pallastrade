# frozen_string_literal: true

RSpec.describe 'API v1 compatibility', type: :request do
  let(:password) { 'pallastrade123' }
  let!(:admin_user) do
    create(
      :admin_user,
      email: 'admin-v1@example.com',
      password: password,
      password_confirmation: password
    )
  end

  def login(path)
    post path,
         params: { email: admin_user.email, password: password },
         as: :json
  end

  shared_examples 'a working admin login' do |path|
    it "authenticates through #{path}" do
      login(path)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/json')
      expect(json_response[:token]).to be_present
      expect(json_response.dig(:user, :email)).to eq(admin_user.email)
    end
  end

  include_examples 'a working admin login', '/api/v1/admin/auth/login'
  include_examples 'a working admin login', '/api/v3/admin/auth/login'

  it 'uses a v1 admin JWT to list products' do
    login('/api/v1/admin/auth/login')
    token = json_response.fetch(:token)

    get '/api/v1/admin/products', headers: { 'Authorization' => "Bearer #{token}" }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('application/json')
    expect(json_response).to have_key(:data)
  end

  it 'returns the JSON error contract for malformed login JSON' do
    post '/api/v1/admin/auth/login',
         params: '{invalid',
         headers: { 'CONTENT_TYPE' => 'application/json' }

    expect(response).to have_http_status(:bad_request)
    expect(response.media_type).to eq('application/json')
    expect(json_response.dig(:error, :code)).to eq('invalid_request')
  end

  it 'returns a JSON 404 for a missing v1 store product' do
    api_key = create(:api_key, :publishable, store: @default_store)

    get '/api/v1/store/products/nonexistent',
        headers: { 'X-PallasTrade-Api-Key' => api_key.token }

    expect(response).to have_http_status(:not_found)
    expect(response.media_type).to eq('application/json')
    expect(json_response.dig(:error, :code)).to eq('record_not_found')
  end

  it 'returns a JSON 404 for an unmatched API route' do
    get '/api/v1/does-not-exist'

    expect(response).to have_http_status(:not_found)
    expect(response.media_type).to eq('application/json')
    expect(JSON.parse(response.body)).to eq(
      'error' => {
        'code' => 'route_not_found',
        'message' => 'API endpoint not found'
      }
    )
  end
end
