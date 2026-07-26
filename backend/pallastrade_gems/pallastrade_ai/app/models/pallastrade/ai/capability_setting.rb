# frozen_string_literal: true

module PallasTrade
  module AI
    # Per-store configuration for a registered capability.
    # Controls: active switch, primary/fallback model, parameter overrides, and budget limits.
    class CapabilitySetting < BaseModel
      self.table_name = 'pallastrade_ai_capability_settings'
      include PallasTrade::SingleStoreResource

      belongs_to :store, class_name: 'PallasTrade::Store'
      belongs_to :primary_model, class_name: 'PallasTrade::AI::Model', optional: true
      belongs_to :fallback_model, class_name: 'PallasTrade::AI::Model', optional: true

      validates :capability_key, presence: true
      validates :capability_key, uniqueness: { scope: :store_id }
      validates :daily_request_limit, numericality: { greater_than: 0 }, allow_nil: true
      validates :daily_token_limit, numericality: { greater_than: 0 }, allow_nil: true

      validate :models_belong_to_same_store
      validate :capability_key_is_registered, unless: :orphaned?
      validate :primary_model_satisfies_capability, if: -> { primary_model.present? && capability_registered? }

      scope :active, -> { where(active: true) }
      scope :for_capability, ->(key) { where(capability_key: key) }

      # Check if this capability setting is available.
      def available?
        return false unless active?
        return false if orphaned?
        return false unless primary_model.present?
        return false unless primary_model.active?
        return false unless primary_model.provider&.active?

        true
      end

      # Get the capability registry entry for this setting.
      def capability_entry
        PallasTrade::AI.capabilities[capability_key]
      end

      private

      def models_belong_to_same_store
        [primary_model, fallback_model].compact.each do |model|
          if model.store_id != store_id
            errors.add(:base, :model_must_belong_to_same_store)
            return
          end
        end
      end

      def capability_key_is_registered
        unless PallasTrade::AI.capabilities.registered?(capability_key)
          errors.add(:capability_key, :not_registered)
        end
      end

      def capability_registered?
        PallasTrade::AI.capabilities.registered?(capability_key)
      end

      def primary_model_satisfies_capability
        entry = capability_entry
        return unless entry

        required = entry.required_model_capabilities || []
        model_caps = primary_model.capabilities || []

        missing = required.map(&:to_s) - model_caps.map(&:to_s)
        if missing.any?
          errors.add(:primary_model, :missing_required_capabilities, missing: missing.join(', '))
        end
      end
    end
  end
end
