# frozen_string_literal: true

# PRD-20260824-checkout-正向订单-逆向订单链路重构或优化 FR-035 / AC-035
# 父订单售后：批量创建其下全部子订单的 ReturnAuthorization，幂等
require 'rails_helper'

RSpec.describe PallasTrade::Returns::FromParent, type: :service do
  let(:store) { create(:store, code: 'returns_parent_test') }
  let(:user) { create(:user) }
  let(:parent) { create(:order_with_line_items, store: store, user: user, currency: 'USD') }
  let(:reason) { create(:return_authorization_reason) }
  let(:stock_location) { create(:stock_location) }

  # 让订单具备可售后的 shipped inventory_units（RA 创建校验 must_have_shipped_units）
  def add_shipped_units(order)
    order.line_items.each do |li|
      create(:inventory_unit, order: order, line_item: li, variant: li.variant, state: 'shipped')
    end
  end

  describe '#call' do
    it 'AC-035: 对未拆单订单 → 仅创建 1 个 RA（父=子）' do
      parent
      add_shipped_units(parent)

      result = described_class.call(order: parent, reason: reason, stock_location: stock_location)

      expect(result).to be_success
      expect(result.value.size).to eq(1)
      expect(result.value.first.order).to eq(parent)
    end

    it 'AC-035: 对父订单（含子订单）→ 为父订单 + 全部子订单各创建 1 个 RA' do
      parent
      extra = create(:line_item, order: parent, price: 50)
      add_shipped_units(parent)

      split_result = PallasTrade::Orders::Splitter.call(order: parent, groups: { 'g1' => [extra.id] })
      child = split_result.value.first
      # 拆单后 extra 的行项目属于子订单，为子订单补 shipped units（模拟子订单已发货）
      add_shipped_units(child)

      result = described_class.call(order: parent, reason: reason, stock_location: stock_location)

      expect(result).to be_success
      ra_orders = result.value.map(&:order)
      expect(ra_orders).to contain_exactly(parent, child)
    end

    it 'AC-035: 幂等 — 已有非 canceled RA 的子订单不重复创建，全部已存在时返回 failure' do
      parent
      extra = create(:line_item, order: parent, price: 50)
      add_shipped_units(parent)
      split_result = PallasTrade::Orders::Splitter.call(order: parent, groups: { 'g1' => [extra.id] })
      child = split_result.value.first
      add_shipped_units(child)

      first = described_class.call(order: parent, reason: reason, stock_location: stock_location)
      expect(first).to be_success
      expect(first.value.size).to eq(2)

      second = described_class.call(order: parent, reason: reason, stock_location: stock_location)
      expect(second).to be_failure
      expect(second.error.value[:code]).to eq(:no_return_authorization_created)

      # 数据库里仍只有首次创建的 2 个 RA
      expect(PallasTrade::ReturnAuthorization.where(order_id: [parent.id, child.id]).count).to eq(2)
    end

    it 'AC-035: 无 shipped units 的子订单被跳过（RA 校验失败），不阻塞其他订单' do
      parent
      extra = create(:line_item, order: parent, price: 50)
      add_shipped_units(parent)
      split_result = PallasTrade::Orders::Splitter.call(order: parent, groups: { 'g1' => [extra.id] })
      child = split_result.value.first
      # 子订单不补 shipped units

      result = described_class.call(order: parent, reason: reason, stock_location: stock_location)

      expect(result).to be_success
      expect(result.value.size).to eq(1)
      expect(result.value.first.order).to eq(parent)
      expect(child.return_authorizations).to be_empty
    end
  end
end
