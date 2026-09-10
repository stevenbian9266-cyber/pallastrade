# frozen_string_literal: true

# PRD-20260910-promotions-promo-batch3a-redemption-ledger (FR-002)
#
# 核销台账：一笔 (promotion, order) 一行，记录占用/核销/释放历史。
#   reserved  —— 占用中（4b 的超时/并发场景；4a 在 order.complete 短事务内直接完成）
#   committed —— 已核销（usage_limit 的唯一口径，见 `Promotion#credits_count`）
#   released  —— 已释放（取消/移除/超时；释放后可复用一次性码）
#
# 唯一约束（DB 层为准，模型校验仅提供友好错误）：
#   * (promotion_id, order_id)          —— 同一订单同一促销只能核销一次
#   * (coupon_code_id) WHERE state <> 'released' —— 一次性码同一时刻只能被一单占用
module PallasTrade
  class PromotionRedemption < PallasTrade.base_class
    has_prefix_id :redemption

    include PallasTrade::SingleStoreResource

    STATES = %w[reserved committed released].freeze
    ACTIVE_STATES = %w[reserved committed].freeze
    RELEASE_REASONS = %w[order_canceled coupon_removed reserved_timeout refunded manual].freeze

    belongs_to :store, class_name: 'PallasTrade::Store'
    belongs_to :promotion, class_name: 'PallasTrade::Promotion'
    belongs_to :order, class_name: 'PallasTrade::Order'
    belongs_to :user, class_name: PallasTrade.user_class.to_s, optional: true
    belongs_to :coupon_code, class_name: 'PallasTrade::CouponCode', optional: true

    # prefix: :redemption —— `committed!` 与 Active Record 现有方法冲突（enum 默认方法名），
    # 加前缀后生成 redemption_reserved? / redemption_committed? / redemption_released?。
    enum :state, { reserved: 'reserved', committed: 'committed', released: 'released' }, prefix: :redemption

    scope :active, -> { where(state: ACTIVE_STATES) }
    # enum 加 prefix 后不再生成同名 scope，这里显式声明（promotion#credits_count 等依赖）。
    scope :committed, -> { where(state: 'committed') }
    scope :reserved, -> { where(state: 'reserved') }
    scope :released, -> { where(state: 'released') }

    validates :state, inclusion: { in: STATES }
    validates :release_reason, inclusion: { in: RELEASE_REASONS }, allow_nil: true
    validates :promotion_id, uniqueness: { scope: :order_id }
    validate :coupon_code_available, if: -> { coupon_code_id.present? && !redemption_released? }

    def active_state?
      ACTIVE_STATES.include?(state)
    end

    # 重新占用（released → reserved）：取消/释放后同一 (promotion, order) 再次成交时复用该行
    # （唯一索引不允许同键二次插入）。
    def revive!(reserved_until: nil)
      update!(
        state: 'reserved', reserved_at: Time.current, reserved_until: reserved_until,
        committed_at: nil, released_at: nil, release_reason: nil
      )
      self
    end

    # 释放该核销（幂等）：写 released_at/reason，并回退占用中的一次性码。
    def release!(reason:)
      return self if redemption_released?

      transaction do
        update!(state: 'released', released_at: Time.current, release_reason: reason.to_s)
        revert_coupon_code
      end
      self
    end

    private

    # 与 DB 部分唯一索引一致：同一码只能被一条**非 released** 记录占用。
    def coupon_code_available
      conflict = self.class.where(coupon_code_id: coupon_code_id).
                 where.not(state: 'released').
                 where.not(id: id).exists?
      errors.add(:coupon_code, :taken) if conflict
    end

    def revert_coupon_code
      return unless coupon_code.present?
      return unless coupon_code.order_id == order_id

      coupon_code.remove_from_order
    end
  end
end
