# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# 任务类定义在 gem 的 rake 文件里（与 batch1/batch3a 一致），测试前显式加载。
load Rails.root.join('pallastrade_gems/pallastrade_core/lib/tasks/promotions.rake')

# PRD-20260910-promotions-promo-batch4a-orderpromotion-snapshot AC-008
# 存量回填：dry-run 不写库、APPLY 冻结存量、二次运行跳过、单条失败被隔离。
RSpec.describe PallasTrade::Tasks::PromoOrderPromotionSnapshotBackfill do
  let!(:store) { create(:store, code: 'promo_snapshot_backfill_store') }

  def completed_order_with_promotion(code:, name:)
    promotion = create(:promotion_with_order_adjustment, store: store, code: code, name: name,
                                                         weighted_order_adjustment_amount: 10)
    order = create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: 100)
    order.coupon_code = promotion.code
    PallasTrade::PromotionHandler::Coupon.new(order).apply
    order.update_with_updater!
    order.update_columns(completed_at: Time.current, state: 'complete')
    [order.reload, promotion]
  end

  it 'does not write anything on a dry run（AC-008）' do
    order, promotion = completed_order_with_promotion(code: 'SNAPB1', name: 'Backfill One')

    expect { described_class.new(dry_run: true).call }.to output(/dry_run=true/).to_stdout

    row = order.order_promotions.reload.find_by(promotion_id: promotion.id)
    expect(row&.frozen_at).to be_nil
  end

  it 'freezes historical orders on APPLY and is idempotent（AC-008）' do
    order, promotion = completed_order_with_promotion(code: 'SNAPB2', name: 'Backfill Two')

    described_class.new(dry_run: false).call
    row = order.order_promotions.reload.find_by(promotion_id: promotion.id)
    expect(row).to be_frozen
    expect(row.name).to eq('Backfill Two')

    expect { described_class.new(dry_run: false).call }.to output(/skipped_orders=1/).to_stdout
    expect(row.reload.frozen_at).to be_present
  end

  it 'skips orders that never had a promotion adjustment（AC-008）' do
    order = create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: 100)
    order.update_columns(completed_at: Time.current, state: 'complete')

    expect { described_class.new(dry_run: false).call }.to output(/candidates=0|frozen=0/).to_stdout
    expect(order.order_promotions.reload).to be_empty
  end

  it 'isolates a failing order and keeps processing the rest（AC-008）' do
    failing_order, failing_promotion = completed_order_with_promotion(code: 'SNAPB4', name: 'Backfill Four')
    good_order, good_promotion = completed_order_with_promotion(code: 'SNAPB5', name: 'Backfill Five')

    original = PallasTrade::Promotions::Snapshot::Freeze.method(:call)
    allow(PallasTrade::Promotions::Snapshot::Freeze).to receive(:call) do |record|
      raise StandardError, 'boom' if record.id == failing_order.id

      original.call(record)
    end

    described_class.new(dry_run: false).call

    expect(good_order.order_promotions.reload.find_by(promotion_id: good_promotion.id)).to be_frozen
    expect(failing_order.order_promotions.reload.find_by(promotion_id: failing_promotion.id)&.frozen_at).to be_nil
  end
end
