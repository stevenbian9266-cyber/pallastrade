# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-payments-d15b-risk-rules（D15 切片2，后台工作台）
#   AC-012 ← FR-006：列表/详情渲染（计数与列表同源、版本历史、生效规则表、权限）
#   AC-013 ← FR-005/006：五个动作（草稿/发布/金丝雀/**回滚**/停用）——校验失败不落库、各写审计
#   AC-014 ← FR-006：试算（订单维度展示版本/金丝雀/桶/命中规则）且**零写入**
RSpec.describe 'Admin risk rules (D15b)', type: :request do
  let!(:store) do
    create(:store, code: "d15b_admin_#{SecureRandom.hex(4)}", default: true, default_currency: 'USD',
                   name: 'D15b Rules Store', url: 'https://d15b-rules.example.com',
                   mail_from_address: 'no-reply@d15b-rules.example.com')
  end
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }
  let(:suffix) { SecureRandom.hex(4) }

  def sign_in_as_admin
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  def default_rules
    [{ 'code' => 'amount_review', 'priority' => 10, 'action' => 'review', 'note' => nil,
       'conditions' => { 'amount_gte' => 100 } }]
  end

  def build_published_rule_set(code: "rules_#{suffix}", rules: default_rules, canary_percent: 0)
    rule_set = create(:risk_rule_set, code: code, store: store)
    version = create(:risk_rule_version, rule_set: rule_set, version: 1, state: 'published', rules: rules,
                                         published_at: Time.current)
    rule_set.update!(active_version_id: version.id)
    if canary_percent.positive?
      canary = create(:risk_rule_version, rule_set: rule_set, version: 2, state: 'published', rules: rules,
                                          published_at: Time.current)
      rule_set.update!(canary_version_id: canary.id, canary_percent: canary_percent)
    end
    rule_set
  end

  def build_order(amount: 200)
    order = create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: amount,
                                           shipment_cost: 0)
    order.update_columns(total: amount, item_total: amount, payment_total: 0,
                         email: "d15b-admin-#{suffix}@example.com")
    order.reload
  end

  # AC-012
  it 'renders the workspace with counts sourced from the same scope' do
    sign_in_as_admin
    build_published_rule_set(code: "listed_#{suffix}", canary_percent: 25)
    create(:risk_rule_set, code: "draft_only_#{suffix}", store: store, status: 'inactive')

    get '/admin/risk_rules'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(PallasTrade.t('admin.risk_rules.title'))

    %w[all active inactive].each do |status_filter|
      scope = PallasTrade::RiskRuleSet.for_store(store)
      expected = status_filter == 'all' ? scope.count : scope.where(status: status_filter).count
      expect(response.body).to include(%(data-count-scope="#{status_filter}">#{expected}</h3>))
    end

    expect(response.body).to include(%(data-rule-set-code="listed_#{suffix}"))
    expect(response.body).to include(%(data-rule-set-active-version="1"))
    expect(response.body).to include(%(data-rule-set-canary-percent="25"))
    expect(response.body).to include(%(data-rule-set-status="inactive"))
  end

  # AC-012（详情页：版本历史 + 生效规则表）
  it 'renders the version history and the active rules on the detail page' do
    sign_in_as_admin
    rule_set = build_published_rule_set(code: "detail_#{suffix}")

    get "/admin/risk_rules/#{rule_set.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(data-version="1"))
    expect(response.body).to include(%(data-version-state="published"))
    expect(response.body).to include(%(data-active-rules))
    expect(response.body).to include(%(data-rule-code="amount_review"))
    expect(response.body).to include(%(data-rule-set-active-version="1"))
  end

  # AC-013
  it 'creates a rule set container and refuses an invalid code' do
    sign_in_as_admin

    expect do
      post '/admin/risk_rules', params: { risk_rule_set: { code: "created_#{suffix}", name: 'Created' },
                                          store_scope: 'store' }
    end.to change(PallasTrade::RiskRuleSet, :count).by(1)
    expect(response).to have_http_status(:found)

    expect do
      post '/admin/risk_rules', params: { risk_rule_set: { code: 'BAD CODE', name: 'Nope' },
                                          store_scope: 'store' }
    end.not_to change(PallasTrade::RiskRuleSet, :count)
    expect(flash[:error]).to be_present
  end

  # AC-013
  it 'stores a valid draft version and refuses an invalid one' do
    sign_in_as_admin
    rule_set = create(:risk_rule_set, code: "draft_#{suffix}", store: store)

    expect do
      post "/admin/risk_rules/#{rule_set.id}/versions",
           params: { rules: JSON.generate(default_rules), reason: 'first' }
    end.to change { rule_set.versions.count }.by(1)

    expect do
      post "/admin/risk_rules/#{rule_set.id}/versions",
           params: { rules: JSON.generate([{ 'code' => 'bin_rule', 'action' => 'block',
                                             'conditions' => { 'bin_in' => %w[411111] } }]) }
    end.not_to change { rule_set.versions.count }
    expect(flash[:error]).to include('bin_in')
  end

  # AC-013
  it 'publishes a version and sets the canary' do
    sign_in_as_admin
    rule_set = create(:risk_rule_set, code: "publish_#{suffix}", store: store)
    post "/admin/risk_rules/#{rule_set.id}/versions", params: { rules: JSON.generate(default_rules) }
    version = rule_set.versions.reload.first

    post "/admin/risk_rules/#{rule_set.id}/publish", params: { version: version.version }

    expect(rule_set.reload.active_version_id).to eq(version.id)
    expect(version.reload.state).to eq('published')

    post "/admin/risk_rules/#{rule_set.id}/canary", params: { version: version.version, percent: 40 }

    expect(rule_set.reload.canary_percent).to eq(40)
    expect(rule_set.canary_version_id).to eq(version.id)
  end

  # AC-013（可达性：金丝雀下拉必须列出**草稿**，否则运营侧永远只看到生效版 → 灰度用不了）
  it 'offers draft versions in the canary picker and lets a draft be rolled out without becoming the live version' do
    sign_in_as_admin
    rule_set = build_published_rule_set(code: "canary_pick_#{suffix}")
    stable = rule_set.active_version
    draft = create(:risk_rule_version, rule_set: rule_set, version: 2, state: 'draft',
                                       rules: [{ 'code' => 'block_kp', 'action' => 'block',
                                                 'conditions' => { 'country_in' => %w[KP] } }])

    get "/admin/risk_rules/#{rule_set.id}"

    expect(response).to have_http_status(:ok)
    # 草稿作为候选出现（含状态标注），已归档版本不出现
    expect(response.body).to include(%(<option value="#{draft.version}">))
    expect(response.body).to include(PallasTrade.t('admin.risk_rules.state_draft'))
    archived = create(:risk_rule_version, rule_set: rule_set, version: 3, state: 'archived', rules: default_rules)
    get "/admin/risk_rules/#{rule_set.id}"
    expect(response.body).not_to include(%(<option value="#{archived.version}">))

    post "/admin/risk_rules/#{rule_set.id}/canary", params: { version: draft.version, percent: 30 }

    rule_set.reload
    expect(rule_set.canary_version_id).to eq(draft.id)
    expect(rule_set.canary_percent).to eq(30)
    # 草稿被发布为金丝雀，但**没有**成为生效版
    expect(draft.reload.state).to eq('published')
    expect(rule_set.active_version_id).to eq(stable.id)
    expect(stable.reload.state).to eq('published')
  end

  # AC-013（回滚：原因必填）
  it 'rolls back to an older version only when a reason is given' do
    sign_in_as_admin
    rule_set = build_published_rule_set(code: "rollback_#{suffix}")
    first = rule_set.active_version
    second = create(:risk_rule_version, rule_set: rule_set, version: 2, state: 'published',
                                        rules: [{ 'code' => 'block_all', 'priority' => 1, 'action' => 'block',
                                                  'conditions' => { 'amount_gte' => 1 } }],
                                        published_at: Time.current)
    rule_set.update!(active_version_id: second.id)

    expect do
      post "/admin/risk_rules/#{rule_set.id}/rollback", params: { version: first.version, reason: '' }
    end.not_to change { rule_set.versions.count }
    expect(flash[:error]).to be_present

    expect do
      post "/admin/risk_rules/#{rule_set.id}/rollback",
           params: { version: first.version, reason: 'blocked good orders' }
    end.to change { rule_set.versions.count }.by(1)

    rolled = rule_set.versions.reload.max_by(&:version)
    expect(rolled.rolled_back).to be(true)
    expect(rolled.source_version).to eq(first.version)
    expect(rule_set.reload.active_version_id).to eq(rolled.id)
  end

  # AC-013（停用）
  it 'toggles the rule set off' do
    sign_in_as_admin
    rule_set = build_published_rule_set(code: "toggle_#{suffix}")

    post "/admin/risk_rules/#{rule_set.id}/toggle"

    expect(rule_set.reload.status).to eq('inactive')
  end

  # AC-014（试算：只读）
  it 'previews the decision for one order without writing anything' do
    sign_in_as_admin
    rule_set = build_published_rule_set(code: "preview_#{suffix}")
    order = build_order
    snapshot = lambda do
      [PallasTrade::PaymentRiskAssessment.count, PallasTrade::AuditLog.count,
       order.reload.state, PallasTrade::RiskRuleVersion.count]
    end
    before = snapshot.call

    get '/admin/risk_rules/preview', params: { order_number: order.prefixed_id }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(data-preview-result))
    expect(response.body).to include(%(data-preview-rule-set="preview_#{suffix}"))
    expect(response.body).to include(%(data-preview-version="1"))
    expect(response.body).to include(%(data-preview-rule="amount_review"))
    expect(response.body).to include(%(data-preview-action="review"))
    expect(response.body).to include(%(data-preview-bucket="))
    expect(before).to eq(snapshot.call)
    expect(rule_set.reload.active_version_id).to be_present
  end

  # AC-014（找不到订单）
  it 'reports an unknown order number on the preview page' do
    sign_in_as_admin

    get '/admin/risk_rules/preview', params: { order_number: 'or_doesnotexist' }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(data-preview-error))
  end

  # AC-012（权限）
  it 'denies the workspace without the permission' do
    other_admin = create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true)
    sign_in other_admin

    get '/admin/risk_rules'

    expect(response).not_to have_http_status(:ok)
  end
end
