# frozen_string_literal: true

require 'rails_helper'

# INV-P3-1 (PRD-20260905-shipping-库存事务集成与预留生命周期-p3-...)
# StockReservation 生命周期：RESERVED/COMMITTED/RELEASED/EXPIRED；终态不可逆；
# active = RESERVED 且未过期；仅 RESERVED 占用 available-to-sell（AC-3012/3018/3019）。
RSpec.describe PallasTrade::StockReservation, type: :model do
  let!(:store) { create(:store, code: 'res_lifecycle_store') }
  let!(:stock_location) { create(:stock_location, name: 'WH-R', active: true) }
  let(:product) { create(:product, store: store) }
  let(:variant) { product.master }
  let(:stock_item) do
    variant.stock_items.where(stock_location: stock_location).first || create(:stock_item, variant: variant, stock_location: stock_location)
  end
  let!(:order) do
    create(:order_with_line_items, store: store, line_items_count: 1, line_items_price: 10,
                                   variants: [variant])
  end
  let(:line_item) { order.line_items.first }
  let!(:reservation) do
    create(:stock_reservation, order: order, line_item: line_item,
                               stock_item: stock_item, quantity: 1)
  end

  before do
    variant.update_column(:track_inventory, true)
    stock_item.update_columns(count_on_hand: 5, backorderable: false)
  end

  describe 'state machine lifecycle' do
    it 'starts as reserved with reserved_at set' do
      expect(reservation.state).to eq('reserved')
      expect(reservation.reserved_at).to be_present
      expect(reservation).not_to be_terminal
      expect(reservation.active?).to be true
    end

    it 'commits: RESERVED → COMMITTED and records committed_at' do
      reservation.commit!
      expect(reservation.state).to eq('committed')
      expect(reservation.committed_at).to be_present
      expect(reservation).to be_terminal
      expect(reservation.active?).to be false
    end

    it 'release: RESERVED → RELEASED records released_at and reason' do
      reservation.update!(release_reason: 'customer_canceled')
      reservation.release!
      expect(reservation.state).to eq('released')
      expect(reservation.release_reason).to eq('customer_canceled')
      expect(reservation.released_at).to be_present
    end

    it 'expire: RESERVED → EXPIRED records expired_at' do
      reservation.expire!
      expect(reservation.state).to eq('expired')
      expect(reservation.expired_at).to be_present
    end

    it 'terminal states cannot transition back to reserved' do
      reservation.commit!
      expect { reservation.release! }.to raise_error(StateMachines::InvalidTransition)
      expect { reservation.expire! }.to raise_error(StateMachines::InvalidTransition)
    end

    it 'idempotent re-commit from terminal state is rejected without state change' do
      reservation.commit!
      expect { reservation.commit! }.to raise_error(StateMachines::InvalidTransition)
      expect(PallasTrade::StockReservation.committed.count).to eq(1)
    end
  end

  describe 'scopes' do
    it 'active includes reserved not-expired rows only' do
      expect(described_class.active).to include(reservation)
      reservation.update_column(:expires_at, 1.minute.ago)
      expect(described_class.active).not_to include(reservation)
      expect(described_class.expired).to include(reservation)
    end

    it 'terminal rows are excluded from active' do
      reservation.commit!
      expect(described_class.active).not_to include(reservation)
      expect(described_class.committed).to include(reservation)
    end
  end

  describe 'Quantifier interplay (AC-3012/3019)' do
    it 'only RESERVED rows reduce available-to-sell; COMMITTED frees ATS' do
      quantifier = PallasTrade::Stock::Quantifier.new(variant)
      expect(quantifier.total_on_hand).to eq(4) # 5 on-hand − 1 active reservation

      reservation.commit!
      expect(PallasTrade::Stock::Quantifier.new(variant).total_on_hand).to eq(5)
    end

    it 'expired RESERVED rows no longer reduce available-to-sell' do
      reservation.update_column(:expires_at, 1.minute.ago)
      expect(PallasTrade::Stock::Quantifier.new(variant).total_on_hand).to eq(5)
    end
  end
end
