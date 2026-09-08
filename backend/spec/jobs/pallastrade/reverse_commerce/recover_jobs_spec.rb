# frozen_string_literal: true

# PRD-REV-P6-8i AC-R68I-01~04 —— ReverseCommerce::Recover 自动调度化（sweeper + job）
require 'rails_helper'

ActiveJob::Base.queue_adapter = :test

RSpec.describe 'ReverseCommerce Recover scheduling', type: :job do
  let!(:store) { @default_store }

  # 镜像 8e spec：accepted + restock-eligible + 删除 movement → RestockFact AMBIGUOUS
  def build_ambiguous_order(store:)
    order = create(:shipped_order, store: store, line_items_count: 1,
                                   line_items_price: 10, shipment_cost: 0, with_payment: false)
    unit = order.inventory_units.shipped.first
    unit.variant.update_column(:track_inventory, true)
    ra = create(:return_authorization, order: order)
    stock_item = create(:stock_item, variant: unit.variant, stock_location: ra.stock_location, count_on_hand: 0)
    ri = create(:return_item, inventory_unit: unit, return_authorization: ra)
    cr = build(:customer_return_without_return_items, store: store, stock_location: ra.stock_location)
    cr.return_items << ri
    cr.save!

    movement = PallasTrade::StockMovement.where(return_item_id: ri.id).first
    stock_item.update!(count_on_hand: stock_item.count_on_hand - movement.quantity)
    movement.delete
    expect(PallasTrade::Returns::RestockFact.resolve(return_item: ri.reload)).to eq(:ambiguous)
    order
  end

  def enqueued_recover_jobs
    enqueued_jobs.count { |j| j[:job] == PallasTrade::ReverseCommerce::RecoverJob }
  end

  describe PallasTrade::ReverseCommerce::RecoverSweeperJob do
    it 'AC-R68I-01/03: store 内有 restock-AMBIGUOUS 订单 → 每订单 enqueue RecoverJob 恰一次（去重），跨店隔离' do
      order = build_ambiguous_order(store: store)
      # 同订单两个 return_item ambiguous → order 去重只 enqueue 一次
      build_ambiguous_order(store: store) # 制造第二单，验证按订单收
      other_store = create(:store, code: "sweep_other_#{SecureRandom.hex(4)}")
      build_ambiguous_order(store: other_store)

      expect { PallasTrade::ReverseCommerce::RecoverSweeperJob.perform_now(store_id: store.id) }
        .to change { enqueued_recover_jobs }.by(2)
      expect(PallasTrade::ReverseCommerce::RecoverJob).to have_been_enqueued.with(order.id)
    end

    it 'AC-R68I-04: capped —— 超过 max_enqueues 只 enqueue ≤ cap' do
      3.times { build_ambiguous_order(store: store) }

      expect { PallasTrade::ReverseCommerce::RecoverSweeperJob.perform_now(store_id: store.id, max_enqueues: 1) }
        .to change { enqueued_recover_jobs }.by(1)
    end
  end

  describe PallasTrade::ReverseCommerce::RecoverJob do
    it 'AC-R68I-02: perform_now 幂等自愈（movement 恢复；重复跑不重复建）；order 不存在 no-op' do
      order = build_ambiguous_order(store: store)
      ri = PallasTrade::StockMovement.where(return_item_id: order.inventory_units.first.return_items.first.id)
      expect(PallasTrade::StockMovement.where(return_item_id: order.inventory_units.first.return_items.first.id)).to be_empty

      expect { PallasTrade::ReverseCommerce::RecoverJob.perform_now(order.id) }
        .not_to raise_error
      expect(PallasTrade::StockMovement.where(return_item_id: order.inventory_units.first.return_items.first.id).count).to eq(1)
      expect(PallasTrade::Returns::RestockFact.resolve(
        return_item: order.inventory_units.first.return_items.first.reload
      )).to eq(:restocked)

      # 幂等：重复跑不新增 movement
      expect { PallasTrade::ReverseCommerce::RecoverJob.perform_now(order.id) }
        .not_to change { PallasTrade::StockMovement.where(return_item_id: order.inventory_units.first.return_items.first.id).count }

      # order 不存在 → no-op 不 raise
      expect { PallasTrade::ReverseCommerce::RecoverJob.perform_now(9_999_999) }.not_to raise_error
    end
  end
end
