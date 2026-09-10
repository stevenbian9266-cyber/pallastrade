# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# 任务类定义在 gem 的 rake 文件里（与 batch1 的 PromoDuplicateCodeChecker 一致），
# 测试前显式加载，避免 PallasTrade::Tasks 常量在 describe 时未定义。
load Rails.root.join('pallastrade_gems/pallastrade_core/lib/tasks/promotions.rake')

# PRD-20260910-promotions-promo-batch3a-redemption-ledger AC-008
# 历史数据回填：dry-run 不写库、实跑幂等、回填后 usage_limit 口径与历史事实一致。
RSpec.describe PallasTrade::Tasks::PromoRedemptionBackfill do
  let!(:store) { create(:store, code: 'promo_backfill_store') }

  def prepare_history
    promotion = create(:promotion_with_order_adjustment, store: store, code: 'BACKFILL5',
                                                         weighted_order_adjustment_amount: 5)
    order = create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: 100)
    order.coupon_code = promotion.code
    PallasTrade::PromotionHandler::Coupon.new(order).apply
    order.update_with_updater!
    [order.reload, promotion]
  end

  it 'does not write anything on a dry run（AC-008）' do
    prepare_history

    expect { described_class.new(dry_run: true).call }.to output(/dry_run=true/).to_stdout
    expect(PallasTrade::PromotionRedemption.count).to eq(0)
  end

  it 'backfills committed redemptions idempotently（AC-008）' do
    order, promotion = prepare_history

    described_class.new(dry_run: false).call
    expect(PallasTrade::PromotionRedemption.committed.count).to eq(1)
    expect(promotion.reload.credits_count).to eq(1)
    expect(promotion.usage_limit_exceeded?(order)).to be false

    expect { described_class.new(dry_run: false).call }.to output(/created=0/).to_stdout
    expect(PallasTrade::PromotionRedemption.count).to eq(1)
  end

  it 'never overwrites an existing ledger row（AC-008）' do
    order, promotion = prepare_history
    existing = PallasTrade::Promotions::Redemption::Reserve.call(order: order, promotion: promotion)

    described_class.new(dry_run: false).call

    expect(PallasTrade::PromotionRedemption.count).to eq(1)
    expect(existing.reload.state).to eq('reserved')
  end
end
