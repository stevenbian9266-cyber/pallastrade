# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-catalog-batch-e3-ai-fix-suggestion —— Catalog Health AI 修复建议（业务服务）
#
#   AC-001 ← FR-001：能力注册（authorization = read Product）
#   AC-002 ← FR-001：输入/输出 schema 校验生效
#   AC-003 ← FR-002：工作台级采样只取该 issue 作用域、≤5、字段最小化（不含客户/成本等）
#   AC-006 ← FR-002：计数 0 / 未知 issue → 拒绝且零 Run、零 provider 调用
#   AC-007 ← FR-002：steps 入口白名单过滤；商品级命中判定只含真实命中的问题
RSpec.describe PallasTrade::AI::Catalog::HealthFixSuggestion do
  # CI 不注入 PALLASTRADE_AI_ENABLED（系统总开关默认 false）→ 可用性 Gate 1 会先于店铺/能力
  # 配置拦下请求。这里显式打开系统开关，让用例在本地与 CI 行为一致。
  before { allow(PallasTradeAI::Config).to receive(:system_enabled?).and_return(true) }

  let!(:store) do
    create(:store, code: "health_ai_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD',
                   default_locale: 'en', supported_locales: 'de,fr', name: 'Health AI Store')
  end
  let(:admin) do
    create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
  end

  # 与 B-2 规格同款夹具：默认语言（en）无描述的问题商品（列 + 翻译行双保险）
  def product_missing_description(name)
    product = create(:product, store: store, name: name, description: nil)
    product.translations.where(locale: 'en').update_all(description: nil)
    product.update_columns(description: nil)
    product
  end

  # 完全健康：有图、有描述、有 SEO、active 有库存、目标语言翻译齐备
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
      usage: { 'input_tokens' => 30, 'output_tokens' => 60 },
      provider_request_id: 'req_test_health'
    )
    allow_any_instance_of(PallasTrade::AI::Providers::DeepSeek)
      .to receive(:generate).and_return(response)
    response
  end

  # CI 不注入 ACTIVE_RECORD_ENCRYPTION_*，ProviderSecret 的 fail-closed 守卫会拒绝真实写入
  # （设计如此：无密钥不落库）。可用性 Gate 7 只要求 secret「已配置」，而 provider adapter
  # 已被 stub、不会取用密钥 —— 用内存替身满足前置条件。
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
    # PRD-20260916-catalog-batch-e3-ai-fix-suggestion AC-001
    it 'registers the suggestion capability as a read-only product authorization' do
      entry = PallasTrade::AI.capabilities['catalog.health_fix_suggestion']

      expect(entry).to be_present
      expect(entry.handler_class).to eq('PallasTrade::AI::Schemas::Catalog::HealthFixSuggestion::Handler')
      expect(entry.execution_mode).to eq(:sync)
      expect(entry.authorization).to eq({ action: :read, subject: 'PallasTrade::Product' })
    end
  end

  describe 'schemas (AC-002)' do
    let(:input) { PallasTrade::AI::Schemas::Catalog::HealthFixSuggestion::Input }
    let(:output) { PallasTrade::AI::Schemas::Catalog::HealthFixSuggestion::Output }

    # PRD-20260916-catalog-batch-e3-ai-fix-suggestion AC-002
    it 'validates both granularities and rejects unknown issue keys' do
      catalog = { scope: 'catalog', issue_key: 'missing_description', count: 31 }
      product = { scope: 'product', product_name: 'Espresso Machine', issue_keys: %w[missing_description] }

      expect(input.valid?(**catalog)).to be(true)
      expect(input.valid?(**catalog.except(:issue_key))).to be(false)
      expect(input.valid?(**catalog.merge(issue_key: 'made_up_issue'))).to be(false)
      expect(input.valid?(**catalog.merge(scope: 'galaxy'))).to be(false)
      expect(input.valid?(**catalog.except(:count))).to be(false)
      expect(input.valid?(**product)).to be(true)
      expect(input.valid?(**product.merge(issue_keys: []))).to be(false)
      expect(input.valid?(**product.except(:product_name))).to be(false)
    end

    # PRD-20260916-catalog-batch-e3-ai-fix-suggestion AC-002
    it 'requires a summary and at least one titled step' do
      good = { summary: 'Tidy the catalog first.', steps: [{ 'title' => 'Fill descriptions' }] }

      expect(output.valid?(**good)).to be(true)
      expect(output.valid?(**good.merge(steps: []))).to be(false)
      expect(output.valid?(**good.merge(steps: [{ 'detail' => 'no title' }]))).to be(false)
      expect(output.valid?({})).to be(false)
    end
  end

  describe '.generate (AC-003/AC-006/AC-007)' do
    before { configure_capability!('catalog.health_fix_suggestion') }

    # PRD-20260916-catalog-batch-e3-ai-fix-suggestion AC-003
    it 'samples only the issue scope, caps at five products and keeps the facts minimal' do
      products = Array.new(7) { |index| product_missing_description("Missing Copy #{index}") }
      healthy = healthy_product('Nothing Wrong Here')
      stub_provider({ 'summary' => 'Fix the descriptions.', 'steps' => [{ 'title' => 'Use the AI description assistant', 'entry' => 'product_edit_ai' }] })

      captured = nil
      original = PallasTrade::AI::Gateway.method(:call)
      allow(PallasTrade::AI::Gateway).to receive(:call) do |**kwargs|
        captured = kwargs
        original.call(**kwargs)
      end

      result = described_class.generate(store: store, actor: admin, issue_key: 'missing_description')

      expect(captured[:capability]).to eq('catalog.health_fix_suggestion')
      expect(captured[:input][:scope]).to eq('catalog')
      expect(captured[:input][:count]).to eq(products.size)
      expect(captured[:input][:sample].size).to eq(5)
      expect(captured[:input][:sample].first.keys).to contain_exactly(:name, :status, :price, :stock_on_hand)
      expect(captured[:input][:sample].map { |fact| fact[:name] }).not_to include(healthy.name)

      expect(result).to be_success
      expect(result.count).to eq(products.size)
      expect(result.steps.first['entry']).to eq('product_edit_ai')
      expect(result.run_id).to be_present
      expect(PallasTrade::AI::Run.find(result.run_id).capability_key).to eq('catalog.health_fix_suggestion')
    end

    # PRD-20260916-catalog-batch-e3-ai-fix-suggestion AC-007
    it 'drops an entry the admin does not have, keeping the step' do
      product_missing_description('Missing Copy')
      stub_provider(
        {
          'summary' => 'Plan',
          'steps' => [
            { 'title' => 'Use the description assistant', 'entry' => 'product_edit_ai' },
            { 'title' => 'Press the magic fix button', 'entry' => 'invented_surface' }
          ]
        }
      )

      result = described_class.generate(store: store, actor: admin, issue_key: 'missing_description')

      expect(result.steps.size).to eq(2)
      expect(result.steps[0]['entry']).to eq('product_edit_ai')
      expect(result.steps[1]['title']).to eq('Press the magic fix button')
      expect(result.steps[1]['entry']).to be_nil
    end

    # PRD-20260916-catalog-batch-e3-ai-fix-suggestion AC-006
    it 'answers nothing_to_fix without a provider call or a run' do
      result = described_class.generate(store: store, actor: admin, issue_key: 'missing_translations')

      expect(result).not_to be_success
      expect(result.error_code).to eq('nothing_to_fix')
      expect(result.count).to eq(0)
      expect(result.run_id).to be_nil
      expect(PallasTrade::AI::Run.count).to eq(0)
    end

    # PRD-20260916-catalog-batch-e3-ai-fix-suggestion AC-006
    it 'rejects an issue key the worklist does not track' do
      result = described_class.generate(store: store, actor: admin, issue_key: 'not_a_real_issue')

      expect(result).not_to be_success
      expect(result.error_code).to eq('unknown_issue')
      expect(PallasTrade::AI::Run.count).to eq(0)
    end
  end

  describe '.generate_for_product (AC-007/AC-011)' do
    before { configure_capability!('catalog.health_fix_suggestion') }

    # PRD-20260916-catalog-batch-e3-ai-fix-suggestion AC-007
    it 'lists only the issues the product actually hits' do
      problem = product_missing_description('Needs Attention')
      problem.update_columns(meta_title: nil, meta_description: nil)

      keys = described_class.product_issue_keys(problem, store: store)

      expect(keys).to include('missing_description', 'missing_seo')
      expect(keys).not_to include('active_zero_stock', 'old_drafts')
      expect(described_class.product_issue_keys(healthy_product('All Good'), store: store)).to be_empty
    end

    # PRD-20260916-catalog-batch-e3-ai-fix-suggestion AC-011
    it 'answers with a plan for that product and creates a run' do
      problem = product_missing_description('Needs Attention')
      stub_provider(
        {
          'summary' => 'Two quick fixes.',
          'steps' => [{ 'title' => 'Generate the description', 'entry' => 'product_edit_ai' }]
        }
      )

      result = described_class.generate_for_product(product: problem, actor: admin)

      expect(result).to be_success
      expect(result.summary).to eq('Two quick fixes.')
      expect(result.issue_keys).to include('missing_description')
      expect(result.run_id).to be_present
      # 建议只是文本：商品属性零变化
      expect(problem.reload.description).to be_blank
    end

    # PRD-20260916-catalog-batch-e3-ai-fix-suggestion AC-011
    it 'answers nothing_to_fix for a product without any issue, without a run' do
      result = described_class.generate_for_product(product: healthy_product('All Good'), actor: admin)

      expect(result).not_to be_success
      expect(result.error_code).to eq('nothing_to_fix')
      expect(PallasTrade::AI::Run.count).to eq(0)
    end
  end
end
