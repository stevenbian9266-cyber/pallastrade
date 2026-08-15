# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin back-in-stock subscriptions pages', type: :request do
  let(:store) { create(:store, code: 'bis_admin_test') }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end

  before do
    sign_in admin
    admin_role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: admin_role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::BackInStockSubscriptionsController).to receive(:current_store).and_return(store)
  end

  describe 'GET /admin/back_in_stock_subscriptions' do
    it 'renders the subscriptions list' do
      product = create(:product, store: store, name: 'Sold Out Blender')
      create(:back_in_stock_subscription, store: store, product: product, email: 'waiting@example.com')

      get '/admin/back_in_stock_subscriptions'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Back in Stock Subscriptions')
      expect(response.body).to include('waiting@example.com')
      expect(response.body).to include('Sold Out Blender')
    end
  end
end
