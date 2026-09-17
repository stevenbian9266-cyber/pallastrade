# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-catalog-product-events AC-006（保留策略）+ AC-012（保留期）
RSpec.describe PallasTrade::CatalogEvents::Prune, type: :service do
  let(:store) { @default_store }

  def event(store:, days_ago:, event_id: SecureRandom.uuid)
    PallasTrade::CatalogEvent.create!(
      store: store, event_id: event_id, event_name: 'impression',
      session_hash: 'a' * 32, occurred_at: days_ago.days.ago, created_at: days_ago.days.ago
    )
  end

  it 'deletes rows older than the retention window and keeps recent ones' do
    old = event(store: store, days_ago: PallasTrade::CatalogEvent::RETENTION_DAYS + 10)
    fresh = event(store: store, days_ago: 1)

    expect(described_class.call(store: store)).to eq(1)

    expect(PallasTrade::CatalogEvent.exists?(old.id)).to be(false)
    expect(PallasTrade::CatalogEvent.exists?(fresh.id)).to be(true)
  end

  it 'is idempotent' do
    event(store: store, days_ago: PallasTrade::CatalogEvent::RETENTION_DAYS + 10)

    expect(described_class.call(store: store)).to eq(1)
    expect(described_class.call(store: store)).to eq(0)
  end

  it 'honours an explicit cutoff' do
    event(store: store, days_ago: 10)

    expect(described_class.call(store: store, before: 5.days.ago)).to eq(1)
  end

  it 'keeps rows exactly on the boundary out of scope' do
    # 边界以内（比 before 新）不应被删除
    recent = event(store: store, days_ago: 0)

    described_class.call(store: store)

    expect(PallasTrade::CatalogEvent.exists?(recent.id)).to be(true)
  end

  it 'scopes to one store when given' do
    other = create(:store, code: 'catalog_events_prune_other_store')
    mine = event(store: store, days_ago: PallasTrade::CatalogEvent::RETENTION_DAYS + 10)
    theirs = event(store: other, days_ago: PallasTrade::CatalogEvent::RETENTION_DAYS + 10)

    described_class.call(store: store)

    expect(PallasTrade::CatalogEvent.exists?(mine.id)).to be(false)
    expect(PallasTrade::CatalogEvent.exists?(theirs.id)).to be(true)
  end

  it 'prunes every store when no store is given' do
    other = create(:store, code: 'catalog_events_prune_all_store')
    mine = event(store: store, days_ago: PallasTrade::CatalogEvent::RETENTION_DAYS + 10)
    theirs = event(store: other, days_ago: PallasTrade::CatalogEvent::RETENTION_DAYS + 10)

    described_class.call

    expect(PallasTrade::CatalogEvent.exists?(mine.id)).to be(false)
    expect(PallasTrade::CatalogEvent.exists?(theirs.id)).to be(false)
  end
end
