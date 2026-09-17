# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-catalog-batch-e3-ai-fix-suggestion —— Catalog Health AI 修复建议（端点 + 渲染 + 安全边界）
#
#   AC-004 ← FR-003：POST /admin/ai/catalog_health_suggestion（工作台级）→ 200 + Run
#   AC-005 ← FR-007：零写库（请求前后商品与计数不变）
#   AC-008 ← FR-004/FR-005：工作台渲染（count>0 有按钮 / count==0 无按钮 / 未配置 disabled + title）
#   AC-009 ← FR-003：无 Product 读权限 → 拒绝且零 Run
#   AC-010 ← FR-008：i18n 键齐备
#   AC-011 ← FR-003：商品级端点 → 200 + issue_keys；无命中 → 422 nothing_to_fix
#   AC-012 ← FR-004b：商品编辑页侧栏卡片渲染（命中清单 / 空态 / 跨店 404）
RSpec.describe 'Admin catalog health AI suggestion', type: :request do
  # CI 不注入 PALLASTRADE_AI_ENABLED（系统总开关默认 false）→ 可用性 Gate 1 会先于店铺/能力
  # 配置拦下请求。这里显式打开系统开关，让用例在本地与 CI 行为一致。
  before { allow(PallasTradeAI::Config).to receive(:system_enabled?).and_return(true) }

  let!(:store) do
    create(:store, code: "health_ai_http_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD',
                   default_locale: 'en', supported_locales: 'de,fr', name: 'Health AI HTTP Store')
  end
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end

  def sign_in_as_admin
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::AIController).to receive(:current_store).and_return(store)
  end

  # 与 B-2 规格同款夹具：默认语言（en）无描述的问题商品（列 + 翻译行双保险）
  def product_missing_description(name)
    product = create(:product, store: store, name: name, description: nil)
    product.translations.where(locale: 'en').update_all(description: nil)
    product.update_columns(description: nil)
    product
  end

  def healthy_product(name)
    product = create(:product, store: store, name: name, description: 'A description')
    create(:image, viewable: product)
    product.update!(meta_title: 'Title', meta_description: 'Meta description')
    product.update_columns(status: 'active')
    product.master.stock_items.update_all(count_on_hand: 5, backorderable: false)
    # 不补翻译则 missing_translations 恒命中（店铺支持 de/fr）
    %w[de fr].each { |locale| product.translations.create!(locale: locale, name: "#{name} #{locale}") }
    product
  end

  def stub_provider(structured_output)
    response = double(
      'ai_response',
      text: structured_output.values.first,
      structured_output: structured_output,
      usage: { 'input_tokens' => 12, 'output_tokens' => 40 },
      provider_request_id: 'req_test_health_http'
    )
    allow_any_instance_of(PallasTrade::AI::Providers::DeepSeek).to receive(:generate).and_return(response)
  end

  def configure_provider_secret!(provider)
    allow(PallasTrade::AI::ProviderSecret).to receive(:find_by)
      .and_return(instance_double(PallasTrade::AI::ProviderSecret, configured?: true))
  end

  def configure_capability!(capability_key)
    PallasTrade::AI::ProvisionProviders.call(store: store)
    provider = store.ai_providers.find_by(type: 'PallasTrade::AI::Provider::DeepSeek')
    provider.update!(active: true)
    configure_provider_secret!(provider)
    PallasTrade::AI::ProvisionModels.call(provider: provider)
    model = PallasTrade::AI::Model.where(provider: provider, active: false).order(:name).first
    model.update!(active: true)
    PallasTrade::AI::Setting.find_or_initialize_by(store: store).update!(active: true)
    PallasTrade::AI::CapabilitySetting.find_or_create_by!(store: store, capability_key: capability_key) do |setting|
      setting.primary_model = model
      setting.active = true
    end
  end

  describe 'POST /admin/ai/catalog_health_suggestion（工作台级）' do
    before { configure_capability!('catalog.health_fix_suggestion') }

    # PRD-20260916-catalog-batch-e3-ai-fix-suggestion AC-004 AC-005
    it 'returns the plan and a run id without changing any catalog data' do
      product_missing_description('Missing Copy One')
      product_missing_description('Missing Copy Two')
      stub_provider(
        {
          'summary' => 'Descriptions first, then SEO.',
          'steps' => [
            { 'title' => 'Generate descriptions with the AI assistant', 'entry' => 'product_edit_ai' },
            { 'title' => 'Then review the SEO card', 'entry' => 'product_edit_ai' }
          ]
        }
      )
      sign_in_as_admin

      before_counts = PallasTrade::CatalogHealth::Issues::KEYS.map { |key| [key, PallasTrade::CatalogHealth::Issues.count(store, key)] }
      before_products = store.products.order(:id).pluck(:id, :status, :description)

      post '/admin/ai/catalog_health_suggestion', params: { issue_key: 'missing_description' }, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['summary']).to eq('Descriptions first, then SEO.')
      expect(body['steps'].size).to eq(2)
      expect(body['steps'].first['entry']).to eq('product_edit_ai')
      expect(body['issue_key']).to eq('missing_description')
      expect(body['count']).to eq(2)
      expect(body['run_id']).to be_present
      expect(PallasTrade::AI::Run.where(capability_key: 'catalog.health_fix_suggestion').count).to eq(1)

      # 零写库：计数与商品属性逐项一致
      expect(PallasTrade::CatalogHealth::Issues::KEYS.map { |key| [key, PallasTrade::CatalogHealth::Issues.count(store, key)] })
        .to eq(before_counts)
      expect(store.products.order(:id).pluck(:id, :status, :description)).to eq(before_products)
    end

    # PRD-20260916-catalog-batch-e3-ai-fix-suggestion AC-006
    it 'answers 422 nothing_to_fix without a run when the issue is empty' do
      sign_in_as_admin

      post '/admin/ai/catalog_health_suggestion', params: { issue_key: 'missing_translations' }, as: :json

      expect(response).to have_http_status(422)
      expect(response.parsed_body.dig('error', 'code')).to eq('nothing_to_fix')
      expect(PallasTrade::AI::Run.count).to eq(0)
    end

    # PRD-20260916-catalog-batch-e3-ai-fix-suggestion AC-006
    it 'answers 422 unknown_issue without a run' do
      sign_in_as_admin

      post '/admin/ai/catalog_health_suggestion', params: { issue_key: 'nope' }, as: :json

      expect(response).to have_http_status(422)
      expect(response.parsed_body.dig('error', 'code')).to eq('unknown_issue')
      expect(PallasTrade::AI::Run.count).to eq(0)
    end
  end

  describe 'POST /admin/ai/catalog_health_suggestion（商品级）(AC-011)' do
    before { configure_capability!('catalog.health_fix_suggestion') }

    # PRD-20260916-catalog-batch-e3-ai-fix-suggestion AC-011
    it 'answers with the plan for one product and its real issue keys' do
      problem = product_missing_description('Needs Attention')
      stub_provider({ 'summary' => 'Fix the copy.', 'steps' => [{ 'title' => 'Write it', 'entry' => 'product_edit_ai' }] })
      sign_in_as_admin

      post '/admin/ai/catalog_health_suggestion', params: { product_id: problem.prefixed_id }, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['summary']).to eq('Fix the copy.')
      expect(body['issue_keys']).to include('missing_description')
      expect(body['run_id']).to be_present
      expect(problem.reload.description).to be_blank
    end

    # PRD-20260916-catalog-batch-e3-ai-fix-suggestion AC-011
    it 'answers 422 nothing_to_fix for a healthy product' do
      healthy = healthy_product('All Good')
      sign_in_as_admin

      post '/admin/ai/catalog_health_suggestion', params: { product_id: healthy.prefixed_id }, as: :json

      expect(response).to have_http_status(422)
      expect(response.parsed_body.dig('error', 'code')).to eq('nothing_to_fix')
      expect(PallasTrade::AI::Run.count).to eq(0)
    end

    # PRD-20260916-catalog-batch-e3-ai-fix-suggestion AC-012
    it 'rejects a product from another store' do
      other_store = create(:store, code: "health_ai_other_#{SecureRandom.hex(4)}", default_currency: 'USD',
                                   default_locale: 'en', supported_locales: 'de')
      stranger = create(:product, store: other_store, name: 'Not Mine')
      sign_in_as_admin

      post '/admin/ai/catalog_health_suggestion', params: { product_id: stranger.prefixed_id }, as: :json

      expect(response).to have_http_status(:not_found)
      expect(PallasTrade::AI::Run.count).to eq(0)
    end
  end

  describe 'degradation + rendering (AC-008/AC-012)' do
    # PRD-20260916-catalog-batch-e3-ai-fix-suggestion AC-008
    it 'renders the worklist assistant disabled with a reason when AI is not configured' do
      product_missing_description('Missing Copy')
      sign_in_as_admin

      get '/admin/catalog_health'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t('admin.catalog_health.ai.button'))

      doc = Nokogiri::HTML(response.body)
      buttons = doc.css('[data-ai-assist-role="generate"]')
      expect(buttons.size).to eq(PallasTrade::CatalogHealth::Issues::KEYS.count { |key| PallasTrade::CatalogHealth::Issues.count(store, key).positive? })
      expect(buttons.map { |button| button['disabled'] }).to all(be_truthy)
      expect(buttons.first['title']).to be_present
      expect(response.body).to include('data-testid="ai-health-suggestion-preview"')
    end

    # PRD-20260916-catalog-batch-e3-ai-fix-suggestion AC-008
    it 'renders no assistant for issues with a zero count' do
      product_missing_description('Missing Copy')
      sign_in_as_admin

      get '/admin/catalog_health'

      doc = Nokogiri::HTML(response.body)
      # 把查询限定在「issue 清单」那张表：页面上还有别的表格（健康分明细），
      # 不限定的话 `doc.css('tbody')` 会把它也数进来。
      worklist = doc.at_css('[data-testid="catalog-health-issues"]')
      with_button = worklist.css('tbody').count { |tbody| tbody.at_css('[data-ai-assist-role="generate"]').present? }
      without_button = worklist.css('tbody').count { |tbody| tbody.at_css('[data-ai-assist-role="generate"]').nil? }
      zero_keys = PallasTrade::CatalogHealth::Issues::KEYS.count { |key| PallasTrade::CatalogHealth::Issues.count(store, key).zero? }

      # 每个 issue 一个 tbody；只有计数 > 0 的行才有按钮
      expect(with_button).to eq(PallasTrade::CatalogHealth::Issues::KEYS.size - zero_keys)
      expect(without_button).to eq(zero_keys)
      expect(zero_keys).to be_positive
    end

    # PRD-20260916-catalog-batch-e3-ai-fix-suggestion AC-012
    it 'renders the product card with the issues and a disabled assistant when AI is missing' do
      problem = product_missing_description('Needs Attention')
      problem.update_columns(meta_title: nil, meta_description: nil)
      sign_in_as_admin

      get "/admin/products/#{problem.slug}/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="product-catalog-health-card"')
      expect(response.body).to include('data-testid="product-catalog-health-issues"')
      expect(response.body).to include(PallasTrade.t('admin.catalog_health.issues.missing_description'))

      card = Nokogiri::HTML(response.body).at_css('[data-testid="product-catalog-health-card"]')
      button = card.at_css('[data-ai-assist-role="generate"]')
      expect(button).to be_present
      expect(button['disabled']).to be_truthy
      expect(button['title']).to be_present
    end

    # PRD-20260916-catalog-batch-e3-ai-fix-suggestion AC-012
    it 'renders the product card empty state for a healthy product' do
      healthy = healthy_product('All Good')
      sign_in_as_admin

      get "/admin/products/#{healthy.slug}/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="product-catalog-health-empty"')
      expect(response.body).not_to include('data-testid="ai-product-health-suggestion"')
    end
  end

  describe 'permissions (AC-009)' do
    # PRD-20260916-catalog-batch-e3-ai-fix-suggestion AC-009
    it 'denies a user who may not read products' do
      configure_capability!('catalog.health_fix_suggestion')
      product_missing_description('Missing Copy')
      stranger = create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
      sign_in stranger
      allow_any_instance_of(PallasTrade::Admin::AIController).to receive(:current_store).and_return(store)

      post '/admin/ai/catalog_health_suggestion', params: { issue_key: 'missing_description' }, as: :json

      expect(response).not_to have_http_status(:ok)
      expect(PallasTrade::AI::Run.count).to eq(0)
    end
  end

  describe 'i18n (AC-010)' do
    # PRD-20260916-catalog-batch-e3-ai-fix-suggestion AC-010
    it 'ships every suggestion label and entry name' do
      keys = %w[
        admin.catalog_health.ai.button
        admin.catalog_health.ai.dismiss
        admin.catalog_health.ai.generating
        admin.catalog_health.ai.summary_heading
        admin.catalog_health.ai.errors.default
        admin.catalog_health.ai.errors.nothing_to_fix
        admin.catalog_health.ai.errors.unknown_issue
        admin.catalog_health.card.title
        admin.catalog_health.card.empty
        admin.catalog_health.card.issues_heading
        admin.catalog_health.card.ai_heading
      ] + PallasTrade::AI::Catalog::HealthFixSuggestion::ENTRIES.map { |entry| "admin.catalog_health.ai.entries.#{entry}" }

      keys.each do |key|
        expect(PallasTrade.t(key, default: nil)).to be_present, "missing translation for #{key}"
      end
    end
  end
end
