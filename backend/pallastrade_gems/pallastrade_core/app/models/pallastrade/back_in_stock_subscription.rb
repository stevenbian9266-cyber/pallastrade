# frozen_string_literal: true

# Back-in-stock subscriptions: customers leave an email on an out-of-stock
# variant and are notified (via the `product.back_in_stock` event) when the
# product is back in stock.
#
# @note No raw `PallasTrade::BackInStockSubscription` queries outside `current_store`.
class PallasTrade::BackInStockSubscription < PallasTrade.base_class
  include PallasTrade::SingleStoreResource

  belongs_to :store, class_name: 'PallasTrade::Store'
  belongs_to :product, class_name: 'PallasTrade::Product'

  STATUSES = %w[active notified].freeze

  scope :active, -> { where(status: 'active') }

  validates :store, :product, :email, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :email, uniqueness: { scope: [:product_id, *pallastrade_base_uniqueness_scope] }
  validates :status, inclusion: { in: STATUSES }

  # Mark a subscription as notified (idempotent).
  def mark_notified!
    update!(status: 'notified')
  end
end
