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
  end

  describe 'GET /admin/redirects/new' do
    it 'renders the new redirect form (regression: check_box arg count)' do
      get '/admin/redirects/new'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('from_path')
      expect(response.body).to include('to_path')
      expect(response.body).to include('active')
    end
  end
end
