# frozen_string_literal: true

require 'spec_helper'

# PRD-20260916-catalog-d3-product-merge AC-003 AC-004 AC-005 AC-006 AC-007 AC-008 AC-009 AC-013 AC-014
#
#   AC-003 ← FR-002：迁移守恒（迁移数 + 跳过数 = 原数），引用落到 survivor
#   AC-004 ← FR-002：旧 slug 建 301（active），重复合并不产生第二条
#   AC-005 ← FR-002：被合并商品 archived + 软删 + merged_into 标记
#   AC-006 ← FR-003：**历史交易零改写**（行项目/订单/支付快照不变）
#   AC-007/008 ← FR-002：SKU / 评论冲突跳过并报告
#   AC-009 ← FR-004/FR-005：跨店/自身 → 拒绝；重复执行 → 幂等
#   AC-013/014 ← FR-002/FR-009：审计 + 台账
RSpec.describe PallasTrade::Products::Merge do
  let(:store) { PallasTrade::Store.default }
  let!(:survivor) { create(:product, store: store, name: 'Survivor', slug: 'd3-survivor') }
  let!(:absorbed) { create(:product, store: store, name: 'Duplicate', slug: 'd3-absorbed') }
  let(:actor) { create(:admin_user) }

  # 历史交易快照：合并**必须**让这些数字与内容逐字节不变。
  def trading_snapshot
    {
      line_items: PallasTrade::LineItem.order(:id).pluck(:id, :variant_id, :quantity, :price).hash,
      orders: PallasTrade::Order.order(:id).pluck(:id, :state, :total, :updated_at).hash,
      payments: PallasTrade::Payment.order(:id).pluck(:id, :amount, :state).hash
    }
  end

  def existing_order_line
    variant = create(:variant, product: absorbed, sku: 'D3-TXN-1')
    order = create(:order, store: store)
    create(:line_item, order: order, variant: variant, quantity: 1, price: variant.price)
    variant
  end

  # 同店 SKU 唯一由校验保证；重复 SKU 来自历史数据或关闭校验的导入，
  # 因此只能绕过校验来装配这个场景。
  def variant_with_shared_sku(product, sku)
    variant = build(:variant, product: product, sku: sku)
    variant.save(validate: false)
    variant
  end

  it 'moves what it can and keeps the accounting closed (AC-003)' do
    variant = create(:variant, product: absorbed, sku: 'D3-MOVE-1')
    reviewer = create(:user)
    review = create(:review, store: store, product: absorbed, user: reviewer, status: 'approved')

    result = described_class.call(store: store, survivor: survivor, absorbed: absorbed, actor: actor)

    expect(result.ledger.counts['variants']).to eq('move' => 1, 'skip' => 0)
    expect(variant.reload.product_id).to eq(survivor.id)
    expect(review.reload.product_id).to eq(survivor.id)
    # 守恒：搬迁数 + 跳过数 == 预检看到的总数
    expect(result.preview.total_moved + result.preview.total_skipped)
      .to eq(result.preview.sections.values.sum(&:total))
  end

  it 'keeps SKU and review conflicts where they were (AC-007 / AC-008)' do
    create(:variant, product: survivor, sku: 'D3-SHARED')
    conflicting_variant = variant_with_shared_sku(absorbed, 'd3-shared')
    reviewer = create(:user)
    create(:review, store: store, product: survivor, user: reviewer, status: 'approved')
    conflicting_review = create(:review, store: store, product: absorbed, user: reviewer, status: 'approved')

    result = described_class.call(store: store, survivor: survivor, absorbed: absorbed, actor: actor)

    expect(result.skipped.map { |item| item[:reason] })
      .to include('sku_conflict', 'review_conflict')
    expect(conflicting_variant.reload.product_id).to eq(absorbed.id)
    expect(conflicting_review.reload.product_id).to eq(absorbed.id)
  end

  it 'archives and soft-deletes the absorbed product with a trace (AC-005)' do
    described_class.call(store: store, survivor: survivor, absorbed: absorbed, actor: actor)

    reloaded = PallasTrade::Product.with_deleted.find(absorbed.id)
    expect(reloaded.deleted?).to be(true)
    expect(reloaded.status).to eq('archived')
    expect(reloaded.private_metadata['merged_into']).to eq(survivor.prefixed_id)
  end

  it 'never rewrites historical transactions (AC-006)' do
    existing_order_line
    before = trading_snapshot

    described_class.call(store: store, survivor: survivor, absorbed: absorbed, actor: actor)

    expect(trading_snapshot).to eq(before)
  end

  it 'points the old URLs at the survivor and stays idempotent (AC-004 / AC-009)' do
    result = described_class.call(store: store, survivor: survivor, absorbed: absorbed, actor: actor)

    redirect = PallasTrade::Redirect.find_by(from_path: result.preview.redirects.first[:from_path])
    expect(redirect).to be_present
    expect(redirect.to_path).to include(survivor.slug)
    expect(redirect.active).to be(true)

    again = described_class.call(store: store, survivor: survivor, absorbed: absorbed, actor: actor)

    expect(again.already_merged?).to be(true)
    expect(PallasTrade::ProductMerge.count).to eq(1)
    expect(PallasTrade::Redirect.where(from_path: result.preview.redirects.first[:from_path]).count).to eq(1)
  end

  it 'refuses to merge a product with itself or across stores (AC-009)' do
    expect { described_class.call(store: store, survivor: survivor, absorbed: survivor, actor: actor) }
      .to raise_error(described_class::InvalidMerge, /same_product/)

    other_store = create(:store, code: "d3_other_#{SecureRandom.hex(3)}")
    foreign = create(:product, store: other_store, slug: 'd3-foreign')

    expect { described_class.call(store: store, survivor: survivor, absorbed: foreign, actor: actor) }
      .to raise_error(described_class::InvalidMerge, /not_same_store/)

    expect(PallasTrade::ProductMerge.count).to eq(0)
  end

  it 'writes one ledger row and one audit entry (AC-013 / AC-014)' do
    expected_audits = PallasTrade::AuditLog.where(action: 'product_merged').count

    result = described_class.call(store: store, survivor: survivor, absorbed: absorbed, actor: actor)

    ledger = result.ledger
    expect(ledger).to be_persisted
    expect(ledger.survivor_id).to eq(survivor.id)
    expect(ledger.absorbed_id).to eq(absorbed.id)
    expect(ledger.moved).to include('variants')
    expect(ledger.counts).to eq(result.preview.counts)
    expect(ledger.actor_label).to include(actor.email)
    expect(PallasTrade::AuditLog.where(action: 'product_merged').count).to eq(expected_audits + 1)
  end
end
