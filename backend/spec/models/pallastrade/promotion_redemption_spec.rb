# frozen_string_literal: true

require 'rails_helper'

# PRD-20260910-promotions-promo-batch3a-redemption-ledger AC-001 AC-002 AC-003 AC-013
RSpec.describe PallasTrade::PromotionRedemption do
  let!(:store) { create(:store, code: 'promo_redemption_store') }
  let(:order) { create(:order_with_line_items, store: store, line_items_price: 100) }
  let(:promotion) do
    create(:promotion_with_order_adjustment, store: store, code: 'SAVE10', weighted_order_adjustment_amount: 10)
  end
  let(:multi_code_promotion) do
    promo = create(:promotion, store: store, kind: :coupon_code, multi_codes: true, code: nil, number_of_codes: 1)
    create(:promotion_action_create_adjustment, promotion: promo)
    promo.reload
  end

  def build_redemption(promotion:, coupon_code: nil, state: 'reserved', target_order: nil)
    described_class.create!(
      store: store, promotion: promotion, order: target_order || order, state: state,
      currency: (target_order || order).currency, reserved_at: Time.current, coupon_code: coupon_code
    )
  end

  describe 'state machine（AC-003）' do
    it 'defaults to reserved and exposes predicates' do
      redemption = build_redemption(promotion: promotion)

      expect(redemption).to be_redemption_reserved
      expect(redemption).not_to be_redemption_committed
      expect(described_class.active).to include(redemption)
    end

    it 'releases idempotently without overwriting the first release' do
      redemption = build_redemption(promotion: promotion)
      redemption.update!(state: 'committed', committed_at: Time.current)

      redemption.release!(reason: 'order_canceled')
      expect(redemption).to be_redemption_released
      expect(redemption.release_reason).to eq('order_canceled')
      expect(described_class.active).not_to include(redemption)

      released_at = redemption.released_at
      redemption.release!(reason: 'manual')
      expect(redemption.reload.release_reason).to eq('order_canceled')
      expect(redemption.released_at).to eq(released_at)
    end

    it 'rejects unknown states' do
      expect { build_redemption(promotion: promotion, state: 'bogus') }.
        to raise_error(ArgumentError, /not a valid state/)
    end
  end

  describe 'uniqueness（AC-001 / AC-002）' do
    it 'rejects a second active redemption for the same promotion + order' do
      build_redemption(promotion: promotion)

      expect { build_redemption(promotion: promotion) }.
        to raise_error(ActiveRecord::RecordInvalid, /already been taken/)
    end

    it 'enforces the DB unique index even when validations are bypassed' do
      existing = build_redemption(promotion: promotion)

      expect do
        ActiveRecord::Base.transaction(requires_new: true) do
          described_class.connection.execute(<<~SQL.squish)
            INSERT INTO pallastrade_promotion_redemptions
              (store_id, promotion_id, order_id, state, created_at, updated_at)
            VALUES
              (#{store.id}, #{existing.promotion_id}, #{existing.order_id}, 'reserved', NOW(), NOW())
          SQL
        end
      end.to raise_error(ActiveRecord::StatementInvalid)
    end

    it 'allows one active redemption per coupon code and frees it after release' do
      code = multi_code_promotion.coupon_codes.first
      first = build_redemption(promotion: multi_code_promotion, coupon_code: code)
      other_order = create(:order_with_line_items, store: store, line_items_price: 100)

      expect do
        build_redemption(promotion: multi_code_promotion, coupon_code: code, target_order: other_order)
      end.to raise_error(ActiveRecord::RecordInvalid)

      first.release!(reason: 'manual')

      expect do
        build_redemption(promotion: multi_code_promotion, coupon_code: code, target_order: other_order)
      end.not_to raise_error
    end
  end

  describe 'coupon code helpers（AC-013 regression）' do
    it 'defines remove_from_order (batch1 typo regression)' do
      expect(PallasTrade::CouponCode.new).to respond_to(:remove_from_order)
    end

    it 'attaches and detaches without consuming the code' do
      code = multi_code_promotion.coupon_codes.first

      code.attach_to_order!(order)
      expect(code.reload.order_id).to eq(order.id)
      expect(code.state).to eq('unused')

      code.detach_from_order
      expect(code.reload.order_id).to be_nil
      expect(code.state).to eq('unused')
    end
  end
end
