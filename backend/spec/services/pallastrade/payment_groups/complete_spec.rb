# frozen_string_literal: true

# PRD-20260823-checkout-多订单拆分与合并支付 AC-004
require 'rails_helper'

RSpec.describe PallasTrade::PaymentGroups::Complete, type: :service do
  let(:store) { create(:store, code: 'pg_complete_test') }
  let(:user) { create(:user) }
  let(:gateway) { create(:credit_card_payment_method, stores: [store]) }

  let(:group) { create(:payment_group, store: store, customer: user) }
  let(:order_a) { create(:order_with_totals, store: store, user: user, payment_group: group, currency: 'USD') }
  let(:order_b) { create(:order_with_totals, store: store, user: user, payment_group: group, currency: 'USD') }

  let(:payment_session) do
    create(:payment_session, order: order_a, payment_group: group, payment_method: gateway,
                             amount: group.total_minus_store_credits, currency: 'USD')
  end

  describe '#call' do
    it 'completes every member order and the group idempotently' do
      order_a
      order_b

      result = described_class.call(payment_group: group, payment_session: payment_session)

      expect(result).to be_success
      expect(order_a.reload).to be_completed
      expect(order_b.reload).to be_completed
      expect(group.reload.status).to eq('completed')

      # Second run is a no-op (idempotent)
      expect { described_class.call(payment_group: group, payment_session: payment_session) }
        .not_to(change { order_a.reload.completed_at })
    end

    it 'creates a payment record per member order sharing the external id' do
      order_a
      order_b

      described_class.call(payment_group: group, payment_session: payment_session)

      expect(order_a.payments.map(&:response_code)).to include(payment_session.external_id)
      expect(order_b.payments.map(&:response_code)).to include(payment_session.external_id)
    end
  end
end
