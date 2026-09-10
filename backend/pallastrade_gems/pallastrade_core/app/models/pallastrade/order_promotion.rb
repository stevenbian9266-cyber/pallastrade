# PRD-20260910-promotions-promo-batch4a-orderpromotion-snapshot (FR-002, D1/D4)
#
# Order promotion link row + **成交快照**。列语义（架构 §35）：
#   name / kind / code / description —— 成交时的促销展示事实
#   definition_digest               —— 成交时促销定义摘要（审计/比对证据）
#   item_amount / order_amount / shipping_amount / total_amount —— 成交时的三分项金额
#   currency                        —— 成交订单币种（架构 §58：不做 FX 转换）
#   frozen_at                       —— 冻结时间（nil = 未冻结）
#
# 读方法「快照优先」：已冻结时一律返回快照值；未冻结（购物车 / 未回填存量订单）
# 回退实时促销定义——保证本批次对购物车行为零影响。
module PallasTrade
  class OrderPromotion < PallasTrade.base_class
    has_prefix_id :discount

    belongs_to :order, class_name: 'PallasTrade::Order'
    belongs_to :promotion, class_name: 'PallasTrade::Promotion'

    # name / description / code 不再 delegate（PRD batch4a）：它们是「成交后必须
    # 冻结」的展示事实，改由下面的快照优先读方法提供。
    delegate :public_metadata, to: :promotion
    delegate :currency, to: :order

    validates :order, :promotion, presence: true
    validates :order, uniqueness: { scope: :promotion }

    extend PallasTrade::DisplayMoney

    money_methods :amount

    # 快照是否齐备：冻结时间失 + 名称缺失即视为未冻结（金额列有默认值，不作为信号）。
    def frozen?
      frozen_at.present? && self[:name].present?
    end
    alias frozen frozen?

    # 成交时的促销展示名（未冻结时实时取当前定义）。
    def name
      self[:name].presence || promotion&.name
    end

    # 成交时实际使用的码（多码促销 = 该订单占用的 CouponCode）。
    def code
      self[:code].presence || promotion&.code_for_order(order)
    end

    def description
      self[:description].presence || promotion&.description
    end

    # 成交时的促销类型（coupon_code / automatic）。
    def kind
      self[:kind].presence || promotion&.kind
    end

    def coupon_code?
      kind.to_s == 'coupon_code'
    end

    # 只读快照载荷（Admin 展示 / 调试 / spec 断言用）。
    def snapshot_payload
      {
        name: name,
        kind: kind,
        code: code,
        description: description,
        definition_digest: definition_digest,
        item_amount: item_amount,
        order_amount: order_amount,
        shipping_amount: shipping_amount,
        total_amount: total_amount,
        currency: self[:currency] || order&.currency,
        frozen_at: frozen_at
      }
    end

    # 金额语义不变：本促销 eligible 调整求和（批量展示走 DiscountProjection）。
    def amount
      order.all_adjustments.promotion.where(source: promotion.actions).sum(:amount)
    end
  end
end
