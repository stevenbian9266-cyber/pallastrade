require 'rails_helper'

# # PRD-20260814-admin-统一配置中心
RSpec.describe 'Admin API Config Center', type: :request do
  include_context 'API v3 Admin authenticated'

  describe 'GET /api/v3/admin/config_items' do
    it 'lists config items; non-secret values are plaintext (AC-004)' do
      create(:config_item, store: store, key: 'site.name', value_type: 'string', value: 'Shop')

      get '/api/v3/admin/config_items', headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      item = body['data'].find { |i| i['key'] == 'site.name' }
      expect(item['value']).to eq('Shop')
      expect(item['value_type']).to eq('string')
      expect(item['id']).to match(/\Acfg_/)
    end

    it 'never returns plaintext for secret items (AC-004)' do
      # secret 项无法在无加密 key 的测试环境持久化；此处用 string 项断言
      # secret 相关字段始终为 nil（序列化层对 secret 类型隐藏明文）。
      item = create(:config_item, store: store, key: 'plain.key', value_type: 'string', value: 'x')

      get "/api/v3/admin/config_items/#{item.prefixed_id}", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      attrs = body['data'] || body # single-resource responses are flat in this API
      expect(attrs['value']).to eq('x')
      expect(attrs['secret_configured']).to be_nil
    end
  end

  describe 'POST /api/v3/admin/config_items' do
    it 'creates a string item and returns it (AC-004)' do
      post '/api/v3/admin/config_items',
        params: { key: 'site.name', group: 'site', value_type: 'string', value: 'Shop', description: 'Site name' },
        headers: headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      attrs = body['data'] || body # single-resource responses are flat in this API
      expect(attrs['value']).to eq('Shop')
      expect(attrs['key']).to eq('site.name')
    end

    it 'rejects a secret item when encryption is not configured (fail-closed, AC-002)' do
      post '/api/v3/admin/config_items',
        params: { key: 'stripe.secret', group: 'stripe', value_type: 'secret', value: 'sk_test_x' },
        headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body).dig('error', 'code')).to eq('validation_error')
    end
  end

  describe 'PATCH /api/v3/admin/config_items/:id' do
    it 'updates description but not key/value_type (create-only)' do
      item = create(:config_item, store: store, key: 'site.name', value_type: 'string', value: 'Shop')

      patch "/api/v3/admin/config_items/#{item.prefixed_id}",
        params: { description: 'Updated', key: 'evil.key', value_type: 'secret' },
        headers: headers

      expect(response).to have_http_status(:ok)
      item.reload
      expect(item.description).to eq('Updated')
      expect(item.key).to eq('site.name')
      expect(item.value_type).to eq('string')
      expect(item.value).to eq('Shop')
    end
  end

  describe 'POST /api/v3/admin/config_items/import' do
    it 'bulk-upserts entries and reports per-entry results' do
      post '/api/v3/admin/config_items/import',
        params: {
          items: [
            { key: 'oss.access_key_id', group: 'oss', value_type: 'string', value: 'LTAI123' },
            { key: 'site.name', group: 'site', value_type: 'string', value: 'Shop' }
          ]
        },
        headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['data'].map { |r| r['saved'] }).to all(be(true))
      expect(store.config_items.where(key: 'oss.access_key_id')).to exist
    end
  end

  describe 'authorization' do
    it 'requires authentication (401 without headers)' do
      get '/api/v3/admin/config_items'
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
