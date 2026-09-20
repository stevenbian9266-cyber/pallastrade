# frozen_string_literal: true

require 'rails_helper'

# PRD-20260920-checkout 支付核心统一 · 切片 P0-A —— 后台「厂商配置诊断」卡（AC-7）
#
#   AC-7：支付方式编辑页渲染只读诊断卡（data-testid="provider-diagnostics"）：
#         三态徽标 + 能力/账户/生效清单行 + 诊断项（i18n 文案，无 "translation missing"）。
RSpec.describe 'Admin payment provider diagnostics', type: :request do
  let!(:store) { create(:store, code: "p0a_diag_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD', name: 'P0A Diagnostics Store') }
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
  end

  def make_optionized!(payment_method, options)
    payment_method.update_columns(private_metadata: { 'optionized' => true, 'options' => options })
    payment_method.reload
  end

  def render_edit(payment_method)
    sign_in_as_superuser
    get "/admin/payment_methods/#{payment_method.prefixed_id}/edit"
    expect(response).to have_http_status(:ok)

    Nokogiri::HTML(response.body)
  end

  it 'renders the read-only diagnostics card with the provider state' do
    gateway = create(:stripe_gateway, store: store)
    doc = render_edit(gateway)

    card = doc.at_css("[data-testid='provider-diagnostics']")
    expect(card).to be_present
    expect(card.at_css("[data-testid='provider-diagnostics-state']").text.strip).to eq('Enabled')

    %w[capability account methods currencies countries markets].each do |row|
      expect(card.at_css("[data-testid='provider-diagnostics-#{row}']")).to be_present
    end

    # AC-7：卡内文案必须走 i18n（断言收窄到卡片本身，避免受页面其它区域影响）
    expect(card.text).not_to include('translation missing')
    expect(card.text).to include('Provider capability')
  end

  it 'shows the consistent state when capability and account agree' do
    gateway = create(:stripe_gateway, store: store)
    make_optionized!(gateway, [{ 'kind' => 'card', 'active' => true, 'position' => 1 }])
    gateway.update_columns(private_metadata: gateway.metadata.merge('account' => { 'methods' => %w[card] }))
    gateway.reload

    doc = render_edit(gateway)

    expect(doc.at_css("[data-testid='provider-diagnostics-consistent']")).to be_present
    expect(doc.at_css("[data-testid='provider-diagnostics-issues']")).to be_nil
  end

  it 'lists mismatches with their severity when the provider does not declare an option' do
    gateway = create(:stripe_gateway, store: store)
    make_optionized!(gateway, [
                       { 'kind' => 'card', 'active' => true, 'position' => 1 },
                       { 'kind' => 'klarna', 'active' => true, 'position' => 2 }
                     ])

    doc = render_edit(gateway)

    list = doc.at_css("[data-testid='provider-diagnostics-issues']")
    expect(list).to be_present
    expect(list.at_css("li[data-severity='error']")).to be_present
    expect(list.text).to include('klarna')
  end

  it 'marks a disabled provider in the state badge' do
    gateway = create(:stripe_gateway, store: store)
    PallasTrade::Payments::Providers::State.disable!(gateway)

    doc = render_edit(gateway)

    expect(doc.at_css("[data-testid='provider-diagnostics-state']").text.strip).to eq('Disabled')
  end

  it 'marks a suspended (breaker open) provider in the state badge' do
    gateway = create(:stripe_gateway, store: store)
    PallasTrade::Payments::Providers::State.suspend!(gateway, reason: 'provider outage', manual: true)

    doc = render_edit(gateway)

    expect(doc.at_css("[data-testid='provider-diagnostics-state']").text.strip).to eq('Suspended')
  end

  # PALLAS-CUSTOM: S1（PRD-20260915-admin §1.1 / FR-013）—— P3-C 后台「支付路由」预览区块**已下架**。
  # 原 4 例渲染断言改写为**反向断言**：无论是否选项化 / 是否被停用，诊断卡内都不再出现路由预览区块，
  # 且对应 i18n 键已一并移除。路由**引擎**未改动（见 `harness verify payment-routing-rspec`）。
  describe 'S1：路由预览已下架（FR-013）' do
    def optionized!(payment_method, kind: 'card', position: 1)
      payment_method.update_columns(private_metadata: {
                                      'optionized' => true,
                                      'options' => [{ 'kind' => kind, 'active' => true, 'position' => position }]
                                    })
      payment_method.reload
    end

    it 'does not render the routing preview block for an optionized provider' do
      gateway = create(:stripe_gateway, store: store)
      optionized!(gateway)

      render_edit(gateway)

      expect(response.body).not_to include('provider-routing-preview')
      expect(response.body).not_to include('provider-routing-mode')
      expect(response.body).not_to include('provider-routing-gates-note')
    end

    it 'does not render it for a disabled provider either' do
      gateway = create(:stripe_gateway, store: store)
      optionized!(gateway)
      PallasTrade::Payments::Providers::State.disable!(gateway)

      render_edit(gateway.reload)

      expect(response.body).not_to include('provider-routing-preview')
    end

    it 'no longer ships the routing preview i18n keys' do
      keys = %w[routing_title routing_help routing_empty routing_mine routing_other
                routing_not_selected routing_modes routing_basis]

      keys.each do |key|
        expect(I18n.exists?("pallastrade.admin.payment_methods.provider_diagnostics.#{key}")).to be(false),
                                                                                                  "#{key} 应随 FR-013 一并移除"
      end
    end
  end
end
