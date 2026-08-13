require 'rails_helper'

# # PRD-20260813-storefront 第 3 项：Store API CORS 收紧为 allowed_origins 白名单
RSpec.describe 'CORS policy', type: :request do
  let(:store) { create(:store) }

  before { Rails.cache.clear }

  describe 'Store API (/api/v3/store/*)' do
    it 'allows an explicitly allowed storefront origin (# AC: 白名单放行)' do
      create(:allowed_origin, store: store, origin: 'https://dev.pallastrade.cn')

      get '/api/v3/store/products', headers: { 'Origin' => 'https://dev.pallastrade.cn' }

      expect(response.headers['Access-Control-Allow-Origin']).to eq('https://dev.pallastrade.cn')
    end

    it 'answers CORS preflight for an allowed origin (# AC: 预检放行)' do
      create(:allowed_origin, store: store, origin: 'https://dev.pallastrade.cn')

      options '/api/v3/store/products', headers: {
        'Origin' => 'https://dev.pallastrade.cn',
        'Access-Control-Request-Method' => 'GET'
      }

      expect(response.headers['Access-Control-Allow-Origin']).to eq('https://dev.pallastrade.cn')
    end

    it 'does not grant CORS to a non-allowed origin (# AC: 非白名单拦截)' do
      get '/api/v3/store/products', headers: { 'Origin' => 'https://evil.example.com' }

      expect(response.headers['Access-Control-Allow-Origin']).to be_nil
    end

    it 'does not grant CORS preflight to a non-allowed origin (# AC: 预检拦截)' do
      options '/api/v3/store/products', headers: {
        'Origin' => 'https://evil.example.com',
        'Access-Control-Request-Method' => 'GET'
      }

      expect(response.headers['Access-Control-Allow-Origin']).to be_nil
    end
  end

  describe 'Admin API (/api/v3/admin/*) still uses the allowlist (regression)' do
    it 'rejects a non-allowed origin' do
      get '/api/v3/admin/products', headers: { 'Origin' => 'https://evil.example.com' }

      expect(response.headers['Access-Control-Allow-Origin']).to be_nil
    end
  end
end
