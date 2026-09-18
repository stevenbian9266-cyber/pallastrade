# frozen_string_literal: true

require 'rails_helper'

# PRD-20260918-admin-ai-output-validation FR-004 —— 后台 AI 助手的「接线契约」。
#
# 这个规格把两侧放在一起断言，因为两边各自看都「像是对的」：
#   * ERB 侧：写一个属性哈希，期望它变成 Stimulus 需要的 `data-*`；
#   * JS 侧：按数据集键去取文案。
# 只要中间的编码规则不一致，按钮点了没反应、状态区一直是空白，
# 而任何只看 ERB 或只看 JS 的评审都会放行 —— 2026-09-18 前的五处视图正是如此：
# 属性没有 `data-` 前缀，Stimulus 从未挂载。
RSpec.describe 'Admin AI assist wiring', type: :request do
  # CI 不注入 PALLASTRADE_AI_ENABLED（系统总开关默认 false）→ 可用性 Gate 1 会先拦下，
  # 页面就不会渲染助手。显式打开，使本地与 CI 一致。
  before { allow(PallasTradeAI::Config).to receive(:system_enabled?).and_return(true) }

  let!(:store) do
    # `supported_locales` + 缺描述的 product 会命中 catalog_health 的
    # `missing_description` / `missing_translations` —— 页面上那两处 AI 单元格
    # 只在 issue 计数为正时才渲染，没有 issue 就无从验证它们的接线。
    create(:store, code: "ai_wiring_#{SecureRandom.hex(4)}", default: true,
                   default_currency: 'USD', default_locale: 'en', supported_locales: 'de,fr',
                   name: 'AI Wiring Store')
  end
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end
  # `let!` 而非 `let`：catalog_health 的 `before { get … }` 早于任何对 product 的引用，
  # 惰性求值会让「问题商品」在请求发出之后才创建，issue 计数恒为 0。
  let!(:product) { product_missing_description('Grinder Deluxe') }

  before do
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  # 默认语言（en）没有描述的「问题商品」：工厂会同时写一条 en 翻译行，只把列置空
  # 并不会让 issue 计数为正 —— 与 catalog_health_spec 的口径保持一致。
  def product_missing_description(name)
    product = create(:product, store: store, name: name, description: nil)
    product.translations.where(locale: 'en').update_all(description: nil)
    product.update_columns(description: nil)
    product
  end

  def ai_assist_nodes(body)
    Nokogiri::HTML(body).css('[data-controller~="ai-assist"]')
  end

  def ai_assist_labels(body)
    JSON.parse(ai_assist_nodes(body).first&.[]('data-ai-assist-labels') || '{}')
  end

  describe 'GET /admin/products/:id/edit' do
    before { get "/admin/products/#{product.slug}/edit" }

    it 'attaches the Stimulus controller and its values through data attributes (AC-010)' do
      expect(response).to have_http_status(:ok)

      nodes = ai_assist_nodes(response.body)
      message = 'AI 助手容器缺少 data-controller="ai-assist" —— 控制器不会挂载，按钮点了没反应'
      expect(nodes).not_to be_empty, message

      description_node = nodes.find { |node| node['data-ai-assist-kind-value'] == 'description' }
      expect(description_node).not_to be_nil, '商品描述助手容器未渲染'
      expect(description_node['data-ai-assist-endpoint-value']).to be_present
      expect(description_node['data-ai-assist-product-id-value']).to be_present
    end

    it 'ships every label the controller looks up (AC-010/AC-011)' do
      labels = ai_assist_labels(response.body)

      %w[Idle Generating Review Accepted ErrorFallback].each do |name|
        expect(labels).to have_key(name), "缺少控制器会查找的文案键 #{name}（现有：#{labels.keys.sort.inspect}）"
      end
      expect(labels['Generating']).to be_present
    end

    it 'has wording for the output and provider failure codes (AC-011)' do
      labels = ai_assist_labels(response.body)

      %w[Error:ai_output_invalid Error:ai_provider_unavailable Error:ai_credentials_invalid].each do |key|
        expect(labels[key]).to be_present, "缺少 #{key} 的文案"
      end
    end

    it 'keeps a generic fallback that is never empty (AC-010)' do
      expect(ai_assist_labels(response.body)['ErrorFallback']).to be_present
    end
  end

  describe 'GET /admin/catalog_health' do
    before { get '/admin/catalog_health' }

    it 'wires the assistant the same way (AC-010)' do
      expect(response).to have_http_status(:ok)

      # 页面上的 AI 单元格只在对应 issue 计数为正时才渲染。
      expect(PallasTrade::CatalogHealth::Issues.count(store, 'missing_description')).to be_positive
      message = 'catalog_health 的 AI 单元格未接上 data-controller'
      expect(ai_assist_nodes(response.body)).not_to be_empty, message
      expect(ai_assist_labels(response.body)['ErrorFallback']).to be_present
    end
  end
end
