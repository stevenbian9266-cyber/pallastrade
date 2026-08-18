# frozen_string_literal: true

# Customer product reviews (P0-4, 2026-08-18).
#
# One review per (product, user); admin-moderated through status:
#   pending → approved | rejected
# Only `approved` reviews are exposed via the Store API / storefront and
# counted in the product's average rating.
#
# @note No raw `PallasTrade::Review` queries outside `current_store`.
class PallasTrade::Review < PallasTrade.base_class
  include PallasTrade::SingleStoreResource

  has_prefix_id :rev  # PallasTrade-specific: review

  belongs_to :store, class_name: 'PallasTrade::Store'
  belongs_to :product, class_name: 'PallasTrade::Product'
  belongs_to :user, class_name: "::#{PallasTrade.user_class}"

  STATUSES = %w[pending approved rejected].freeze

  scope :approved, -> { where(status: 'approved') }
  scope :rejected, -> { where(status: 'rejected') }
  scope :pending, -> { where(status: 'pending') }

  validates :store, :product, :user, presence: true
  validates :rating, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 5 }
  validates :title, length: { maximum: 255, allow_blank: true }
  validates :status, inclusion: { in: STATUSES }
  validates :product_id, uniqueness: { scope: [:user_id, *pallastrade_base_uniqueness_scope] }

  # Approve a review (admin moderation). Returns true when the transition happened.
  def approve!
    update!(status: 'approved')
  end

  # Reject a review (admin moderation). Returns true when the transition happened.
  def reject!
    update!(status: 'rejected')
  end

  def approved?
    status == 'approved'
  end

  def pending?
    status == 'pending'
  end
end
