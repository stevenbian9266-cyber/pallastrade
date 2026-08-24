# frozen_string_literal: true

require 'spec_helper'

# 修复：合并支付收银台处理支付组非激活状态（failed/expired 组不再抛状态机裸错误）
# failed 会话被重复 complete（陈旧重试）时：不得抛 InvalidTransition，不得把
# "Status cannot transition via complete" 写进 errors（否则 controller 返回 422 裸错误）。
RSpec.describe PallasTradeStripe::Gateway, type: :model do
  subject(:gateway) { create(:stripe_gateway) }

  let(:order) { create(:order_with_line_items) }
  let(:payment_session) do
    create(:stripe_payment_session,
           order: order,
           payment_method: gateway,
           amount: order.total,
           external_id: 'pi_complete_123')
  end

  describe '#complete_payment_session' do
    let(:stripe_pi) do
      Stripe::StripeObject.construct_from(
        id: 'pi_complete_123', status: 'succeeded', amount: payment_session.amount_in_cents,
        currency: payment_session.currency, latest_charge: 'ch_test_123',
        payment_method: { type: 'card' }
      )
    end

    before do
      allow(gateway).to receive(:retrieve_payment_intent).and_return(stripe_pi)
      allow(gateway).to receive(:verify_payment_intent_matches!).and_return(true)
      # 绕过 Payment 记录创建与 Stripe charge 查询（测试环境无有效 Stripe key）——
      # 聚焦状态机容错
      allow(payment_session).to receive(:find_or_create_payment!).and_return(nil)
      allow(payment_session).to receive(:payment).and_return(nil)
      allow(payment_session).to receive(:stripe_charge).and_return(nil)
    end

    context 'when the session has already failed (stale retry)' do
      before { payment_session.update_column(:status, 'failed') }

      it 'does not raise and does not add state-machine errors to the session' do
        expect { gateway.complete_payment_session(payment_session: payment_session) }
          .not_to raise_error
        expect(payment_session.errors).to be_empty
        expect(payment_session.reload.status).to eq('failed')
      end
    end

    context 'when the session is active and the intent succeeded' do
      it 'completes the session' do
        gateway.complete_payment_session(payment_session: payment_session)
        expect(payment_session.reload.status).to eq('completed')
      end
    end
  end
end
