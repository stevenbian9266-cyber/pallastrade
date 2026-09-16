# frozen_string_literal: true

require 'rails_helper'

# PRD-20260916-catalog-ai-acceptance-audit AC-001 AC-002 AC-006 AC-007
#
#   AC-001：acceptance_state 只接受 accepted / discarded / nil
#   AC-002：未标记时 accepted? / discarded? 均为 false
#   AC-006：重复上报同一状态是幂等（不移动时间戳）
#   AC-007：改判会覆盖状态并更新时间戳
RSpec.describe PallasTrade::AI::Run, type: :model do
  let!(:store) do
    create(:store, code: "ai_accept_#{SecureRandom.hex(4)}", default: true, name: 'AI Accept Store')
  end

  # 没有 AI Run factory：Run 是一张纯审计表，直接建一条已成功的记录即可。
  def build_run
    described_class.create!(
      store: store,
      status: 'succeeded',
      mode: 'sync',
      capability_key: 'product_description'
    )
  end

  describe 'acceptance state (AC-001/AC-002)' do
    it 'starts undecided and claims neither accepted nor discarded' do
      run = build_run

      expect(run.acceptance_state).to be_nil
      expect(run.accepted?).to be(false)
      expect(run.discarded?).to be(false)
      expect(run.accepted_at).to be_nil
    end

    it 'only accepts the two declared states' do
      run = build_run

      run.acceptance_state = 'maybe'
      expect(run).not_to be_valid
      expect(run.errors[:acceptance_state]).to be_present

      described_class::ACCEPTANCE_STATES.each do |state|
        run.acceptance_state = state
        expect(run).to be_valid
      end
    end
  end

  describe '#record_acceptance! (AC-006/AC-007)' do
    it 'records an acceptance with a timestamp' do
      run = build_run

      expect(run.record_acceptance!('accepted')).to be(true)
      expect(run.reload.accepted?).to be(true)
      expect(run.accepted_at).to be_present
    end

    it 'is idempotent for a repeated state — the stamp must not move' do
      run = build_run
      run.record_acceptance!('accepted')
      first_stamp = run.reload.accepted_at

      expect(run.record_acceptance!('accepted')).to be(false)
      expect(run.reload.accepted_at).to eq(first_stamp)
    end

    it 'lets a change of mind overwrite the state and refresh the stamp' do
      run = build_run
      run.record_acceptance!('accepted')
      first_stamp = run.reload.accepted_at

      expect(run.record_acceptance!('discarded')).to be(true)
      run.reload
      expect(run.discarded?).to be(true)
      expect(run.accepted_at).to be >= first_stamp
    end
  end
end
