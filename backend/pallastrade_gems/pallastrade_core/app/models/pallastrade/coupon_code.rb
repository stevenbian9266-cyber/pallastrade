module PallasTrade
  class CouponCode < PallasTrade.base_class
    has_prefix_id :coupon

    include PallasTrade::Security::CouponCodes if defined?(PallasTrade::Security::CouponCodes)

    enum :state, %i(unused used)

    acts_as_paranoid

    scope :used_with_code, ->(code) { used.where(code: code.downcase) }
    scope :with_order, ->(order_id) { where(order_id: order_id) }
    scope :in_promotions, ->(promotion_ids) { where(promotion_id: promotion_ids) }
    scope :not_in_promotions, ->(promotion_ids) { where.not(promotion_id: promotion_ids) }

    belongs_to :promotion, class_name: 'PallasTrade::Promotion', touch: true
    belongs_to :order, class_name: 'PallasTrade::Order'

    validates :code, presence: true, uniqueness: { scope: pallastrade_base_uniqueness_scope, conditions: -> { where(deleted_at: nil) } }
    validates :state, :promotion, presence: true
    # PRD-20260909-promo-batch1 AC-P3-4: guard against colliding with a
    # single-code promotion in the same store (insert_all bypasses this, so
    # BulkGenerate also carries its own guard).
    validate :code_unique_against_single_code_promotions_in_store, on: :create

    self.whitelisted_ransackable_attributes = %w[state code promotion_id]
    self.whitelisted_ransackable_associations = %w[promotion]

    def self.used?(code)
      used_with_code(code).any?
    end

    # PRD-20260910-promotions-promo-batch3a (D5): 核销时占用（used + 关联订单）。
    # 购物车 apply 不再调用本方法（改为 attach_to_order!，只关联不消耗）。
    def apply_order!(order)
      update(order: order, state: 'used')
    end

    # 释放/移除时回退为可用（并解除订单关联）。
    # 修复：batch1 提交误把方法名写成 remove_from_orde（缺 r），导致多码券
    # 移除路径 NoMethodError（PRD-20260910-promo-batch3a AC-013）。
    def remove_from_order
      update(order: nil, state: 'unused')
    end

    # 只把码关联到订单（保持 unused），供购物车阶段展示与核销时占用（PRD batch3a）。
    def attach_to_order!(order)
      return self if order_id == order.id

      update(order: order)
    end

    # 解除订单关联但不改变 state（未消耗时使用）。
    def detach_from_order
      return self if order_id.nil?

      update(order: nil)
    end

    def display_code
      code.upcase
    end

    def to_csv(_store = nil)
      PallasTrade::CSV::CouponCodePresenter.new(self).call
    end

    private

    # Generated coupon codes share the customer input space with single-code
    # promotions, so a new code must not collide with one (PRD-20260909 AC-P3-4).
    def code_unique_against_single_code_promotions_in_store
      return if code.blank? || promotion.nil? || promotion.store_id.blank?

      collision = PallasTrade::Promotion.
                  where(store_id: promotion.store_id, kind: :coupon_code).
                  where.not(multi_codes: true).
                  where('lower(btrim(code)) = ?', code.to_s.strip.downcase).
                  exists?
      errors.add(:code, PallasTrade.t('coupon_code_taken_in_store')) if collision
    end
  end
end
