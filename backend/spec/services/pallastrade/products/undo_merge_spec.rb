# frozen_string_literal: true

require 'spec_helper'

# PRD-20260916-catalog-d3-product-merge AC-015 AC-016 AC-017 AC-018
#
#   AC-015 ← FR-010：撤销把引用**逐项**还原到合并前，absorbed 恢复可见
#   AC-016 ← FR-010：撤销后 redirect 停用；再次撤销 → 幂等
#   AC-017 ← FR-011：清单项缺失/易主 → 拒绝且零写入（不做部分撤销）
#   AC-018 ← FR-003：撤销同样不改写历史交易
RSpec.describe PallasTrade::Products::UndoMerge do
  let(:store) { PallasTrade::Store.default }
  let!(:survivor) { create(:product, store: store, name: 'Survivor', slug: 'd3u-survivor') }
  let!(:absorbed) { create(:product, store: store, name: 'Duplicate', slug: 'd3u-absorbed') }
  let(:actor) { create(:admin_user) }

  def trading_snapshot
    {
      line_items: PallasTrade::LineItem.order(:id).pluck(:id, :variant_id, :quantity, :price).hash,
      orders: PallasTrade::Order.order(:id).pluck(:id, :state, :total, :updated_at).hash
    }
  end

  # 一个已经合并过的世界
  def merged!
    @status_before = absorbed.status
    @variant = create(:variant, product: absorbed, sku: 'D3U-MOVE-1')
    @reviewer = create(:user)
    @review = create(:review, store: store, product: absorbed, user: @reviewer, status: 'approved')
    @result = PallasTrade::Products::Merge.call(store: store, survivor: survivor, absorbed: absorbed, actor: actor)
    @result.ledger
  end

  it 'moves every recorded item back and makes the product visible again (AC-015)' do
    ledger = merged!
    expect(@variant.reload.product_id).to eq(survivor.id)

    result = described_class.call(store: store, merge: ledger, actor: actor)

    expect(result.already_undone?).to be(false)
    expect(@variant.reload.product_id).to eq(absorbed.id)
    expect(@review.reload.product_id).to eq(absorbed.id)

    restored = PallasTrade::Product.with_deleted.find(absorbed.id)
    expect(restored.deleted?).to be(false)
    expect(restored.private_metadata['merged_into']).to be_nil
    # 回到**合并前**的状态，而不是一律 activate
    expect(restored.status).to eq(@status_before)
    expect(ledger.absorbed_status_before).to eq(@status_before)
  end

  it 'deactivates the redirect it created and is idempotent (AC-016)' do
    ledger = merged!
    from_path = ledger.moved.any? ? @result.preview.redirects.first[:from_path] : nil
    expect(PallasTrade::Redirect.find_by(from_path: from_path).active).to be(true)

    described_class.call(store: store, merge: ledger, actor: actor)

    expect(PallasTrade::Redirect.find_by(from_path: from_path).active).to be(false)

    again = described_class.call(store: store, merge: ledger.reload, actor: actor)
    expect(again.already_undone?).to be(true)
  end

  it 'refuses to undo when a recorded item is gone, writing nothing (AC-017)' do
    ledger = merged!
    variant_id = @variant.id
    @variant.destroy # 模拟合并后变体被删除

    snapshot = {
      variants: PallasTrade::Variant.with_deleted.count,
      reviews: PallasTrade::Review.count,
      redirects_active: PallasTrade::Redirect.where(active: true).count,
      undone: PallasTrade::ProductMerge.where.not(undone_at: nil).count
    }

    expect { described_class.call(store: store, merge: ledger, actor: actor) }
      .to raise_error(described_class::Blocked) { |error|
        expect(error.blockers.map { |b| b[:reason] }).to include('missing')
      }

    expect(PallasTrade::Review.where(id: @review.id).first.product_id).to eq(survivor.id)
    expect(PallasTrade::Variant.with_deleted.where(id: variant_id).count).to eq(1)
    expect(PallasTrade::Redirect.where(active: true).count).to eq(snapshot[:redirects_active])
    expect(ledger.reload.undone_at).to be_nil
  end

  it 'leaves historical transactions untouched (AC-018)' do
    variant = create(:variant, product: absorbed, sku: 'D3U-TXN-1')
    order = create(:order, store: store)
    create(:line_item, order: order, variant: variant, quantity: 1, price: variant.price)

    before = trading_snapshot

    ledger = merged!
    described_class.call(store: store, merge: ledger, actor: actor)

    expect(trading_snapshot).to eq(before)
  end
end
