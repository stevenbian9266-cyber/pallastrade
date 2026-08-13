# frozen_string_literal: true

module PallasTrade
  module AI
    # Base class for AI provider configurations (DeepSeek, OpenAI, etc.).
    #
    # Independent STI model — decoupled from the legacy PallasTrade::Integration
    # framework. One record per (store, provider type), storing non-sensitive
    # settings in `preferences`. Provider secrets live in
    # PallasTrade::AI::ProviderSecret (encrypted), keyed by `provider_id`.
    #
    # # PRD-20260813-admin-移除管理后台-integrations-菜单及相关逻辑
    # # AI 模块解耦：独立 Provider 模型，不再继承 PallasTrade::Integration
    class Provider < PallasTrade.base_class
      has_prefix_id :aip

      include PallasTrade::SingleStoreResource

      #
      # Associations
      #
      belongs_to :store, class_name: 'PallasTrade::Store', touch: true

      #
      # Validations
      #
      validates :type, presence: true
      validates :store, presence: true, uniqueness: { scope: :type }

      #
      # Scopes
      #
      scope :active, -> { where(active: true) }

      # Connection-related fields. Not persisted (matching legacy behaviour);
      # surfaced so serializers/controllers can reference them without error.
      attr_accessor :connection_error_message, :last_verified_at, :verification_status

      # Display name for a provider type (e.g. "DeepSeek").
      def self.integration_name
        name.demodulize.titleize.strip
      end

      # Stable key for a provider type (e.g. "deepseek").
      def self.integration_key
        name.demodulize.underscore
      end

      def name
        self.class.integration_name
      end

      def key
        self.class.integration_key
      end

      # Checks if the provider can establish a connection.
      # Subclasses should override with their own validation logic.
      def can_connect?
        true
      end
    end
  end
end
