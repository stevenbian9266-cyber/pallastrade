# frozen_string_literal: true

require 'rails_helper'

# PRD-20260909-promotions-promo-batch1
# AC-P3-1/AC-013 单码 store 级唯一；AC-P3-3/AC-015 确定性 lookup；AC-P3-4/AC-016 撞码防新增；AC-P3-5/AC-017 自动/多码不受影响
RSpec.describe PallasTrade::Promotion, type: :model do
  describe 'store-scoped single-code uniqueness（AC-P3-1/AC-013）' do
    let!(:store) { create(:store, code: 'promo_dup_store_a') }
    let!(:other_store) { create(:store, code: 'promo_dup_store_b') }

    # PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-P3-1/AC-013
    it 'rejects a second single-code promotion with the same code in the same store' do
      create(:promotion, store: store, code: 'save10')

      promo = build(:promotion, store: store, code: 'save10')
      expect(promo).not_to be_valid
      expect(promo.errors[:code]).to include(PallasTrade.t('promotion_code_taken_in_store'))
    end

    # PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-P3-1/AC-013
    it 'treats case / whitespace variants as the same code' do
      create(:promotion, store: store, code: 'summer20')

      ['SUMMER20', ' Summer20 ', 'summer20'].each do |variant|
        expect(build(:promotion, store: store, code: variant)).not_to be_valid
      end
    end

    # PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-P3-1/AC-013
    it 'allows the same code in another store' do
      create(:promotion, store: store, code: 'save10')
      expect(build(:promotion, store: other_store, code: 'save10')).to be_valid
    end

    # PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-P3-1/AC-013
    it 'does not self-collide when updating the same promotion' do
      promo = create(:promotion, store: store, code: 'save10')
      promo.name = 'Renamed'
      expect(promo).to be_valid
    end

    # PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-P3-5/AC-017
    it 'leaves automatic promotions untouched（AC-P3-5/AC-017）' do
      create(:promotion, store: store, kind: :automatic, code: nil)
      expect(build(:promotion, store: store, kind: :automatic, code: nil)).to be_valid
    end

    # PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-P3-5/AC-017
    it 'leaves multi-code promotions untouched（AC-P3-5/AC-017）' do
      create(:promotion, store: store, kind: :coupon_code, multi_codes: true, code: nil, code_prefix: 'AB', number_of_codes: 2)
      expect(build(:promotion, store: store, kind: :coupon_code, multi_codes: true, code: nil, code_prefix: 'CD', number_of_codes: 2)).to be_valid
    end
  end

  describe '.with_coupon_code deterministic lookup（AC-P3-3/AC-015）' do
    let!(:store) { create(:store, code: 'promo_lookup_store') }

    # PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-P3-3/AC-015
    it 'finds a single-code promotion regardless of case/whitespace' do
      promo = create(:promotion_with_order_adjustment, store: store, code: 'save10', weighted_order_adjustment_amount: 10)

      expect(store.promotions.with_coupon_code('save10')).to eq(promo)
      expect(store.promotions.with_coupon_code(' SAVE10 ')).to eq(promo)
    end

    # PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-P3-3/AC-015
    it 'falls back to a promotion owning a matching generated CouponCode' do
      promo = create(:promotion, store: store, kind: :coupon_code, multi_codes: true, code: nil, number_of_codes: 2)
      create(:promotion_action_create_adjustment, promotion: promo)
      promo.coupon_codes.create!(code: 'genxy')

      expect(store.promotions.with_coupon_code('genxy')).to eq(promo)
    end

    # PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-P3-3/AC-015
    it 'prefers the single-code promotion over a colliding generated code' do
      multi = create(:promotion, store: store, kind: :coupon_code, multi_codes: true, code: nil, number_of_codes: 2)
      create(:promotion_action_create_adjustment, promotion: multi)
      multi.coupon_codes.create!(code: 'shared1')

      single = create(:promotion_with_order_adjustment, store: store, code: 'shared1', weighted_order_adjustment_amount: 10)

      expect(store.promotions.with_coupon_code('shared1')).to eq(single)
    end

    # PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-P3-3/AC-015
    it 'returns nil when nothing matches' do
      expect(store.promotions.with_coupon_code('nope99')).to be_nil
    end
  end

  describe 'CouponCode ↔ single-code collision guard（AC-P3-4/AC-016）' do
    let!(:store) { create(:store, code: 'promo_collision_store') }

    # PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-P3-4/AC-016
    it 'rejects a new generated code that collides with a single-code promotion in the store' do
      create(:promotion_with_order_adjustment, store: store, code: 'save10', weighted_order_adjustment_amount: 10)
      multi = create(:promotion, store: store, kind: :coupon_code, multi_codes: true, code: nil, number_of_codes: 2)

      coupon = multi.coupon_codes.build(code: 'save10')
      expect(coupon).not_to be_valid
      expect(coupon.errors[:code]).to include(PallasTrade.t('coupon_code_taken_in_store'))
    end

    # PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness AC-P3-4/AC-016
    it 'allows a generated code that does not collide' do
      create(:promotion_with_order_adjustment, store: store, code: 'save10', weighted_order_adjustment_amount: 10)
      multi = create(:promotion, store: store, kind: :coupon_code, multi_codes: true, code: nil, number_of_codes: 2)

      coupon = multi.coupon_codes.build(code: 'fresh99')
      expect(coupon).to be_valid
    end
  end
end
