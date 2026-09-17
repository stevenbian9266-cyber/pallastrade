# frozen_string_literal: true

require 'spec_helper'

# PRD-20260917-catalog-product-events
# AC-001 幂等、AC-002 白名单、AC-003 批量上限、AC-004 零 PII、
# AC-005 跨店隔离、AC-011 限流声明不变量
RSpec.describe 'POST /api/v3/store/catalog_events', type: :request do
  include_context 'API v3 Store guest'

  let(:store) { @default_store }
  let(:path) { '/api/v3/store/catalog_events' }
  let(:product) { create(:product, store: store) }
  let(:visitor_id) { 'visitor-abc' }
  let(:rows) { PallasTrade::CatalogEvent.for_store(store) }

  def post_events(events, visitor: visitor_id, **extra)
    post path,
         params: { visitor_id: visitor, events: events }.merge(extra),
         headers: headers,
         as: :json
  end

  def event_row(overrides = {})
    { event_id: SecureRandom.uuid, event_name: 'impression', list_id: 'related' }.merge(overrides)
  end

  describe 'happy path' do
    it 'persists a batch and returns the received count' do
      post_events([event_row, event_row(event_name: 'click')])

      expect(response).to have_http_status(:created)
      expect(json_response[:received]).to eq(2)
      expect(rows.count).to eq(2)
      expect(rows.pluck(:event_name)).to contain_exactly('impression', 'click')
    end

    it 'stores an irreversible visitor digest instead of the raw identifier' do
      post_events([event_row])

      digest = rows.first.session_hash

      expect(digest).to be_present
      expect(digest).not_to include(visitor_id)
      expect(digest).to eq(PallasTrade::CatalogEvent.digest_visitor(visitor_id, store))
    end

    it 'resolves a prefixed product id to its integer primary key' do
      post_events([event_row(product_id: product.prefixed_id)])

      expect(rows.first.product_id).to eq(product.id)
    end

    it 'accepts an anonymous guest (no customer JWT)' do
      post_events([event_row])

      expect(response).to have_http_status(:created)
    end
  end

  # AC-001 幂等
  describe 'idempotency' do
    it 'does not double count a replayed event_id' do
      2.times { post_events([{ event_id: 'fixed-id', event_name: 'impression', list_id: 'related' }]) }

      expect(response).to have_http_status(:created)
      expect(rows.count).to eq(1)
      expect(rows.first.event_id).to eq('fixed-id')
    end
  end

  # AC-002 白名单
  describe 'event name whitelist' do
    it 'rejects the whole batch when any name is unknown, writing nothing' do
      post_events([event_row, event_row(event_name: 'totally_made_up')])

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response[:error][:code]).to eq('invalid_request')
      expect(rows.count).to eq(0)
    end

    it 'accepts every whitelisted name' do
      post_events(PallasTrade::CatalogEvent::EVENT_NAMES.map { |name| event_row(event_name: name) })

      expect(response).to have_http_status(:created)
      expect(rows.count).to eq(PallasTrade::CatalogEvent::EVENT_NAMES.length)
    end
  end

  # AC-003 批量上限与字段白名单
  describe 'batch bounds' do
    it 'accepts exactly the maximum batch size' do
      post_events(Array.new(PallasTrade::CatalogEvent::MAX_BATCH_SIZE) { event_row })

      expect(response).to have_http_status(:created)
      expect(rows.count).to eq(PallasTrade::CatalogEvent::MAX_BATCH_SIZE)
    end

    it 'rejects one over the maximum without partial writes' do
      post_events(Array.new(PallasTrade::CatalogEvent::MAX_BATCH_SIZE + 1) { event_row })

      expect(response).to have_http_status(:unprocessable_content)
      expect(rows.count).to eq(0)
    end

    it 'rejects an empty batch' do
      post_events([])

      expect(response).to have_http_status(:unprocessable_content)
      expect(rows.count).to eq(0)
    end

    it 'drops attributes outside the whitelist (no arbitrary payload)' do
      post_events([event_row(email: 'a@b.com', ip: '1.2.3.4', user_agent: 'curl', metadata: { secret: 'x' })])

      expect(response).to have_http_status(:created)
      expect(rows.count).to eq(1)
      expect(rows.first.metadata).to be_nil
    end

    it 'ignores an unknown extra top-level field' do
      post_events([event_row], store_id: 999_999)

      expect(rows.first.store_id).to eq(store.id)
    end
  end

  # AC-004 零 PII
  describe 'zero PII' do
    it 'has no column able to hold an IP, user agent, email or customer identity' do
      columns = PallasTrade::CatalogEvent.column_names

      expect(columns).not_to include(
        'ip', 'remote_ip', 'user_agent', 'email', 'customer_id', 'user_id', 'visitor_id'
      )
    end

    it 'requires a visitor id' do
      post_events([event_row], visitor: '')

      expect(response).to have_http_status(:unprocessable_content)
      expect(rows.count).to eq(0)
    end
  end

  # AC-005 跨店隔离
  describe 'store scoping' do
    it 'writes only to the current store' do
      other = create(:store, code: 'catalog_events_api_scope_store')

      post_events([event_row])

      expect(rows.count).to eq(1)
      expect(PallasTrade::CatalogEvent.for_store(other).count).to eq(0)
    end
  end

  # AC-011 限流声明（⚠️ 见下方说明：Rails rate_limit 在测试环境不生效）
  #
  # 测试环境 `config.cache_store = :null_store`，而 `rate_limit ... store: Rails.cache`
  # 在**类定义时**绑定该 store ⇒ 所有 Rails 内置限流在 spec 中都是 inert
  # （既有端点如 back_in_stock_subscriptions 同样无法在 spec 中验证 429）。
  # 因此这里验证**设计不变量**：端点自带的 per-IP 配额必须严格低于父类按 API key
  # 计的整店配额，否则它形同虚设。
  describe 'rate limit design invariant' do
    it 'declares a per-IP limit stricter than the store-wide per-key cap' do
      controller = PallasTrade::Api::V3::Store::CatalogEventsController

      expect(controller::PER_IP_LIMIT_PER_WINDOW).to be < PallasTrade::Api::Config[:rate_limit_per_key]
      expect(controller::PER_IP_LIMIT_PER_WINDOW).to be > 0
    end
  end
end
