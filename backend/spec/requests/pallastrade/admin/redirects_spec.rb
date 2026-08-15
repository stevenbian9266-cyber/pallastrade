# frozen_string_literal: true

require 'rails_helper'

# Regression: /admin/redirects/new rendered a blank page because the form used
# `pallastrade_check_box :active, {}, true, false` (4 positional args) while the
# helper only accepts (method, options = {}) → ArgumentError → 500 blank page.
RSpec.describe 'Admin redirects pages', type: :request do
  # Explicit code: the global :store sequence may collide with leftover rows in
  # the shared test DB (index_pt_stores_on_code), so pin a unique code here.
  let(:store) { create(:store, code: 'admin_redirects_test_store') }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end

  before do
    sign_in admin
    admin_role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: admin_role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::RedirectsController).to receive(:current_store).and_return(store)
  end

  describe 'GET /admin/redirects' do
    it 'renders the redirects index page' do
      get '/admin/redirects'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('New Redirect')
    end

    it 'shows a plain-language intro explaining what redirects do' do
      get '/admin/redirects'

      expect(response.body).to include('Redirects let old links automatically jump to new ones')
    end

    it 'shows the URL-change list for products whose slug changed' do
      product = create(:product, store: store, name: 'Old Shaver')
      product.update!(slug: 'new-shaver')

      get '/admin/redirects'

      expect(response.body).to include('Products with changed URLs')
      expect(response.body).to include('Old Shaver')
      expect(response.body).to include('/products/old-shaver')
      expect(response.body).to include('/products/new-shaver')
    end
  end

  describe 'GET /admin/redirects/new' do
    it 'renders the new redirect form (regression: check_box arg count)' do
      get '/admin/redirects/new'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('from_path')
      expect(response.body).to include('to_path')
      expect(response.body).to include('active')
    end

    it 'shows a plain-language fill-in guide on the form' do
      get '/admin/redirects/new'

      expect(response.body).to include('Create one rule: old path (From Path)')
    end

    it 'pre-fills from_path/to_path from query params (URL-change quick action)' do
      get '/admin/redirects/new', params: { from_path: '/products/old-shaver', to_path: '/products/new-shaver' }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('value="/products/old-shaver"')
      expect(response.body).to include('value="/products/new-shaver"')
    end
  end
end
