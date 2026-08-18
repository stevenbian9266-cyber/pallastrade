# frozen_string_literal: true

module PallasTrade
  # Admin-editable email template. Keyed per store by a stable identifier
  # (e.g. "order.confirm_email"). When a row exists and is active, mailers
  # render this content (subject + HTML/text) with placeholder substitution;
  # otherwise they fall back to the code templates shipped in the gems.
  class EmailTemplate < PallasTrade.base_class
    has_prefix_id :emtp

    include PallasTrade::SingleStoreResource

    belongs_to :store, class_name: 'PallasTrade::Store'

    validates :store, :key, :name, :subject, presence: true
    validates :key, uniqueness: { scope: [:store_id, *pallastrade_base_uniqueness_scope] }

    scope :active, -> { where(active: true) }

    # All known template keys (mailer.action) that admins can edit.
    # Extend this list as new transactional emails are added.
    KNOWN_KEYS = %w[
      order.confirm_email
      order.cancel_email
      order.payment_link_email
      order.store_owner_notification_email
      shipment.shipped_email
      reimbursement.reimbursement_email
      customer.password_reset_email
      newsletter.email_confirmation
      back_in_stock.back_in_stock
      abandoned_cart.recovery_email
    ].freeze

    # Render subject with {placeholder} substitution.
    def render_subject(context = {})
      replace_placeholders(subject, context)
    end

    # Render body (html or text) with {placeholder} substitution.
    def render_body(format = :html, context = {})
      source = format == :text ? body_text : body_html
      replace_placeholders(source.to_s, context)
    end

    def placeholders_list
      Array(placeholders.to_s.split(',').map(&:strip).reject(&:empty?))
    end

    # Send a test email with the rendered template to a given address.
    # Uses the store's current mail settings via PallasTrade::TestMailer.
    # @param to [String] recipient email
    # @param context [Hash] placeholder substitution values
    # @return [Boolean] true if delivery was accepted
    def test_send(to, context = {})
      PallasTrade::TestMailer.test_email(
        to: to,
        subject: render_subject(context),
        body_html: render_body(:html, context),
        body_text: render_body(:text, context),
        store: store
      ).deliver_now
      true
    rescue StandardError => e
      Rails.logger.warn("[email_template] test send failed for #{key}: #{e.message}")
      false
    end

    private

    def replace_placeholders(template, context)
      return template if context.blank?

      template.gsub(/\{(\w+)\}/) do
        key = Regexp.last_match(1).to_sym
        context.key?(key) ? context[key].to_s : Regexp.last_match(0)
      end
    end
  end
end
