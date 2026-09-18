# frozen_string_literal: true

require 'rails_helper'

# PRD-20260918-admin-ai-output-validation —— 异步路径的输出校验。
#
#   AC-007 ← FR-002：声明了 output schema 却拿不到结构化输出 → Run failed 且不写 artifact
#   AC-008 ← FR-002：合规输出 → Run succeeded 且写 1 条 artifact（不回归）
#
# 异步路径原先完全不校验 output schema（先 succeed!，再"有就写 artifact"），
# 于是与同步路径一样把失败记成了成功。
RSpec.describe PallasTrade::AI::ExecuteRunJob do
  before { allow(PallasTradeAI::Config).to receive(:system_enabled?).and_return(true) }

  let!(:store) do
    create(:store, code: "ai_job_#{SecureRandom.hex(4)}", default: true,
                   default_currency: 'USD', default_locale: 'en', name: 'AI Job Store')
  end
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end
  let!(:product) { create(:product, store: store, name: 'Espresso Machine', description: 'Old copy') }

  # CI 不注入 ACTIVE_RECORD_ENCRYPTION_*，ProviderSecret 会 fail-closed 拒绝真实写入。
  def configure_provider_secret!(_provider)
    allow(PallasTrade::AI::ProviderSecret).to receive(:find_by).
      and_return(instance_double(PallasTrade::AI::ProviderSecret, configured?: true))
  end

  before do
    PallasTrade::AI::ProvisionProviders.call(store: store)
    provider.update!(active: true)
    configure_provider_secret!(provider)
    PallasTrade::AI::ProvisionModels.call(provider: provider)
    model.update!(active: true)
    PallasTrade::AI::Setting.find_or_initialize_by(store: store).update!(active: true)
    PallasTrade::AI::CapabilitySetting.find_or_create_by!(store: store, capability_key: 'catalog.product_description') do |setting|
      setting.primary_model = model
      setting.active = true
    end
  end

  let(:provider) { store.ai_providers.find_by(type: 'PallasTrade::AI::Provider::DeepSeek') }
  let(:model) { PallasTrade::AI::Model.where(provider: provider, active: false).order(:name).first }

  def build_run
    PallasTrade::AI::Run.create!(
      store: store, user: admin, capability_key: 'catalog.product_description',
      provider_type: provider.type, provider_id: provider.id,
      model_id: model.id, provider_model_id: model.provider_model_id,
      mode: 'async', status: 'queued', output_schema_version: '1.0.0', queued_at: Time.current
    )
  end

  def stub_provider(structured_output:, text: nil)
    response = PallasTrade::AI::Providers::Response.new(
      text: text || structured_output.to_s,
      structured_output: structured_output,
      provider_request_id: 'req_job_1',
      provider_model_id: 'deepseek-flash',
      finish_reason: 'stop',
      usage: { 'input_tokens' => 7, 'output_tokens' => 11 }
    )
    allow_any_instance_of(PallasTrade::AI::Providers::DeepSeek).to receive(:generate).and_return(response)
  end

  it 'fails the run and stores no artifact when the model returns prose (AC-007)' do
    stub_provider(structured_output: nil, text: 'A sturdy burr grinder for daily espresso.')
    run = build_run

    described_class.perform_now(run.id)

    run.reload
    expect(run.status).to eq('failed')
    expect(run.error_code).to eq('ai_output_invalid')
    expect(run.artifacts.count).to eq(0)
  end

  it 'succeeds and stores the artifact for valid structured output (AC-008)' do
    stub_provider(structured_output: { 'text' => 'A sturdy burr grinder for daily espresso.' })
    run = build_run

    described_class.perform_now(run.id)

    run.reload
    expect(run.status).to eq('succeeded')
    expect(run.artifacts.count).to eq(1)
    expect(run.artifacts.first.payload).to eq('text' => 'A sturdy burr grinder for daily espresso.')
  end

  it 'reports the output failure with a code that names it (AC-007)' do
    stub_provider(structured_output: nil, text: 'prose')
    run = build_run

    described_class.perform_now(run.id)

    run.reload
    expect(run.error_code).not_to eq('ai_provider_unavailable')
    expect(run.error_message).to include('catalog.product_description')
  end
end
