# frozen_string_literal: true

require 'rails_helper'

# PRD-20260910-promotions-promo-batch4a-orderpromotion-snapshot AC-001 AC-002
# 模型层：快照列的「三态 frozen?」判定 + 快照优先读方法 + 只读载荷。
RSpec.describe PallasTrade::OrderPromotion, 'snapshot columns' do
  let!(:store) { create(:store, code: 'order_promo_snapshot_model_store') }
  let(:promotion) do
    create(:promotion_with_order_adjustment, store: store, code: 'SNAPMODEL', name: 'Snapshot Model Promo',
                                             weighted_order_adjustment_amount: 10)
  end
  let(:order) { create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: 100) }
  let(:row) { PallasTrade::OrderPromotion.create!(order: order, promotion: promotion) }

  describe 'frozen? 三态（AC-001）' do
    it 'is not frozen for a brand new row' do
      expect(row).not_to be_frozen
    end

    it 'is not frozen when only part of the snapshot is present' do
      row.update_columns(name: 'Partial')

      expect(row.reload).not_to be_frozen
    end

    it 'is frozen once name and frozen_at are present' do
      row.update_columns(name: 'Frozen', total_amount: -10, frozen_at: Time.current)

      expect(row.reload).to be_frozen
    end
  end

  describe '快照优先读方法（AC-001）' do
    it 'falls back to the live promotion before freezing' do
      expect(row.name).to eq(promotion.name)
      expect(row.code).to eq(promotion.code)
      expect(row.kind).to eq('coupon_code')
      expect(row.description).to eq(promotion.description)
      expect(row).to be_coupon_code
    end

    it 'prefers the frozen values and ignores later promotion edits' do
      row.update_columns(
        name: 'Frozen Name', kind: 'automatic', code: 'FROZEN20', description: 'Frozen description',
        total_amount: -20, frozen_at: Time.current
      )
      promotion.update!(name: 'Renamed Live')

      reloaded = row.reload
      expect(reloaded.name).to eq('Frozen Name')
      expect(reloaded.code).to eq('FROZEN20')
      expect(reloaded.kind).to eq('automatic')
      expect(reloaded.description).to eq('Frozen description')
      expect(reloaded).not_to be_coupon_code
    end
  end

  describe 'snapshot_payload（AC-002）' do
    it 'exposes a stable key set' do
      expect(row.snapshot_payload.keys).to eq(
        %i[name kind code description definition_digest item_amount order_amount shipping_amount
           total_amount currency frozen_at]
      )
    end

    it 'falls back to the order currency while unfrozen' do
      expect(row.snapshot_payload[:currency]).to eq(order.currency)
    end
  end
end
