# frozen_string_literal: true

module PallasTrade
  module AI
    # Stores encrypted credentials for AI provider integrations.
    # One-to-one with a PallasTrade::Integration record of an AI provider type.
    #
    # Credentials are encrypted using Active Record Encryption (non-deterministic).
    # The plaintext API key is NEVER accessible via API, logs, Sentry, or Sidekiq.
    #
    # Fail closed: if Active Record Encryption is not configured, creating/updating
    # secrets will raise an error.
    class ProviderSecret < BaseModel
      self.table_name = 'pallastrade_ai_provider_secrets'
      belongs_to :integration, class_name: 'PallasTrade::Integration'

      validates :integration, presence: true, uniqueness: true
      validates :credentials, presence: true

      before_save :ensure_encryption_configured!
      before_save :set_key_hint, if: :credentials_changed?
      before_save :set_rotated_at, if: :credentials_changed?

      # Encrypt credentials using Active Record Encryption.
      # Conditional: only activates when encryption keys are configured via
      # ENV or Rails credentials. This avoids a boot-time crash when the
      # model is autoloaded before the encryption initializer runs.
      if ENV['ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY'].present?
        encrypts :credentials
      end

      # Generate a masked hint for display (e.g., "sk-e93••••••••••••••68cb").
      # Never exposes the full key.
      def key_hint_display
        return '' if key_hint.blank?

        parts = key_hint.to_s.split('::', 2)
        if parts.length == 2
          prefix, suffix = parts
          "#{prefix}#{'•' * 14}#{suffix}"
        else
          # Legacy hint format — show first 5 chars masked
          hint = key_hint.to_s
          hint.length > 10 ? "#{hint[0..4]}...#{hint[-4..]}" : "#{hint[0..4]}..."
        end
      end

      # Check if credentials have been configured.
      def configured?
        credentials.present?
      end

      # Safely describe credential state for API serialization.
      def credential_summary
        {
          credential_configured: configured?,
          credential_hint: key_hint_display,
          credential_rotated_at: rotated_at&.iso8601
        }
      end

      private

      def ensure_encryption_configured!
        return if ENV['ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY'].present?

        raise PallasTrade::AI::Errors::EncryptionNotConfigured,
          'Active Record Encryption primary key is not configured. Cannot store AI provider secrets.'
      end

      def set_key_hint
        return if credentials.blank?

        plain = credentials.is_a?(String) ? credentials : credentials.to_s
        self.key_hint = if plain.length > 8
                          # Store prefix(5) and suffix(4) separated by "::"
                          "#{plain[0..4]}::#{plain[-4..]}"
                        else
                          "#{plain[0..2]}..."
                        end
      end

      def set_rotated_at
        self.rotated_at = Time.current
      end
    end
  end
end
