# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-catalog-ai-acceptance-audit AC-003 AC-004 AC-005 AC-008
#
#   AC-003：合法 run_id + accepted → 200 且写入状态与时间
#   AC-004：跨店 run_id → 404 且该 run 零改动
#   AC-005：非法 state → 422 且零写入
#   AC-008：Runs 列表展示采纳状态；未处理显示对应文案
RSpec.describe 'Admin AI acceptances', type: :request do
  let!(:store) do
    create(:store, code: "ai_acc_#{SecureRandom.hex(4)}", default: true, name: 'AI Acc Store')
  end
  let!(:other_store) { create(:store, code: "ai_acc_other_#{SecureRandom.hex(4)}", name: 'Other Store') }
  let(:admin) { create(:admin_user, without_admin_role: true) }

  let!(:run) do
    PallasTrade::AI::Run.create!(
      store: store, status: 'succeeded', mode: 'sync', capability_key: 'product_description'
    )
  end
  let!(:foreign_run) do
    PallasTrade::AI::Run.create!(
      store: other_store, status: 'succeeded', mode: 'sync', capability_key: 'product_description'
    )
  end

  def sign_in_as_superuser
    sign_in admin
    role = PallasTrade::Role.default_admin_role
    create(:role_user, user: admin, role: role, resource: store, store: store)
    allow_any_instance_of(PallasTrade::Admin::AIController).to receive(:current_store).and_return(store)
    allow_any_instance_of(PallasTrade::Admin::AIController)
      .to receive(:try_pallastrade_current_user).and_return(admin)
  end

  describe 'POST /admin/ai/acceptances (AC-003)' do
    it 'records the acceptance on the run' do
      sign_in_as_superuser

      post '/admin/ai/acceptances', params: { run_id: run.id, state: 'accepted' }

      expect(response).to have_http_status(:ok)
      run.reload
      expect(run.acceptance_state).to eq('accepted')
      expect(run.accepted_at).to be_present
      expect(JSON.parse(response.body)['acceptance_state']).to eq('accepted')
    end
  end

  describe 'store isolation (AC-004)' do
    it 'answers 404 for another store\'s run and touches nothing' do
      sign_in_as_superuser

      post '/admin/ai/acceptances', params: { run_id: foreign_run.id, state: 'accepted' }

      expect(response).to have_http_status(:not_found)
      foreign_run.reload
      expect(foreign_run.acceptance_state).to be_nil
      expect(foreign_run.accepted_at).to be_nil
    end
  end

  describe 'invalid input (AC-005)' do
    it 'rejects an unknown state without writing' do
      sign_in_as_superuser

      post '/admin/ai/acceptances', params: { run_id: run.id, state: 'maybe' }

      expect(response).to have_http_status(:unprocessable_entity)
      run.reload
      expect(run.acceptance_state).to be_nil
      expect(run.accepted_at).to be_nil
    end
  end

  describe 'GET /admin/ai/runs (AC-008)' do
    it 'marks undecided runs and shows the recorded state' do
      sign_in_as_superuser

      get '/admin/ai/runs'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Not decided')

      run.record_acceptance!('accepted')

      get '/admin/ai/runs'
      expect(response.body).to include('accepted')
    end
  end
end
