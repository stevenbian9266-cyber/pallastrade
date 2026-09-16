# frozen_string_literal: true

require 'rails_helper'

# PRD-20260915-catalog-batch-e1-ai-copilot —— 商品编辑页 AI 助手（端点 + 渲染 + 安全边界）
#
#   AC-004 ← FR-003：POST /admin/ai/product_description → { text, run_id }
#   AC-005 ← FR-004：POST /admin/ai/product_seo       → { meta_title, meta_description, run_id }
#   AC-006 ← FR-005：接受前商品字段不变（AI 无写库路径）
#   AC-007 ← FR-006：AI 未配置 → 422 + 可读原因码；页面按钮 disabled
#   AC-008 ← FR-008：无商品 update 权限 → 拒绝且不产生 Run
#   AC-010 ← FR-009：i18n 键齐备
RSpec.describe 'Admin product AI copilot', type: :request do
  # CI 不注入 PALLASTRADE_AI_ENABLED（系统总开关默认 false）→ 可用性 Gate 1 会先于店铺/能力
  # 配置拦下请求。这里显式打开系统开关，让用例在本地与 CI 行为一致。
  before { allow(PallasTradeAI::Config).to receive(:system_enabled?).and_return(true) }

  let!(:store) do
    create(:store, code: "ai_copilot_#{SecureRandom.hex(4)}", default: true,
                   default_currency: 'USD', default_locale: 'en', name: 'AI Copilot Store')
  end
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end
  let(:product) { create(:product, store: store, name: 'Grinder Deluxe', description: 'Old copy') }

  def sign_in_as_admin
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::AIController).to receive(:current_store).and_return(store)
  end

  def stub_provider(structured_output)
    response = double(
      'ai_response',
      text: structured_output.values.first,
      structured_output: structured_output,
      usage: { 'input_tokens' => 5, 'output_tokens' => 15 },
      provider_request_id: 'req_test_2'
    )
    allow_any_instance_of(PallasTrade::AI::Providers::DeepSeek).to receive(:generate).and_return(response)
  end

  # CI 不注入 ACTIVE_RECORD_ENCRYPTION_*，而 ProviderSecret 的 fail-closed 守卫会拒绝真实写入
  # （设计如此：无密钥不落库）。可用性 Gate 7 只要求 secret「已配置」，且本用例已把 provider
  # adapter stub 掉、不会真正取用密钥 —— 因此用内存替身满足前置条件，让用例在
  # 「有/无加密密钥」的环境下行为一致。
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

  describe 'POST /admin/ai/product_description (AC-004/AC-006)' do
    before { configure_capability!('catalog.product_description') }

    it 'returns the draft and a run id without writing the product' do
      stub_provider({ 'text' => 'A sturdy burr grinder for daily espresso.' })
      sign_in_as_admin
      before_attributes = product.reload.attributes

      post '/admin/ai/product_description',
           params: { product_id: product.prefixed_id, mode: 'generate' },
           as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['text']).to eq('A sturdy burr grinder for daily espresso.')
      expect(body['run_id']).to be_present
      expect(product.reload.attributes).to eq(before_attributes)
      expect(product.reload.description).to eq('Old copy')
    end

    it 'rejects a product from another store' do
      other_store = create(:store, code: "ai_other_#{SecureRandom.hex(4)}", default_currency: 'USD', default_locale: 'en')
      stranger = create(:product, store: other_store, name: 'Not Mine')
      sign_in_as_admin

      post '/admin/ai/product_description', params: { product_id: stranger.prefixed_id }, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /admin/ai/product_seo (AC-005)' do
    before { configure_capability!('catalog.product_seo') }

    it 'returns both meta fields' do
      stub_provider({ 'meta_title' => 'Grinder Deluxe | Shop', 'meta_description' => 'Shop the Grinder Deluxe.' })
      sign_in_as_admin

      post '/admin/ai/product_seo', params: { product_id: product.prefixed_id }, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['meta_title']).to eq('Grinder Deluxe | Shop')
      expect(body['meta_description']).to eq('Shop the Grinder Deluxe.')
      expect(product.reload.meta_title).to be_blank
    end
  end

  describe 'degradation (AC-007)' do
    it 'answers 422 with a reason code when the capability is not configured' do
      PallasTrade::AI::Setting.find_or_initialize_by(store: store).update!(active: true)
      sign_in_as_admin

      post '/admin/ai/product_description', params: { product_id: product.prefixed_id }, as: :json

      expect(response).to have_http_status(422)
      expect(response.parsed_body.dig('error', 'code')).to eq('ai_capability_disabled')
      expect(PallasTrade::AI::Run.count).to eq(0)
    end

    it 'renders the assistant buttons disabled with a reason on the edit page' do
      sign_in_as_admin

      get "/admin/products/#{product.slug}/edit"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t('admin.products.ai.generate'))
      expect(response.body).to include(PallasTrade.t('admin.products.ai.generate_seo'))
      expect(response.body).to include('data-ai-assist-target="preview"')

      doc = Nokogiri::HTML(response.body)
      buttons = doc.css('[data-ai-assist-role="generate"]')
      # 描述区两个（Generate / Rewrite）+ SEO 卡片一个（Generate SEO）
      expect(buttons.size).to eq(3)
      expect(buttons.map { |button| button['disabled'] }).to all(be_truthy)
      expect(buttons.first['title']).to be_present
    end
  end

  describe 'permissions (AC-008)' do
    it 'denies a user who may not update products' do
      configure_capability!('catalog.product_description')
      stranger = create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
      sign_in stranger
      allow_any_instance_of(PallasTrade::Admin::AIController).to receive(:current_store).and_return(store)

      post '/admin/ai/product_description', params: { product_id: product.prefixed_id }, as: :json

      expect(response).not_to have_http_status(:ok)
      expect(PallasTrade::AI::Run.count).to eq(0)
    end
  end

  describe 'i18n (AC-010)' do
    it 'ships every copilot label' do
      keys = %w[
        admin.products.ai.generate
        admin.products.ai.rewrite
        admin.products.ai.generate_seo
        admin.products.ai.generating
        admin.products.ai.preview_heading
        admin.products.ai.review_hint
        admin.products.ai.accept
        admin.products.ai.discard
        admin.products.ai.accepted
        admin.products.ai.meta_title
        admin.products.ai.meta_description
        admin.products.ai.errors.default
        admin.products.ai.disabled_reason.default
      ]

      keys.each do |key|
        expect(PallasTrade.t(key, default: nil)).to be_present, "missing i18n key #{key}"
      end
    end
  end
end
