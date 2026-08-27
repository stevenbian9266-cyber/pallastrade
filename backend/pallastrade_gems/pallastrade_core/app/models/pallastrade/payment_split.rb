module PallasTrade
  # Per-order share of a combined payment. One row per member order of a
  # PaymentCombination. authorized/captured/refunded_amount are the
  # authoritative split for the order's paid / refundable totals — a partial
  # refund on one order updates only that order's split, never its siblings'.
  class PaymentSplit < PallasTrade.base_class
    has_prefix_id :psplit

    include PallasTrade::Metafields
    include PallasTrade::Metadata

    # payment_combination 可空：P2 拆单时先记账分摊（未归入组合），P4 合并支付再归入组合。
    belongs_to :payment_combination, class_name: 'PallasTrade::PaymentCombination',
                                     inverse_of: :payment_splits, optional: true
    belongs_to :order, class_name: 'PallasTrade::Order'
    belongs_to :payment, class_name: 'PallasTrade::Payment'

    validates :order, :payment, :currency, presence: true
    validates :authorized_amount, :captured_amount, :refunded_amount,
              numericality: { greater_than_or_equal_to: 0 }
    validates :order_id, uniqueness: { scope: :payment_combination_id }

    # Amount still capturable for this order's share.
    def uncaptured_amount
      captured_amount - authorized_amount
    end

    # Amount still refundable for this order's share.
    def credit_allowed
      captured_amount - refunded_amount
    end
  end
end
