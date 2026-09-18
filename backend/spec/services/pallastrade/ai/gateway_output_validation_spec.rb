# frozen_string_literal: true

require 'rails_helper'

# PRD-20260918-admin-ai-output-validation —— 网关的输出校验缺口。
#
#   AC-001 ← FR-001：声明了 output schema 却拿不到结构化输出 → 判失败
#   AC-002 ← FR-003：错误码是 ai_output_invalid（不是 ai_provider_unavailable）
#   AC-003 ← FR-001：Run 落为 failed（不再 succeeded）
#   AC-004 ← FR-001：结构化输出不符合 schema → 同样失败且同码
#   AC-005 ← FR-001：合规输出仍成功（不回归）
#   AC-006 ← FR-001：未声明 output schema 的能力不受影响（不误伤）
#   AC-010 ← FR-005：失败信息含能力键（可排障）
#   AC-014 ← FR-006：失败路径不改动业务数据
#   AC-015 ← FR-001/002：四个 catalog 能力同口径
RSpec.describe PallasTrade::AI::Gateway do
  # CI 不注入 PALLASTRADE_AI_ENABLED（系统总开关默认 false）→ 可用性 Gate 1 会先拦下。
  before { allow(PallasTradeAI::Config).to receive(:system_enabled?).and_return(true) }

  let!(:store) do
    create(:store, code: "ai_out_#{SecureRandom.hex(4)}", default: true,
                   default_currency: 'USD', default_locale: 'en', name: 'AI Output Store')
  end
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end
  let(:product) { create(:product, store: store, name: 'Espresso Machine', description: 'Old copy') }

  # 与既有 AI 规格同一套装配：CI 不注入 ACTIVE_RECORD_ENCRYPTION_*，
  # ProviderSecret 会 fail-closed 拒绝真实写入 —— 用内存替身满足可用性 Gate 7。
  def configure_provider_secret!(_provider)
    allow(PallasTrade::AI::ProviderSecret).to receive(:find_by).
      and_return(instance_double(PallasTrade::AI::ProviderSecret, configured?: true))
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

  # 适配器换成假响应：结构化输出由参数决定，其余（Gateway / Run / 校验）走真实路径。
  def stub_provider(structured_output:, text: nil, finish_reason: 'stop')
    response = PallasTrade::AI::Providers::Response.new(
      text: text || structured_output.to_s,
      structured_output: structured_output,
      provider_request_id: 'req_output_1',
      provider_model_id: 'deepseek-flash',
      finish_reason: finish_reason,
      usage: { 'input_tokens' => 7, 'output_tokens' => 11 }
    )
    allow_any_instance_of(PallasTrade::AI::Providers::DeepSeek).to receive(:generate).and_return(response)
    response
  end

  def call_gateway(capability_key, input)
    described_class.call(capability: capability_key, store: store, actor: admin, input: input, resource: product)
  end

  # 四个能力的合法输入（各自由自己的 Input schema 定义）。
  def inputs
    {
      'catalog.product_description' => {
        product_name: product.name, locale: 'en', mode: 'generate',
        messages: [{ role: 'user', content: 'Write a product description.' }],
        system_instructions: 'Return a JSON object with a "text" field.'
      },
      'catalog.product_seo' => {
        product_name: product.name, locale: 'en',
        messages: [{ role: 'user', content: 'Write the SEO listing.' }],
        system_instructions: 'Return a JSON object with "meta_title" and "meta_description".'
      },
      'catalog.product_translation' => {
        product_name: product.name, source_locale: 'en', target_locale: 'de',
        fields: { 'name' => product.name },
        messages: [{ role: 'user', content: 'Translate the listed fields.' }],
        system_instructions: 'Return a JSON object with a "translations" field.'
      },
      'catalog.health_fix_suggestion' => {
        # scope=product 要求 product_name + 至少一个已知 issue_key（见该能力的 Input schema）。
        scope: 'product', product_name: product.name, issue_keys: %w[missing_description],
        messages: [{ role: 'user', content: 'Suggest a fix plan.' }],
        system_instructions: 'Return a JSON object with "summary" and "steps".'
      }
    }
  end

  describe 'a capability that declares an output schema' do
    before { configure_capability!('catalog.product_description') }

    let(:capability_key) { 'catalog.product_description' }
    let(:input) { inputs.fetch(capability_key) }

    it 'fails when the provider answers with prose instead of the promised shape (AC-001/AC-002/AC-003/AC-010)' do
      stub_provider(structured_output: nil, text: 'A sturdy burr grinder for daily espresso.')

      result = call_gateway(capability_key, input)

      expect(result.status).to eq(:failure)
      expect(result.error_code).to eq('ai_output_invalid')
      expect(result.error_code).not_to eq('ai_provider_unavailable')
      expect(result.run.reload.status).to eq('failed')
      # FR-005：失败要能排障 —— 信息里带能力键。
      expect(result.error_message).to include('catalog.product_description')
    end

    it 'fails when the structured output does not match the schema (AC-004)' do
      stub_provider(structured_output: { 'wrong_field' => 'nope' })

      result = call_gateway(capability_key, input)

      expect(result.status).to eq(:failure)
      expect(result.error_code).to eq('ai_output_invalid')
      expect(result.run.reload.status).to eq('failed')
    end

    it 'still succeeds on valid structured output (AC-005)' do
      stub_provider(structured_output: { 'text' => 'A sturdy burr grinder for daily espresso.' })

      result = call_gateway(capability_key, input)

      expect(result.status).to eq(:success)
      expect(result.run.reload.status).to eq('succeeded')
    end

    it 'leaves the product untouched when the output is unusable (AC-014)' do
      stub_provider(structured_output: nil, text: 'prose')
      before_attributes = product.reload.attributes

      call_gateway(capability_key, input)

      expect(product.reload.attributes).to eq(before_attributes)
    end

    it 'does not fail a capability with no declared output schema (AC-006)' do
      entry = instance_double(
        PallasTrade::AI::CapabilityRegistry::Entry,
        output_schema_class: nil, allowed_parameters: [], version: '1.0.0'
      )
      gateway = described_class.new(capability_key, store, admin, input, product, nil)
      gateway.instance_variable_set(:@capability_entry, entry)

      response = PallasTrade::AI::Providers::Response.new(
        text: 'plain text', structured_output: nil, finish_reason: 'stop'
      )

      expect { gateway.send(:validate_output!, response) }.not_to raise_error
    end
  end

  describe 'every catalog capability shares the rule (AC-015)' do
    %w[
      catalog.product_description
      catalog.product_seo
      catalog.product_translation
      catalog.health_fix_suggestion
    ].each do |capability_key|
      it "fails #{capability_key} with ai_output_invalid when the model returns prose" do
        configure_capability!(capability_key)
        stub_provider(structured_output: nil, text: 'free-form prose')

        result = call_gateway(capability_key, inputs.fetch(capability_key))

        expect(result.status).to eq(:failure)
        expect(result.error_code).to eq('ai_output_invalid')
        expect(result.run.reload.status).to eq('failed')
      end
    end
  end
end
