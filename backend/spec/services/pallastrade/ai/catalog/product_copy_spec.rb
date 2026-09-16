# frozen_string_literal: true

require 'rails_helper'

# PRD-20260915-catalog-batch-e1-ai-copilot —— AI Product Copilot 业务服务
#
#   AC-001 ← FR-001：两个能力在非测试环境也注册（幂等）
#   AC-002 ← FR-001：输入/输出 schema 校验生效
#   AC-003 ← FR-002：用商品事实构造 messages / system instructions，并传 resource
#   AC-009 ← FR-007：每次执行产生 Run（capability_key / actor / 状态）
RSpec.describe PallasTrade::AI::Catalog::ProductCopy do
  # CI 不注入 PALLASTRADE_AI_ENABLED（系统总开关默认 false）→ 可用性 Gate 1 会先于店铺/能力
  # 配置拦下请求。这里显式打开系统开关，让用例在本地与 CI 行为一致。
  before { allow(PallasTradeAI::Config).to receive(:system_enabled?).and_return(true) }

  let!(:store) do
    create(:store, code: "ai_copy_#{SecureRandom.hex(4)}", default: true,
                   default_currency: 'USD', default_locale: 'en', name: 'AI Copy Store')
  end
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end
  let(:product) { create(:product, store: store, name: 'Espresso Machine', description: 'Old copy') }

  # 生成类服务的既有测试范式：走真实 Gateway（含 Run 审计），只把 provider 适配器换成假响应。
  def stub_provider(structured_output)
    response = double(
      'ai_response',
      text: structured_output.values.first,
      structured_output: structured_output,
      usage: { 'input_tokens' => 12, 'output_tokens' => 30 },
      provider_request_id: 'req_test_1'
    )
    allow_any_instance_of(PallasTrade::AI::Providers::DeepSeek)
      .to receive(:generate).and_return(response)
    response
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

  describe 'capability registration (AC-001)' do
    it 'registers both product capabilities outside the test-only registry, idempotently' do
      keys = PallasTrade::AI.capabilities.keys

      expect(keys).to include('catalog.product_description', 'catalog.product_seo')
      expect(PallasTrade::AI.capabilities['catalog.product_description'].handler_class)
        .to eq('PallasTrade::AI::Schemas::Catalog::ProductDescription::Handler')
      expect(PallasTrade::AI.capabilities['catalog.product_seo'].execution_mode).to eq(:sync)
      expect(PallasTrade::AI.capabilities['catalog.product_description'].authorization)
        .to eq({ action: :update, subject: 'PallasTrade::Product' })
    end
  end

  describe 'schemas (AC-002)' do
    it 'rejects a description input without a product name and without a valid mode' do
      input = PallasTrade::AI::Schemas::Catalog::ProductDescription::Input

      expect(input.valid?(product_name: 'X', locale: 'en', mode: 'generate')).to be(true)
      expect(input.valid?(locale: 'en')).to be(false)
      expect(input.valid?(product_name: 'X', locale: 'en', mode: 'translate')).to be(false)
    end

    it 'rejects blank or oversized SEO output' do
      output = PallasTrade::AI::Schemas::Catalog::ProductSeo::Output

      expect(output.valid?(meta_title: 'Espresso Machine', meta_description: 'Shop the Espresso Machine.')).to be(true)
      expect(output.valid?(meta_title: ' ', meta_description: 'x')).to be(false)
      expect(output.valid?(meta_title: 'a' * 71, meta_description: 'x')).to be(false)
    end
  end

  describe '.generate_description (AC-003/AC-009)' do
    before { configure_capability!('catalog.product_description') }

    it 'records a run and returns the drafted text without touching the product' do
      stub_provider({ 'text' => 'Fresh espresso copy' })
      before_attributes = product.reload.attributes

      result = described_class.generate_description(product: product, actor: admin, mode: 'rewrite')

      expect(result).to be_success
      expect(result.text).to eq('Fresh espresso copy')
      expect(result.run_id).to be_present

      run = PallasTrade::AI::Run.find(result.run_id)
      expect(run.capability_key).to eq('catalog.product_description')
      expect(run.user_id).to eq(admin.id)
      expect(run.status).to eq('succeeded')
      expect(product.reload.attributes).to eq(before_attributes)
    end

    it 'passes the product facts and the resource to the gateway' do
      stub_provider({ 'text' => 'Copy' })
      captured = nil
      original = PallasTrade::AI::Gateway.method(:call)
      allow(PallasTrade::AI::Gateway).to receive(:call) do |**kwargs|
        captured = kwargs
        original.call(**kwargs)
      end

      described_class.generate_description(product: product, actor: admin, mode: 'generate')

      expect(captured[:capability]).to eq('catalog.product_description')
      expect(captured[:resource]).to eq(product)
      expect(captured[:input][:messages].first[:content]).to include('Espresso Machine')
      expect(captured[:input][:locale]).to eq('en')
      expect(captured[:input][:mode]).to eq('generate')
    end

    it 'reports the reason code when the capability is not configured (AC-007 preview)' do
      PallasTrade::AI::CapabilitySetting.where(capability_key: 'catalog.product_description').delete_all

      result = described_class.generate_description(product: product, actor: admin)

      expect(result).not_to be_success
      expect(result.error_code).to eq('ai_capability_disabled')
      expect(result.run_id).to be_nil
    end
  end

  describe '.generate_seo' do
    before { configure_capability!('catalog.product_seo') }

    it 'returns both meta fields and a run id' do
      stub_provider({ 'meta_title' => 'Espresso Machine | Shop', 'meta_description' => 'Buy the Espresso Machine.' })

      result = described_class.generate_seo(product: product, actor: admin)

      expect(result).to be_success
      expect(result.meta_title).to eq('Espresso Machine | Shop')
      expect(result.meta_description).to eq('Buy the Espresso Machine.')
      expect(PallasTrade::AI::Run.find(result.run_id).capability_key).to eq('catalog.product_seo')
    end
  end
end
