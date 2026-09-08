# frozen_string_literal: true

require 'rails_helper'

# PRD-REV-P6-8e AC-R68E-03/04 —— ReverseCommerce::Recover 跨域收敛（restock 自愈 + 复用 Refunds::Recover）
RSpec.describe PallasTrade::ReverseCommerce::Recover, type: :service do
  let!(:store) { @default_store }
  let(:user) { create(:user) }

  def build_order_with_ambiguous_restock
    order = create(:shipped_order, store: store, user: user, line_items_count: 1,
                                   line_items_price: 10, shipment_cost: 0, with_payment: false)
    unit = order.inventory_units.shipped.first
    unit.variant.update_column(:track_inventory, true)
    ra = create(:return_authorization, order: order)
    stock_item = create(:stock_item, variant: unit.variant, stock_location: ra.stock_location, count_on_hand: 0)
    ri = create(:return_item, inventory_unit: unit, return_authorization: ra)
    cr = build(:customer_return_without_return_items, store: store, stock_location: ra.stock_location)
    cr.return_items << ri
    cr.save!
    ri.reload

    # 模拟「accepted 但 movement 丢失」→ AMBIGUOUS
    movement = PallasTrade::StockMovement.where(return_item_id: ri.id).first
    stock_item.update!(count_on_hand: stock_item.count_on_hand - movement.quantity)
    movement.delete
    expect(PallasTrade::Returns::RestockFact.resolve(return_item: ri.reload)).to eq(:ambiguous)
    [order, ri, stock_item]
  end

  def attach_fresh_refund(order)
    pm = create(:bogus_payment_method, store: store, active: true)
    payment = create(:payment, order: order, payment_method: pm, amount: 10,
                               state: 'completed', source: nil, skip_source_requirement: true)
    create(:payment_capture_event, payment: payment, amount: 10.0)
    reason = create(:refund_reason)
    refund = create(:refund, payment: payment, reason: reason, amount: 5,
                             state: 'requested', transaction_id: nil)
    refund.update_columns(provider_idempotency_key: "refund:#{refund.prefixed_id}:execute")
    refund
  end

  describe 'AC-R68E-03 跨域收敛' do
    it 'AMBIGUOUS 自愈 healed + 计数正确 + fresh refund 复用 Recover 零副作用' do
      order, ri, stock_item = build_order_with_ambiguous_restock
      fresh_refund = attach_fresh_refund(order)

      outcome = described_class.call(order: order)
      expect(outcome).to be_success
      v = outcome.value

      expect(v[:restock][:ambiguous]).to eq(1)
      expect(v[:restock][:healed]).to eq(1)
      expect(PallasTrade::StockMovement.where(return_item_id: ri.id).count).to eq(1)
      expect(PallasTrade::Returns::RestockFact.resolve(return_item: ri.reload)).to eq(:restocked)

      # refund 域复用 Refunds::Recover：fresh requested → attempted + ok（no-op 不动作）
      expect(v[:refunds][:attempted]).to eq(1)
      expect(v[:refunds][:ok]).to eq(1)
      expect(fresh_refund.reload.state).to eq('requested')
    end

    it '已 RESTOCKED / 未决（PENDING/rejected）不动作只计数' do
      order = create(:shipped_order, store: store, user: user, line_items_count: 1,
                                     line_items_price: 10, shipment_cost: 0, with_payment: false)
      unit = order.inventory_units.shipped.first
      unit.variant.update_column(:track_inventory, true)
      ra = create(:return_authorization, order: order)
      create(:stock_item, variant: unit.variant, stock_location: ra.stock_location, count_on_hand: 0)

      # rejected（无 restock 决策）
      ri = create(:return_item, inventory_unit: unit, return_authorization: ra)
      allow_any_instance_of(PallasTrade::ReturnItem::EligibilityValidator::Default)
        .to receive(:eligible_for_return?).and_return(false)
      allow_any_instance_of(PallasTrade::ReturnItem::EligibilityValidator::Default)
        .to receive(:requires_manual_intervention?).and_return(false)
      cr = build(:customer_return_without_return_items, store: store, stock_location: ra.stock_location)
      cr.return_items << ri
      cr.save!

      outcome = described_class.call(order: order)
      v = outcome.value
      expect(v[:restock][:not_required]).to eq(1)
      expect(v[:restock][:healed]).to eq(0)
      expect(v[:restock][:errors]).to eq(0)
      expect(PallasTrade::StockMovement.where(return_item_id: ri.id)).to be_empty
    end
  end
end
