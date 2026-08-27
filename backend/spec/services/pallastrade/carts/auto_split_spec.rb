# frozen_string_literal: true

require 'rails_helper'

# PRD-20260827-checkout-实施-p5 P5a 自动拆单
# AC-001/002/003：默认关闭 / 配置策略后拆分 / 拆单失败不影响完成

# 测试专用策略：groups_for 抛异常（验证 AutoSplit 的 rescue 路径）
class AutoSplitBoomStrategy
  def groups_for(_order)
    raise StandardError, 'boom'
  end
end

RSpec.describe PallasTrade::Carts::AutoSplit, type: :service do
  let!(:store) { create(:store, code: 'auto_split_store') }
  let(:strategy_name) { 'PallasTrade::Orders::SplitStrategies::ByStockLocation' }

  describe '#call' do
    it 'AC-001 does nothing when no strategies configured (default closed)' do
      order = create(:order, store: store, state: 'complete', completed_at: Time.current)

      result = described_class.call(order: order)

      expect(result.success?).to be true
      expect(order.reload.children).to be_empty
      expect(order.reload.split_orders).to be_empty
    end

    it 'AC-002 splits the order by the configured strategy and conserves totals' do
      # store preference 开启自动拆单（ByStockLocation）
      store.update!(preferred_auto_split_orders: "[\"#{strategy_name}\"]")

      wh_a = create(:stock_location, name: 'WH-A', active: true)
      wh_b = create(:stock_location, name: 'WH-B', active: true)
      variant_a = create(:product, store: store).default_variant
      variant_b = create(:product, store: store).default_variant
      create(:stock_item, variant: variant_a, stock_location: wh_a, count_on_hand: 5)
      create(:stock_item, variant: variant_b, stock_location: wh_b, count_on_hand: 5)

      order = create(:order, store: store)
      create(:line_item, order: order, variant: variant_a, price: 10)
      create(:line_item, order: order, variant: variant_b, price: 10)

      result = described_class.call(order: order)

      expect(result.success?).to be true
      order.reload
      expect(order.children.count).to eq(2)
      expect(order.children.map(&:parent_id)).to all(eq(order.id))
      # 行项目全部迁移到子订单，金额守恒
      expect(order.children.to_a.sum { |c| c.line_items.size }).to eq(2)
      expect(order.children.to_a.sum { |c| c.item_total.to_f }).to eq(20.0)
    end

    it 'AC-003 keeps the order completed when the strategy raises' do
      store.update!(preferred_auto_split_orders: '["AutoSplitBoomStrategy"]')
      order = create(:order, store: store, state: 'complete', completed_at: Time.current)

      result = described_class.call(order: order)

      expect(result.success?).to be true
      expect(order.reload).to be_completed
      expect(order.children).to be_empty
    end

    it 'AC-003 keeps the order completed when splitting yields no groups' do
      store.update!(preferred_auto_split_orders: "[\"#{strategy_name}\"]")
      order = create(:order, store: store, state: 'complete', completed_at: Time.current)

      result = described_class.call(order: order)

      expect(result.success?).to be true
      expect(order.reload).to be_completed
      expect(order.children).to be_empty
    end
  end
end
