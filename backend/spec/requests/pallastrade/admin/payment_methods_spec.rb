# frozen_string_literal: true

require 'rails_helper'

# PRD-20260915-admin-管理后台支付配置选项化（切片3）—— 后台「支付方式」页签 + Test connection + 凭证脱敏
#   AC-001 ← FR-001/002：后台可看到 Stripe 的能力目录表并分别勾选 card / apple_pay / google_pay
#   AC-003 ← FR-004：调整 position → 前台列表顺序随之变化
#   AC-004 ← FR-005：Test connection 成功/失败均有明确结果写入（provider 探测以 stub 覆盖）
#   AC-005 ← FR-006：页面与 API 响应均不含明文密钥（只回后 4 位掩码）
#
# 入口（PaymentOption）过渡期存 metadata['options']（业务方案 §63.4）：
#   勾选任一入口 → optionized=true（0 可用入口 = 0 前台入口）；未选项化 → 前台回落默认入口（零回归）。
RSpec.describe 'Admin payment methods option configuration', type: :request do
  # 显式随机 code：store 工厂的序列 code（pallastrade_N）会与历史测试库残留冲突（已知测试卫生问题）
  let!(:store) { create(:store, code: "admin_pm_options_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD', name: 'Option Store') }
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
  end

  def stripe_gateway(**attrs)
    create(:stripe_gateway, store: store, **attrs)
  end

  def option_params(entries)
    entries.transform_keys(&:to_s)
  end

  # 测试库（CI）可能已预置国家数据 → 复用既有记录，避免因唯一索引而失败
  def country_for(iso)
    PallasTrade::Country.find_by(iso: iso) || create(:country, iso: iso)
  end

  before do
    # 测试环境 host 不匹配触发 OpenRedirectError（环境 default_url host=localhost:3000）
    # —— 沿用 roles_permissions_spec 的既有做法。
    allow_any_instance_of(PallasTrade::Admin::PaymentMethodsController)
      .to receive(:location_after_save).and_return('/admin/payment_methods')
  end

  describe 'AC-001 能力目录表' do
    # PRD-20260915-admin-管理后台支付配置选项化-支付商-支付方式-前台入口 AC-001
    it 'renders one editable row per catalog method (kind read-only, frontend form read-only)' do
      gateway = stripe_gateway
      sign_in_as_superuser

      get "/admin/payment_methods/#{gateway.prefixed_id}/edit"
      expect(response).to have_http_status(:ok)

      doc = Nokogiri::HTML(response.body)
      %w[card apple_pay google_pay].each do |kind|
        expect(doc.at_css("input[type='checkbox'][name='payment_method[payment_options][#{kind}][active]']")).to be_present
        expect(doc.at_css("input[type='text'][name='payment_method[payment_options][#{kind}][display_name]']")).to be_present
        expect(doc.at_css("input[type='number'][name='payment_method[payment_options][#{kind}][position]']")).to be_present
        # method 名与前端形态只读：不得有可提交的 kind / frontend_kind 控件
        expect(doc.at_css("input[name='payment_method[payment_options][#{kind}][kind]']")).to be_nil
        expect(doc.at_css("input[name='payment_method[payment_options][#{kind}][frontend_kind]']")).to be_nil
      end

      body = response.body
      expect(body).to include('apple_pay')
      expect(body).to include('Wallet button (express)')
      expect(body).to include(PallasTrade.t('admin.payment_methods.test_connection'))
      expect(body).to include('data-turbo-method="post"')
    end

    it 'keeps a non-optionized provider on its legacy default entry (no row pre-checked, zero regression)' do
      gateway = stripe_gateway
      sign_in_as_superuser

      get "/admin/payment_methods/#{gateway.prefixed_id}/edit"

      doc = Nokogiri::HTML(response.body)
      %w[card apple_pay google_pay].each do |kind|
        checkbox = doc.at_css("input[type='checkbox'][name='payment_method[payment_options][#{kind}][active]']")
        expect(checkbox['checked']).to be_nil
      end
      expect(response.body).to include(PallasTrade.t('admin.payment_methods.payment_options_not_optionized'))
    end
  end

  describe '保存归一（FR-001/002/004 + FR-007 门控）' do
    # PRD-20260915-admin-管理后台支付配置选项化-支付商-支付方式-前台入口 AC-003
    it 'writes the option list into metadata and flips optionized when at least one option is enabled' do
      gateway = stripe_gateway
      sign_in_as_superuser

      patch "/admin/payment_methods/#{gateway.prefixed_id}", params: {
        payment_method: {
          name: gateway.name,
          payment_options: option_params(
            'card' => { 'active' => '1', 'display_name' => 'Credit Card', 'position' => '3' },
            'apple_pay' => { 'active' => '0', 'display_name' => 'Apple Pay', 'position' => '2' },
            'google_pay' => { 'active' => '1', 'display_name' => 'Google Pay', 'position' => '1' }
          )
        }
      }

      expect(response).to have_http_status(:see_other)

      gateway.reload
      expect(gateway.optionized?).to be(true)
      # 停用的入口不出现；可用入口按 position 升序（AC-003 的后台侧）
      expect(gateway.available_payment_options.map { |option| option['kind'] }).to eq(%w[google_pay card])
      expect(gateway.payment_option_for('card')['display_name']).to eq('Credit Card')
      expect(gateway.payment_option_for('card')['frontend_kind']).to eq('inline')
      expect(gateway.payment_option_for('apple_pay')['active']).to be(false)
      expect(gateway.frontend_visible?).to be(true)
    end

    # PRD-20260915-admin-管理后台支付配置选项化-支付商-支付方式-前台入口 AC-006
    it 'stays non-optionized when nothing is enabled (legacy default entry preserved)' do
      gateway = stripe_gateway
      sign_in_as_superuser

      patch "/admin/payment_methods/#{gateway.prefixed_id}", params: {
        payment_method: {
          name: gateway.name,
          payment_options: option_params(
            'card' => { 'active' => '0' },
            'apple_pay' => { 'active' => '0' },
            'google_pay' => { 'active' => '0' }
          )
        }
      }

      gateway.reload
      expect(gateway.optionized?).to be(false)
      expect(gateway.frontend_visible?).to be(true)
      expect(gateway.effective_payment_options.size).to eq(1)
    end

    # PRD-20260915-admin-管理后台支付配置选项化-支付商-支付方式-前台入口 AC-007
    it 'keeps optionized=true after every option is disabled (0 storefront entries)' do
      gateway = stripe_gateway(
        metadata: { 'optionized' => true, 'options' => [{ 'kind' => 'card', 'active' => true, 'position' => 1 }] }
      )
      sign_in_as_superuser

      patch "/admin/payment_methods/#{gateway.prefixed_id}", params: {
        payment_method: {
          name: gateway.name,
          payment_options: option_params('card' => { 'active' => '0' })
        }
      }

      gateway.reload
      expect(gateway.optionized?).to be(true)
      expect(gateway.available_payment_options).to be_empty
      expect(gateway.frontend_visible?).to be(false)
    end

    it 'ignores kinds outside the capability catalog (no arbitrary entry injection)' do
      gateway = stripe_gateway
      sign_in_as_superuser

      patch "/admin/payment_methods/#{gateway.prefixed_id}", params: {
        payment_method: {
          name: gateway.name,
          payment_options: option_params('evil_kind' => { 'active' => '1', 'display_name' => 'Evil' })
        }
      }

      gateway.reload
      expect(gateway.payment_option_for('evil_kind')).to be_nil
      expect(gateway.optionized?).to be(false)
    end

    it 'leaves a provider without option params untouched (list-page inline edits keep working)' do
      gateway = stripe_gateway(
        metadata: { 'optionized' => true, 'options' => [{ 'kind' => 'card', 'active' => true, 'position' => 1 }] }
      )
      sign_in_as_superuser

      patch "/admin/payment_methods/#{gateway.prefixed_id}", params: {
        payment_method: { name: 'Renamed provider' }
      }

      gateway.reload
      expect(gateway.name).to eq('Renamed provider')
      expect(gateway.payment_options.map { |option| option['kind'] }).to eq(%w[card])
      expect(gateway.optionized?).to be(true)
    end
  end

  describe 'AC-004 Test connection' do
    # PRD-20260915-admin-管理后台支付配置选项化-支付商-支付方式-前台入口 AC-004
    it 'records a successful check into metadata and audits the action' do
      gateway = stripe_gateway
      allow_any_instance_of(PallasTradeStripe::Gateway).to receive(:test_connection)
        .and_return({ ok: true, code: 'balance_ok', message: 'Stripe reachable' })
      sign_in_as_superuser

      post "/admin/payment_methods/#{gateway.prefixed_id}/test_connection"

      expect(response).to have_http_status(:see_other)
      report = gateway.reload.metadata['last_test_connection']
      expect(report['ok']).to be(true)
      expect(report['code']).to eq('balance_ok')
      expect(report['message']).to eq('Stripe reachable')
      expect(Time.iso8601(report['checked_at'])).to be_present
      expect(PallasTrade::AuditLog.where(action: 'payment_method_test_connection').count).to eq(1)
    end

    it 'records a failed check with a clear reason' do
      gateway = stripe_gateway
      allow_any_instance_of(PallasTradeStripe::Gateway).to receive(:test_connection)
        .and_return({ ok: false, code: 'invalid_credentials', message: 'Secret key is invalid' })
      sign_in_as_superuser

      post "/admin/payment_methods/#{gateway.prefixed_id}/test_connection"

      report = gateway.reload.metadata['last_test_connection']
      expect(report['ok']).to be(false)
      expect(report['code']).to eq('invalid_credentials')
      expect(report['message']).to eq('Secret key is invalid')
    end

    it 'records the failure without leaking credentials when the provider raises' do
      gateway = stripe_gateway
      secret = gateway.preferences[:secret_key]
      allow_any_instance_of(PallasTradeStripe::Gateway).to receive(:test_connection)
        .and_raise(StandardError, "boom #{secret} boom")
      sign_in_as_superuser

      post "/admin/payment_methods/#{gateway.prefixed_id}/test_connection"

      report = gateway.reload.metadata['last_test_connection']
      expect(report['ok']).to be(false)
      expect(report['code']).to eq('probe_error')
      expect(report['message']).to include('[FILTERED]')
      expect(report['message']).not_to include(secret)
    end
  end

  describe 'AC-005 凭证脱敏' do
    # PRD-20260915-admin-管理后台支付配置选项化-支付商-支付方式-前台入口 AC-005
    it 'never renders plaintext credentials and shows the masked hint' do
      gateway = stripe_gateway
      sign_in_as_superuser

      get "/admin/payment_methods/#{gateway.prefixed_id}/edit"
      expect(response).to have_http_status(:ok)

      secret = gateway.preferences[:secret_key]
      publishable = gateway.preferences[:publishable_key]
      expect(secret).to be_present
      expect(publishable).to be_present

      body = response.body
      expect(body).not_to include(secret)
      expect(body).not_to include(publishable)
      expect(body).to include(PallasTrade::Preferences::Masking.mask(secret))
      expect(body).to include(PallasTrade::Preferences::Masking.mask(publishable))
    end

    it 'masks credentials in the admin API payload as well' do
      gateway = stripe_gateway
      payload = PallasTrade.api.admin_payment_method_serializer.new(gateway, params: {}).to_h.to_json

      secret = gateway.preferences[:secret_key]
      expect(payload).not_to include(secret)
      expect(payload).to include("#{PallasTrade::Preferences::Masking::TOKEN}#{secret.last(4)}")
    end
  end

  describe 'D8 适用范围（FR-001/003/004/006）' do
    # PRD-20260915-payments-d8-支付适用范围引擎-支付商-支付方式-市场-国家-zone-币种-前台入口过滤 AC-005
    it 'persists the submitted scope as normalized include conditions' do
      gateway = stripe_gateway
      market = create(:market, store: store, countries: [country_for('AT')])
      zone = create(:zone, name: "D8 scope #{SecureRandom.hex(3)}")
      # 币种白名单 = 店铺支持的币种（有 market 时按 market 币种推导，故动态取值）
      valid_currency = store.reload.supported_currencies_list.first.iso_code.upcase
      sign_in_as_superuser

      patch "/admin/payment_methods/#{gateway.prefixed_id}", params: {
        payment_method: {
          name: gateway.name,
          payment_options: option_params(
            'card' => {
              'active' => '1',
              'rule_set' => {
                'present' => '1',
                'market' => [market.prefixed_id],
                'zone' => [zone.prefixed_id],
                # 小写 ISO / 未知国家 → 归一为大写 / 丢弃
                'country' => %w[at zz],
                'currency' => [valid_currency.downcase, 'xyz'],
                # 未上线维度（amount）不落库：capability 之外的输入一律忽略
                'amount' => %w[50]
              }
            }
          )
        }
      }

      expect(response).to have_http_status(:see_other)

      rule_set = gateway.reload.payment_option_rule_set('card')
      expect(rule_set['match']).to eq('all')
      # 前台提交前缀 ID / 小写 ISO，落库必须是原始 ID / 大写 ISO（AC-005 归一）
      expect(rule_set['include']).to contain_exactly(
        { 'dimension' => 'market', 'operator' => 'in', 'values' => [market.id.to_s] },
        { 'dimension' => 'zone', 'operator' => 'in', 'values' => [zone.id.to_s] },
        { 'dimension' => 'country', 'operator' => 'in', 'values' => %w[AT] },
        { 'dimension' => 'currency', 'operator' => 'in', 'values' => [valid_currency] }
      )
    end

    # PRD-20260915-payments-d8-支付适用范围引擎-支付商-支付方式-市场-国家-zone-币种-前台入口过滤 AC-005
    it 'drops a cross-store market id (store scope enforced)' do
      gateway = stripe_gateway
      zone = create(:zone, name: "D8 zone #{SecureRandom.hex(3)}")
      foreign_store = create(:store, code: "d8_foreign_#{SecureRandom.hex(4)}")
      foreign_market = create(:market, store: foreign_store, countries: [country_for('NZ')])
      sign_in_as_superuser

      patch "/admin/payment_methods/#{gateway.prefixed_id}", params: {
        payment_method: {
          name: gateway.name,
          payment_options: option_params(
            'card' => {
              'active' => '1',
              'rule_set' => {
                'present' => '1',
                'market' => [foreign_market.prefixed_id],
                'zone' => [zone.prefixed_id]
              }
            }
          )
        }
      }

      expect(response).to have_http_status(:see_other)

      rule_set = gateway.reload.payment_option_rule_set('card')
      expect(rule_set['include']).to contain_exactly(
        { 'dimension' => 'zone', 'operator' => 'in', 'values' => [zone.id.to_s] }
      )
    end

    # PRD-20260915-payments-d8-支付适用范围引擎-支付商-支付方式-市场-国家-zone-币种-前台入口过滤 AC-006
    it 'clears the rule when the scope section is submitted empty' do
      gateway = stripe_gateway(
        metadata: {
          'optionized' => true,
          'options' => [
            {
              'kind' => 'card', 'active' => true, 'position' => 1,
              'rule_set' => { 'include' => [{ 'dimension' => 'currency', 'operator' => 'in', 'values' => %w[EUR] }] }
            }
          ]
        }
      )
      sign_in_as_superuser

      patch "/admin/payment_methods/#{gateway.prefixed_id}", params: {
        payment_method: {
          name: gateway.name,
          payment_options: option_params('card' => { 'active' => '1', 'rule_set' => { 'present' => '1' } })
        }
      }

      # 全空选择 = 不限：规则被清空（回到全局可用）
      expect(gateway.reload.payment_option_rule_set('card')).to be_nil
    end

    # PRD-20260915-payments-d8-支付适用范围引擎-支付商-支付方式-市场-国家-zone-币种-前台入口过滤 AC-006
    it 'preserves stored rules when the scope section is not submitted (inline list edits)' do
      gateway = stripe_gateway(
        metadata: {
          'optionized' => true,
          'options' => [
            {
              'kind' => 'card', 'active' => true, 'position' => 1,
              'rule_set' => { 'include' => [{ 'dimension' => 'currency', 'operator' => 'in', 'values' => %w[EUR] }] }
            }
          ]
        }
      )
      sign_in_as_superuser

      patch "/admin/payment_methods/#{gateway.prefixed_id}", params: {
        payment_method: { name: 'Renamed provider', payment_options: option_params('card' => { 'active' => '1' }) }
      }

      expect(gateway.reload.payment_option_for('card')['rule_set']).to be_present
    end

    # PRD-20260915-payments-d8-支付适用范围引擎-支付商-支付方式-市场-国家-zone-币种-前台入口过滤 AC-005
    it 'renders the scope editor and the human summary on the edit page' do
      market = create(:market, store: store, countries: [country_for('AT')])
      gateway = stripe_gateway(
        metadata: {
          'optionized' => true,
          'options' => [
            {
              'kind' => 'card', 'active' => true, 'position' => 1,
              'rule_set' => {
                'include' => [{ 'dimension' => 'market', 'operator' => 'in', 'values' => [market.id.to_s] }]
              }
            }
          ]
        }
      )
      sign_in_as_superuser

      get "/admin/payment_methods/#{gateway.prefixed_id}/edit"
      expect(response).to have_http_status(:ok)

      doc = Nokogiri::HTML(response.body)
      %w[market country zone currency].each do |dimension|
        expect(doc.at_css("select[name='payment_method[payment_options][card][rule_set][#{dimension}][]']")).to be_present
      end
      # 已存规则回填为前缀 ID（前台可读），摘要展示已存范围
      expect(doc.at_css("select[name='payment_method[payment_options][card][rule_set][market][]'] option[selected]")&.attr('value'))
        .to eq(market.prefixed_id)
      expect(response.body).to include(market.prefixed_id)
    end

    # PRD-20260915-payments-d8-支付适用范围引擎-支付商-支付方式-市场-国家-zone-币种-前台入口过滤 AC-007
    it 'projects the normalized rule set and a readable summary in the admin API payload' do
      market = create(:market, store: store, countries: [country_for('AT')])
      gateway = stripe_gateway(
        metadata: {
          'optionized' => true,
          'options' => [
            {
              'kind' => 'card', 'active' => true, 'position' => 1,
              'rule_set' => {
                'match' => 'all',
                'include' => [{ 'dimension' => 'market', 'operator' => 'in', 'values' => [market.id.to_s] }],
                # 未上线维度（amount）与非法算子不得进入投影（读归一）
                'exclude' => [{ 'dimension' => 'amount', 'operator' => 'gte', 'values' => %w[50] }]
              }
            }
          ]
        }
      )

      payload = JSON.parse(PallasTrade.api.admin_payment_method_serializer.new(gateway, params: {}).to_h.to_json)
      option = payload['options'].first

      expect(option['rule_set']).to eq(
        'match' => 'all',
        'include' => [{ 'dimension' => 'market', 'operator' => 'in', 'values' => [market.id.to_s] }],
        'exclude' => []
      )
      # 摘要对人可读：市场回记录名（默认 labels），不是内部 ID
      expect(option['scope_summary']).to include(market.name)
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # PALLAS-CUSTOM: S1（PRD-20260915-admin §1.1 / FR-010..FR-014）—— Stripe 厂商详情页定向优化。
  #   AC-009 ← FR-010：Stripe 渲染专用版面；其他 provider 仍渲染通用版面
  #   AC-010 ← FR-011：Stripe 首卡 =「连接」（凭证 + 环境 + [测试连接] + 最近结果）；
  #                    通用版面的按钮仍留在「支付方式」卡内
  #   AC-011 ← FR-012：Stripe 不再渲染配置指南（其 0 字节 partial 已删除）
  #   AC-013 ← FR-014：熔断卡外层可折叠，锚点与软置灰动作不变
  describe 'S1 Stripe 厂商详情页（FR-010..014）' do
    def render_edit_page(payment_method)
      sign_in_as_superuser
      get "/admin/payment_methods/#{payment_method.prefixed_id}/edit"
      expect(response).to have_http_status(:ok)
      Nokogiri::HTML5(response.body)
    end

    it 'renders the Stripe-specific page with the connection card first (AC-009/010)' do
      doc = render_edit_page(stripe_gateway)

      connection = doc.at_css("[data-testid='stripe-connection']")
      expect(connection).to be_present

      # 凭证 + 环境 + [测试连接] 同在「连接」卡（FR-011 的核心诉求：先连接、再配置）
      expect(connection.css("input[name='payment_method[preferred_publishable_key]']")).to be_present
      expect(connection.css("input[name='payment_method[preferred_secret_key]']")).to be_present
      expect(connection.css("select[name='payment_method[environment]']")).to be_present
      expect(connection.at_css("[data-testid='stripe-test-connection']")).to be_present

      # 连接卡是内容列第一张卡（诊断卡被移到主表单之后）
      ordered = doc.css("[data-testid='stripe-connection'], [data-testid='provider-diagnostics']")
      expect(ordered.first['data-testid']).to eq('stripe-connection')
    end

    it 'shows the last connection check result inside the connection card (AC-010)' do
      gateway = stripe_gateway
      gateway.update_columns(
        private_metadata: (gateway.private_metadata || {}).merge(
          'last_test_connection' => { 'ok' => true, 'code' => 'credentials_present',
                                      'message' => 'Credentials are present',
                                      'checked_at' => '2026-09-20T10:00:00Z' }
        )
      )

      doc = render_edit_page(gateway.reload)
      result = doc.at_css("[data-testid='stripe-test-connection-result']")

      expect(result).to be_present
      expect(result.text).to include('credentials_present')
      # 专用版面下，「支付方式」卡不再重复承载按钮
      expect(doc.at_css("[data-testid='options-test-connection']")).to be_nil
    end

    it 'no longer renders the deleted Stripe configuration guide (AC-011)' do
      doc = render_edit_page(stripe_gateway)

      expect(doc.text).not_to include('translation missing')
      expect(File.exist?(
               Rails.root.join('pallastrade_gems/pallastrade_stripe/app/views/pallastrade/admin/payment_methods/' \
                               'configuration_guides/_pallastrade_stripe.html.erb')
             )).to be(false)
    end

    it 'folds the breaker card while keeping its anchor and actions (AC-013)' do
      doc = render_edit_page(stripe_gateway)
      card = doc.at_css('#payment_method_breaker')

      expect(card).to be_present
      expect(card['data-controller']).to eq('reveal')
      expect(card.at_css('[data-reveal-target="item"]')['class']).to include('is-collapsed')
      expect(card.at_css("[data-testid='breaker-soft-disable-save']")).to be_present
    end

    it 'keeps a non-Stripe provider on the generic page (AC-009/010 zero regression)' do
      check_gateway = create(:check_payment_method, store: store, active: true, display_on: 'both', name: 'Check')
      doc = render_edit_page(check_gateway)

      expect(doc.at_css("[data-testid='stripe-connection']")).to be_nil
      # 通用版面：按钮仍在「支付方式」卡；诊断卡仍在主表单之前
      expect(doc.at_css("[data-testid='payment-options'] [data-testid='options-test-connection']")).to be_present
      ordered = doc.css("[data-testid='payment-options'], [data-testid='provider-diagnostics']")
      expect(ordered.first['data-testid']).to eq('provider-diagnostics')
    end
  end
end
