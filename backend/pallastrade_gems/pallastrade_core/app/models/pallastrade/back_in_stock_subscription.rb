# frozen_string_literal: true

# Back-in-stock subscriptions: customers leave an email on an out-of-stock
# product (or one specific SKU) and are notified when it is back in stock.
#
# Batch C-2 (PRD-20260915-catalog-batch-c2-sku-back-in-stock):
# - `variant_id` present → SKU-level subscription, notified by the
#   `variant.back_in_stock` event (only that SKU's subscribers).
# - `variant_id` nil → legacy product-level subscription, notified by
#   `product.back_in_stock` (the product as a whole is back).
#
# @note No raw `PallasTrade::BackInStockSubscription` queries outside `current_store`.
class PallasTrade::BackInStockSubscription < PallasTrade.base_class
  include PallasTrade::SingleStoreResource

  belongs_to :store, class_name: 'PallasTrade::Store'
  belongs_to :product, class_name: 'PallasTrade::Product'
  belongs_to :variant, class_name: 'PallasTrade::Variant', optional: true

  STATUSES = %w[active notified].freeze

  scope :active, -> { where(status: 'active') }
  # SKU-level rows vs. the historical product-level rows (migration keeps both).
  scope :for_variant, ->(variant_id) { where(variant_id: variant_id) }
  scope :product_level, -> { where(variant_id: nil) }

  validates :store, :product, :email, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :email, uniqueness: { scope: [:product_id, :variant_id, *pallastrade_base_uniqueness_scope] }
  validates :status, inclusion: { in: STATUSES }
  validate :variant_belongs_to_product

  # Mark a subscription as notified (idempotent).
  def mark_notified!
    update!(status: 'notified')
  end

  private

  def variant_belongs_to_product
    return if variant.blank? || product.blank? || variant.product_id == product.id

    errors.add(:variant, :invalid)
  end
end
