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

  # Review photos (PRD-20260916-catalog-batch-f1-reviews FR-001).
  #
  # Deliberately ActiveStorage-only: a dedicated table would duplicate what the
  # storage tables already do, and the product asset pipeline
  # (`PallasTrade::Asset` -> `increment_viewable_media_count`) assumes a
  # Product/Variant viewable. Photos are exposed only for approved reviews.
  MAX_IMAGES = 3
  ALLOWED_IMAGE_TYPES = %w[image/jpeg image/png image/webp].freeze
  MAX_IMAGE_BYTES = 5.megabytes

  # Blob metadata key written by the store direct-upload presign endpoint. The
  # review API rejects attaching a blob that belongs to somebody else.
  IMAGE_UPLOADER_METADATA_KEY = 'review_uploader_id'

  has_many_attached :images

  validate :images_are_acceptable

  # Photos in upload order (ActiveStorage has no position column).
  def ordered_images
    images.includes(:blob).order(:id)
  end

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

  private

  def images_are_acceptable
    return if images.blank?

    if images.size > MAX_IMAGES
      errors.add(:images, "can attach at most #{MAX_IMAGES} photos")
    end

    images.each do |image|
      unless ALLOWED_IMAGE_TYPES.include?(image.blob.content_type)
        errors.add(:images, 'must be a JPEG, PNG or WebP image')
      end

      errors.add(:images, 'must be 5MB or smaller') if image.blob.byte_size > MAX_IMAGE_BYTES
    end
  end
end
