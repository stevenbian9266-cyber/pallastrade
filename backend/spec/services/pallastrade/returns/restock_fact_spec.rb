# frozen_string_literal: true

require 'rails_helper'

# PRD-REV-P6-5 AC-R65-04 —— Returns::RestockFact（源 REV-P6 §41）
# RESTOCKED / NOT_RESTOCKABLE / NOT_REQUIRED / PENDING / AMBIGUOUS —— 只读派生，不写库。
RSpec.describe PallasTrade::Returns::RestockFact, type: :service do
  let!(:store) { @default_store }
  let(:user) { create(:user) }

  def build_restocked_item
    order = create(:shipped_order, store: store, user: user, line_items_count: 1,
                                   line_items_price: 10, shipment_cost: 0, with_payment: false)
    unit = order.inventory_units.shipped.first
    unit.variant.update_column(:track_inventory, true)
    ra = create(:return_authorization, order: order)
    create(:stock_item, variant: unit.variant, stock_location: ra.stock_location, count_on_hand: 0)
    ri = create(:return_item, inventory_unit: unit, return_authorization: ra)
    cr = build(:customer_return_without_return_items, store: store, stock_location: ra.stock_location)
    cr.return_items << ri
    cr.save!
    ri.reload
  end

  it 'RESTOCKED：accepted 且可 restock 且存在 return_item movement' do
    ri = build_restocked_item
    expect(PallasTrade::Returns::RestockFact.resolve(return_item: ri)).to eq(:restocked)
  end

  it 'NOT_RESTOCKABLE：accepted 但不可 restock（resellable=false）' do
    order = create(:shipped_order, store: store, user: user, line_items_count: 1,
                                   line_items_price: 10, shipment_cost: 0, with_payment: false)
    unit = order.inventory_units.shipped.first
    unit.variant.update_column(:track_inventory, true)
    ra = create(:return_authorization, order: order)
    create(:stock_item, variant: unit.variant, stock_location: ra.stock_location, count_on_hand: 0)
    ri = create(:return_item, inventory_unit: unit, return_authorization: ra)
    ri.update_column(:resellable, false)
    cr = build(:customer_return_without_return_items, store: store, stock_location: ra.stock_location)
    cr.return_items << ri
    cr.save!

    expect(PallasTrade::Returns::RestockFact.resolve(return_item: ri.reload)).to eq(:not_restockable)
  end

  it 'NOT_REQUIRED：未 accepted 的终态（rejected）' do
    order = create(:shipped_order, store: store, user: user, line_items_count: 1,
                                   line_items_price: 10, shipment_cost: 0, with_payment: false)
    unit = order.inventory_units.shipped.first
    unit.variant.update_column(:track_inventory, true)
    ra = create(:return_authorization, order: order)
    create(:stock_item, variant: unit.variant, stock_location: ra.stock_location, count_on_hand: 0)
    ri = create(:return_item, inventory_unit: unit, return_authorization: ra)
    allow_any_instance_of(PallasTrade::ReturnItem::EligibilityValidator::Default)
      .to receive(:eligible_for_return?).and_return(false)
    allow_any_instance_of(PallasTrade::ReturnItem::EligibilityValidator::Default)
      .to receive(:requires_manual_intervention?).and_return(false)
    cr = build(:customer_return_without_return_items, store: store, stock_location: ra.stock_location)
    cr.return_items << ri
    cr.save!

    expect(PallasTrade::Returns::RestockFact.resolve(return_item: ri.reload)).to eq(:not_required)
  end

  it 'PENDING：未决（pending / manual_intervention_required）' do
    order = create(:shipped_order, store: store, user: user, line_items_count: 1,
                                   line_items_price: 10, shipment_cost: 0, with_payment: false)
    unit = order.inventory_units.shipped.first
    unit.variant.update_column(:track_inventory, true)
    ra = create(:return_authorization, order: order)
    create(:stock_item, variant: unit.variant, stock_location: ra.stock_location, count_on_hand: 0)
    ri = create(:return_item, inventory_unit: unit, return_authorization: ra)
    allow_any_instance_of(PallasTrade::ReturnItem::EligibilityValidator::Default)
      .to receive(:eligible_for_return?).and_return(false)
    allow_any_instance_of(PallasTrade::ReturnItem::EligibilityValidator::Default)
      .to receive(:requires_manual_intervention?).and_return(true)
    cr = build(:customer_return_without_return_items, store: store, stock_location: ra.stock_location)
    cr.return_items << ri
    cr.save!

    expect(PallasTrade::Returns::RestockFact.resolve(return_item: ri.reload)).to eq(:pending)
  end

  it 'AMBIGUOUS：accepted 且应 restock 但无 movement（异常，供 REV-P6-6 收敛）' do
    ri = build_restocked_item
    # 模拟 movement 缺失（被外部删除/竞态）→ ambiguous
    PallasTrade::StockMovement.where(return_item_id: ri.id).delete_all

    expect(PallasTrade::Returns::RestockFact.resolve(return_item: ri)).to eq(:ambiguous)
  end
end
