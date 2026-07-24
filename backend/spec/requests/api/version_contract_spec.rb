require 'spec_helper'

RSpec.describe 'API version contract', type: :request do
  retired_paths = [
    '/api/v1/store/products',
    '/api/v1/admin/products',
    '/api/v2/storefront/products',
    '/api/v2/platform/products'
  ]

  retired_paths.each do |path|
    it "rejects #{path} with the JSON route-not-found contract" do
      get path

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
end
