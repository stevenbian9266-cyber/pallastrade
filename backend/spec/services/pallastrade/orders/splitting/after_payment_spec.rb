require 'rails_helper'

# PRD-20260824-checkout-正向订单-逆向订单链路重构或优化
# FR-022/023/026 — 支付后系统自动拆单（策略评估）
RSpec.describe PallasTrade::Orders::Splitting::AfterPayment, type: :service do
  let(:store) { PallasTrade::Store.default }
  let(:user) { create(:user) }

  after do
    PallasTrade::Config[:auto_split_orders] = nil
    PallasTrade::Config[:auto_split_orders_custom] = nil
  end

  def paid_order(line_items_count = 1)
    order = create(:order_with_line_items, store: store, user: user, currency: 'USD',
                                           line_items_count: line_items_count)
    # Order#paid? 基于 payments.valid.completed，需创建真实 Payment 记录（factory 自动建 payment_method）
    create(:payment, order: order, amount: order.total, state: 'completed')
    order.update_columns(payment_state: 'paid', payment_total: order.total)
    order
  end

  it 'AC-026: 拆单策略未配置（关闭）→ 不拆单' do
    PallasTrade::Config[:auto_split_orders] = nil
    order = paid_order
    result = described_class.call(order: order)
    expect(result).to be_success
    expect(order.children.reload).to be_empty
  end

  it 'AC-022: 策略=store 但单店订单无多组 → 不拆单（正常）' do
    PallasTrade::Config[:auto_split_orders] = 'store'
    order = paid_order
    result = described_class.call(order: order)
    expect(result).to be_success
    expect(order.children.reload).to be_empty
  end

  it 'AC-023: 自定义策略返回多组时拆分（归入父订单）' do
    PallasTrade::Config[:auto_split_orders] = 'custom'
    PallasTrade::Config[:auto_split_orders_custom] = lambda { |order|
      ids = order.line_items.map(&:id)
      { 'A' => [ids[0]], 'B' => [ids[1]] }
    }

    order = paid_order(2)
    result = described_class.call(order: order)
    expect(result).to be_success
    children = order.children.reload
    expect(children.size).to eq(2)
    children.each do |child|
      expect(child.parent).to eq(order)
      expect(child.split_from).to eq(order)
    end
  end

  it 'AC-023: 拆分后已付金额按行项目分摊（子订单继承 paid，不重复支付）' do
    PallasTrade::Config[:auto_split_orders] = 'custom'
    PallasTrade::Config[:auto_split_orders_custom] = lambda { |order|
      ids = order.line_items.map(&:id)
      { 'A' => [ids[0]], 'B' => [ids[1]] }
    }

    order = paid_order(2)
    # 拆分前行项目总额（拆分后源订单行项目被移走；shipment 成本归属父订单不参与分摊）
    items_total = order.line_items.sum(&:amount).to_f
    described_class.call(order: order)
    children = order.children.reload
    children.each do |child|
      child.reload
      # 子订单有真实的 completed Payment 记录（Order#paid? 基于 payments）
      expect(child.payments.completed.sum(:amount)).to be > 0
      expect(child.payment_state).to eq('paid')
    end
    # 分摊总额守恒：全部子订单已付金额合计 = 拆分前行项目总额
    expect(children.sum { |c| c.payments.completed.sum(:amount).to_f })
      .to be_within(0.01).of(items_total)
  end
end
