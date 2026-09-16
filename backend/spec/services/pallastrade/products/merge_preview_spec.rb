# frozen_string_literal: true

require 'spec_helper'

# PRD-20260916-catalog-d3-product-merge AC-001 AC-002
#
#   AC-001 ← FR-001：预检回答影响面，且**零写入**
#   AC-002 ← FR-001：跳过项被显式标记（不静默合并）
RSpec.describe PallasTrade::Products::MergePreview do
  let(:store) { PallasTrade::Store.default }
  let!(:survivor) { create(:product, store: store, name: 'Survivor', slug: 'merge-survivor') }
  let!(:absorbed) { create(:product, store: store, name: 'Duplicate', slug: 'merge-absorbed') }

  def snapshot
    {
      products: PallasTrade::Product.with_deleted.count,
      variants: PallasTrade::Variant.count,
      reviews: PallasTrade::Review.count,
      classifications: PallasTrade::Classification.count,
      redirects: PallasTrade::Redirect.count,
      merges: PallasTrade::ProductMerge.count
    }
  end

  # 正常情况下同店 SKU 唯一（校验保证），重复 SKU 只能来自历史数据或
  # `disable_sku_validation` 配置 —— 而这正是「重复商品」的成因之一。
  def variant_with_shared_sku(product, sku)
    variant = build(:variant, product: product, sku: sku)
    variant.save(validate: false)
    variant
  end

  it 'reports what would move and writes nothing (AC-001)' do
    create(:variant, product: absorbed, sku: 'MERGE-DUP-1')
    before = snapshot

    preview = described_class.call(store: store, survivor: survivor, absorbed: absorbed)

    expect(preview.counts['variants']['move']).to eq(1)
    expect(preview.total_moved).to be >= 1
    expect(snapshot).to eq(before)
  end

  it 'flags a SKU that already exists on the survivor (AC-002)' do
    create(:variant, product: survivor, sku: 'SHARED-SKU')
    conflicting = variant_with_shared_sku(absorbed, 'shared-sku')

    preview = described_class.call(store: store, survivor: survivor, absorbed: absorbed)

    expect(preview.counts['variants']['skip']).to eq(1)
    expect(preview.skipped_by_reason).to include('sku_conflict')
    expect(preview.skipped.first[:section]).to eq('variants')
    # 预检绝不改动数据
    expect(conflicting.reload.product_id).to eq(absorbed.id)
  end

  it 'flags a customer who already reviewed the survivor (AC-002)' do
    reviewer = create(:user)
    create(:review, store: store, product: survivor, user: reviewer, status: 'approved')
    duplicate = create(:review, store: store, product: absorbed, user: reviewer, status: 'approved')

    preview = described_class.call(store: store, survivor: survivor, absorbed: absorbed)

    expect(preview.counts['reviews']['skip']).to eq(1)
    expect(preview.skipped.map { |item| item[:reason] }).to include('review_conflict')
    expect(duplicate.reload.product_id).to eq(absorbed.id)
  end

  it 'plans a redirect per supported locale and counts history read-only (AC-001)' do
    locale = store.supported_locales_list.first || 'en'
    country = store.default_country&.iso&.downcase

    preview = described_class.call(store: store, survivor: survivor, absorbed: absorbed)

    expect(preview.redirects).not_to be_empty
    expect(preview.redirects.first[:from_path]).to include(absorbed.slug)
    expect(preview.redirects.first[:to_path]).to include(survivor.slug)
    expect(preview.redirects.first[:from_path]).to include(locale) if locale.present?
    expect(preview.redirects.first[:from_path]).to include("/#{country}/") if country.present?
    expect(preview.historical).to include(:line_items, :orders)
    expect(preview.warnings).to be_an(Array)
  end
end
