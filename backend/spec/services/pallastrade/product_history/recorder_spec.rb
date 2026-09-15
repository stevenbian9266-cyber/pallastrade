# frozen_string_literal: true

require 'rails_helper'

# PRD-20260915-catalog-batch-d1-product-history —— 时间线写入
RSpec.describe PallasTrade::ProductHistory::Recorder do
  let(:store) { create(:store, code: 'product_history_recorder') }
  let(:product) { create(:product, store: store, name: 'History Blender') }
  let(:actor) do
    create(:admin_user, email: 'ops@example.com', password: 'secret',
                        password_confirmation: 'secret', without_admin_role: true)
  end

  describe '.snapshot' do
    it 'captures every tracked attribute' do
      expect(described_class.snapshot(product).keys)
        .to match_array(PallasTrade::ProductHistory::Recorder::TRACKED_ATTRIBUTES)
    end
  end

  describe '.record_product' do
    it 'stores only the attributes that changed, with the actor label' do
      before = described_class.snapshot(product)
      product.update!(name: 'History Blender 2', slug: 'history-blender-2')

      log = described_class.record_product(
        product: product, action: 'product.updated', actor: actor, before: before
      )

      expect(log).to be_present
      expect(log.action).to eq('product.updated')
      expect(log.actor_label).to eq('ops@example.com')
      expect(log.before.keys).to match_array(%w[name slug])
      expect(log.after['name']).to eq('History Blender 2')
      expect(log.metadata['changed']).to match_array(%w[name slug])
    end

    it 'skips an update that changed nothing and carries no context' do
      before = described_class.snapshot(product)

      expect(
        described_class.record_product(
          product: product, action: 'product.updated', actor: actor, before: before
        )
      ).to be_nil
      expect(PallasTrade::AuditLog.where(action: 'product.updated')).not_to exist
    end

    it 'keeps an update that only touched nested form sections' do
      before = described_class.snapshot(product)

      log = described_class.record_product(
        product: product, action: 'product.updated', actor: actor, before: before,
        metadata: { 'sections' => ['media'] }
      )

      expect(log).to be_present
      expect(log.metadata['sections']).to eq(['media'])
    end

    it 'records a create with every tracked attribute and a string actor' do
      log = described_class.record_product(product: product, action: 'product.created', actor: 'system')

      expect(log).to be_present
      expect(log.after.keys).to match_array(PallasTrade::ProductHistory::Recorder::TRACKED_ATTRIBUTES)
      expect(log.actor_label).to eq('system')
    end
  end

  describe '.record_bulk' do
    it 'records one entry per affected product with the batch counts' do
      other = create(:product, store: store, name: 'Other Blender')

      described_class.record_bulk(
        products: [product, other],
        action: 'product.bulk_price_updated',
        actor: actor,
        metadata: { 'updated_count' => 2, 'skipped_count' => 1 }
      )

      logs = PallasTrade::AuditLog.where(action: 'product.bulk_price_updated')
      expect(logs.count).to eq(2)
      expect(logs.map(&:resource_id)).to match_array([product.id, other.id])
      expect(logs.first.metadata['source']).to eq('bulk')
      expect(logs.first.metadata['updated_count']).to eq(2)
      expect(logs.first.actor_label).to eq('ops@example.com')
    end
  end
end
