require 'rails_helper'

# # PRD-20260814-admin-统一配置中心
RSpec.describe 'Admin Config Center page', type: :request do
  let(:store) { create(:store) }
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end

  before do
    sign_in admin
    admin_role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: admin_role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::ConfigItemsController).to receive(:current_store).and_return(store)
  end

  describe 'GET /admin/config_items' do
    it 'renders the Config Center page with items (AC-003)' do
      create(:config_item, store: store, key: 'site.name', value_type: 'string', value: 'Shop')

      get '/admin/config_items'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Config Center')
      expect(response.body).to include('site.name')
      expect(response.body).to include('Import from ENV')
    end
  end

  describe 'POST /admin/config_items' do
    it 'creates a string config item and redirects (AC-003)' do
      post '/admin/config_items', params: {
        config_item: { key: 'site.name', group: 'site', value_type: 'string', value: 'Shop', description: 'Site name' }
      }

      expect(response).to have_http_status(:see_other)
      expect(store.config_items.find_by(key: 'site.name').value).to eq('Shop')
    end

    it 'fails closed for secret items without encryption key (AC-002)' do
      post '/admin/config_items', params: {
        config_item: { key: 'stripe.secret', group: 'stripe', value_type: 'secret', value: 'sk_test_x' }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(store.config_items.where(key: 'stripe.secret')).not_to exist
    end
  end

  describe 'PATCH /admin/config_items/:id' do
    it 'updates description but keeps key immutable' do
      item = create(:config_item, store: store, key: 'site.name', value_type: 'string', value: 'Shop')

      patch "/admin/config_items/#{item.prefixed_id}", params: {
        config_item: { description: 'Updated', key: 'evil.key' }
      }

      expect(response).to have_http_status(:see_other)
      item.reload
      expect(item.description).to eq('Updated')
      expect(item.key).to eq('site.name')
    end
  end

  describe 'POST /admin/config_items/import' do
    it 'imports non-sensitive ENV vars as string items (AC-007)' do
      ENV['SITE_NAME'] = 'PallasTrade Shop'
      post '/admin/config_items/import', params: { env_keys: 'SITE_NAME' }

      expect(response).to have_http_status(:see_other)
      item = store.config_items.find_by(key: 'site.name')
      expect(item).not_to be_nil
      expect(item.value_type).to eq('string')
      expect(item.raw_value).to eq('PallasTrade Shop')
    ensure
      ENV.delete('SITE_NAME')
    end
  end
end
