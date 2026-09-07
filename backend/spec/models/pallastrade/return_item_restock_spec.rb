# frozen_string_literal: true

require 'rails_helper'

# PRD-REV-P6-5 AC-R65-01/02/03 —— ReturnItem restock 决策（acceptance 后）+ exactly-once
# 源 REV-P6 §39-42：Inspection/Acceptance → Restock Decision；one logical restock → at most
# one positive StockMovement（return_item_id partial unique 兜底）。
RSpec.describe PallasTrade::ReturnItem, type: :model do
  let!(:store) { @default_store }
  let(:user) { create(:user) }

  # shipped_order 一个已发货 inventory unit；variant 跟踪库存；
  # RA 自带 stock_location 放 stock_item（restock 目标）；CR 挂该 item → after_create
  # process_return!（receive! → attempt_accept 自动裁决）。
  def build_restock_fixture
    order = create(:shipped_order, store: store, user: user, line_items_count: 1,
                                   line_items_price: 10, shipment_cost: 0, with_payment: false)
    unit = order.inventory_units.shipped.first
    variant = unit.variant
    variant.update_column(:track_inventory, true)
    ra = create(:return_authorization, order: order)
    stock_item = create(:stock_item, variant: variant, stock_location: ra.stock_location,
                                     count_on_hand: 0)
    ri = create(:return_item, inventory_unit: unit, return_authorization: ra)
    [ri, ra, stock_item, unit]
  end

  def save_customer_return(ri, ra)
    cr = build(:customer_return_without_return_items, store: store, stock_location: ra.stock_location)
    cr.return_items << ri
    cr.save!
    cr
  end

  it 'AC-R65-01: 可售退货 receive → auto accept → restock（movement 带 return_item_id，与旧行为一致）' do
    ri, ra, stock_item, unit = build_restock_fixture
    before_count = stock_item.reload.count_on_hand

    save_customer_return(ri, ra)

    expect(ri.reload).to be_accepted
    movement = PallasTrade::StockMovement.where(return_item_id: ri.id)
    expect(movement.count).to eq(1)
    expect(movement.first.quantity).to eq(unit.quantity)
    expect(movement.first.originator).to eq(ra)
    expect(stock_item.reload.count_on_hand).to eq(before_count + unit.quantity)
  end

  it 'AC-R65-02: manual_intervention_required 未决（receive 后）→ 不 restock；手动 accept 后才 restock' do
    ri, ra, stock_item, = build_restock_fixture
    allow_any_instance_of(PallasTrade::ReturnItem::EligibilityValidator::Default)
      .to receive(:eligible_for_return?).and_return(false)
    allow_any_instance_of(PallasTrade::ReturnItem::EligibilityValidator::Default)
      .to receive(:requires_manual_intervention?).and_return(true)
    before_count = stock_item.reload.count_on_hand

    save_customer_return(ri, ra)

    expect(ri.reload).to be_manual_intervention_required
    expect(PallasTrade::StockMovement.where(return_item_id: ri.id)).to be_empty
    expect(stock_item.reload.count_on_hand).to eq(before_count) # 坏品/未决不提前入库（原 bug 修复）

    # 手动 accept（bypass）→ restock
    ri.accept!
    movement = PallasTrade::StockMovement.where(return_item_id: ri.id)
    expect(movement.count).to eq(1)
    expect(stock_item.reload.count_on_hand).to eq(before_count + ri.inventory_unit.quantity)
  end

  it 'AC-R65-02: rejected（不通过）→ 永不 restock' do
    ri, ra, stock_item, = build_restock_fixture
    allow_any_instance_of(PallasTrade::ReturnItem::EligibilityValidator::Default)
      .to receive(:eligible_for_return?).and_return(false)
    allow_any_instance_of(PallasTrade::ReturnItem::EligibilityValidator::Default)
      .to receive(:requires_manual_intervention?).and_return(false)
    before_count = stock_item.reload.count_on_hand

    save_customer_return(ri, ra)

    expect(ri.reload).to be_rejected
    expect(PallasTrade::StockMovement.where(return_item_id: ri.id)).to be_empty
    expect(stock_item.reload.count_on_hand).to eq(before_count)
  end

  it 'AC-R65-03: 同一 return_item 重复 restock（重试）→ 仅 1 条正向 movement（DB partial unique 幂等）' do
    ri, ra, stock_item, unit = build_restock_fixture
    before_count = stock_item.reload.count_on_hand

    save_customer_return(ri, ra)
    expect(PallasTrade::StockMovement.where(return_item_id: ri.id).count).to eq(1)
    expect(stock_item.reload.count_on_hand).to eq(before_count + unit.quantity)

    # 重复触发（同 return_item 再次建 movement → RecordNotUnique 幂等跳过）
    expect { ri.send(:restock_if_needed) }.not_to(change { PallasTrade::StockMovement.where(return_item_id: ri.id).count })
    expect(stock_item.reload.count_on_hand).to eq(before_count + unit.quantity)
  end
end
