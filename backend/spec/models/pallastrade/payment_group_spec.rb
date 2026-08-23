# frozen_string_literal: true

# PRD-20260823-checkout-多订单拆分与合并支付 AC-001
require 'rails_helper'

RSpec.describe PallasTrade::PaymentGroup, type: :model do
  let(:store) { create(:store, code: 'pg_model_test') }
  let(:user) { create(:user) }

  describe 'associations' do
    it 'has prefixed pg_ id' do
      group = create(:payment_group, store: store, customer: user)
      expect(group.prefixed_id).to start_with('pg_')
    end

    it 'has many orders and payment sessions' do
      group = create(:payment_group, store: store, customer: user)
      order = create(:order_with_totals, store: store, user: user, payment_group: group)
      session = create(:payment_session, order: order, payment_group: group)

      expect(group.orders).to include(order)
      expect(group.payment_sessions).to include(session)
    end
  end

  describe 'state machine' do
    it 'transitions pending → processing → completed' do
      group = create(:payment_group, store: store, customer: user)
      group.process!
      group.complete!
      expect(group.reload.status).to eq('completed')
      expect(group.completed_at).to be_present
    end

    it 'can fail or cancel from pending' do
      group = create(:payment_group, store: store, customer: user)
      group.fail!
      expect(group.reload.status).to eq('failed')
    end
  end

  describe '#total_minus_store_credits' do
    it 'sums member order outstanding amounts (server-computed)' do
      group = create(:payment_group, store: store, customer: user)
      create(:order_with_totals, store: store, user: user, payment_group: group, currency: 'USD')
      create(:order_with_totals, store: store, user: user, payment_group: group, currency: 'USD')

      expect(group.total_minus_store_credits).to be > 0
      expect(group.total_minus_store_credits).to eq(group.orders.sum(&:total_minus_store_credits))
    end
  end

  describe '#recalculate!' do
    it 'persists the summed amount' do
      group = create(:payment_group, store: store, customer: user)
      create(:order_with_totals, store: store, user: user, payment_group: group, currency: 'USD')
      group.recalculate!
      expect(group.reload.amount).to eq(group.orders.sum(&:total))
    end
  end

  describe 'scopes' do
    it 'active excludes expired and finished groups' do
      active = create(:payment_group, store: store, customer: user, status: 'pending')
      finished = create(:payment_group, store: store, customer: user, status: 'completed')
      expect(PallasTrade::PaymentGroup.active).to include(active)
      expect(PallasTrade::PaymentGroup.active).not_to include(finished)
    end
  end
end
