# frozen_string_literal: true

require 'rails_helper'

# PRD-20260919-checkout-结算页待支付订单再次支付重验-失效行剔除-优惠复核-订单金额变化提示-收银台弹窗退役 AC-001 / AC-003 / AC-006 / AC-007
# 补付重验（OrderCheckout::Revalidate）
#
# - dry-run（页面预检）：零副作用（不落库、不发事件）
# - 写路径：失效行剔除（只对有效商品扣款）+ 报价窗口签发/续期
# - 全部失效：no_payable_items 硬阻断
RSpec.describe PallasTrade::OrderCheckout::Revalidate do
  let(:store) { @default_store || create(:store, default: true, default_currency: 'USD') }
  let(:user) { create(:user) }

  # 标准流程「已提交未支付」订单（两行，便于构造部分失效）
  def pending_order(line_items_count: 2)
    order = create(:order_with_line_items, store: store, user: user,
                                           line_items_count: line_items_count,
                                           line_items_price: 100, shipment_cost: 0)
    order.update_columns(state: 'pending', status: 'placed', submitted_at: Time.current,
                         completed_at: nil, payment_state: 'balance_due', payment_total: 0)
    PallasTrade::OrderUpdater.new(order).update
    order.reload
  end

  def archive_product!(line_item)
    line_item.variant.product.update_columns(status: 'archived')
  end

  describe 'dry-run（页面预检）' do
    it 'AC-001: 报告失效行且零副作用（不删行、不改金额、不发事件）' do
      order = pending_order
      archived = order.line_items.first
      archive_product!(archived)

      items_before = order.line_items.count
      total_before = order.total.to_s
      # 事务外可观察的副作用：dry-run 绝不发布事件
      expect(PallasTrade::Events).not_to receive(:publish)

      result = described_class.call(order: order)

      expect(result.success?).to be true
      report = result.value
      expect(report['payable']).to be true
      expect(report['invalid_items'].map { |item| item['line_item_id'] })
        .to include(archived.prefixed_id)
      expect(report['invalid_items'].first['reason']).to eq('archived')

      order.reload
      expect(order.line_items.count).to eq(items_before)
      expect(order.total.to_s).to eq(total_before)
    end

    it 'AC-007: 无报价窗口 → window.valid=false 且 dry-run 不签发窗口' do
      order = pending_order
      order.update_columns(checkout_expires_at: nil)

      result = described_class.call(order: order)

      expect(result.value['window']['valid']).to be false
      expect(order.reload.checkout_expires_at).to be_nil
    end

    it 'AC-007: 窗口内 → 锁价（window.valid=true，不触发重定价）' do
      order = pending_order
      order.update_columns(checkout_expires_at: 10.minutes.from_now)

      result = described_class.call(order: order)

      expect(result.value['window']['valid']).to be true
      expect(result.value['changes'].map { |change| change['kind'] }).not_to include('price_changed')
    end
  end

  describe '写路径（dry_run: false）' do
    it 'AC-003: 剔除失效行并签发报价窗口（amount_due 按剩余有效商品重算）' do
      order = pending_order
      archived = order.line_items.first
      archive_product!(archived)
      order.update_columns(checkout_expires_at: nil)
      total_before = order.total.to_d
      items_before = order.line_items.count
      # 写路径要留痕（审计事件）
      expect(PallasTrade::Events).to receive(:publish).at_least(:once)

      result = described_class.call(order: order, dry_run: false)

      expect(result.success?).to be true
      report = result.value
      expect(report['payable']).to be true
      expect(report['changes'].map { |change| change['kind'] }).to include('item_removed')

      order.reload
      expect(order.line_items.count).to eq(items_before - 1)
      expect(order.line_items.map(&:id)).not_to include(archived.id)
      expect(order.total.to_d).to be < total_before
      expect(report['amount_due_after']).to eq(order.amount_due.to_s)
      # 窗口已签发（Refresh 续窗）
      expect(order.checkout_expires_at).to be_present
      expect(report['window']['reissued']).to be true
    end

    it 'AC-006: 全部商品失效 → no_payable_items（不可支付）' do
      order = pending_order(line_items_count: 1)
      archive_product!(order.line_items.first)

      result = described_class.call(order: order, dry_run: false)

      expect(result.success?).to be true
      report = result.value
      expect(report['payable']).to be false
      expect(report['blockers'].map { |blocker| blocker['code'] }).to include('no_payable_items')
      expect(order.reload.line_items.count).to eq(0)
    end
  end
end
