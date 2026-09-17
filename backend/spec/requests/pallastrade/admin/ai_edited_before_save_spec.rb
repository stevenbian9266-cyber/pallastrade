# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-catalog-ai-edited-before-save AC-001 AC-002 AC-003 AC-004 AC-005
#   AC-001 edited 是合法终态；未知状态仍 422
#   AC-002 accepted 之后报 edited 会覆盖为 edited
#   AC-003 重复报 edited 幂等（不报错、不产生额外副作用）
#   AC-004 跨店「他人 run」→ 404 且不修改
#   AC-005 AI Runs 列表在 zh-CN 下能显示 edited（本域不泄漏 missing）
RSpec.describe 'AI acceptance — edited before save', type: :request do
  # 显式随机 code：store 工厂的序列 code 会与历史测试库残留冲突（已知测试卫生问题）
  let!(:store) do
    create(:store, code: "ai_edit_#{SecureRandom.hex(4)}", default: true,
                   default_currency: 'USD', default_locale: 'en', name: 'AI Edit Store')
  end
  let(:admin) { create(:admin_user, password: 'secret', password_confirmation: 'secret', without_admin_role: true) }

  # `PallasTrade::AI::Run` 是内部模型 —— 它没有 `prefix_id`（那是对外资源的机制），
  # 端点按主键查找。所以这里一律传 `record.id`。
  def new_run(for_store)
    PallasTrade::AI::Run.create!(store: for_store, capability_key: 'catalog.product_copy', status: 'succeeded')
  end

  def sign_in_as_admin
    sign_in admin
    create(:role_user, user: admin, role: PallasTrade::Role.default_admin_role, resource: store, store: store)
  end

  def report(record, state)
    post '/admin/ai/acceptances', params: { run_id: record.id, state: state }, as: :json
  end

  before { sign_in_as_admin }

  describe 'the edited terminal state (AC-001)' do
    it 'accepts edited as a valid state' do
      run = new_run(store)

      report(run, 'edited')

      expect(response).to have_http_status(:ok)
      expect(run.reload.acceptance_state).to eq('edited')
    end

    it 'still rejects an unknown state' do
      run = new_run(store)

      report(run, 'rewritten')

      expect(response).to have_http_status(:unprocessable_content).or have_http_status(:unprocessable_entity)
      expect(run.reload.acceptance_state).to be_nil
    end
  end

  # D1：edited 覆盖 accepted —— 「商家最终怎么处理这份草稿」只有一个答案。
  describe 'edited supersedes accepted (AC-002)' do
    it 'overwrites a previous accepted decision' do
      run = new_run(store)

      report(run, 'accepted')
      expect(run.reload.acceptance_state).to eq('accepted')

      report(run, 'edited')
      expect(run.reload.acceptance_state).to eq('edited')
    end

    it 'keeps a decision timestamp' do
      run = new_run(store)

      report(run, 'edited')

      expect(run.reload.accepted_at).to be_present
    end
  end

  describe 'idempotency (AC-003)' do
    it 'does not fail when the same state is reported twice' do
      run = new_run(store)

      report(run, 'edited')
      first_at = run.reload.accepted_at

      report(run, 'edited')

      expect(response).to have_http_status(:ok)
      expect(run.reload.acceptance_state).to eq('edited')
      expect(run.reload.accepted_at).to eq(first_at)
    end
  end

  describe 'store isolation (AC-004)' do
    it 'answers 404 for another store and leaves it untouched' do
      other_store = create(:store, code: "ai_edit_other_#{SecureRandom.hex(4)}")
      foreign = new_run(other_store)

      report(foreign, 'edited')

      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.acceptance_state).to be_nil
    end
  end

  describe 'list rendering (AC-005)' do
    it 'renders the page in en without leaking its own translations' do
      new_run(store).record_acceptance!('edited')

      get '/admin/ai/runs'

      expect(response).to have_http_status(:ok)
      expect(response.body.scan(/translation missing: [^<"&]+/i)).to be_empty
    end

    it 'renders the Chinese label for the edited state' do
      store.update!(preferred_admin_locale: 'zh-CN')
      new_run(store).record_acceptance!('edited')

      get '/admin/ai/runs'

      expect(response.body).to include('采纳后已修改')
    end

    # 只对本域负责：页面里还有一条 **Rails 内置**的中文缺失
    # （datetime.distance_in_words）—— 那属于后台 i18n 量化报告里的既有缺口，
    # 见 docs/research/RESEARCH-20260917-admin-i18n-gap.md
    it 'never leaks a translation-missing string belonging to the ai namespace' do
      store.update!(preferred_admin_locale: 'zh-CN')
      new_run(store).record_acceptance!('edited')

      get '/admin/ai/runs'

      leaked = response.body.scan(/translation missing: [^<"&]+/i)
      expect(leaked.grep(/pallastrade\.ai\./)).to be_empty
    end
  end
end
