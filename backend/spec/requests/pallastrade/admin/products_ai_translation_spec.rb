# frozen_string_literal: true

require 'rails_helper'

# PRD-20260915-catalog-batch-e2-ai-translate-missing —— 商品翻译抽屉 AI 助手（端点 + 渲染 + 安全边界）
#
#   AC-005 ← FR-003：POST /admin/ai/product_translation → { translations, locale, run_id }
#   AC-006 ← FR-007：接受前翻译不落库（请求前后 DB 值一致）
#   AC-007 ← FR-002/FR-003：无缺失字段 → 422 no_missing_fields 且不产生 Run
#   AC-008 ← FR-005：AI 未配置 → 422 + 可读原因码；抽屉按钮 disabled + title
#   AC-009 ← FR-003：无商品 update 权限 → 拒绝且不产生 Run；跨店商品 → 404
#   AC-010 ← FR-008：i18n 键齐备
RSpec.describe 'Admin product AI translation', type: :request do
  let!(:store) do
    create(:store, code: "ai_trans_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD',
                   default_locale: 'en', supported_locales: 'de,fr', name: 'AI Translation Store')
  end
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end
  # let! —— 工厂必须在默认语言下建好，否则放在 I18n.with_locale 里会把 name 写进目标语言翻译表
  let!(:product) { create(:product, store: store, name: 'Grinder Deluxe', description: 'Old copy') }

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
      usage: { 'input_tokens' => 9, 'output_tokens' => 22 },
      provider_request_id: 'req_test_translation_http'
    )
    allow_any_instance_of(PallasTrade::AI::Providers::DeepSeek).to receive(:generate).and_return(response)
  end

  # CI 不注入 ACTIVE_RECORD_ENCRYPTION_*，ProviderSecret 的 fail-closed 守卫会拒绝真实写入
  # （设计如此：无密钥不落库）。可用性 Gate 7 只要求 secret「已配置」，而 provider adapter
  # 已被 stub、不会取用密钥 —— 用内存替身满足前置条件，让用例在两种环境下行为一致。
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

  describe 'POST /admin/ai/product_translation (AC-005/AC-006)' do
    before { configure_capability!('catalog.product_translation') }

    # PRD-20260915-catalog-batch-e2-ai-translate-missing AC-005 AC-006
    it 'returns the missing-field draft and a run id without writing the translation' do
      stub_provider({ 'translations' => { 'name' => 'Kaffeemühle Deluxe', 'description' => 'Neue Beschreibung' } })
      sign_in_as_admin
      translations_before = product.translations.count

      post '/admin/ai/product_translation',
           params: { product_id: product.prefixed_id, target_locale: 'de' },
           as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['translations']).to eq('name' => 'Kaffeemühle Deluxe', 'description' => 'Neue Beschreibung')
      expect(body['locale']).to eq('de')
      expect(body['fields']).to contain_exactly('name', 'description', 'meta_title', 'meta_description')
      expect(body['run_id']).to be_present

      # 接受前 AI 不落库：目标语言仍为空，翻译行数不变
      expect(product.reload.get_field_with_locale('de', :name, fallback: false)).to be_nil
      expect(product.translations.count).to eq(translations_before)
      expect(PallasTrade::AI::Run.where(capability_key: 'catalog.product_translation').count).to eq(1)
    end

    # PRD-20260915-catalog-batch-e2-ai-translate-missing AC-005
    it 'only asks for the fields that are still missing' do
      translate_into('de', name: 'Kaffeemühle Deluxe')
      stub_provider({ 'translations' => { 'description' => 'Neue Beschreibung' } })
      sign_in_as_admin

      post '/admin/ai/product_translation',
           params: { product_id: product.prefixed_id, target_locale: 'de' },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['fields']).to contain_exactly('description', 'meta_title', 'meta_description')
      expect(response.parsed_body['translations']).not_to have_key('name')
    end
  end

  describe 'nothing to translate (AC-007)' do
    before { configure_capability!('catalog.product_translation') }

    # PRD-20260915-catalog-batch-e2-ai-translate-missing AC-007
    it 'answers 422 no_missing_fields without creating a run' do
      translate_into('de', name: 'Kaffeemühle Deluxe', description: 'Beschreibung',
                           meta_title: 'Kaffeemühle', meta_description: 'Kaffeemühle kaufen')
      sign_in_as_admin

      post '/admin/ai/product_translation',
           params: { product_id: product.prefixed_id, target_locale: 'de' },
           as: :json

      expect(response).to have_http_status(422)
      expect(response.parsed_body.dig('error', 'code')).to eq('no_missing_fields')
      expect(PallasTrade::AI::Run.count).to eq(0)
    end
  end

  describe 'degradation (AC-008)' do
    # PRD-20260915-catalog-batch-e2-ai-translate-missing AC-008
    it 'answers 422 with a reason code when the capability is not configured' do
      PallasTrade::AI::Setting.find_or_initialize_by(store: store).update!(active: true)
      sign_in_as_admin

      post '/admin/ai/product_translation',
           params: { product_id: product.prefixed_id, target_locale: 'de' },
           as: :json

      expect(response).to have_http_status(422)
      expect(response.parsed_body.dig('error', 'code')).to eq('ai_capability_disabled')
      expect(PallasTrade::AI::Run.count).to eq(0)
    end

    # PRD-20260915-catalog-batch-e2-ai-translate-missing AC-008
    it 'renders the drawer assistant disabled with a reason and one row per translatable field' do
      sign_in_as_admin

      get "/admin/translations/PallasTrade::Product/#{product.to_param}/edit",
          params: { translation_locale: 'de' }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(PallasTrade.t('admin.translations.ai.translate_missing'))
      expect(response.body).to include('data-ai-assist-target="preview"')

      doc = Nokogiri::HTML(response.body)
      buttons = doc.css('[data-ai-assist-role="generate"]')
      expect(buttons.size).to eq(1)
      expect(buttons.first['disabled']).to be_truthy
      expect(buttons.first['title']).to be_present

      rows = doc.css('[data-ai-translation-row]').map { |row| row['data-ai-translation-row'] }
      expect(rows).to include('name', 'description', 'meta_title', 'meta_description')
    end
  end

  describe 'permissions (AC-009)' do
    # PRD-20260915-catalog-batch-e2-ai-translate-missing AC-009
    it 'denies a user who may not update products' do
      configure_capability!('catalog.product_translation')
      stranger = create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
      sign_in stranger
      allow_any_instance_of(PallasTrade::Admin::AIController).to receive(:current_store).and_return(store)

      post '/admin/ai/product_translation',
           params: { product_id: product.prefixed_id, target_locale: 'de' },
           as: :json

      expect(response).not_to have_http_status(:ok)
      expect(PallasTrade::AI::Run.count).to eq(0)
    end

    # PRD-20260915-catalog-batch-e2-ai-translate-missing AC-009
    it 'rejects a product from another store' do
      other_store = create(:store, code: "ai_trans_other_#{SecureRandom.hex(4)}", default_currency: 'USD',
                                   default_locale: 'en', supported_locales: 'de')
      stranger = create(:product, store: other_store, name: 'Not Mine')
      configure_capability!('catalog.product_translation')
      sign_in_as_admin

      post '/admin/ai/product_translation',
           params: { product_id: stranger.prefixed_id, target_locale: 'de' },
           as: :json

      expect(response).to have_http_status(:not_found)
      expect(PallasTrade::AI::Run.count).to eq(0)
    end
  end

  describe 'i18n (AC-010)' do
    # PRD-20260915-catalog-batch-e2-ai-translate-missing AC-010
    it 'ships every translation assistant label' do
      keys = %w[
        admin.translations.ai.translate_missing
        admin.translations.ai.review_hint
        admin.translations.ai.no_missing_fields
        admin.translations.ai.errors.unsupported_locale
        admin.translations.ai.errors.ai_credentials_missing
      ]

      keys.each do |key|
        expect(PallasTrade.t(key, default: nil)).to be_present, "missing translation for #{key}"
      end
    end
  end
end
