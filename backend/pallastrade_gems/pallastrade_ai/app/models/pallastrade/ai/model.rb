# frozen_string_literal: true

module PallasTrade
  module AI
    # Represents a model configuration under a provider.
    # Each model maps to a remote model ID (e.g., 'deepseek-v4-flash') and has its
    # own active switch, capabilities declaration, and default parameters.
    class Model < BaseModel
      self.table_name = 'pallastrade_ai_models'
      include PallasTrade::SingleStoreResource

      belongs_to :store, class_name: 'PallasTrade::Store'
      belongs_to :provider, class_name: 'PallasTrade::AI::Provider'

      has_many :capability_settings_as_primary,
               class_name: 'PallasTrade::AI::CapabilitySetting',
               foreign_key: :primary_model_id,
               dependent: :restrict_with_error
      has_many :capability_settings_as_fallback,
               class_name: 'PallasTrade::AI::CapabilitySetting',
               foreign_key: :fallback_model_id,
               dependent: :restrict_with_error

      validates :name, presence: true
      validates :provider_model_id, presence: true
      validates :provider_model_id, uniqueness: { scope: :provider_id }
      validates :kind, inclusion: { in: %w[text multimodal embedding image audio] }
      validates :provider, presence: true

      validate :provider_belongs_to_same_store

      scope :active, -> { where(active: true) }
      scope :built_in, -> { where(built_in: true) }
      scope :custom, -> { where(built_in: false) }

      # List of standard model kinds.
      KINDS = %w[text multimodal embedding image audio].freeze

      # Available canonical parameter keys.
      CANONICAL_PARAMETERS = %i[
        max_output_tokens temperature reasoning_effort thinking
        response_format stream timeout_seconds stop seed
      ].freeze

      def text_model?
        kind == 'text'
      end

      def multimodal_model?
        kind == 'multimodal'
      end

      def available?
        active? && provider&.active?
      end

      private

      def provider_belongs_to_same_store
        return unless provider && store

        unless provider.store_id == store_id
          errors.add(:provider, :must_belong_to_same_store)
        end
      end
    end
  end
end
