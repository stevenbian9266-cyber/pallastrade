# frozen_string_literal: true

# One-row-per (cart, email) record proving an abandoned-cart recovery email has
# already been sent. Unique on (cart_id, email) so a scan can never re-notify.
#
# @note No raw `PallasTrade::AbandonedCartNotification` queries outside `current_store`.
class PallasTrade::AbandonedCartNotification < PallasTrade.base_class
  include PallasTrade::SingleStoreResource

  belongs_to :store, class_name: 'PallasTrade::Store'
  belongs_to :cart, class_name: 'PallasTrade::Order'

  validates :store, :cart, :email, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :email, uniqueness: { scope: [:cart_id, *pallastrade_base_uniqueness_scope] }

  scope :sent, -> { where.not(sent_at: nil) }

  # Mark the notification as delivered (idempotent).
  def mark_sent!
    update!(sent_at: Time.current)
  end

  def sent?
    sent_at.present?
  end
end
