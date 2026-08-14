# frozen_string_literal: true

module PallasTrade
  # Unified Config Center entry — one row per managed parameter.
  #
  # Two storage lanes:
  #   * value        — plaintext, for non-sensitive params (string/boolean/number)
  #   * secret_value — encrypted via Active Record Encryption (non-deterministic),
  #                    for sensitive params. Plaintext is NEVER exposed via API,
  #                    logs, Sentry, or Sidekiq. Only the masked +key_hint+ and
  #                    +rotated_at+ are shown.
  #
  # Fail closed: if Active Record Encryption is not configured, writing a secret
  # raises +EncryptionNotConfigured+.
  #
  # Application code should read through {PallasTrade::ConfigCenter} (get /
  # fetch_secret) rather than querying this model directly.
  class ConfigItem < PallasTrade.base_class
    self.table_name = 'pallastrade_config_items'

    has_prefix_id :cfg # PallasTrade-specific: config item

    VALUE_TYPES = %w[secret string boolean number].freeze

    belongs_to :store, class_name: 'PallasTrade::Store', inverse_of: :config_items

    validates :key, presence: true,
                    uniqueness: { case_sensitive: false, scope: :store_id }
    validates :value_type, inclusion: { in: VALUE_TYPES }
    validates :value, presence: true, if: -> { plain? && value_changed? && value.nil? }
    validate :validate_secret_encryption!, if: :secret_value_changed?

    before_validation :normalize_key
    before_save :set_key_hint, if: :secret_value_changed?
    before_save :set_rotated_at, if: :secret_value_changed?
    after_commit :invalidate_config_center_cache

    # Encrypt secret lane using Active Record Encryption. Writes are gated by
    # validate_secret_encryption! (fail-closed) before they reach the DB, and the
    # encrypts layer itself raises if no key is configured — double protection.
    encrypts :secret_value

    scope :ordered, -> { order(:group, :key) }
    scope :for_key, ->(key) { where(key: key.to_s) }

    # ------------------------------------------------------------------
    # Type helpers
    # ------------------------------------------------------------------

    def secret?
      value_type == 'secret'
    end

    def plain?
      !secret?
    end

    # Whether a value is actually configured for this item.
    def configured?
      secret? ? secret_value.present? : value.present?
    end

    # Plaintext value. ONLY for server-internal consumption — never serialize.
    def raw_value
      secret? ? secret_value : value
    end

    # Coerced value according to +value_type+.
    def typed_value
      case value_type
      when 'boolean'
        %w[true 1 yes on].include?(raw_value.to_s.downcase)
      when 'number'
        Float(raw_value)
      else
        raw_value.to_s
      end
    rescue ArgumentError, TypeError
      raw_value
    end

    # ENV-style key, e.g. +oss.access_key_id+ → +OSS_ACCESS_KEY_ID+.
    def env_key
      key.to_s.upcase.tr('.', '_')
    end

    # ------------------------------------------------------------------
    # Secret display helpers
    # ------------------------------------------------------------------

    def key_hint_display
      return '' if key_hint.blank?

      parts = key_hint.to_s.split('::', 2)
      if parts.length == 2
        "#{parts[0]}#{'•' * 14}#{parts[1]}"
      else
        hint = key_hint.to_s
        hint.length > 10 ? "#{hint[0..4]}...#{hint[-4..]}" : "#{hint[0..4]}..."
      end
    end

    # Safely describe state for API serialization — never leaks plaintext.
    def credential_summary
      return nil unless secret?

      {
        configured: configured?,
        hint: key_hint_display,
        rotated_at: rotated_at&.iso8601
      }
    end

    # ------------------------------------------------------------------
    # Writer helpers (assigns to the right lane)
    # ------------------------------------------------------------------

    def assign_value(new_value)
      if secret?
        self.secret_value = new_value
        self.value = nil
      else
        self.value = new_value
        self.secret_value = nil
      end
    end

    private

    def invalidate_config_center_cache
      PallasTrade::ConfigCenter.invalidate!
    end

    def normalize_key
      self.key = key.to_s.strip.downcase.tr(' ', '_') if key.present?
      self.group = group.to_s.strip.presence || 'general'
    end

    def validate_secret_encryption!
      return if ENV['ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY'].present?

      errors.add(:secret_value, 'requires Active Record Encryption to be configured')
    end

    def set_key_hint
      plain = secret_value.to_s
      self.key_hint = if plain.length > 8
                        "#{plain[0..4]}::#{plain[-4..]}"
                      elsif plain.present?
                        "#{plain[0..2]}..."
                      else
                        ''
                      end
    end

    def set_rotated_at
      self.rotated_at = Time.current
    end
  end
end
