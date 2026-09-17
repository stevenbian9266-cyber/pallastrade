# frozen_string_literal: true

require 'rails_helper'

# PRD-20260917-catalog-product-events
# AC-004（零 PII 摘要口径）、AC-008（聚合与 CTR nil）、AC-009（旁路语义）、AC-012（保留期常量）
RSpec.describe PallasTrade::CatalogEvent, type: :model do
  let(:store) { @default_store }
  let(:product) { create(:product, store: store) }

  def event(attrs = {})
    described_class.create!(
      { store: store, event_id: SecureRandom.uuid, event_name: 'impression',
        session_hash: 'a' * 32, occurred_at: Time.current }.merge(attrs)
    )
  end

  describe 'validations' do
    it 'accepts every whitelisted event name' do
      described_class::EVENT_NAMES.each do |name|
        expect(event(event_name: name)).to be_persisted
      end
    end

    it 'rejects an unknown event name' do
      record = described_class.new(
        store: store, event_id: 'x', event_name: 'totally_made_up',
        session_hash: 'a' * 32, occurred_at: Time.current
      )

      expect(record).not_to be_valid
      expect(record.errors[:event_name]).to be_present
    end

    it 'requires event_id, session_hash and occurred_at' do
      record = described_class.new(store: store, event_name: 'impression')

      expect(record).not_to be_valid
      expect(record.errors[:event_id]).to be_present
      expect(record.errors[:session_hash]).to be_present
      expect(record.errors[:occurred_at]).to be_present
    end
  end

  describe 'idempotency key' do
    it 'enforces (store_id, event_id) uniqueness at the database level' do
      event(event_id: 'dup-id')

      expect { event(event_id: 'dup-id') }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows the same event_id in a different store' do
      other = create(:store, code: 'catalog_events_model_other_store')
      event(event_id: 'shared')
      described_class.create!(
        store: other, event_id: 'shared', event_name: 'impression',
        session_hash: 'b' * 32, occurred_at: Time.current
      )

      expect(described_class.for_store(other).count).to eq(1)
    end
  end

  # AC-004 零 PII
  describe '.digest_visitor' do
    it 'is stable for the same visitor' do
      expect(described_class.digest_visitor('visitor-a', store))
        .to eq(described_class.digest_visitor('visitor-a', store))
    end

    it 'never contains the raw value and is 32 hex chars' do
      digest = described_class.digest_visitor('visitor-a', store)

      expect(digest).not_to include('visitor-a')
      expect(digest.length).to eq(32)
      expect(digest).to match(/\A[0-9a-f]{32}\z/)
    end

    it 'differs across visitors' do
      expect(described_class.digest_visitor('visitor-a', store))
        .not_to eq(described_class.digest_visitor('visitor-b', store))
    end

    it 'is store-scoped, so the same visitor is not correlatable across stores' do
      other = create(:store, code: 'catalog_events_digest_store')

      expect(described_class.digest_visitor('visitor-a', other))
        .not_to eq(described_class.digest_visitor('visitor-a', store))
    end

    it 'returns nil for a blank visitor' do
      expect(described_class.digest_visitor(nil, store)).to be_nil
      expect(described_class.digest_visitor('   ', store)).to be_nil
    end
  end

  # AC-008 聚合与 CTR
  describe '.list_metrics' do
    it 'reports impressions, clicks and CTR per list' do
      2.times { event(event_name: 'impression', list_id: 'related') }
      event(event_name: 'click', list_id: 'related')

      metrics = described_class.list_metrics(store).index_by { |row| row[:list_id] }

      expect(metrics['related'][:impressions]).to eq(2)
      expect(metrics['related'][:clicks]).to eq(1)
      expect(metrics['related'][:ctr]).to eq(0.5)
    end

    it 'returns a nil CTR when the denominator is zero (never fabricates a ratio)' do
      event(event_name: 'click', list_id: 'orphan')

      metrics = described_class.list_metrics(store).index_by { |row| row[:list_id] }

      expect(metrics['orphan'][:impressions]).to eq(0)
      expect(metrics['orphan'][:ctr]).to be_nil
    end

    it 'ignores non-CTR events' do
      event(event_name: 'product_added', list_id: 'related')

      expect(described_class.list_metrics(store)).to be_empty
    end

    it 'excludes events outside the window' do
      event(event_name: 'impression', list_id: 'related', occurred_at: 30.days.ago)

      expect(described_class.list_metrics(store, from: 7.days.ago)).to be_empty
    end

    it 'can narrow to a single list' do
      event(event_name: 'impression', list_id: 'related')
      event(event_name: 'impression', list_id: 'bestsellers')

      metrics = described_class.list_metrics(store, list_id: 'related')

      expect(metrics.map { |row| row[:list_id] }).to eq(['related'])
    end

    it 'is scoped to the store' do
      other = create(:store, code: 'catalog_events_metrics_store')
      described_class.create!(
        store: other, event_id: 'other-1', event_name: 'impression', list_id: 'related',
        session_hash: 'c' * 32, occurred_at: Time.current
      )

      expect(described_class.list_metrics(store)).to be_empty
      expect(described_class.list_metrics(other).length).to eq(1)
    end
  end

  describe '.product_metrics' do
    it 'aggregates impressions and add-to-cart per product' do
      event(event_name: 'impression', product_id: product.id)
      event(event_name: 'product_added', product_id: product.id)

      metrics = described_class.product_metrics(store)

      expect(metrics[product.id][:impressions]).to eq(1)
      expect(metrics[product.id][:product_added]).to eq(1)
    end

    it 'skips rows without a product' do
      event(event_name: 'product_searched')

      expect(described_class.product_metrics(store)).to be_empty
    end
  end

  # AC-009 旁路语义
  describe 'side-channel semantics' do
    it 'writing events changes no business data' do
      product

      expect do
        event(event_name: 'impression', product_id: product.id)
        event(event_name: 'product_added', product_id: product.id)
      end.not_to change { [PallasTrade::Product.count, PallasTrade::Order.count] }
    end

    it 'can be truncated without touching business rows' do
      order = create(:order, store: store)
      event(product_id: product.id)

      described_class.for_store(store).delete_all

      expect(PallasTrade::Product.exists?(product.id)).to be(true)
      expect(PallasTrade::Order.exists?(order.id)).to be(true)
    end
  end

  # AC-012 保留期与批量常量
  it 'bounds retention and batch size' do
    expect(described_class::RETENTION_DAYS).to be > 0
    expect(described_class::MAX_BATCH_SIZE).to eq(100)
  end
end
