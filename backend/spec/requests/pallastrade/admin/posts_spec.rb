# frozen_string_literal: true

require 'rails_helper'

# PRD-20260816-other-新增cms博客 AC-004
RSpec.describe 'Admin blog posts pages', type: :request do
  let(:store) { create(:store, code: 'posts_admin_test') }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end

  before do
    sign_in admin
    admin_role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: admin_role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::PostsController).to receive(:current_store).and_return(store)
  end

  describe 'GET /admin/posts (Blog menu)' do
    it 'renders the posts list with a created post' do
      create(:post, store: store, title: 'Welcome Post')
      get '/admin/posts'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Welcome Post')
      expect(response.body).to include('Blog')
    end

    it 'renders the new post page with editor fields' do
      get '/admin/posts/new'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('New Post')
      expect(response.body).to include('title')
      expect(response.body).to include('published_at')
    end
  end

  describe 'POST /admin/posts' do
    it 'creates a post' do
      post '/admin/posts', params: {
        post: { title: 'My First Post', slug: 'my-first-post', excerpt: 'Hello', author: 'Admin' }
      }
      expect(response).to have_http_status(:see_other)
      expect(store.posts.find_by(slug: 'my-first-post')).to be_present
    end
  end

  describe 'PATCH /admin/posts/:id' do
    it 'updates a post' do
      post = create(:post, :draft, store: store, title: 'Draft', slug: 'draft-post')
      patch "/admin/posts/#{post.slug}", params: {
        post: { title: 'Published now', published_at: Time.current.iso8601 }
      }
      expect(response).to have_http_status(:see_other)
      expect(post.reload.title).to eq('Published now')
      expect(post.reload.published?).to be(true)
    end
  end
end
