# frozen_string_literal: true

# PRD-REV-P6-8j AC-R68J-02 —— OrderCancellation durable intent 状态机
require 'rails_helper'

RSpec.describe PallasTrade::OrderCancellation, type: :model do
  let!(:store) { @default_store }
  let(:order) do
    create(:order, store: store, state: 'pending', status: 'placed', submitted_at: Time.current,
                   item_total: 10, total: 10, payment_state: 'paid',
                   currency: store.default_currency, email: 'oc@example.com')
  end

  def build_cancellation(state: 'requested')
    order.cancellations.create!(reason: 'staff', state: state)
  end

  describe 'state machine' do
    it 'AC-R68J-02: 默认 requested；apply → applied；谓词/scopes 生效' do
      oc = build_cancellation
      expect(oc.state).to eq('requested')
      expect(oc).to be_requested

      expect { oc.apply! }.not_to raise_error
      expect(oc.reload.state).to eq('applied')
      expect(PallasTrade::OrderCancellation.applied).to include(oc)
      expect(PallasTrade::OrderCancellation.requested).not_to include(oc)
    end

    it 'AC-R68J-02: 非法迁移（applied→apply）raise；recovery_required/manual_review/failed 事件按 from-state 守卫' do
      oc = build_cancellation(state: 'applied')
      expect { oc.apply! }.to raise_error(StateMachines::InvalidTransition)

      expect { oc.flag_recovery_required! }.not_to raise_error
      expect(oc.reload.state).to eq('recovery_required')
      expect(oc).to be_recovery_attention
      expect(PallasTrade::OrderCancellation.needs_attention).to include(oc)

      expect { oc.flag_manual_review! }.not_to raise_error
      expect(oc.reload.state).to eq('manual_review')

      # reapply：人工裁决后回到 applied
      expect { oc.reapply! }.not_to raise_error
      expect(oc.reload.state).to eq('applied')

      # fail：可从 applied 标记失败
      expect { oc.fail! }.not_to raise_error
      expect(oc.reload.state).to eq('failed')
    end

    it 'AC-R68J-02: 事件 from-state 守卫（requested 不可直接 flag_recovery_required）' do
      oc = build_cancellation # requested
      expect { oc.flag_recovery_required! }.to raise_error(StateMachines::InvalidTransition)
    end
  end
end
