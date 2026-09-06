# frozen_string_literal: true

# bugfix C1 (FIN-P4 review 批1, 2026-09-06): 组合 Payment（order_id=nil，PaymentCombinations::
# Settlement 新建路径）complete! 提交后 after_commit 发布 payment.paid，`publish_order_paid_event`
# 对 nil order 抛 NoMethodError → 异常从 Settlement 冒出、中断 Transactions::Finalize。
# 回归：order 缺失时 paid 事件发布不崩；order 存在且已 paid 时仍发布 order.paid。
require 'rails_helper'

RSpec.describe PallasTrade::Payment, type: :model do
  let(:store) { @default_store }

  describe 'custom paid events' do
    it 'publishing paid event for an order=nil combination payment does not crash (C1 nil-guard)' do
      pm = create(:bogus_payment_method, store: store, active: true)
      combo = create(:payment_combination, store: store, customer: create(:user),
                                           currency: 'USD', amount: 100)
      payment = create(:payment, order: nil, payment_combination: combo, payment_method: pm,
                                 amount: 100, state: 'checkout',
                                 source: nil, skip_source_requirement: true)

      # after_commit 在事务性 spec 不自动触发 —— 直接驱动回调逻辑（events enabled + completed 迁移）。
      allow(PallasTrade::Events).to receive(:enabled?).and_return(true)
      allow(payment).to receive(:publish_event)
      expect { payment.send(:publish_payment_paid_event) }.not_to raise_error
    end

    it 'still publishes order.paid when an order is present and fully paid' do
      order = create(:order, store: store, state: 'pending', status: 'placed', item_total: 100,
                             total: 100, payment_state: 'paid')
      pm = create(:bogus_payment_method, store: store, active: true)
      payment = create(:payment, order: order, payment_method: pm, amount: 100, state: 'completed',
                                 source: nil, skip_source_requirement: true)

      allow(PallasTrade::Events).to receive(:enabled?).and_return(true)
      allow(order).to receive(:paid?).and_return(true)
      expect(payment).to receive(:publish_event).with('payment.paid')
      expect(order).to receive(:publish_event).with('order.paid')
      expect { payment.send(:publish_payment_paid_event) }.not_to raise_error
    end
  end
end
