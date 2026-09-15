# frozen_string_literal: true

require 'rails_helper'

# PRD-20260915-catalog-batch-d1-product-history —— 时间线读取（审计 + 改价合并）
RSpec.describe PallasTrade::ProductHistory::Timeline do
  let(:store) { create(:store, code: 'product_history_timeline') }
  let(:product) { create(:product, store: store, name: 'Timeline Blender') }
  let(:variant) { product.default_variant }
  let(:price) { variant.prices.base_prices.first }

  def audit(action, resource: product, before: nil, after: nil, occurred_at: Time.current, actor: 'ops')
    PallasTrade::Audit.record(
      action: action, actor: actor, resource: resource,
      before: before, after: after
    ).tap { |log| log.update!(occurred_at: occurred_at) }
  end

  it 'merges audit entries with price history, newest first' do
    audit('product.updated', before: { 'name' => 'Old' }, after: { 'name' => 'New' }, occurred_at: 2.hours.ago)
    create(:price_history, variant: variant, price: price, amount: 25, currency: 'USD', recorded_at: 1.hour.ago)

    entries = described_class.call(product: product)

    expect(entries.map(&:kind)).to include('updated', 'price')
    expect(entries.first.kind).to eq('price')
  end

  it 'derives the previous amount from the earlier row of the same price record' do
    create(:price_history, variant: variant, price: price, amount: 10, currency: 'USD', recorded_at: 3.hours.ago)
    create(:price_history, variant: variant, price: price, amount: 15, currency: 'USD', recorded_at: 1.hour.ago)

    # 工厂建商品时也会给 master 写一条 price_history（价格回调），所以按金额定位目标行。
    entry = described_class.call(product: product).find do |candidate|
      candidate.kind == 'price' && candidate.changes.any? { |change| change[:field] == 'price' && change[:after] == 15 }
    end
    amounts = entry.changes.index_by { |change| change[:field] }

    expect(amounts['price'][:before]).to eq(10)
    expect(amounts['price'][:after]).to eq(15)
    expect(amounts['currency'][:after]).to eq('USD')
    expect(entry.metadata['variant_sku']).to eq(variant.sku)
  end

  it 'shapes audit changes into field rows and keeps the actor label' do
    audit('product.updated', before: { 'status' => 'draft' }, after: { 'status' => 'active' })

    entry = described_class.call(product: product).find { |candidate| candidate.kind == 'updated' }

    expect(entry.actor_label).to eq('ops')
    expect(entry.changes).to eq([{ field: 'status', before: 'draft', after: 'active' }])
  end

  it 'caps the timeline at the limit and never leaks another product' do
    other = create(:product, store: store, name: 'Other Blender')
    audit('product.updated', resource: other, after: { 'name' => 'X' })
    3.times { audit('product.updated', before: { 'name' => 'a' }, after: { 'name' => 'b' }) }

    entries = described_class.call(product: product, limit: 2)

    expect(entries.length).to eq(2)
    expect(PallasTrade::AuditLog.for_resource('PallasTrade::Product', other.id)).to exist
    expect(entries).to all(have_attributes(kind: 'updated'))
  end

  it 'returns an empty timeline for a product without history' do
    # 商品工厂建价时会写一条 price_history，先清掉以便只验证“无审计 = 无条目”。
    PallasTrade::PriceHistory.where(variant_id: product.variants_including_master.select(:id)).delete_all

    expect(described_class.call(product: product)).to eq([])
  end
end
