# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'GET /api/v3/store/redirects/resolve (SEO 301)', type: :request do
  include_context 'API v3 Store guest'

  let(:store) { @default_store }

  context 'when the path matches an active redirect' do
    let!(:redirect) { create(:redirect, store: store, from_path: '/old-product', to_path: '/new-product') }

    it 'returns the target path and status code' do
      get '/api/v3/store/redirects/resolve', params: { path: '/old-product' }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response[:data][:path]).to eq('/new-product')
      expect(json_response[:data][:status_code]).to eq(301)
    end

    it 'matches after normalization (trailing slash / origin stripped)' do
      get '/api/v3/store/redirects/resolve', params: { path: 'old-product/' }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response[:data][:path]).to eq('/new-product')
    end
  end

  context 'when the redirect is inactive' do
    let!(:redirect) { create(:redirect, store: store, from_path: '/old', to_path: '/new', active: false) }

    it 'returns data: null' do
      get '/api/v3/store/redirects/resolve', params: { path: '/old' }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response[:data]).to be_nil
    end
  end

  context 'when the path does not match' do
    it 'returns data: null' do
      get '/api/v3/store/redirects/resolve', params: { path: '/unmatched' }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response[:data]).to be_nil
    end
  end

  context 'when no path param is provided' do
    it 'returns data: null' do
      get '/api/v3/store/redirects/resolve', params: {}, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response[:data]).to be_nil
    end
  end
end
