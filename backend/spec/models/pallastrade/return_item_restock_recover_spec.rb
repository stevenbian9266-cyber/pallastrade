# frozen_string_literal: true

require 'rails_helper'

# PRD-REV-P6-8e AC-R68E-01/02 —— ReturnItem#restock_if_ambiguous! 幂等自愈（RestockFact AMBIGUOUS）
RSpec.describe PallasTrade::ReturnItem, type: :model do
  let!(:store) { @default_store }
  let(:user) { create(:user) }

  def build_fixture(auto_restock: true)
    order = create(:shipped_order, store: store, user: user, line_items_count: 1,
                                   line_items_price: 10, shipment_cost: 0, with_payment: false)
    unit = order.inventory_units.shipped.first
    variant = unit.variant
    variant.update_column(:track_inventory, true)
    ra = create(:return_authorization, order: order)
    stock_item = create(:stock_item, variant: variant, stock_location: ra.stock_location, count_on_hand: 0)
    ri = create(:return_item, inventory_unit: unit, return_authorization: ra)

    if auto_restock
      cr = build(:customer_return_without_return_items, store: store, stock_location: ra.stock_location)
      cr.return_items << ri
      cr.save!
      ri.reload
    end
    [ri, ra, stock_item]
  end

  def simulate_lost_restock(ri, stock_item)
    movement = PallasTrade::StockMovement.where(return_item_id: ri.id).first
    stock_item.update!(count_on_hand: stock_item.count_on_hand - movement.quantity)
    movement.delete
    expect(PallasTrade::Returns::RestockFact.resolve(return_item: ri.reload)).to eq(:ambiguous)
  end

  describe 'AC-R68E-01 AMBIGUOUS 幂等自愈' do
    it 'accepted+eligible 但 movement 缺失 → restock_if_ambiguous! 回补一次；再调 no-op' do
      ri, _ra, stock_item = build_fixture
      simulate_lost_restock(ri, stock_item)

      expect(ri.restock_if_ambiguous!).to be true
      expect(PallasTrade::StockMovement.where(return_item_id: ri.id).count).to eq(1)
      expect(PallasTrade::Returns::RestockFact.resolve(return_item: ri.reload)).to eq(:restocked)

      expect(ri.restock_if_ambiguous!).to be false # 已有 movement → 守卫 no-op
      expect(PallasTrade::StockMovement.where(return_item_id: ri.id).count).to eq(1)
    end

    it 'rejected（未决/不可回补）→ false 且不建行' do
      ri, _ra, _stock_item = build_fixture(auto_restock: false)
      allow_any_instance_of(PallasTrade::ReturnItem::EligibilityValidator::Default)
        .to receive(:eligible_for_return?).and_return(false)
      allow_any_instance_of(PallasTrade::ReturnItem::EligibilityValidator::Default)
        .to receive(:requires_manual_intervention?).and_return(false)

      cr = build(:customer_return_without_return_items, store: store, stock_location: ri.return_authorization.stock_location)
      cr.return_items << ri
      cr.save!
      expect(ri.reload).to be_rejected

      expect(ri.restock_if_ambiguous!).to be false
      expect(PallasTrade::StockMovement.where(return_item_id: ri.id)).to be_empty
    end
  end
end
