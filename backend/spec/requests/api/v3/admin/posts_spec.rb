# frozen_string_literal: true

require 'spec_helper'

# PRD-20260816-other-新增cms博客 AC-003
RSpec.describe '/api/v3/admin/posts (CMS blog CRUD)', type: :request do
  include_context 'API v3 Admin authenticated'

  let(:store) { @default_store }

  describe 'GET /api/v3/admin/posts' do
    it 'lists posts including drafts and scheduled' do
      create(:post, store: store, title: 'Published')
      create(:post, :draft, store: store, title: 'Draft')
      create(:post, :scheduled, store: store, title: 'Scheduled')

      get '/api/v3/admin/posts', headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response[:data].length).to eq(3)
    end

    it 'includes a status attribute' do
      create(:post, store: store, title: 'Published')
      create(:post, :draft, store: store, title: 'Draft')

      get '/api/v3/admin/posts', headers: headers

      statuses = json_response[:data].map { |p| p[:status] }.sort
      expect(statuses).to eq(%w[draft published])
    end
  end

  describe 'POST /api/v3/admin/posts' do
    it 'creates a published post' do
      post '/api/v3/admin/posts',
           params: { title: 'Hello world', slug: 'hello-world', excerpt: 'Intro', author: 'Admin', published_at: Time.current.iso8601 },
           headers: headers

      expect(response).to have_http_status(:created)
      expect(json_response[:title]).to eq('Hello world')
      expect(json_response[:slug]).to eq('hello-world')
      expect(json_response[:status]).to eq('published')
      expect(PallasTrade::Post.for_store(store).count).to eq(1)
    end

    it 'creates a draft post when published_at is blank' do
      post '/api/v3/admin/posts',
           params: { title: 'Draft post' },
           headers: headers

      expect(response).to have_http_status(:created)
      expect(json_response[:status]).to eq('draft')
    end

    it 'creates a scheduled post with a future published_at' do
      post '/api/v3/admin/posts',
           params: { title: 'Future', published_at: 2.days.from_now.iso8601 },
           headers: headers

      expect(response).to have_http_status(:created)
      expect(json_response[:status]).to eq('scheduled')
    end

    it 'rejects a missing title' do
      post '/api/v3/admin/posts',
           params: { slug: 'no-title' },
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'PATCH /api/v3/admin/posts/:id' do
    it 'updates a post' do
      post = create(:post, :draft, store: store, title: 'Draft')

      patch "/api/v3/admin/posts/#{post.prefixed_id}",
            params: { title: 'Updated', published_at: Time.current.iso8601 },
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response[:title]).to eq('Updated')
      expect(json_response[:status]).to eq('published')
    end
  end

  describe 'DELETE /api/v3/admin/posts/:id' do
    it 'destroys a post' do
      post = create(:post, store: store)

      delete "/api/v3/admin/posts/#{post.prefixed_id}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(PallasTrade::Post.find_by_prefix_id(post.prefixed_id)).to be_nil
    end
  end
end
