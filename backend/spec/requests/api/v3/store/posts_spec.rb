# frozen_string_literal: true

require 'spec_helper'

# PRD-20260816-other-新增cms博客 AC-002
RSpec.describe 'GET /api/v3/store/posts', type: :request do
  include_context 'API v3 Store guest'

  let(:store) { @default_store }

  describe 'GET /api/v3/store/posts' do
    it 'lists only published posts' do
      published = create(:post, store: store, title: 'Published post')
      create(:post, :draft, store: store, title: 'Draft post')
      create(:post, :scheduled, store: store, title: 'Scheduled post')

      get '/api/v3/store/posts', headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response[:data].length).to eq(1)
      expect(json_response[:data].first[:title]).to eq('Published post')
      expect(json_response[:data].first[:id]).to eq(published.prefixed_id)
      expect(json_response[:meta][:count]).to eq(1)
    end

    it 'orders newest first' do
      create(:post, store: store, title: 'Older', published_at: 2.days.ago)
      create(:post, store: store, title: 'Newer', published_at: 1.hour.ago)

      get '/api/v3/store/posts', headers: headers

      expect(json_response[:data].first[:title]).to eq('Newer')
    end

    it 'returns empty list when no published posts' do
      create(:post, :draft, store: store)

      get '/api/v3/store/posts', headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response[:data]).to be_empty
    end
  end

  describe 'GET /api/v3/store/posts/:slug' do
    it 'returns a published post by slug' do
      post = create(:post, store: store, slug: 'welcome', title: 'Welcome!', body: '<p>Hello world</p>')

      get '/api/v3/store/posts/welcome', headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response[:title]).to eq('Welcome!')
      expect(json_response[:slug]).to eq('welcome')
      expect(json_response[:body]).to eq('Hello world')
      expect(json_response[:id]).to eq(post.prefixed_id)
    end

    it 'returns a published post by prefixed ID' do
      post = create(:post, store: store, title: 'By ID')

      get "/api/v3/store/posts/#{post.prefixed_id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response[:title]).to eq('By ID')
    end

    it 'returns 404 for a draft post' do
      create(:post, :draft, store: store, slug: 'draft-post')

      get '/api/v3/store/posts/draft-post', headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for a scheduled post' do
      create(:post, :scheduled, store: store, slug: 'future-post')

      get '/api/v3/store/posts/future-post', headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for unknown slug' do
      get '/api/v3/store/posts/does-not-exist', headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
