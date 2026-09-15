# frozen_string_literal: true

require 'rails_helper'

# PRD-20260915-catalog-batch-e2-ai-translate-missing —— AI Translate Missing 业务服务
#
#   AC-001 ← FR-001：能力在非测试环境也注册（幂等）
#   AC-002 ← FR-001：输入/输出 schema 校验生效
#   AC-003 ← FR-002：missing_fields 只含目标语言为空的字段（已有译文/ slug 不进列表）
#   AC-004 ← FR-002：用商品事实构造 messages，并传 resource
#   AC-007 ← FR-002：无缺失字段时不调用 provider、不建 Run
RSpec.describe PallasTrade::AI::Catalog::ProductTranslation do
  let!(:store) do
    create(:store, code: "ai_trans_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD',
                   default_locale: 'en', supported_locales: 'de,fr', name: 'AI Translation Store')
  end
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end
  # let! —— 工厂必须在默认语言下建好，否则放在 I18n.with_locale 里会把 name 写进目标语言翻译表
  let!(:product) { create(:product, store: store, name: 'Espresso Machine', description: 'Old copy') }

  # 生成类服务的既有测试范式：走真实 Gateway（含 Run 审计），只把 provider 适配器换成假响应。
  def stub_provider(structured_output)
    response = double(
      'ai_response',
      text: structured_output.values.first,
      structured_output: structured_output,
      usage: { 'input_tokens' => 21, 'output_tokens' => 40 },
      provider_request_id: 'req_test_translation'
    )
    allow_any_instance_of(PallasTrade::AI::Providers::DeepSeek)
      .to receive(:generate).and_return(response)
    response
  end

  # CI 不注入 ACTIVE_RECORD_ENCRYPTION_*，而 ProviderSecret 的 fail-closed 守卫会拒绝真实写入
  # （设计如此：无密钥不落库）。可用性 Gate 7 只要求 secret「已配置」，且本用例已把 provider
  # adapter stub 掉、不会真正取用密钥 —— 因此用内存替身满足前置条件。
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

  def translate_into(locale, attributes)
    product # 强制先物化（工厂建在默认语言下）
    I18n.with_locale(locale) { product.update!(attributes) }
  end

  describe 'capability registration (AC-001)' do
    # PRD-20260915-catalog-batch-e2-ai-translate-missing AC-001
    it 'registers the translation capability with the product authorization' do
      entry = PallasTrade::AI.capabilities['catalog.product_translation']

      expect(entry).to be_present
      expect(entry.handler_class).to eq('PallasTrade::AI::Schemas::Catalog::ProductTranslation::Handler')
      expect(entry.execution_mode).to eq(:sync)
      expect(entry.authorization).to eq({ action: :update, subject: 'PallasTrade::Product' })
    end
  end

  describe 'schemas (AC-002)' do
    let(:input) { PallasTrade::AI::Schemas::Catalog::ProductTranslation::Input }
    let(:output) { PallasTrade::AI::Schemas::Catalog::ProductTranslation::Output }

    # PRD-20260915-catalog-batch-e2-ai-translate-missing AC-002
    it 'requires product facts, both locales and at least one translatable field' do
      valid = { product_name: 'Espresso Machine', source_locale: 'en', target_locale: 'de',
                fields: { 'name' => 'Espresso Machine' } }

      expect(input.valid?(**valid)).to be(true)
      expect(input.valid?(**valid.except(:product_name))).to be(false)
      expect(input.valid?(**valid.except(:target_locale))).to be(false)
      expect(input.valid?(**valid.merge(fields: {}))).to be(false)
      expect(input.valid?(**valid.merge(fields: { 'slug' => 'espresso' }))).to be(false)
      expect(input.valid?(**valid.merge(target_locale: 'en'))).to be(false)
    end

    # PRD-20260915-catalog-batch-e2-ai-translate-missing AC-002
    it 'rejects blank or empty output' do
      expect(output.valid?(translations: { 'name' => 'Espressomaschine' })).to be(true)
      expect(output.valid?(translations: {})).to be(false)
      expect(output.valid?({})).to be(false)
    end
  end

  describe '.missing_fields (AC-003)' do
    # PRD-20260915-catalog-batch-e2-ai-translate-missing AC-003
    it 'returns only the fields without a value in the target locale' do
      translate_into('de', name: 'Espressomaschine')

      expect(described_class.missing_fields(product, target_locale: 'de'))
        .to contain_exactly(:description, :meta_title, :meta_description)
    end

    # PRD-20260915-catalog-batch-e2-ai-translate-missing AC-003
    it 'never reports slug and treats another locale as untranslated' do
      translate_into('de', name: 'Espressomaschine', description: 'Kaffee')

      fields = described_class.missing_fields(product, target_locale: 'de')
      expect(fields).not_to include(:slug)
      expect(described_class.missing_fields(product, target_locale: 'fr'))
        .to contain_exactly(:name, :description, :meta_title, :meta_description)
    end
  end

  describe '.generate_missing (AC-004/AC-007)' do
    before { configure_capability!('catalog.product_translation') }

    # PRD-20260915-catalog-batch-e2-ai-translate-missing AC-004
    it 'passes the source values, both locales and the resource to the gateway' do
      stub_provider({ 'translations' => { 'name' => 'Espressomaschine', 'description' => 'Neue Beschreibung' } })
      captured = nil
      original = PallasTrade::AI::Gateway.method(:call)
      allow(PallasTrade::AI::Gateway).to receive(:call) do |**kwargs|
        captured = kwargs
        original.call(**kwargs)
      end

      result = described_class.generate_missing(product: product, actor: admin, target_locale: 'de')

      expect(captured[:capability]).to eq('catalog.product_translation')
      expect(captured[:resource]).to eq(product)
      expect(captured[:input][:source_locale]).to eq('en')
      expect(captured[:input][:target_locale]).to eq('de')
      expect(captured[:input][:fields].keys).to contain_exactly(:name, :description, :meta_title, :meta_description)
      expect(captured[:input][:messages].first[:content]).to include('Espresso Machine')

      expect(result).to be_success
      expect(result.translations).to eq('name' => 'Espressomaschine', 'description' => 'Neue Beschreibung')
      expect(result.target_locale).to eq('de')
      expect(result.run_id).to be_present
      expect(PallasTrade::AI::Run.find(result.run_id).capability_key).to eq('catalog.product_translation')
    end

    # PRD-20260915-catalog-batch-e2-ai-translate-missing AC-007
    it 'answers no_missing_fields without a provider call or a run' do
      translate_into('de', name: 'Espressomaschine', description: 'Kaffee',
                           meta_title: 'Espressomaschine', meta_description: 'Kaffee kaufen')

      result = described_class.generate_missing(product: product, actor: admin, target_locale: 'de')

      expect(result).not_to be_success
      expect(result.error_code).to eq('no_missing_fields')
      expect(result.run_id).to be_nil
      expect(PallasTrade::AI::Run.count).to eq(0)
    end

    # PRD-20260915-catalog-batch-e2-ai-translate-missing AC-007
    it 'reports unsupported_locale for a locale the store does not offer' do
      result = described_class.generate_missing(product: product, actor: admin, target_locale: 'zh-CN')

      expect(result).not_to be_success
      expect(result.error_code).to eq('unsupported_locale')
      expect(PallasTrade::AI::Run.count).to eq(0)
    end

    it 'accepts the normalized locale suffix the translations drawer sends' do
      stub_provider({ 'translations' => { 'name' => 'Espressomaschine' } })

      result = described_class.generate_missing(product: product, actor: admin, target_locale: 'de')

      expect(result.target_locale).to eq('de')
      expect(PallasTrade::AI::Run.count).to eq(1)
    end
  end
end
