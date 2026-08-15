# frozen_string_literal: true

require 'spec_helper'

RSpec.describe '/api/v3/admin/redirects (SEO 301 CRUD)', type: :request do
  include_context 'API v3 Admin authenticated'

  let(:store) { @default_store }

  describe 'GET /api/v3/admin/redirects' do
    it 'lists redirects' do
      create(:redirect, store: store, from_path: '/a', to_path: '/b')
      create(:redirect, store: store, from_path: '/c', to_path: '/d')

      get '/api/v3/admin/redirects', headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response[:data].length).to eq(2)
    end
  end

  describe 'POST /api/v3/admin/redirects' do
    it 'creates a redirect' do
      post '/api/v3/admin/redirects',
           params: { from_path: '/old', to_path: '/new', status_code: 301, active: true },
           headers: headers

      expect(response).to have_http_status(:created)
      expect(json_response[:from_path]).to eq('/old')
      expect(json_response[:to_path]).to eq('/new')
    end

    it 'creates a redirect with a business title and description' do
      post '/api/v3/admin/redirects',
           params: { from_path: '/old', to_path: '/new', title: 'Espresso rename redirect', description: 'Old link jumps to the renamed product.' },
           headers: headers

      expect(response).to have_http_status(:created)
      expect(json_response[:title]).to eq('Espresso rename redirect')
      expect(json_response[:description]).to eq('Old link jumps to the renamed product.')
    end

    it 'rejects invalid redirects' do
      post '/api/v3/admin/redirects',
           params: { from_path: 'bad', to_path: 'https://evil.example.com/x' },
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'PATCH /api/v3/admin/redirects/:id' do
    it 'updates a redirect' do
      redirect = create(:redirect, store: store, from_path: '/old', to_path: '/new')

      patch "/api/v3/admin/redirects/#{redirect.prefixed_id}",
            params: { to_path: '/updated', active: false },
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response[:to_path]).to eq('/updated')
      expect(json_response[:active]).to eq(false)
    end
  end

  describe 'DELETE /api/v3/admin/redirects/:id' do
    it 'destroys a redirect' do
      redirect = create(:redirect, store: store)

      delete "/api/v3/admin/redirects/#{redirect.prefixed_id}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(PallasTrade::Redirect.find_by_prefix_id(redirect.prefixed_id)).to be_nil
    end
  end
end
