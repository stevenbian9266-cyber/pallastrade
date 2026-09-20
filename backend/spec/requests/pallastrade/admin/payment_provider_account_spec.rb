# frozen_string_literal: true

require 'rails_helper'

# PRD-20260920-checkout 支付核心统一 · 切片 P0-B —— 后台账户配置写入口（AC-4 / AC-5 / AC-7）
#
#   POST /admin/payment_methods/:id/update_provider_account
#   越界值忽略并回显；同值幂等；权限不足零写入；审计留痕。
RSpec.describe 'Admin payment provider account configuration', type: :request do
  let!(:store) { create(:store, code: "p0b_diag_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD', name: 'P0B Diagnostics Store') }
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }
  let(:gateway) { create(:stripe_gateway, store: store) }

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
  end

  def post_account(payload)
    post "/admin/payment_methods/#{gateway.prefixed_id}/update_provider_account",
         params: { provider_account: payload }
  end

  before do
    allow_any_instance_of(PallasTrade::Admin::PaymentMethodsController)
      .to receive(:location_after_save).and_return('/admin/payment_methods')
  end

  describe 'AC-4 保存后收窄生效' do
    it 'stores the account configuration and reflects it on the edit page' do
      sign_in_as_superuser
      post_account(methods: %w[card])

      expect(response).to have_http_status(:see_other)
      expect(gateway.reload.provider_account_config['methods']).to eq(%w[card])

      get "/admin/payment_methods/#{gateway.prefixed_id}/edit"
      doc = Nokogiri::HTML(response.body)
      card = doc.at_css("[data-testid='provider-diagnostics']")

      expect(card.at_css("[data-testid='provider-diagnostics-account']").text).to include('card')
      expect(card.text).not_to include('translation missing')
      expect(card.at_css("[data-testid='provider-account-form']")).to be_present
    end

    it 'narrows the effective methods with the account side' do
      sign_in_as_superuser
      post_account(methods: %w[card apple_pay])

      effective = gateway.reload.provider_effective_scope

      expect(effective['methods']['values']).to match_array(%w[card apple_pay])
      expect(effective['methods']['basis']).to eq('capability+account')
    end
  end

  describe 'AC-1 越界回显（不静默丢数据）' do
    it 'ignores unknown kinds and tells the operator' do
      sign_in_as_superuser
      post_account(methods: %w[card klarna])

      expect(gateway.reload.provider_account_config['methods']).to eq(%w[card])
      expect(flash[:warning]).to be_present
      expect(flash[:warning]).to include('klarna')
    end
  end

  describe 'AC-7 审计与幂等' do
    it 'records one audit entry per change' do
      sign_in_as_superuser
      expect(PallasTrade::Audit).to receive(:record).with(
        hash_including(action: 'payment_method_provider_account_updated')
      ).once

      post_account(methods: %w[card])
    end

    it 'is idempotent — the same payload twice does not raise and does not audit again' do
      sign_in_as_superuser
      post_account(methods: %w[card])
      expect(PallasTrade::Audit).not_to receive(:record).with(
        hash_including(action: 'payment_method_provider_account_updated')
      )

      post_account(methods: %w[card])

      expect(response).to have_http_status(:see_other)
      expect(flash[:notice]).to be_present
    end
  end

  describe 'AC-5 权限' do
    it 'denies the write without update permission (zero writes)' do
      sign_in admin # 无 role_user → 无 update 权限
      before_metadata = gateway.private_metadata

      post_account(methods: %w[card])

      expect(response.status).to be_in([302, 403])
      expect(gateway.reload.private_metadata).to eq(before_metadata)
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  # S0（2026-09-20）—— 后台支付方式编辑页**不得出现嵌套 `<form>`**。
  #
  # 背景：`edit.html.erb` 的主表单是 `form_for`，而 `_provider_diagnostics`（账户配置）与
  # `_breaker`（软置灰）各自带一个 `form_with` → 内层 `<form>` 落在主表单**内部**（HTML 非法）。
  # HTML5 解析器（浏览器与 `Nokogiri::HTML5` 同一套算法）对此有两条互相牵连的行为：
  #   ① 内层 `<form>` 起始标签被**丢弃** → 其提交控件归属到「最近的外层表单」
  #      （实测：点「保存账户配置」提交到主表单 action → 账户配置静默丢失，主表单反被保存一次）；
  #   ② 遇到内层 `</form>` 时把**外层** form 从「开放元素栈」上移除 → 其后出现的 `<form>`
  #      起始标签反而能被正常创建（这正是 `_breaker` 排在第二个才侥幸可用的原因）。
  # 因此两者**必须一起修**：只修其一，另一个立刻退化成 ①。
  #
  # 断言口径 = **浏览器实际会怎么提交**：次级提交控件的「最近祖先 `<form>`」（表单所有者）必须
  # 存在，且 action 指向该功能自己的 member 路由；同时主表单子树内不得再出现任何 `<form>`。
  describe 'S0 表单结构：次级表单不得嵌套在主表单内' do
    # 浏览器提交时的表单所有者 = 最近的祖先 <form>（本页无 form 属性引用）
    def owning_form(node)
      node&.ancestors('form')&.first
    end

    it 'renders the account form outside the main form and lets its submit own it' do
      sign_in_as_superuser
      get "/admin/payment_methods/#{gateway.prefixed_id}/edit"

      # 必须用 HTML5 解析（与浏览器同算法）；Nokogiri::HTML 的容错规则不同，会掩盖本缺陷
      doc = Nokogiri::HTML5(response.body)
      save = doc.at_css("[data-testid='provider-account-save']")
      expect(save).to be_present

      form = owning_form(save)
      expect(form).to be_present, '账户配置的提交控件不属于任何表单（内层 <form> 被解析器丢弃）'
      expect(form['action']).to end_with("/admin/payment_methods/#{gateway.prefixed_id}/update_provider_account"),
                                 "账户配置的提交会落到 #{form['action'].inspect}（应为其自己的 member 路由）"
    end

    it 'renders the breaker form outside the main form and lets its submit own it' do
      sign_in_as_superuser
      get "/admin/payment_methods/#{gateway.prefixed_id}/edit"

      doc = Nokogiri::HTML5(response.body)
      save = doc.at_css("[data-testid='breaker-soft-disable-save']")
      expect(save).to be_present

      form = owning_form(save)
      expect(form).to be_present, '软置灰的提交控件不属于任何表单（内层 <form> 被解析器丢弃）'
      expect(form['action']).to end_with("/admin/payment_methods/#{gateway.prefixed_id}/soft_disable"),
                                 "软置灰的提交会落到 #{form['action'].inspect}（应为其自己的 member 路由）"
    end

    it 'keeps the main edit form free of nested forms' do
      sign_in_as_superuser
      get "/admin/payment_methods/#{gateway.prefixed_id}/edit"

      doc = Nokogiri::HTML5(response.body)
      main = doc.at_css("form#edit_payment_method_#{gateway.id}")
      expect(main).to be_present

      expect(main.css('form')).to be_empty,
                                 '主表单内出现嵌套 <form>：内层会被解析器丢弃/挤掉外层，导致提交归属错乱'
    end
  end
end
